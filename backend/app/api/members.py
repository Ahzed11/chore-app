"""Member management endpoints for a household.

Routes (all scoped to /households/{household_id}):
  GET    /members                    — list active members (any member)
  DELETE /members/{user_id}          — remove a member (admin only)
  PATCH  /members/{user_id}/role     — change a member's role (admin only)
  POST   /leave                      — leave the household (any member)
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_admin, require_household_member
from app.db.session import get_db
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from app.schemas.member import MemberResponse, RoleUpdateRequest
from app.services.redistribution import redistribute_chores_for_removed_member

router = APIRouter(prefix="/households/{household_id}", tags=["members"])


# ---------------------------------------------------------------------------
# Internal helper
# ---------------------------------------------------------------------------


async def _count_active_admins(household_id: uuid.UUID, db: AsyncSession) -> int:
    """Return the number of active admins in the given household."""
    result = await db.execute(
        select(func.count(HouseholdMembership.id))
        .where(
            HouseholdMembership.household_id == household_id,
            HouseholdMembership.is_active == True,  # noqa: E712
            HouseholdMembership.role == "admin",
        )
    )
    return result.scalar_one()


# ---------------------------------------------------------------------------
# GET /households/{household_id}/members
# ---------------------------------------------------------------------------


@router.get("/members", response_model=list[MemberResponse])
async def list_members(
    household_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> list[MemberResponse]:
    """Return all active members of a household.

    Any active member may call this endpoint.
    """
    result = await db.execute(
        select(HouseholdMembership, User.display_name)
        .join(User, HouseholdMembership.user_id == User.id)
        .where(
            HouseholdMembership.household_id == household_id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
        .order_by(HouseholdMembership.joined_at.asc())
    )
    rows = result.all()
    return [
        MemberResponse(
            user_id=membership.user_id,
            display_name=display_name,
            role=membership.role,
            joined_at=membership.joined_at,
        )
        for membership, display_name in rows
    ]


# ---------------------------------------------------------------------------
# DELETE /households/{household_id}/members/{user_id}
# ---------------------------------------------------------------------------


@router.delete("/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(
    household_id: uuid.UUID,
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin_membership: HouseholdMembership = Depends(require_admin),
) -> None:
    """Remove a member from the household (admin only).

    Marks the membership inactive and redistributes any pending/overdue chores
    that were assigned to the removed member — all within the same transaction.

    Raises 409 if the caller is trying to remove themselves and they are the
    only active admin.
    """
    # Load the target member's active membership
    target_result = await db.execute(
        select(HouseholdMembership).where(
            HouseholdMembership.household_id == household_id,
            HouseholdMembership.user_id == user_id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
    )
    target = target_result.scalar_one_or_none()
    if target is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        )

    # Guard: cannot remove yourself when you are the only admin
    if user_id == admin_membership.user_id:
        admin_count = await _count_active_admins(household_id, db)
        if admin_count <= 1:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot remove the sole admin",
            )

    # Soft-delete: flush so redistribution queries see no active membership
    target.is_active = False
    await db.flush()

    # Redistribute the removed member's open chores in the same transaction
    await redistribute_chores_for_removed_member(user_id, household_id, db)


# ---------------------------------------------------------------------------
# PATCH /households/{household_id}/members/{user_id}/role
# ---------------------------------------------------------------------------


@router.patch("/members/{user_id}/role", response_model=MemberResponse)
async def update_member_role(
    household_id: uuid.UUID,
    user_id: uuid.UUID,
    body: RoleUpdateRequest,
    db: AsyncSession = Depends(get_db),
    admin_membership: HouseholdMembership = Depends(require_admin),
) -> MemberResponse:
    """Change a member's role to 'admin' or 'member' (admin only).

    Raises 409 if the caller tries to demote themselves while being the sole
    active admin.
    """
    target_result = await db.execute(
        select(HouseholdMembership).where(
            HouseholdMembership.household_id == household_id,
            HouseholdMembership.user_id == user_id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
    )
    target = target_result.scalar_one_or_none()
    if target is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        )

    # Guard: cannot demote yourself when you are the only admin
    if user_id == admin_membership.user_id and body.role == "member":
        admin_count = await _count_active_admins(household_id, db)
        if admin_count <= 1:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot demote the sole admin",
            )

    target.role = body.role
    await db.flush()

    # Resolve display_name for the response (User always exists if membership exists)
    user_result = await db.execute(select(User).where(User.id == user_id))
    user = user_result.scalar_one()

    return MemberResponse(
        user_id=target.user_id,
        display_name=user.display_name,
        role=target.role,
        joined_at=target.joined_at,
    )


# ---------------------------------------------------------------------------
# POST /households/{household_id}/leave
# ---------------------------------------------------------------------------


@router.post("/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_household(
    household_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    membership: HouseholdMembership = Depends(require_household_member),
) -> None:
    """Leave the household.

    Any active member may call this. Marks the membership inactive and
    redistributes the leaving member's pending/overdue chores — all within
    the same transaction.

    Raises 409 if the caller is the sole active admin; they must promote
    another member to admin first.
    """
    if membership.role == "admin":
        admin_count = await _count_active_admins(household_id, db)
        if admin_count <= 1:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot leave as the sole admin. Promote another admin first.",
            )

    leaving_user_id = membership.user_id

    # Soft-delete: flush so redistribution queries see no active membership
    membership.is_active = False
    await db.flush()

    # Redistribute the leaving member's open chores in the same transaction
    await redistribute_chores_for_removed_member(leaving_user_id, household_id, db)
