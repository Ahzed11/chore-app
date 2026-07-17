"""Tests for app/services/notifications.py (TASK-081).

Covers:
- build_message: title/body construction for due-today-only, overdue-only,
  and combined summaries.
- send_daily_reminders: disabled (no HTTP calls) when NOTIFY_URL is unset,
  and when every summary is empty.
- ntfy request shape: plain-text body, Title header (UTF-8 bytes), optional
  Bearer Authorization header.
- gotify request shape: JSON body to {NOTIFY_URL}/message, token as a query
  parameter.
- Delivery failures (network error or non-2xx response) are caught and never
  propagate out of send_daily_reminders.
"""
import uuid

import httpx
import pytest

from app.core.config import settings
from app.services.notifications import (
    HouseholdReminderSummary,
    build_message,
    send_daily_reminders,
)


def _summary(**kwargs) -> HouseholdReminderSummary:
    defaults: dict = {"household_id": uuid.uuid4(), "household_name": "Test House"}
    defaults.update(kwargs)
    return HouseholdReminderSummary(**defaults)


class _FakeResponse:
    def __init__(self, status_code: int = 200) -> None:
        self.status_code = status_code

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise httpx.HTTPStatusError(
                f"status {self.status_code}",
                request=httpx.Request("POST", "http://example.com"),
                response=httpx.Response(self.status_code, request=httpx.Request("POST", "http://example.com")),
            )


@pytest.fixture(autouse=True)
def _reset_notify_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every test starts from the disabled default and opts in explicitly."""
    monkeypatch.setattr(settings, "NOTIFY_URL", None)
    monkeypatch.setattr(settings, "NOTIFY_TOKEN", None)
    monkeypatch.setattr(settings, "NOTIFY_KIND", "ntfy")


# ---------------------------------------------------------------------------
# build_message
# ---------------------------------------------------------------------------


def test_build_message_due_today_only() -> None:
    summary = _summary(due_today=[("Dishes", "Alice")])
    title, body = build_message(summary)
    assert title == "Test House: 1 due today"
    assert "Due today:" in body
    assert "- Dishes (Alice)" in body
    assert "overdue" not in body.lower()


def test_build_message_overdue_only() -> None:
    summary = _summary(newly_overdue=[("Trash", "Bob")])
    title, body = build_message(summary)
    assert title == "Test House: 1 newly overdue"
    assert "Newly overdue:" in body
    assert "- Trash (Bob)" in body
    assert "due today" not in body.lower()


def test_build_message_combined() -> None:
    summary = _summary(
        due_today=[("Dishes", "Alice"), ("Vacuum", "Carol")],
        newly_overdue=[("Trash", "Bob")],
    )
    title, body = build_message(summary)
    assert title == "Test House: 2 due today, 1 newly overdue"
    assert "Due today:" in body
    assert "Newly overdue:" in body
    assert "- Dishes (Alice)" in body
    assert "- Vacuum (Carol)" in body
    assert "- Trash (Bob)" in body


def test_build_message_uses_unassigned_fallback() -> None:
    summary = _summary(due_today=[("Dishes", "Unassigned")])
    _title, body = build_message(summary)
    assert "- Dishes (Unassigned)" in body


# ---------------------------------------------------------------------------
# Disabled feature
# ---------------------------------------------------------------------------


async def test_disabled_when_notify_url_unset(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = []

    async def fake_post(self, *args, **kwargs):
        calls.append((args, kwargs))
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

    summary = _summary(due_today=[("Dishes", "Alice")])
    await send_daily_reminders([summary])

    assert calls == [], "No HTTP calls should be made when NOTIFY_URL is unset"


async def test_noop_when_all_summaries_empty(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")

    calls = []

    async def fake_post(self, *args, **kwargs):
        calls.append((args, kwargs))
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

    await send_daily_reminders([_summary()])  # empty due_today and newly_overdue

    assert calls == [], "Nothing to report — no notification should be sent"


# ---------------------------------------------------------------------------
# ntfy request shape
# ---------------------------------------------------------------------------


async def test_ntfy_posts_plain_text_body_and_title_header(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")
    monkeypatch.setattr(settings, "NOTIFY_KIND", "ntfy")

    captured = {}

    async def fake_post(self, url, **kwargs):
        captured["url"] = url
        captured["kwargs"] = kwargs
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

    summary = _summary(due_today=[("Dishes", "Alice")])
    await send_daily_reminders([summary])

    assert captured["url"] == "https://ntfy.example.com/chores"
    kwargs = captured["kwargs"]
    # Title is sent as raw UTF-8 bytes (not str) to sidestep httpx's ASCII-only
    # header encoding for non-ASCII household/chore names.
    assert kwargs["headers"]["Title"] == "Test House: 1 due today".encode("utf-8")
    assert b"- Dishes (Alice)" in kwargs["content"]
    assert "Authorization" not in kwargs["headers"]


async def test_ntfy_includes_bearer_token_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")
    monkeypatch.setattr(settings, "NOTIFY_KIND", "ntfy")
    monkeypatch.setattr(settings, "NOTIFY_TOKEN", "secret-token")

    captured = {}

    async def fake_post(self, url, **kwargs):
        captured["kwargs"] = kwargs
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

    summary = _summary(due_today=[("Dishes", "Alice")])
    await send_daily_reminders([summary])

    assert captured["kwargs"]["headers"]["Authorization"] == "Bearer secret-token"


# ---------------------------------------------------------------------------
# gotify request shape
# ---------------------------------------------------------------------------


async def test_gotify_posts_json_to_message_endpoint_with_token_param(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://gotify.example.com")
    monkeypatch.setattr(settings, "NOTIFY_KIND", "gotify")
    monkeypatch.setattr(settings, "NOTIFY_TOKEN", "app-token")

    captured = {}

    async def fake_post(self, url, **kwargs):
        captured["url"] = url
        captured["kwargs"] = kwargs
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

    summary = _summary(newly_overdue=[("Trash", "Bob")])
    await send_daily_reminders([summary])

    assert captured["url"] == "https://gotify.example.com/message"
    kwargs = captured["kwargs"]
    assert kwargs["params"] == {"token": "app-token"}
    assert kwargs["json"]["title"] == "Test House: 1 newly overdue"
    assert "- Trash (Bob)" in kwargs["json"]["message"]
    assert kwargs["json"]["priority"] == 5


async def test_gotify_strips_trailing_slash_from_notify_url(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://gotify.example.com/")
    monkeypatch.setattr(settings, "NOTIFY_KIND", "gotify")

    captured = {}

    async def fake_post(self, url, **kwargs):
        captured["url"] = url
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

    await send_daily_reminders([_summary(due_today=[("Dishes", "Alice")])])

    assert captured["url"] == "https://gotify.example.com/message"


async def test_gotify_omits_token_param_when_not_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://gotify.example.com")
    monkeypatch.setattr(settings, "NOTIFY_KIND", "gotify")
    monkeypatch.setattr(settings, "NOTIFY_TOKEN", None)

    captured = {}

    async def fake_post(self, url, **kwargs):
        captured["kwargs"] = kwargs
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)

    await send_daily_reminders([_summary(due_today=[("Dishes", "Alice")])])

    assert captured["kwargs"]["params"] is None


# ---------------------------------------------------------------------------
# Delivery failures never propagate
# ---------------------------------------------------------------------------


async def test_network_error_is_swallowed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")

    async def failing_post(self, *args, **kwargs):
        raise httpx.ConnectError("connection refused")

    monkeypatch.setattr(httpx.AsyncClient, "post", failing_post)

    # Must not raise.
    await send_daily_reminders([_summary(due_today=[("Dishes", "Alice")])])


async def test_non_2xx_response_is_swallowed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")

    async def bad_status_post(self, *args, **kwargs):
        return _FakeResponse(status_code=500)

    monkeypatch.setattr(httpx.AsyncClient, "post", bad_status_post)

    # Must not raise.
    await send_daily_reminders([_summary(due_today=[("Dishes", "Alice")])])


async def test_one_household_failure_does_not_block_the_next(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """If one household's delivery fails, subsequent households are still notified."""
    monkeypatch.setattr(settings, "NOTIFY_URL", "https://ntfy.example.com/chores")

    calls = []

    async def flaky_post(self, url, **kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            raise httpx.ConnectError("boom")
        return _FakeResponse()

    monkeypatch.setattr(httpx.AsyncClient, "post", flaky_post)

    summaries = [
        _summary(household_name="House A", due_today=[("Dishes", "Alice")]),
        _summary(household_name="House B", due_today=[("Trash", "Bob")]),
    ]
    await send_daily_reminders(summaries)

    assert len(calls) == 2, "Second household must still be attempted after the first fails"
