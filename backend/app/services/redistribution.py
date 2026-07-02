"""Redistribution service: reassign a removed member's chores to remaining members.

Implements FR-042, BR-002, BR-003:
  FR-042  pending/overdue chores are redistributed via round-robin on removal.
  BR-002  completed/cancelled chores are never touched.
  BR-003  if no active members remain after removal, assignee_id is set to None.
"""
import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.services.assignment import AssignmentService, RoundRobinStrategy


async def redistribute_chores_for_removed_member(
    removed_user_id: uuid.UUID,
    household_id: uuid.UUID,
    session: AsyncSession,
) -> None:
    """Reassign all pending/overdue chores that belonged to the removed member.

    The removed member's membership MUST already be marked ``is_active=False``
    and the change flushed to the database before this function is called, so
    that remaining-member counts exclude them correctly.

    All mutations happen within the provided ``session``; the caller is
    responsible for committing or rolling back the transaction.
    """
    # ------------------------------------------------------------------
    # Step 1 — collect the removed member's open chore instances
    # ------------------------------------------------------------------
    chores_result = await session.execute(
        select(ChoreInstance)
        .where(
            ChoreInstance.assignee_id == removed_user_id,
            ChoreInstance.household_id == household_id,
            ChoreInstance.status.in_(["pending", "overdue"]),
        )
    )
    chores = chores_result.scalars().all()
    chore_ids = [c.id for c in chores]
    chore_map = {c.id: c for c in chores}

    # ------------------------------------------------------------------
    # Step 2 — count remaining active members (excluding removed user)
    # ------------------------------------------------------------------
    remaining_result = await session.execute(
        select(func.count(HouseholdMembership.id))
        .where(
            HouseholdMembership.household_id == household_id,
            HouseholdMembership.is_active == True,  # noqa: E712
            HouseholdMembership.user_id != removed_user_id,
        )
    )
    remaining_count = remaining_result.scalar_one()

    # ------------------------------------------------------------------
    # Step 5 prep — capture original rotation_pointer BEFORE redistribution
    # advances it, so the pointer adjustment uses the pre-redistribution value.
    # ------------------------------------------------------------------
    household_result = await session.execute(
        select(Household).where(Household.id == household_id)
    )
    household = household_result.scalar_one_or_none()
    original_pointer: int = household.rotation_pointer if household is not None else 0

    # Determine the removed member's 0-based index in the original sorted list
    # (ordered by joined_at ASC, as RoundRobinStrategy uses).  The membership is
    # already inactive at call time, so we query it directly by user_id.
    removed_index: int | None = None
    if household is not None:
        removed_mbr_result = await session.execute(
            select(HouseholdMembership)
            .where(
                HouseholdMembership.household_id == household_id,
                HouseholdMembership.user_id == removed_user_id,
            )
            .order_by(HouseholdMembership.joined_at.desc())
            .limit(1)
        )
        removed_mbr = removed_mbr_result.scalar_one_or_none()

        if removed_mbr is not None:
            # Count remaining active members who joined strictly before the removed
            # member.  This equals the removed member's 0-based index in the
            # original sorted list (ties in joined_at fall after this member).
            earlier_result = await session.execute(
                select(func.count(HouseholdMembership.id))
                .where(
                    HouseholdMembership.household_id == household_id,
                    HouseholdMembership.is_active == True,  # noqa: E712
                    HouseholdMembership.joined_at < removed_mbr.joined_at,
                )
            )
            removed_index = earlier_result.scalar_one()

    # ------------------------------------------------------------------
    # Steps 3 & 4 — redistribute or clear open chores
    # ------------------------------------------------------------------
    if chore_ids:
        if remaining_count == 0:
            # BR-003: no remaining members — clear all assignees
            for chore in chores:
                chore.assignee_id = None
        else:
            # FR-042: redistribute via round-robin using a single lock acquisition
            # — SELECT FOR UPDATE on the household happens once, members are
            # cycled in Python, and rotation_pointer is written once after the
            # loop (O(1) round-trips instead of O(N)).
            service = AssignmentService(RoundRobinStrategy())
            assignments = await service.redistribute_chores_bulk(chore_ids, household_id, session)
            for chore_id, new_assignee in assignments.items():
                if chore_id in chore_map:
                    chore_map[chore_id].assignee_id = new_assignee

    # ------------------------------------------------------------------
    # Step 5 — adjust rotation_pointer for the removed member's position
    #
    # If the removed member's index in the original list was strictly less
    # than the original pointer, decrement the current pointer by 1 so that
    # the "next" member to be assigned is the same one as it would have been
    # without the removal.
    # ------------------------------------------------------------------
    if household is not None and removed_index is not None:
        if removed_index < original_pointer:
            household.rotation_pointer = max(0, household.rotation_pointer - 1)
    # Caller commits the session.
