"""Background scheduler for recurring chore instance generation and overdue flagging.

TASK-012: Provides generate_chore_instances, flag_overdue_instances, run_daily_job,
start_scheduler, and stop_scheduler. Integrate with FastAPI's lifespan event — see the
comment block at the bottom of this module for the exact snippet to add to main.py.
"""
from datetime import date, datetime, timedelta, timezone

import structlog
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from dateutil.relativedelta import relativedelta
from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.session import AsyncSessionLocal
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.services.assignment import AssignmentService, RoundRobinStrategy

logger = structlog.get_logger()

_scheduler: AsyncIOScheduler | None = None


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
) -> list[date]:
    """Return every due date in [first_due_date, horizon] for the given rule.

    recurrence_rule shape::

        {"interval_unit": "days" | "weeks" | "months", "interval_n": int}

    Uses ``timedelta`` for days/weeks and ``dateutil.relativedelta`` for months
    so that month-end arithmetic is handled correctly.
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

    Auto-assignment is applied to each new instance via ``RoundRobinStrategy``.
    """
    today = _today()
    horizon = today + timedelta(days=settings.INSTANCE_GENERATION_DAYS_AHEAD)

    # Load all active recurring definitions in a single query.
    result = await session.execute(
        select(ChoreDefinition).where(
            ChoreDefinition.chore_type == "recurring",
            ChoreDefinition.is_active == True,  # noqa: E712
        )
    )
    definitions = result.scalars().all()

    assignment_service = AssignmentService(RoundRobinStrategy())

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
        )

        for due_date in due_dates:
            if (definition.id, due_date) in existing_pairs:
                continue  # already exists — idempotent guard

            assignee_id = await assignment_service.auto_assign(
                definition.household_id, session
            )

            instance = ChoreInstance(
                definition_id=definition.id,
                household_id=definition.household_id,
                assignee_id=assignee_id,
                assigned_manually=False,
                due_date=due_date,
                status="pending",
            )
            session.add(instance)

            # Track locally so a second iteration within the same call cannot
            # re-create the same (definition, date) pair before the flush hits
            # the database.
            existing_pairs.add((definition.id, due_date))

    await session.flush()


async def flag_overdue_instances(session: AsyncSession) -> None:
    """Batch-update pending ChoreInstances whose due_date has already passed.

    Only rows with ``status='pending'`` are touched.  Instances that are
    ``'complete'`` or ``'cancelled'`` are never modified.
    """
    today = _today()
    await session.execute(
        update(ChoreInstance)
        .where(
            ChoreInstance.status == "pending",
            ChoreInstance.due_date < today,
        )
        .values(status="overdue")
        .execution_options(synchronize_session=False)
    )


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
            await flag_overdue_instances(session)
            await session.commit()
            logger.info("scheduler.daily_job.completed")
        except Exception:
            await session.rollback()
            logger.exception("Daily scheduler job failed; all changes rolled back")
            raise


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
