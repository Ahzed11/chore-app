"""Chore reminder notifications via ntfy / Gotify webhook (TASK-081).

Optional feature: entirely disabled unless ``settings.NOTIFY_URL`` is set.
When enabled, :func:`send_daily_reminders` (called from the scheduler's
``run_daily_job`` after generation/flagging has committed) posts one summary
notification per household listing chores due today and chores that just
became overdue, with assignee display names.

Two backends are supported via ``settings.NOTIFY_KIND`` (default ``"ntfy"``):

- ``"ntfy"``: POST the plain-text message body to the configured topic URL
  (``NOTIFY_URL``), with the title in the ``Title`` header and, if
  ``NOTIFY_TOKEN`` is set, a ``Bearer`` ``Authorization`` header. The title is
  sent as raw UTF-8 bytes (not a ``str``) because household/chore names may
  contain non-ASCII characters and HTTP header values are otherwise
  restricted to ASCII by httpx; ntfy's server assumes UTF-8 for header
  values, so this round-trips correctly.
- ``"gotify"``: POST a JSON body ``{"title", "message", "priority"}`` to
  ``{NOTIFY_URL}/message``, with ``NOTIFY_TOKEN`` (if set) as the ``token``
  query parameter — Gotify's own auth convention for its message API.

Delivery failures (network errors, non-2xx responses, timeouts) are caught,
logged, and never propagate — a broken or unreachable notification endpoint
must never fail the nightly scheduler job.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field

import httpx
import structlog

from app.core.config import settings

logger = structlog.get_logger()


@dataclass
class HouseholdReminderSummary:
    """Due-today / newly-overdue chores for one household, for one notification."""

    household_id: uuid.UUID
    household_name: str
    # Each entry is (chore_title, assignee_display_name).
    due_today: list[tuple[str, str]] = field(default_factory=list)
    newly_overdue: list[tuple[str, str]] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return not self.due_today and not self.newly_overdue


def build_message(summary: HouseholdReminderSummary) -> tuple[str, str]:
    """Return ``(title, body)`` for a household's summary notification."""
    count_parts = []
    if summary.due_today:
        count_parts.append(f"{len(summary.due_today)} due today")
    if summary.newly_overdue:
        count_parts.append(f"{len(summary.newly_overdue)} newly overdue")
    title = f"{summary.household_name}: {', '.join(count_parts)}"

    lines: list[str] = []
    if summary.due_today:
        lines.append("Due today:")
        lines.extend(f"- {chore_title} ({assignee})" for chore_title, assignee in summary.due_today)
    if summary.newly_overdue:
        if lines:
            lines.append("")
        lines.append("Newly overdue:")
        lines.extend(
            f"- {chore_title} ({assignee})" for chore_title, assignee in summary.newly_overdue
        )
    body = "\n".join(lines)
    return title, body


async def _post_ntfy(client: httpx.AsyncClient, title: str, body: str) -> None:
    headers: dict[str, str | bytes] = {"Title": title.encode("utf-8")}
    if settings.NOTIFY_TOKEN:
        headers["Authorization"] = f"Bearer {settings.NOTIFY_TOKEN}"
    response = await client.post(settings.NOTIFY_URL, content=body.encode("utf-8"), headers=headers)
    response.raise_for_status()


async def _post_gotify(client: httpx.AsyncClient, title: str, body: str) -> None:
    url = settings.NOTIFY_URL.rstrip("/") + "/message"
    params = {"token": settings.NOTIFY_TOKEN} if settings.NOTIFY_TOKEN else None
    payload = {"title": title, "message": body, "priority": 5}
    response = await client.post(url, json=payload, params=params)
    response.raise_for_status()


async def send_household_summary(
    client: httpx.AsyncClient, summary: HouseholdReminderSummary
) -> None:
    """POST one summary notification for a household. Never raises."""
    if summary.is_empty:
        return
    title, body = build_message(summary)
    try:
        if settings.NOTIFY_KIND == "gotify":
            await _post_gotify(client, title, body)
        else:
            await _post_ntfy(client, title, body)
        logger.info(
            "notifications.sent",
            household_id=str(summary.household_id),
            kind=settings.NOTIFY_KIND,
            due_today=len(summary.due_today),
            newly_overdue=len(summary.newly_overdue),
        )
    except Exception:
        logger.exception(
            "notifications.delivery_failed",
            household_id=str(summary.household_id),
            kind=settings.NOTIFY_KIND,
        )


async def send_daily_reminders(summaries: list[HouseholdReminderSummary]) -> None:
    """Send one summary notification per non-empty household summary.

    No-op when ``NOTIFY_URL`` is unset — callers are expected to skip the
    (comparatively expensive) summary-gathering step entirely in that case,
    but this is also checked here so the function is safe to call
    unconditionally.
    """
    if not settings.NOTIFY_URL:
        return
    non_empty = [s for s in summaries if not s.is_empty]
    if not non_empty:
        return
    async with httpx.AsyncClient(timeout=settings.NOTIFY_TIMEOUT_SECONDS) as client:
        for summary in non_empty:
            await send_household_summary(client, summary)
