"""Tests for app/tasks/scheduler.py (TASK-012).

Covers:
- generate_chore_instances: creates instances within the horizon for a recurring chore
- generate_chore_instances: is idempotent across multiple same-day runs
- generate_chore_instances: ignores inactive definitions
- generate_chore_instances: handles interval_unit='weeks' and 'months'
- flag_overdue_instances: marks pending + past-due instances as 'overdue'
- flag_overdue_instances: leaves 'complete' and 'cancelled' instances untouched
- flag_overdue_instances: leaves future pending instances as 'pending'
- combined workflow: generate then flag produces expected status transitions
"""
import uuid
from datetime import date, datetime, timezone

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from app.tasks.scheduler import flag_overdue_instances, generate_chore_instances

# ---------------------------------------------------------------------------
# Constants and builder helpers
# ---------------------------------------------------------------------------

_BASE_TIME = datetime(2024, 1, 1, 0, 0, 0, tzinfo=timezone.utc)

# "Today" used by the generate_* tests (monkeypatched into the module).
_FAKE_TODAY = date(2024, 1, 1)

# Horizon with default INSTANCE_GENERATION_DAYS_AHEAD=7: 2024-01-08
_FAKE_HORIZON = date(2024, 1, 8)


def _make_user() -> User:
    uid = uuid.uuid4()
    return User(
        id=uid,
        email=f"user-{uid}@test.example",
        display_name=f"User {uid}",
        password_hash="hashed_pw",
    )


def _make_household() -> Household:
    return Household(
        id=uuid.uuid4(),
        name="Test Household",
        rotation_pointer=0,
    )


def _make_membership(household_id: uuid.UUID, user_id: uuid.UUID) -> HouseholdMembership:
    return HouseholdMembership(
        id=uuid.uuid4(),
        household_id=household_id,
        user_id=user_id,
        role="member",
        joined_at=_BASE_TIME,
        is_active=True,
    )


def _make_recurring_definition(
    household_id: uuid.UUID,
    first_due_date: date,
    recurrence_rule: dict,
    is_active: bool = True,
) -> ChoreDefinition:
    return ChoreDefinition(
        id=uuid.uuid4(),
        household_id=household_id,
        title="Weekly Vacuum",
        category="living_room",
        effort_level="medium",
        chore_type="recurring",
        recurrence_rule=recurrence_rule,
        first_due_date=first_due_date,
        is_active=is_active,
    )


async def _flush(session: AsyncSession, *objs) -> None:
    """Add objects to the session and flush so they are visible within the transaction."""
    for obj in objs:
        session.add(obj)
    await session.flush()


async def _seed_recurring_setup(
    session: AsyncSession,
    first_due_date: date,
    recurrence_rule: dict,
    active: bool = True,
) -> tuple[uuid.UUID, uuid.UUID, ChoreDefinition]:
    """Seed User + Household + active Membership + recurring ChoreDefinition.

    Returns ``(household_id, user_id, definition)``.
    """
    user = _make_user()
    household = _make_household()
    await _flush(session, user, household)

    membership = _make_membership(household.id, user.id)
    await _flush(session, membership)

    definition = _make_recurring_definition(
        household.id, first_due_date, recurrence_rule, is_active=active
    )
    await _flush(session, definition)

    return household.id, user.id, definition


# ---------------------------------------------------------------------------
# generate_chore_instances tests
# ---------------------------------------------------------------------------


async def test_generate_instances_creates_upcoming_instances(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """generate_chore_instances inserts ChoreInstance rows within the horizon.

    With first_due_date=Jan 1, interval=7 days, today=Jan 1, and a 7-day
    horizon (Jan 8), two dates are in-scope: Jan 1 and Jan 8.
    """
    household_id, user_id, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=_FAKE_TODAY,
        recurrence_rule={"interval_unit": "days", "interval_n": 7},
    )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)

    await generate_chore_instances(db_session)

    result = await db_session.execute(
        select(ChoreInstance)
        .where(ChoreInstance.definition_id == definition.id)
        .order_by(ChoreInstance.due_date)
    )
    instances = result.scalars().all()

    assert len(instances) == 2
    assert instances[0].due_date == _FAKE_TODAY          # Jan 1
    assert instances[1].due_date == _FAKE_HORIZON        # Jan 8

    for inst in instances:
        assert inst.assignee_id == user_id, "Should be auto-assigned to the single member"
        assert inst.assigned_manually is False
        assert inst.status == "pending"
        assert inst.household_id == household_id


async def test_generate_instances_is_idempotent(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Calling generate_chore_instances twice on the same day must not create duplicates."""
    _, _, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=_FAKE_TODAY,
        recurrence_rule={"interval_unit": "days", "interval_n": 7},
    )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)

    await generate_chore_instances(db_session)
    await generate_chore_instances(db_session)  # second call — must be a no-op

    result = await db_session.execute(
        select(ChoreInstance).where(ChoreInstance.definition_id == definition.id)
    )
    instances = result.scalars().all()
    assert len(instances) == 2, "Second run must not create extra rows"


async def test_generate_instances_skips_inactive_definitions(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Inactive ChoreDefinitions (is_active=False) are ignored entirely."""
    _, _, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=_FAKE_TODAY,
        recurrence_rule={"interval_unit": "days", "interval_n": 1},
        active=False,
    )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)

    await generate_chore_instances(db_session)

    result = await db_session.execute(
        select(ChoreInstance).where(ChoreInstance.definition_id == definition.id)
    )
    instances = result.scalars().all()
    assert len(instances) == 0, "No instances should be created for inactive definitions"


async def test_generate_instances_handles_weeks_interval(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """interval_unit='weeks' with interval_n=1 produces the same dates as 7-day spacing."""
    _, _, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=_FAKE_TODAY,
        recurrence_rule={"interval_unit": "weeks", "interval_n": 1},
    )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)

    await generate_chore_instances(db_session)

    result = await db_session.execute(
        select(ChoreInstance).where(ChoreInstance.definition_id == definition.id)
    )
    instances = result.scalars().all()
    assert len(instances) == 2  # Jan 1, Jan 8 — same as the 7-day-interval case


async def test_generate_instances_handles_months_interval(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """interval_unit='months' generates only the first_due_date within a 7-day window."""
    _, _, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=_FAKE_TODAY,
        recurrence_rule={"interval_unit": "months", "interval_n": 1},
    )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)

    await generate_chore_instances(db_session)

    result = await db_session.execute(
        select(ChoreInstance).where(ChoreInstance.definition_id == definition.id)
    )
    instances = result.scalars().all()
    # Feb 1 is outside the 7-day horizon; only Jan 1 fits.
    assert len(instances) == 1
    assert instances[0].due_date == _FAKE_TODAY


# ---------------------------------------------------------------------------
# flag_overdue_instances tests
# ---------------------------------------------------------------------------


async def test_flag_overdue_marks_pending_past_due(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Pending instances whose due_date < today are transitioned to 'overdue'."""
    household = _make_household()
    await _flush(db_session, household)

    instance = ChoreInstance(
        household_id=household.id,
        definition_id=None,    # nullable — no definition required for this test
        due_date=date(2024, 1, 1),
        status="pending",
        assigned_manually=False,
    )
    await _flush(db_session, instance)

    fake_today = date(2024, 1, 5)
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    await flag_overdue_instances(db_session)
    await db_session.refresh(instance)

    assert instance.status == "overdue"


async def test_flag_overdue_does_not_change_completed_instances(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Completed instances must stay 'complete' even when their due_date is in the past."""
    household = _make_household()
    await _flush(db_session, household)

    instance = ChoreInstance(
        household_id=household.id,
        definition_id=None,
        due_date=date(2024, 1, 1),
        status="complete",
        completed_at=datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc),
        assigned_manually=False,
    )
    await _flush(db_session, instance)

    fake_today = date(2024, 1, 5)
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    await flag_overdue_instances(db_session)
    await db_session.refresh(instance)

    assert instance.status == "complete"


async def test_flag_overdue_does_not_change_cancelled_instances(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Cancelled instances must stay 'cancelled' even when their due_date is in the past."""
    household = _make_household()
    await _flush(db_session, household)

    instance = ChoreInstance(
        household_id=household.id,
        definition_id=None,
        due_date=date(2024, 1, 1),
        status="cancelled",
        assigned_manually=False,
    )
    await _flush(db_session, instance)

    fake_today = date(2024, 1, 5)
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    await flag_overdue_instances(db_session)
    await db_session.refresh(instance)

    assert instance.status == "cancelled"


async def test_flag_overdue_leaves_future_pending_unchanged(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Pending instances with a future due_date remain 'pending'."""
    household = _make_household()
    await _flush(db_session, household)

    instance = ChoreInstance(
        household_id=household.id,
        definition_id=None,
        due_date=date(2024, 1, 10),   # future date
        status="pending",
        assigned_manually=False,
    )
    await _flush(db_session, instance)

    fake_today = date(2024, 1, 5)     # before the due date
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    await flag_overdue_instances(db_session)
    await db_session.refresh(instance)

    assert instance.status == "pending"


# ---------------------------------------------------------------------------
# Combined workflow test
# ---------------------------------------------------------------------------


async def test_generate_then_flag_produces_correct_statuses(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Full workflow: generate on Jan 1, advance clock to Jan 5, flag overdue.

    Expected outcome:
    - Jan 1 instance (past-due)  → 'overdue'
    - Jan 8 instance (future)    → 'pending'
    """
    _, _, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=_FAKE_TODAY,
        recurrence_rule={"interval_unit": "days", "interval_n": 7},
    )

    # Step 1: generate instances with today = Jan 1
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)
    await generate_chore_instances(db_session)

    # Step 2: advance clock to Jan 5 and flag overdue
    fake_day5 = date(2024, 1, 5)
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_day5)
    await flag_overdue_instances(db_session)

    result = await db_session.execute(
        select(ChoreInstance)
        .where(ChoreInstance.definition_id == definition.id)
        .order_by(ChoreInstance.due_date)
    )
    instances = result.scalars().all()

    assert len(instances) == 2

    jan1_inst = instances[0]
    assert jan1_inst.due_date == _FAKE_TODAY
    assert jan1_inst.status == "overdue"

    jan8_inst = instances[1]
    assert jan8_inst.due_date == _FAKE_HORIZON
    assert jan8_inst.status == "pending"
