"""Tests for scheduler resilience at application startup (TASK-073).

Covers:
- The lifespan handler runs run_daily_job exactly once on startup.
- A failing startup run does not prevent the app (and scheduler) from starting.
- The cron trigger is registered with a misfire grace window.
"""
import pytest

import main
from app.tasks import scheduler as scheduler_module


async def test_lifespan_runs_daily_job_once_on_startup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[int] = []

    async def fake_run_daily_job() -> None:
        calls.append(1)

    monkeypatch.setattr(main, "run_daily_job", fake_run_daily_job)
    monkeypatch.setattr(main, "start_scheduler", lambda: None)
    monkeypatch.setattr(main, "stop_scheduler", lambda: None)

    async with main.lifespan(main.app):
        assert calls == [1], "run_daily_job must run exactly once during startup"
    assert calls == [1], "shutdown must not trigger another run"


async def test_lifespan_survives_startup_job_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A DB hiccup during the startup catch-up run must not crash the app."""
    started: list[bool] = []

    async def failing_run_daily_job() -> None:
        raise RuntimeError("database unavailable")

    monkeypatch.setattr(main, "run_daily_job", failing_run_daily_job)
    monkeypatch.setattr(main, "start_scheduler", lambda: started.append(True))
    monkeypatch.setattr(main, "stop_scheduler", lambda: None)

    async with main.lifespan(main.app):
        pass

    assert started == [True], "scheduler must still start after a failed catch-up run"


async def test_cron_job_registered_with_misfire_grace() -> None:
    """start_scheduler registers the daily job with a ~6h misfire grace window."""
    scheduler_module.start_scheduler()
    try:
        job = scheduler_module._scheduler.get_job("daily_chore_scheduler")
        assert job is not None
        assert job.misfire_grace_time == scheduler_module.MISFIRE_GRACE_SECONDS
        assert scheduler_module.MISFIRE_GRACE_SECONDS == 6 * 3600
        assert job.coalesce is True
    finally:
        scheduler_module.stop_scheduler()
