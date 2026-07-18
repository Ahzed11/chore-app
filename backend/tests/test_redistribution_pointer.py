"""Regression tests for the rotation-pointer adjustment on member removal (TASK-080 L1).

The rotation pointer is stored UNBOUNDED (RoundRobinStrategy writes pointer+1
without a modulo), so the adjustment in redistribute_chores_for_removed_member
must compare the removed member's index against ``pointer % member_count``
(member count including the removed member), not against the raw pointer.
The old code compared against the raw pointer, so with any pointer >= N the
decrement fired for every removal regardless of position.
"""
import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from app.services.redistribution import redistribute_chores_for_removed_member

_BASE_TIME = datetime(2024, 1, 1, 0, 0, 0, tzinfo=timezone.utc)


async def _seed_household(
    session: AsyncSession,
    member_count: int,
    rotation_pointer: int,
) -> tuple[Household, list[User], list[HouseholdMembership]]:
    """Create a household with ``member_count`` active members in join order."""
    household = Household(
        id=uuid.uuid4(), name="Pointer HH", rotation_pointer=rotation_pointer
    )
    session.add(household)
    users: list[User] = []
    memberships: list[HouseholdMembership] = []
    for i in range(member_count):
        uid = uuid.uuid4()
        user = User(
            id=uid,
            email=f"user-{uid}@test.example",
            display_name=f"User {i}",
            password_hash="x",
        )
        session.add(user)
        users.append(user)
    await session.flush()
    for i, user in enumerate(users):
        membership = HouseholdMembership(
            id=uuid.uuid4(),
            household_id=household.id,
            user_id=user.id,
            role="member",
            joined_at=_BASE_TIME + timedelta(seconds=i),
            is_active=True,
        )
        session.add(membership)
        memberships.append(membership)
    await session.flush()
    return household, users, memberships


async def _remove_member(
    session: AsyncSession,
    household: Household,
    membership: HouseholdMembership,
) -> None:
    """Deactivate the membership (as the API does) and run redistribution."""
    membership.is_active = False
    await session.flush()
    await redistribute_chores_for_removed_member(
        membership.user_id, household.id, session
    )


async def test_pointer_gt_member_count_removal_before_pointer(
    db_session: AsyncSession,
) -> None:
    """3 members, pointer 7 (effective 7 % 3 = 1): removing index 0 (< 1)
    decrements the pointer."""
    household, _, memberships = await _seed_household(db_session, 3, rotation_pointer=7)
    await _remove_member(db_session, household, memberships[0])
    assert household.rotation_pointer == 6


async def test_pointer_gt_member_count_removal_at_pointer(
    db_session: AsyncSession,
) -> None:
    """3 members, pointer 7 (effective 1): removing index 1 (== 1) must NOT
    decrement.  The old code compared 1 < 7 and always decremented."""
    household, _, memberships = await _seed_household(db_session, 3, rotation_pointer=7)
    await _remove_member(db_session, household, memberships[1])
    assert household.rotation_pointer == 7


async def test_pointer_gt_member_count_removal_after_pointer(
    db_session: AsyncSession,
) -> None:
    """3 members, pointer 7 (effective 1): removing index 2 (> 1) must NOT
    decrement.  The old code compared 2 < 7 and always decremented."""
    household, _, memberships = await _seed_household(db_session, 3, rotation_pointer=7)
    await _remove_member(db_session, household, memberships[2])
    assert household.rotation_pointer == 7


async def test_pointer_within_range_still_decrements(db_session: AsyncSession) -> None:
    """Sanity: with a small pointer (1), removing index 0 still decrements."""
    household, _, memberships = await _seed_household(db_session, 3, rotation_pointer=1)
    await _remove_member(db_session, household, memberships[0])
    assert household.rotation_pointer == 0


async def test_removal_with_pending_chore_reassigns_and_adjusts(
    db_session: AsyncSession,
) -> None:
    """Removing a member with a pending chore: redistribution advances the
    pointer by one (bulk assign), and no spurious decrement fires when the
    removed index equals the effective pointer position."""
    household, users, memberships = await _seed_household(
        db_session, 3, rotation_pointer=7
    )
    chore = ChoreInstance(
        id=uuid.uuid4(),
        definition_id=None,
        household_id=household.id,
        assignee_id=users[1].id,
        assigned_manually=False,
        due_date=date(2024, 1, 2),
        status="pending",
    )
    db_session.add(chore)
    await db_session.flush()

    # Remove member B (index 1, == effective pointer 7 % 3).
    await _remove_member(db_session, household, memberships[1])

    # The service leaves flushing to the caller.
    await db_session.flush()
    await db_session.refresh(chore)
    # Remaining rotation order is [A, C]; bulk assign picks 7 % 2 = 1 → C.
    assert chore.assignee_id == users[2].id
    # 7 advanced to 8 by the bulk assignment; no decrement (1 !< 1).
    assert household.rotation_pointer == 8
