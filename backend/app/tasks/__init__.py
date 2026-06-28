"""Background task package.

Exports the public scheduler interface so that tests and main.py can import
directly from ``app.tasks`` without knowing the internal module layout.
"""
from app.tasks.scheduler import (
    flag_overdue_instances,
    generate_chore_instances,
    run_daily_job,
    start_scheduler,
    stop_scheduler,
)

__all__ = [
    "run_daily_job",
    "generate_chore_instances",
    "flag_overdue_instances",
    "start_scheduler",
    "stop_scheduler",
]
