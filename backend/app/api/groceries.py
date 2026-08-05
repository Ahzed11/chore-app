"""Grocery list endpoints.

All routes are scoped to a household:
    /households/{household_id}/groceries

Groceries are a shared collaborative space: any active household member may
add, edit, delete, and toggle items. Admin role is not required.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.api.deps import get_current_user, require_household_member
from app.db.session import get_db
from app.models.grocery_item import GroceryItem
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from app.schemas.grocery import (
    GroceryItemCreate,
    GroceryItemResponse,
    GroceryItemUpdate,
)

router = APIRouter(prefix="/households/{household_id}/groceries", tags=["groceries"])

# `purchased_by_id` joins to users too, so the list query needs a second alias.
UserPurchased = aliased(User)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

async def _get_item_or_404(
    item_id: uuid.UUID,
    household_id: uuid.UUID,
    db: AsyncSession,
) -> GroceryItem:
    result = await db.execute(
        select(GroceryItem).where(
            GroceryItem.id == item_id,
            GroceryItem.household_id == household_id,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Grocery item not found",
        )
    return item


def _item_response(
    item: GroceryItem,
    added_by_name: str | None,
    purchased_by_name: str | None,
) -> GroceryItemResponse:
    return GroceryItemResponse(
        id=item.id,
        household_id=item.household_id,
        added_by_id=item.added_by_id,
        added_by_name=added_by_name,
        name=item.name,
        quantity=item.quantity,
        notes=item.notes,
        is_purchased=item.is_purchased,
        purchased_by_id=item.purchased_by_id,
        purchased_by_name=purchased_by_name,
        purchased_at=item.purchased_at,
        created_at=item.created_at,
    )


async def _build_item_response(
    item: GroceryItem,
    db: AsyncSession,
) -> GroceryItemResponse:
    """Join User display names and build a full response."""
    added_by_name: str | None = None
    purchased_by_name: str | None = None
    if item.added_by_id:
        u = await db.get(User, item.added_by_id)
        if u is not None:
            added_by_name = u.display_name
    if item.purchased_by_id:
        u = await db.get(User, item.purchased_by_id)
        if u is not None:
            purchased_by_name = u.display_name
    return _item_response(item, added_by_name, purchased_by_name)


# ---------------------------------------------------------------------------
# POST /households/{household_id}/groceries  — add item (any member)
# ---------------------------------------------------------------------------

@router.post(
    "",
    response_model=GroceryItemResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_grocery_item(
    household_id: uuid.UUID,
    body: GroceryItemCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    """Add a new item to the household's grocery list."""
    item = GroceryItem(
        household_id=household_id,
        added_by_id=current_user.id,
        name=body.name,
        quantity=body.quantity,
        notes=body.notes,
    )
    db.add(item)
    await db.flush()
    await db.refresh(item)
    return _item_response(item, current_user.display_name, None)


# ---------------------------------------------------------------------------
# GET /households/{household_id}/groceries  — list items (any member)
# ---------------------------------------------------------------------------

@router.get("", response_model=list[GroceryItemResponse])
async def list_grocery_items(
    household_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> list[GroceryItemResponse]:
    """Return all grocery items for a household, newest first."""
    stmt = (
        select(GroceryItem, User.display_name, UserPurchased.display_name)
        .outerjoin(User, GroceryItem.added_by_id == User.id)
        .outerjoin(UserPurchased, GroceryItem.purchased_by_id == UserPurchased.id)
        .where(GroceryItem.household_id == household_id)
        .order_by(GroceryItem.created_at.desc())
    )
    result = await db.execute(stmt)
    return [
        _item_response(item, added_by_name, purchased_by_name)
        for item, added_by_name, purchased_by_name in result.all()
    ]


# ---------------------------------------------------------------------------
# PATCH /households/{household_id}/groceries/{item_id}  — update item (any member)
# ---------------------------------------------------------------------------

@router.patch("/{item_id}", response_model=GroceryItemResponse)
async def update_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    body: GroceryItemUpdate,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    """Update an item's name, quantity, or notes."""
    item = await _get_item_or_404(item_id, household_id, db)
    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(item, field, value)
    await db.flush()
    await db.refresh(item)
    return await _build_item_response(item, db)


# ---------------------------------------------------------------------------
# DELETE /households/{household_id}/groceries/{item_id}  — remove item (any member)
# ---------------------------------------------------------------------------

@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> None:
    """Remove an item from the grocery list."""
    item = await _get_item_or_404(item_id, household_id, db)
    await db.delete(item)
    await db.flush()


# ---------------------------------------------------------------------------
# POST /households/{household_id}/groceries/{item_id}/purchase  — any member
# ---------------------------------------------------------------------------

@router.post("/{item_id}/purchase", response_model=GroceryItemResponse)
async def purchase_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    """Mark an item as purchased by the current user."""
    item = await _get_item_or_404(item_id, household_id, db)
    item.is_purchased = True
    item.purchased_by_id = current_user.id
    item.purchased_at = datetime.now(timezone.utc)
    await db.flush()
    await db.refresh(item)
    return await _build_item_response(item, db)


# ---------------------------------------------------------------------------
# POST /households/{household_id}/groceries/{item_id}/unpurchase  — any member
# ---------------------------------------------------------------------------

@router.post("/{item_id}/unpurchase", response_model=GroceryItemResponse)
async def unpurchase_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    """Mark a purchased item as not purchased again (reversible, unlike chores)."""
    item = await _get_item_or_404(item_id, household_id, db)
    item.is_purchased = False
    item.purchased_by_id = None
    item.purchased_at = None
    await db.flush()
    await db.refresh(item)
    return await _build_item_response(item, db)
