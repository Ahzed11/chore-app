"""Account deletion orchestration (TASK-078).

Handles the cross-household bookkeeping required before a user row can be
safely deleted:

  * households where the user is the *sole* active member are deleted
    outright — the household FK cascades (memberships, invites, chore
    definitions/instances, point ledger) take care of the rest;
  * households where the user is an active member alongside others have
    their membership deactivated and open (pending/overdue) chores
    redistributed, exactly as the member-removal flow (``app.api.members``)
    does;
  * a household where the user is the *sole* admin with other active
    members blocks the *entire* deletion with HTTP 409 — the user must
    promote another admin there first.

All households are validated in a first pass before any mutation happens,
so a 409 never leaves the account (or any household) partially modified.

``PointLedger.user_id`` is configured ``ondelete="CASCADE"`` (see
``app/models/point_ledger.py``), not ``SET NULL``, so deleting the user row
also removes their point ledger entries — this mirrors the existing FK
configuration rather than overriding it. ``ChoreInstance.assignee_id`` and
``ChoreDefinition.created_by_id`` are ``SET NULL``, so completed/cancelled
chore history and chore definitions the user authored survive the deletion
with the assignee/author reference cleared.
"""
from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy import delete as sql_delete
from sqlalchemy import func, select
from sqlalchemy import update as sql_update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.services.redistribution import redistribute_chores_for_removed_member


async def delete_user_account(user: User, db: AsyncSession) -> None:
    """Delete ``user``'s account, handling all household memberships first.

    Raises HTTP 409 if the user is the sole admin of a household that has
    other active members (they must promote someone else there first) — in
    that case nothing is mutated. Otherwise: sole-member households are hard
    deleted, other memberships are deactivated with their open chores
    redistributed, all refresh tokens are revoked, and finally the user row
    itself is deleted.

    Committing the transaction is the caller's responsibility (the ``get_db``
    dependency commits on success).
    """
    memberships_result = await db.execute(
        select(HouseholdMembership).where(
            HouseholdMembership.user_id == user.id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
    )
    memberships = memberships_result.scalars().all()

    # ------------------------------------------------------------------
    # Pass 1 — validate only. No mutation happens here, so raising HTTP 409
    # never leaves the account or any household partially changed.
    # ------------------------------------------------------------------
    households_to_delete: list[Household] = []
    memberships_to_leave: list[HouseholdMembership] = []

    for membership in memberships:
        member_count_result = await db.execute(
            select(func.count(HouseholdMembership.id)).where(
                HouseholdMembership.household_id == membership.household_id,
                HouseholdMembership.is_active == True,  # noqa: E712
            )
        )
        member_count: int = member_count_result.scalar_one()

        if member_count <= 1:
            # Sole member of this household — delete it outright.
            household_result = await db.execute(
                select(Household).where(Household.id == membership.household_id)
            )
            household = household_result.scalar_one_or_none()
            if household is not None:
                households_to_delete.append(household)
            continue

        if membership.role == "admin":
            admin_count_result = await db.execute(
                select(func.count(HouseholdMembership.id)).where(
                    HouseholdMembership.household_id == membership.household_id,
                    HouseholdMembership.is_active == True,  # noqa: E712
                    HouseholdMembership.role == "admin",
                )
            )
            admin_count: int = admin_count_result.scalar_one()
            if admin_count <= 1:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "You are the sole admin of a household with other active "
                        "members. Promote another member to admin before deleting "
                        "your account."
                    ),
                )

        memberships_to_leave.append(membership)

    # ------------------------------------------------------------------
    # Pass 2 — mutate. Every branch above either raised or queued work here.
    #
    # Deletions use core DELETE statements (not ``session.delete``) so the
    # database-level ``ON DELETE CASCADE`` / ``SET NULL`` rules do the child
    # cleanup — the ORM relationships are not configured with
    # ``passive_deletes`` and would otherwise try to NULL non-nullable FKs.
    # ------------------------------------------------------------------
    if households_to_delete:
        await db.execute(
            sql_delete(Household).where(
                Household.id.in_([h.id for h in households_to_delete])
            )
        )

    for membership in memberships_to_leave:
        membership.is_active = False
    if memberships_to_leave:
        await db.flush()
        for membership in memberships_to_leave:
            await redistribute_chores_for_removed_member(
                user.id, membership.household_id, db
            )

    # Revoke all outstanding refresh tokens for the account being deleted.
    await db.execute(
        sql_update(RefreshToken)
        .where(
            RefreshToken.user_id == user.id,
            RefreshToken.revoked_at == None,  # noqa: E711
        )
        .values(revoked_at=datetime.now(timezone.utc))
    )

    await db.execute(sql_delete(User).where(User.id == user.id))
    await db.flush()


__all__ = ["delete_user_account"]
