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
- TASK-081: flag_overdue_instances returns newly-flagged ids; reminder summary
  gathering; run_daily_job sends/skips notifications and survives delivery
  failures.
"""
import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

import httpx
import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from app.tasks.scheduler import flag_overdue_instances, generate_chore_instances
from tests.conftest import get_test_database_url, truncate_all_tables

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


# ---------------------------------------------------------------------------
# cleanup_expired_tokens tests (TASK-072)
# ---------------------------------------------------------------------------


async def test_cleanup_removes_only_expired_token_rows(db_session: AsyncSession) -> None:
    """Expired revoked/refresh token rows are purged; unexpired rows survive."""
    from datetime import timedelta

    from app.models.refresh_token import RefreshToken
    from app.models.revoked_token import RevokedToken
    from app.tasks.scheduler import cleanup_expired_tokens

    user = _make_user()
    await _flush(db_session, user)

    now = datetime.now(timezone.utc)
    expired_jti = str(uuid.uuid4())
    active_jti = str(uuid.uuid4())

    await _flush(
        db_session,
        RevokedToken(jti=expired_jti, revoked_at=now - timedelta(days=8), expires_at=now - timedelta(days=1)),
        RevokedToken(jti=active_jti, revoked_at=now, expires_at=now + timedelta(days=1)),
        RefreshToken(
            user_id=user.id,
            token_hash="e" * 64,
            created_at=now - timedelta(days=31),
            expires_at=now - timedelta(days=1),
        ),
        RefreshToken(
            user_id=user.id,
            token_hash="a" * 64,
            created_at=now,
            expires_at=now + timedelta(days=29),
        ),
    )

    await cleanup_expired_tokens(db_session)

    remaining_jtis = set(
        (
            await db_session.execute(
                select(RevokedToken.jti).where(
                    RevokedToken.jti.in_([expired_jti, active_jti])
                )
            )
        ).scalars().all()
    )
    remaining_hashes = set(
        (
            await db_session.execute(
                select(RefreshToken.token_hash).where(
                    RefreshToken.user_id == user.id
                )
            )
        ).scalars().all()
    )

    assert remaining_jtis == {active_jti}
    assert remaining_hashes == {"a" * 64}


# ---------------------------------------------------------------------------
# TASK-073: backfill cap and batch assignment
# ---------------------------------------------------------------------------


async def test_backfill_capped_at_grace_days(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A daily definition whose first_due_date is 30 days old generates only
    instances from today - GRACE_DAYS (default 3) onward — no overdue flood."""
    fake_today = date(2024, 1, 1)
    old_first_due = fake_today - timedelta(days=30)  # 2023-12-02

    _, user_id, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=old_first_due,
        recurrence_rule={"interval_unit": "days", "interval_n": 1},
    )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    await generate_chore_instances(db_session)

    result = await db_session.execute(
        select(ChoreInstance)
        .where(ChoreInstance.definition_id == definition.id)
        .order_by(ChoreInstance.due_date)
    )
    instances = result.scalars().all()

    # [today - 3, today + 7] inclusive → 11 daily instances, not 38.
    assert len(instances) == 11
    assert instances[0].due_date == fake_today - timedelta(days=3)
    assert instances[-1].due_date == fake_today + timedelta(days=7)
    assert all(inst.assignee_id == user_id for inst in instances)


async def test_backfill_cap_preserves_recurrence_phase(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Capping must not shift the cadence: a weekly chore first due 30 days ago
    keeps its original weekly phase (first_due + k*7), it does not restart at
    the cap boundary."""
    fake_today = date(2024, 1, 1)
    old_first_due = fake_today - timedelta(days=30)  # 2023-12-02, weekly

    _, _, definition = await _seed_recurring_setup(
        db_session,
        first_due_date=old_first_due,
        recurrence_rule={"interval_unit": "weeks", "interval_n": 1},
    )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    await generate_chore_instances(db_session)

    result = await db_session.execute(
        select(ChoreInstance)
        .where(ChoreInstance.definition_id == definition.id)
        .order_by(ChoreInstance.due_date)
    )
    due_dates = [inst.due_date for inst in result.scalars().all()]

    # Weekly series from 2023-12-02: ... 12-23, 12-30, 01-06, 01-13 ...
    # Window [12-29, 01-08] keeps exactly 12-30 and 01-06.
    assert due_dates == [
        old_first_due + timedelta(days=28),  # 2023-12-30
        old_first_due + timedelta(days=35),  # 2024-01-06
    ]


async def test_generation_uses_single_household_lock_per_run(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """All new instances of a household are assigned via ONE bulk call (one
    SELECT FOR UPDATE on the household row), never via per-instance assign()."""
    from app.services.assignment import AssignmentService, RoundRobinStrategy

    user = _make_user()
    user_b = _make_user()
    household = _make_household()
    await _flush(db_session, user, user_b, household)
    await _flush(
        db_session,
        _make_membership(household.id, user.id),
        HouseholdMembership(
            id=uuid.uuid4(),
            household_id=household.id,
            user_id=user_b.id,
            role="member",
            joined_at=datetime(2024, 1, 1, 0, 0, 1, tzinfo=timezone.utc),
            is_active=True,
        ),
    )
    # Two daily definitions → 2 * 8 = 16 new instances for this household.
    for _ in range(2):
        await _flush(
            db_session,
            _make_recurring_definition(
                household.id, _FAKE_TODAY, {"interval_unit": "days", "interval_n": 1}
            ),
        )
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)

    bulk_calls: list[tuple] = []
    orig_bulk = AssignmentService.redistribute_chores_bulk

    async def spy_bulk(self, chore_instance_ids, household_id, session):
        bulk_calls.append((household_id, len(chore_instance_ids)))
        return await orig_bulk(self, chore_instance_ids, household_id, session)

    async def fail_assign(self, household_id, session):
        raise AssertionError("per-instance assign() must not be used by the scheduler")

    monkeypatch.setattr(AssignmentService, "redistribute_chores_bulk", spy_bulk)
    monkeypatch.setattr(RoundRobinStrategy, "assign", fail_assign)

    await generate_chore_instances(db_session)

    # Exactly one bulk (single-lock) call for the household, covering all 16 rows.
    assert bulk_calls == [(household.id, 16)]

    await db_session.refresh(household)
    assert household.rotation_pointer == 16

    result = await db_session.execute(
        select(ChoreInstance).where(ChoreInstance.household_id == household.id)
    )
    instances = result.scalars().all()
    assert len(instances) == 16
    # Round-robin split between the two members.
    per_member = {user.id: 0, user_b.id: 0}
    for inst in instances:
        per_member[inst.assignee_id] += 1
    assert per_member == {user.id: 8, user_b.id: 8}


# ---------------------------------------------------------------------------
# TASK-081: notification summary gathering
# ---------------------------------------------------------------------------


async def test_flag_overdue_returns_newly_flagged_ids(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """flag_overdue_instances returns exactly the ids it transitioned this call."""
    household = _make_household()
    user = _make_user()
    await _flush(db_session, household, user)

    fake_today = date(2024, 1, 10)
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    definition = _make_recurring_definition(
        household.id, fake_today, {"interval_unit": "days", "interval_n": 1}
    )
    await _flush(db_session, definition)

    newly_overdue = ChoreInstance(
        id=uuid.uuid4(),
        definition_id=definition.id,
        household_id=household.id,
        assignee_id=user.id,
        due_date=fake_today - timedelta(days=1),
        status="pending",
    )
    already_complete = ChoreInstance(
        id=uuid.uuid4(),
        definition_id=definition.id,
        household_id=household.id,
        assignee_id=user.id,
        due_date=fake_today - timedelta(days=2),
        status="complete",
    )
    still_future = ChoreInstance(
        id=uuid.uuid4(),
        definition_id=definition.id,
        household_id=household.id,
        assignee_id=user.id,
        due_date=fake_today + timedelta(days=1),
        status="pending",
    )
    await _flush(db_session, newly_overdue, already_complete, still_future)

    flagged_ids = await flag_overdue_instances(db_session)

    assert flagged_ids == [newly_overdue.id]

    # A second run flags nothing new — the instance is already 'overdue', not 'pending'.
    flagged_again = await flag_overdue_instances(db_session)
    assert flagged_again == []


async def test_gather_reminder_summaries_due_today_and_newly_overdue(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.tasks.scheduler import _gather_reminder_summaries

    household = _make_household()
    user = _make_user()
    user.display_name = "Alice"
    await _flush(db_session, household, user)

    fake_today = date(2024, 1, 10)
    monkeypatch.setattr("app.tasks.scheduler._today", lambda: fake_today)

    definition = _make_recurring_definition(
        household.id, fake_today, {"interval_unit": "days", "interval_n": 1}
    )
    definition.title = "Vacuum"
    await _flush(db_session, definition)

    due_today = ChoreInstance(
        id=uuid.uuid4(),
        definition_id=definition.id,
        household_id=household.id,
        assignee_id=user.id,
        due_date=fake_today,
        status="pending",
    )
    now_overdue = ChoreInstance(
        id=uuid.uuid4(),
        definition_id=definition.id,
        household_id=household.id,
        assignee_id=user.id,
        due_date=fake_today - timedelta(days=1),
        status="overdue",  # already transitioned by flag_overdue_instances
    )
    unrelated_future = ChoreInstance(
        id=uuid.uuid4(),
        definition_id=definition.id,
        household_id=household.id,
        assignee_id=user.id,
        due_date=fake_today + timedelta(days=3),
        status="pending",
    )
    await _flush(db_session, due_today, now_overdue, unrelated_future)

    summaries = await _gather_reminder_summaries(db_session, [now_overdue.id])

    assert len(summaries) == 1
    summary = summaries[0]
    assert summary.household_id == household.id
    assert summary.household_name == household.name
    assert summary.due_today == [("Vacuum", "Alice")]
    assert summary.newly_overdue == [("Vacuum", "Alice")]


async def test_gather_reminder_summaries_empty_when_nothing_due(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.tasks.scheduler import _gather_reminder_summaries

    monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)

    summaries = await _gather_reminder_summaries(db_session, [])

    assert summaries == []


# ---------------------------------------------------------------------------
# TASK-081: run_daily_job notification integration
#
# run_daily_job opens its own AsyncSessionLocal rather than accepting a
# session, so these tests patch app.tasks.scheduler.AsyncSessionLocal to a
# session factory bound to the real test database (same pattern as
# tests/test_cli.py's _run_reset helper) instead of using the db_session
# fixture's rolled-back transaction.
# ---------------------------------------------------------------------------


async def test_run_daily_job_sends_one_notification_per_household(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    url = get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    await truncate_all_tables(engine)
    session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    try:
        household = _make_household()
        user = _make_user()
        user.display_name = "Alice"
        async with session_factory() as seed_session:
            await _flush(seed_session, household, user)
            await _flush(seed_session, _make_membership(household.id, user.id))
            definition = _make_recurring_definition(
                household.id, _FAKE_TODAY, {"interval_unit": "days", "interval_n": 1}
            )
            definition.title = "Vacuum"
            await _flush(seed_session, definition)
            await seed_session.commit()

        monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)
        monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")
        monkeypatch.setattr(settings, "NOTIFY_KIND", "ntfy")
        monkeypatch.setattr(settings, "NOTIFY_TOKEN", None)

        captured: list[tuple] = []

        async def fake_post(self, url, **kwargs):
            captured.append((url, kwargs))
            return httpx.Response(200, request=httpx.Request("POST", url))

        monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

        with patch("app.tasks.scheduler.AsyncSessionLocal", session_factory):
            from app.tasks.scheduler import run_daily_job

            await run_daily_job()

        assert len(captured) == 1
        notified_url, kwargs = captured[0]
        assert notified_url == "https://ntfy.example.com/chores"
        assert b"Vacuum" in kwargs["content"]
        assert household.name.encode("utf-8") in kwargs["headers"]["Title"]

        # generate_chore_instances still ran and committed as normal.
        async with session_factory() as check_session:
            result = await check_session.execute(
                select(ChoreInstance).where(ChoreInstance.household_id == household.id)
            )
            assert len(result.scalars().all()) == 8  # today .. today+7 daily
    finally:
        await truncate_all_tables(engine)
        await engine.dispose()


async def test_run_daily_job_skips_notification_when_notify_url_unset(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    url = get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    await truncate_all_tables(engine)
    session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    try:
        household = _make_household()
        user = _make_user()
        async with session_factory() as seed_session:
            await _flush(seed_session, household, user)
            await _flush(seed_session, _make_membership(household.id, user.id))
            definition = _make_recurring_definition(
                household.id, _FAKE_TODAY, {"interval_unit": "days", "interval_n": 1}
            )
            await _flush(seed_session, definition)
            await seed_session.commit()

        monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)
        monkeypatch.setattr(settings, "NOTIFY_URL", None)

        async def unexpected_post(self, *args, **kwargs):
            raise AssertionError("no HTTP calls should be made when NOTIFY_URL is unset")

        monkeypatch.setattr(httpx.AsyncClient, "post", unexpected_post)

        with patch("app.tasks.scheduler.AsyncSessionLocal", session_factory):
            from app.tasks.scheduler import run_daily_job

            await run_daily_job()  # must not raise, must not call httpx

        async with session_factory() as check_session:
            result = await check_session.execute(
                select(ChoreInstance).where(ChoreInstance.household_id == household.id)
            )
            assert len(result.scalars().all()) == 8
    finally:
        await truncate_all_tables(engine)
        await engine.dispose()


async def test_run_daily_job_survives_notification_delivery_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Acceptance criterion: notification failure never aborts instance generation."""
    url = get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    await truncate_all_tables(engine)
    session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    try:
        household = _make_household()
        user = _make_user()
        async with session_factory() as seed_session:
            await _flush(seed_session, household, user)
            await _flush(seed_session, _make_membership(household.id, user.id))
            definition = _make_recurring_definition(
                household.id, _FAKE_TODAY, {"interval_unit": "days", "interval_n": 1}
            )
            await _flush(seed_session, definition)
            await seed_session.commit()

        monkeypatch.setattr("app.tasks.scheduler._today", lambda: _FAKE_TODAY)
        monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")

        async def failing_post(self, *args, **kwargs):
            raise httpx.ConnectError("notify server unreachable")

        monkeypatch.setattr(httpx.AsyncClient, "post", failing_post)

        with patch("app.tasks.scheduler.AsyncSessionLocal", session_factory):
            from app.tasks.scheduler import run_daily_job

            await run_daily_job()  # must not raise despite the notify failure

        async with session_factory() as check_session:
            result = await check_session.execute(
                select(ChoreInstance).where(ChoreInstance.household_id == household.id)
            )
            # Instance generation committed successfully before the (failed)
            # notification attempt, which happens after commit.
            assert len(result.scalars().all()) == 8
    finally:
        await truncate_all_tables(engine)
        await engine.dispose()
