"""Background scheduler for recurring chore instance generation and overdue flagging.

TASK-012: Provides generate_chore_instances, flag_overdue_instances, run_daily_job,
start_scheduler, and stop_scheduler. Integrate with FastAPI's lifespan event — see the
comment block at the bottom of this module for the exact snippet to add to main.py.
"""
import uuid
from datetime import date, datetime, timedelta, timezone

import structlog
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from dateutil.relativedelta import relativedelta
from sqlalchemy import delete, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.session import AsyncSessionLocal
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.refresh_token import RefreshToken
from app.models.revoked_token import RevokedToken
from app.models.user import User
from app.services.assignment import AssignmentService, RoundRobinStrategy
from app.services.notifications import HouseholdReminderSummary, send_daily_reminders

logger = structlog.get_logger()

_scheduler: AsyncIOScheduler | None = None

# If the process was suspended (or the event loop stalled) across the scheduled
# midnight run, still fire the job as long as we are within this many seconds
# of the scheduled time (TASK-073).
MISFIRE_GRACE_SECONDS = 6 * 3600


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _today() -> date:
    """Return today's date in UTC.

    Isolated into its own function so that test suites can monkeypatch it
    without touching the built-in datetime class.  Using UTC prevents
    off-by-one errors near midnight when the server timezone is not UTC.
    """
    return datetime.now(timezone.utc).date()


def _compute_due_dates(
    first_due_date: date,
    recurrence_rule: dict,
    horizon: date,
    floor: date | None = None,
) -> list[date]:
    """Return every due date in [first_due_date, horizon] for the given rule.

    recurrence_rule shape::

        {"interval_unit": "days" | "weeks" | "months", "interval_n": int}

    Uses ``timedelta`` for days/weeks and ``dateutil.relativedelta`` for months
    so that month-end arithmetic is handled correctly.

    When ``floor`` is given, due dates earlier than it are skipped (backfill
    cap, TASK-073).  Stepping still starts at ``first_due_date`` so the
    recurrence phase is preserved — capping never shifts the cadence.
    """
    interval_unit: str = recurrence_rule.get("interval_unit", "days")
    interval_n: int = int(recurrence_rule.get("interval_n", 1))

    if interval_unit == "days":
        delta = timedelta(days=interval_n)
    elif interval_unit == "weeks":
        delta = timedelta(weeks=interval_n)
    elif interval_unit == "months":
        delta = relativedelta(months=interval_n)
    else:
        logger.warning(
            "Unsupported recurrence_rule interval_unit %r; skipping definition.",
            interval_unit,
        )
        return []

    due_dates: list[date] = []
    current = first_due_date
    while current <= horizon:
        if floor is None or current >= floor:
            due_dates.append(current)
        current = current + delta

    return due_dates


# ---------------------------------------------------------------------------
# Core task functions
# ---------------------------------------------------------------------------


async def generate_chore_instances(session: AsyncSession) -> None:
    """Generate ChoreInstance rows for all active recurring definitions.

    Computes every due date from each definition's ``first_due_date`` up to
    ``today + INSTANCE_GENERATION_DAYS_AHEAD`` and inserts a new ChoreInstance
    for any date that does not already have one.  Running this function multiple
    times on the same day is **idempotent** — no duplicate rows are ever created.

    TASK-073 hardening:
    - Backfill is capped at ``max(first_due_date, today - GRACE_DAYS)`` so that
      extended downtime (or a definition created with an old date) cannot flood
      a household with dozens of instantly-overdue instances.
    - New instances are batch-assigned with a single household row lock per
      household per run (``AssignmentService.redistribute_chores_bulk``) instead
      of one ``SELECT FOR UPDATE`` per instance.
    """
    today = _today()
    horizon = today + timedelta(days=settings.INSTANCE_GENERATION_DAYS_AHEAD)
    backfill_floor = today - timedelta(days=settings.GRACE_DAYS)

    # Load all active recurring definitions in a single query.
    result = await session.execute(
        select(ChoreDefinition).where(
            ChoreDefinition.chore_type == "recurring",
            ChoreDefinition.is_active == True,  # noqa: E712
        )
    )
    definitions = result.scalars().all()

    # Single bulk query — fetch all (definition_id, due_date) pairs that already
    # have a ChoreInstance for any of the active definitions.  This replaces the
    # previous per-definition SELECT inside the loop (N round-trips → 1).
    if definitions:
        existing_result = await session.execute(
            select(ChoreInstance.definition_id, ChoreInstance.due_date)
            .where(ChoreInstance.definition_id.in_([d.id for d in definitions]))
        )
        existing_pairs: set[tuple] = set(existing_result.all())
    else:
        existing_pairs = set()

    # Collect new (unassigned) instances grouped by household so assignment can
    # be batched with one lock acquisition per household below.
    new_by_household: dict[uuid.UUID, list[ChoreInstance]] = {}

    for definition in definitions:
        if not definition.recurrence_rule:
            logger.warning(
                "ChoreDefinition %s has chore_type='recurring' but recurrence_rule is "
                "NULL; skipping.",
                definition.id,
            )
            continue

        due_dates = _compute_due_dates(
            definition.first_due_date,
            definition.recurrence_rule,
            horizon,
            floor=backfill_floor,
        )

        for due_date in due_dates:
            if (definition.id, due_date) in existing_pairs:
                continue  # already exists — idempotent guard

            instance = ChoreInstance(
                id=uuid.uuid4(),
                definition_id=definition.id,
                household_id=definition.household_id,
                assignee_id=None,
                assigned_manually=False,
                due_date=due_date,
                status="pending",
            )
            session.add(instance)
            new_by_household.setdefault(definition.household_id, []).append(instance)

            # Track locally so a second iteration within the same call cannot
            # re-create the same (definition, date) pair before the flush hits
            # the database.
            existing_pairs.add((definition.id, due_date))

    # Batch auto-assignment: one SELECT FOR UPDATE on the household row per
    # household per run, cycling members in Python and writing the rotation
    # pointer once (same pattern as AssignmentService.redistribute_chores_bulk).
    assignment_service = AssignmentService(RoundRobinStrategy())
    for household_id, instances in new_by_household.items():
        assignments = await assignment_service.redistribute_chores_bulk(
            [inst.id for inst in instances], household_id, session
        )
        for inst in instances:
            inst.assignee_id = assignments.get(inst.id)

    await session.flush()


async def flag_overdue_instances(session: AsyncSession) -> list[uuid.UUID]:
    """Batch-update pending ChoreInstances whose due_date has already passed.

    Only rows with ``status='pending'`` are touched.  Instances that are
    ``'complete'`` or ``'cancelled'`` are never modified.

    Returns the ids of the instances that were flagged *in this call* (i.e.
    just transitioned pending -> overdue) — used by the notification step
    (TASK-081) to distinguish "newly overdue" from instances that were
    already overdue before this run.
    """
    today = _today()
    result = await session.execute(
        update(ChoreInstance)
        .where(
            ChoreInstance.status == "pending",
            ChoreInstance.due_date < today,
        )
        .values(status="overdue")
        .execution_options(synchronize_session=False)
        .returning(ChoreInstance.id)
    )
    return [row[0] for row in result.all()]


async def cleanup_expired_tokens(session: AsyncSession) -> None:
    """Delete expired ``revoked_tokens`` and ``refresh_tokens`` rows.

    Both tables grow forever otherwise: every login adds a ``refresh_tokens``
    row and every logout adds a ``revoked_tokens`` row.  Once a row's
    ``expires_at`` is in the past it no longer serves any purpose — an expired
    JWT is already rejected on ``exp`` alone, and an expired refresh token is
    already rejected by the refresh endpoint — so it is safe to purge.
    """
    now = datetime.now(timezone.utc)
    revoked_result = await session.execute(
        delete(RevokedToken).where(RevokedToken.expires_at < now)
    )
    refresh_result = await session.execute(
        delete(RefreshToken).where(RefreshToken.expires_at < now)
    )
    logger.info(
        "scheduler.token_cleanup",
        revoked_tokens_deleted=revoked_result.rowcount,
        refresh_tokens_deleted=refresh_result.rowcount,
    )


async def _gather_reminder_summaries(
    session: AsyncSession, newly_overdue_ids: list[uuid.UUID]
) -> list[HouseholdReminderSummary]:
    """Build per-household due-today/newly-overdue summaries (TASK-081).

    Only called when ``NOTIFY_URL`` is configured, so a disabled feature
    costs zero extra queries.  Must run *before* ``session.commit()`` so it
    sees the statuses ``flag_overdue_instances`` just wrote in this same
    transaction (that update uses ``synchronize_session=False``, so a fresh
    SELECT — not the ORM identity map — is what reflects it).
    """
    today = _today()

    base_query = (
        select(
            ChoreInstance.household_id,
            Household.name,
            ChoreDefinition.title,
            User.display_name,
        )
        .select_from(ChoreInstance)
        .join(Household, ChoreInstance.household_id == Household.id)
        .outerjoin(ChoreDefinition, ChoreInstance.definition_id == ChoreDefinition.id)
        .outerjoin(User, ChoreInstance.assignee_id == User.id)
    )

    due_today_rows = (
        await session.execute(
            base_query.where(
                ChoreInstance.status == "pending",
                ChoreInstance.due_date == today,
            )
        )
    ).all()

    overdue_rows: list = []
    if newly_overdue_ids:
        overdue_rows = (
            await session.execute(base_query.where(ChoreInstance.id.in_(newly_overdue_ids)))
        ).all()

    summaries: dict[uuid.UUID, HouseholdReminderSummary] = {}

    def _summary_for(household_id: uuid.UUID, household_name: str) -> HouseholdReminderSummary:
        if household_id not in summaries:
            summaries[household_id] = HouseholdReminderSummary(
                household_id=household_id, household_name=household_name
            )
        return summaries[household_id]

    for household_id, household_name, chore_title, assignee_name in due_today_rows:
        summary = _summary_for(household_id, household_name)
        summary.due_today.append((chore_title or "Chore", assignee_name or "Unassigned"))

    for household_id, household_name, chore_title, assignee_name in overdue_rows:
        summary = _summary_for(household_id, household_name)
        summary.newly_overdue.append((chore_title or "Chore", assignee_name or "Unassigned"))

    return list(summaries.values())


async def run_daily_job() -> None:
    """Open a database session, run both scheduler tasks, and commit.

    This is the function registered with APScheduler.  It acquires its own
    ``AsyncSessionLocal`` session so that it is fully independent of any
    HTTP-request sessions.

    A PostgreSQL advisory lock (``pg_try_advisory_xact_lock``) is acquired at
    the start of the transaction so that only one worker executes the job when
    the application is deployed with multiple Uvicorn workers.
    """
    logger.info("scheduler.daily_job.started")
    reminder_summaries: list[HouseholdReminderSummary] = []
    async with AsyncSessionLocal() as session:
        # Try to acquire advisory lock — only one worker runs the job.
        # The lock is held for the duration of the transaction and released
        # automatically on commit or rollback.
        result = await session.execute(
            text("SELECT pg_try_advisory_xact_lock(:lock_id)"),
            {"lock_id": 99_001},
        )
        if not result.scalar():
            logger.info("scheduler.daily_job.skipped", reason="lock_held_by_another_worker")
            return

        try:
            await generate_chore_instances(session)
            newly_overdue_ids = await flag_overdue_instances(session)
            await cleanup_expired_tokens(session)

            # Gather notification data (TASK-081) *inside* the transaction —
            # before commit — so it reflects this run's changes. The actual
            # HTTP delivery happens after commit, below, outside the advisory
            # lock: a slow/unreachable notify endpoint must never hold the
            # lock open and block other workers.
            if settings.NOTIFY_URL:
                reminder_summaries = await _gather_reminder_summaries(session, newly_overdue_ids)

            await session.commit()
            logger.info("scheduler.daily_job.completed")
        except Exception:
            await session.rollback()
            logger.exception("Daily scheduler job failed; all changes rolled back")
            raise

    # Best-effort: delivery failures are caught and logged inside
    # send_daily_reminders and must never fail the job (they run after the
    # job's own commit has already succeeded).
    if reminder_summaries:
        await send_daily_reminders(reminder_summaries)


# ---------------------------------------------------------------------------
# Scheduler lifecycle
# ---------------------------------------------------------------------------


def start_scheduler() -> None:
    """Create and start the APScheduler ``AsyncIOScheduler``.

    Registers a cron job that calls :func:`run_daily_job` daily at
    ``settings.SCHEDULER_RUN_HOUR:00 UTC``.

    Call this from the FastAPI lifespan startup handler — **not** at module
    import time — so that the scheduler runs inside the application's event loop.
    """
    global _scheduler
    _scheduler = AsyncIOScheduler(timezone="UTC")
    _scheduler.add_job(
        run_daily_job,
        trigger="cron",
        hour=settings.SCHEDULER_RUN_HOUR,
        minute=0,
        id="daily_chore_scheduler",
        replace_existing=True,
        misfire_grace_time=MISFIRE_GRACE_SECONDS,
        coalesce=True,
    )
    _scheduler.start()
    logger.info(
        "APScheduler started; daily chore job registered at %02d:00 UTC",
        settings.SCHEDULER_RUN_HOUR,
    )


def stop_scheduler() -> None:
    """Shut down the APScheduler gracefully.

    Call this from the FastAPI lifespan shutdown handler.
    """
    global _scheduler
    if _scheduler is not None and _scheduler.running:
        _scheduler.shutdown(wait=False)
        logger.info("APScheduler stopped")
        _scheduler = None
