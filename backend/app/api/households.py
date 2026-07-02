"""Household CRUD endpoints."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_admin, require_household_member
from app.db.session import get_db
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from app.schemas.household import (
    HouseholdCreate,
    HouseholdDetailResponse,
    HouseholdResponse,
    HouseholdUpdate,
    HouseholdWithRoleResponse,
)

router = APIRouter(prefix="/households", tags=["households"])


@router.post("", response_model=HouseholdResponse, status_code=status.HTTP_201_CREATED)
async def create_household(
    body: HouseholdCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HouseholdResponse:
    """Create a new household and make the creator an admin member."""
    household = Household(name=body.name, rotation_pointer=0)
    db.add(household)
    await db.flush()

    membership = HouseholdMembership(
        household_id=household.id,
        user_id=current_user.id,
        role="admin",
        joined_at=datetime.now(timezone.utc),
        is_active=True,
    )
    db.add(membership)
    await db.flush()
    await db.refresh(household)

    return HouseholdResponse(
        id=household.id,
        name=household.name,
        created_at=household.created_at,
    )


@router.get("", response_model=list[HouseholdWithRoleResponse])
async def list_households(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[HouseholdWithRoleResponse]:
    """List all households where the current user has an active membership."""
    stmt = (
        select(Household, HouseholdMembership.role)
        .join(HouseholdMembership, Household.id == HouseholdMembership.household_id)
        .where(
            HouseholdMembership.user_id == current_user.id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
    )
    result = await db.execute(stmt)
    rows = result.all()

    if not rows:
        return []

    household_ids = [row[0].id for row in rows]

    count_stmt = (
        select(HouseholdMembership.household_id, func.count(HouseholdMembership.id))
        .where(
            HouseholdMembership.household_id.in_(household_ids),
            HouseholdMembership.is_active == True,  # noqa: E712
        )
        .group_by(HouseholdMembership.household_id)
    )
    count_result = await db.execute(count_stmt)
    count_map: dict[uuid.UUID, int] = {row[0]: row[1] for row in count_result.all()}

    return [
        HouseholdWithRoleResponse(
            id=household.id,
            name=household.name,
            created_at=household.created_at,
            role=role,
            member_count=count_map.get(household.id, 0),
        )
        for household, role in rows
    ]


@router.get("/{household_id}", response_model=HouseholdDetailResponse)
async def get_household(
    household_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> HouseholdDetailResponse:
    """Return household detail with active member count (membership required)."""
    result = await db.execute(select(Household).where(Household.id == household_id))
    household = result.scalar_one_or_none()

    if household is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Household not found",
        )

    count_result = await db.execute(
        select(func.count(HouseholdMembership.id)).where(
            HouseholdMembership.household_id == household_id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
    )
    member_count = count_result.scalar_one()

    return HouseholdDetailResponse(
        id=household.id,
        name=household.name,
        created_at=household.created_at,
        member_count=member_count,
    )


@router.patch("/{household_id}", response_model=HouseholdResponse)
async def update_household(
    household_id: uuid.UUID,
    body: HouseholdUpdate,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_admin),
) -> HouseholdResponse:
    """Rename a household (admin only)."""
    result = await db.execute(select(Household).where(Household.id == household_id))
    household = result.scalar_one_or_none()

    if household is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Household not found",
        )

    household.name = body.name
    await db.flush()
    await db.refresh(household)

    return HouseholdResponse(
        id=household.id,
        name=household.name,
        created_at=household.created_at,
    )
