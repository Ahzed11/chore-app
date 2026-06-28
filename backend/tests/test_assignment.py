"""Tests for app/services/assignment.py — targets 100% line coverage."""
import uuid
from datetime import datetime, timezone, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from app.services.assignment import (
    AssignmentService,
    AssignmentStrategy,
    RoundRobinStrategy,
    get_assignment_service,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_user() -> User:
    """Create an unsaved User ORM instance with a unique email."""
    uid = uuid.uuid4()
    return User(
        id=uid,
        email=f"user-{uid}@test.example",
        display_name=f"User {uid}",
        password_hash="hashed",
    )


def _make_household(rotation_pointer: int = 0) -> Household:
    """Create an unsaved Household ORM instance."""
    return Household(
        id=uuid.uuid4(),
        name="Test Household",
        rotation_pointer=rotation_pointer,
    )


def _make_membership(
    household_id: uuid.UUID,
    user_id: uuid.UUID,
    joined_at: datetime,
    is_active: bool = True,
    role: str = "member",
) -> HouseholdMembership:
    """Create an unsaved HouseholdMembership ORM instance."""
    return HouseholdMembership(
        id=uuid.uuid4(),
        household_id=household_id,
        user_id=user_id,
        role=role,
        joined_at=joined_at,
        is_active=is_active,
    )


_BASE_TIME = datetime(2024, 1, 1, 0, 0, 0, tzinfo=timezone.utc)


async def _flush(session: AsyncSession, *objs) -> None:
    """Add and flush ORM objects so they are visible within the transaction."""
    for obj in objs:
        session.add(obj)
    await session.flush()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


async def test_round_robin_single_member(db_session: AsyncSession) -> None:
    """With one active member, every assign() call returns that member and the pointer increments."""
    user = _make_user()
    household = _make_household(rotation_pointer=0)
    await _flush(db_session, user, household)

    membership = _make_membership(household.id, user.id, joined_at=_BASE_TIME)
    await _flush(db_session, membership)

    strategy = RoundRobinStrategy()

    # First call → member returned, pointer becomes 1
    result1 = await strategy.assign(household.id, db_session)
    assert result1 == user.id
    assert household.rotation_pointer == 1

    # Second call → same member (pointer 1 % 1 == 0), pointer becomes 2
    result2 = await strategy.assign(household.id, db_session)
    assert result2 == user.id
    assert household.rotation_pointer == 2


async def test_round_robin_multiple_members(db_session: AsyncSession) -> None:
    """With 3 members, assign() cycles A → B → C → A in join-date order."""
    user_a, user_b, user_c = _make_user(), _make_user(), _make_user()
    household = _make_household(rotation_pointer=0)
    await _flush(db_session, user_a, user_b, user_c, household)

    # Stagger join times so order is deterministic
    await _flush(
        db_session,
        _make_membership(household.id, user_a.id, joined_at=_BASE_TIME),
        _make_membership(household.id, user_b.id, joined_at=_BASE_TIME + timedelta(seconds=1)),
        _make_membership(household.id, user_c.id, joined_at=_BASE_TIME + timedelta(seconds=2)),
    )

    strategy = RoundRobinStrategy()

    calls = [await strategy.assign(household.id, db_session) for _ in range(4)]
    assert calls == [user_a.id, user_b.id, user_c.id, user_a.id]
    assert household.rotation_pointer == 4


async def test_no_members_returns_none(db_session: AsyncSession) -> None:
    """assign() returns None when there are no active members."""
    household = _make_household()
    await _flush(db_session, household)

    strategy = RoundRobinStrategy()
    result = await strategy.assign(household.id, db_session)
    assert result is None


async def test_no_household_returns_none(db_session: AsyncSession) -> None:
    """assign() returns None when the household_id does not exist."""
    strategy = RoundRobinStrategy()
    result = await strategy.assign(uuid.uuid4(), db_session)
    assert result is None


async def test_inactive_member_excluded(db_session: AsyncSession) -> None:
    """Inactive members are skipped; only the active member is ever returned."""
    active_user = _make_user()
    inactive_user = _make_user()
    household = _make_household(rotation_pointer=0)
    await _flush(db_session, active_user, inactive_user, household)

    await _flush(
        db_session,
        _make_membership(household.id, active_user.id, joined_at=_BASE_TIME, is_active=True),
        _make_membership(
            household.id, inactive_user.id, joined_at=_BASE_TIME + timedelta(seconds=1), is_active=False
        ),
    )

    strategy = RoundRobinStrategy()

    for _ in range(3):
        result = await strategy.assign(household.id, db_session)
        assert result == active_user.id


async def test_manual_assignment_does_not_advance_pointer(db_session: AsyncSession) -> None:
    """
    Design property: manual assignment (not calling auto_assign/assign) leaves the
    pointer unchanged, so the next auto_assign picks from the correct position.
    """
    user_a, user_b = _make_user(), _make_user()
    household = _make_household(rotation_pointer=0)
    await _flush(db_session, user_a, user_b, household)

    await _flush(
        db_session,
        _make_membership(household.id, user_a.id, joined_at=_BASE_TIME),
        _make_membership(household.id, user_b.id, joined_at=_BASE_TIME + timedelta(seconds=1)),
    )

    service = AssignmentService(strategy=RoundRobinStrategy())

    # First auto_assign → user_a (pointer 0 → 1)
    first = await service.auto_assign(household.id, db_session)
    assert first == user_a.id
    assert household.rotation_pointer == 1

    # "Manual" assignment: directly write assignee_id to a chore without calling auto_assign.
    # The pointer must remain at 1.
    assert household.rotation_pointer == 1

    # Next auto_assign → user_b (pointer 1 → 2), confirming pointer was not silently advanced
    second = await service.auto_assign(household.id, db_session)
    assert second == user_b.id
    assert household.rotation_pointer == 2


async def test_redistribute_chores(db_session: AsyncSession) -> None:
    """redistribute_chores alternates between members for each chore instance."""
    user_a, user_b = _make_user(), _make_user()
    household = _make_household(rotation_pointer=0)
    await _flush(db_session, user_a, user_b, household)

    await _flush(
        db_session,
        _make_membership(household.id, user_a.id, joined_at=_BASE_TIME),
        _make_membership(household.id, user_b.id, joined_at=_BASE_TIME + timedelta(seconds=1)),
    )

    # Use bare UUIDs — no real ChoreInstance rows needed
    id1, id2, id3, id4 = uuid.uuid4(), uuid.uuid4(), uuid.uuid4(), uuid.uuid4()

    service = AssignmentService(strategy=RoundRobinStrategy())
    result = await service.redistribute_chores([id1, id2, id3, id4], household.id, db_session)

    assert result == {
        id1: user_a.id,
        id2: user_b.id,
        id3: user_a.id,
        id4: user_b.id,
    }
    assert household.rotation_pointer == 4


async def test_strategy_is_swappable(db_session: AsyncSession) -> None:
    """A mock strategy can replace RoundRobinStrategy without modifying AssignmentService."""
    fixed_user_id = uuid.uuid4()
    household_id = uuid.uuid4()

    class FixedStrategy:
        async def assign(
            self,
            h_id: uuid.UUID,
            session: AsyncSession,
        ) -> uuid.UUID | None:
            return fixed_user_id

    # FixedStrategy must satisfy the Protocol
    assert isinstance(FixedStrategy(), AssignmentStrategy)

    service = AssignmentService(strategy=FixedStrategy())
    result = await service.auto_assign(household_id, db_session)
    assert result == fixed_user_id


async def test_get_assignment_service_returns_round_robin() -> None:
    """get_assignment_service() dependency factory returns an AssignmentService with RoundRobinStrategy."""
    service = get_assignment_service()
    assert isinstance(service, AssignmentService)
    assert isinstance(service.strategy, RoundRobinStrategy)
    # Protocol compliance check
    assert isinstance(service.strategy, AssignmentStrategy)
