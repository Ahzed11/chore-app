"""Tests for TASK-031: rate limiting on POST /auth/login, /auth/register,
and /auth/refresh.

The rest of the suite runs with the shared slowapi limiter disabled (see the
session-scoped ``_disable_rate_limiting_by_default`` autouse fixture in
conftest.py) so that tests which log in/register repeatedly don't flake
against the production limits. These tests locally flip the limiter back on
via the ``enable_rate_limiting`` fixture below, with tight test-only limit
strings (monkeypatched onto the shared ``Settings`` singleton, which the
route decorators read per-request), so the 429 + Retry-After behavior can be
asserted quickly and deterministically without waiting out a real window.
"""
import pytest
from httpx import AsyncClient

from app.core.config import settings
from app.core.rate_limit import limiter

_PASSWORD = "securepassword"


@pytest.fixture()
def enable_rate_limiting(monkeypatch: pytest.MonkeyPatch):
    """Turn the shared limiter on with tight (3/minute) test-only limits.

    Resets the in-memory hit counters both before and after the test so this
    test's requests never see counts left over from another test, and so it
    never leaks counts forward into whatever runs after it.
    """
    monkeypatch.setattr(settings, "RATE_LIMIT_LOGIN", "3/minute")
    monkeypatch.setattr(settings, "RATE_LIMIT_REGISTER", "3/minute")
    monkeypatch.setattr(settings, "RATE_LIMIT_REFRESH", "3/minute")
    limiter.reset()
    limiter.enabled = True
    try:
        yield
    finally:
        limiter.enabled = False
        limiter.reset()


def _assert_valid_retry_after(response) -> None:
    assert "Retry-After" in response.headers
    # Must be a non-negative integer number of seconds until the window resets.
    assert int(response.headers["Retry-After"]) >= 0


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_login_under_limit_is_unaffected(
    async_client: AsyncClient, enable_rate_limiting
) -> None:
    """Requests at or below the configured limit must behave normally (no 429)."""
    for _ in range(3):
        response = await async_client.post(
            "/auth/login",
            json={"email": "nobody@example.com", "password": "whatever"},
        )
        # Under the limit: ordinary auth failure, never a rate-limit response.
        assert response.status_code == 401


@pytest.mark.asyncio
async def test_login_returns_429_with_retry_after_once_limit_exceeded(
    async_client: AsyncClient, enable_rate_limiting
) -> None:
    for _ in range(3):
        response = await async_client.post(
            "/auth/login",
            json={"email": "nobody@example.com", "password": "whatever"},
        )
        assert response.status_code == 401

    response = await async_client.post(
        "/auth/login",
        json={"email": "nobody@example.com", "password": "whatever"},
    )
    assert response.status_code == 429
    _assert_valid_retry_after(response)


@pytest.mark.asyncio
async def test_successful_logins_also_count_toward_the_limit(
    async_client: AsyncClient, enable_rate_limiting
) -> None:
    """The limit applies per client IP regardless of whether credentials are valid."""
    await async_client.post(
        "/auth/register",
        json={
            "email": "rl-login-success@example.com",
            "password": _PASSWORD,
            "display_name": "RL",
        },
    )

    login_payload = {"email": "rl-login-success@example.com", "password": _PASSWORD}
    for _ in range(3):
        response = await async_client.post("/auth/login", json=login_payload)
        assert response.status_code == 200

    response = await async_client.post("/auth/login", json=login_payload)
    assert response.status_code == 429
    _assert_valid_retry_after(response)


# ---------------------------------------------------------------------------
# Register
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_register_under_limit_is_unaffected(
    async_client: AsyncClient, enable_rate_limiting
) -> None:
    for i in range(3):
        response = await async_client.post(
            "/auth/register",
            json={
                "email": f"rl-register-ok-{i}@example.com",
                "password": _PASSWORD,
                "display_name": "RL",
            },
        )
        assert response.status_code == 201


@pytest.mark.asyncio
async def test_register_returns_429_with_retry_after_once_limit_exceeded(
    async_client: AsyncClient, enable_rate_limiting
) -> None:
    for i in range(3):
        response = await async_client.post(
            "/auth/register",
            json={
                "email": f"rl-register-limit-{i}@example.com",
                "password": _PASSWORD,
                "display_name": "RL",
            },
        )
        assert response.status_code == 201

    response = await async_client.post(
        "/auth/register",
        json={
            "email": "rl-register-limit-overflow@example.com",
            "password": _PASSWORD,
            "display_name": "RL",
        },
    )
    assert response.status_code == 429
    _assert_valid_retry_after(response)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_refresh_returns_429_with_retry_after_once_limit_exceeded(
    async_client: AsyncClient, enable_rate_limiting
) -> None:
    for _ in range(3):
        response = await async_client.post(
            "/auth/refresh",
            json={"refresh_token": "not-a-real-token"},
        )
        assert response.status_code == 401

    response = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": "not-a-real-token"},
    )
    assert response.status_code == 429
    _assert_valid_retry_after(response)


# ---------------------------------------------------------------------------
# Sanity check that the default-off behavior actually holds
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rate_limiting_stays_disabled_without_the_fixture(
    async_client: AsyncClient,
) -> None:
    """Without ``enable_rate_limiting``, the session default (disabled) must hold.

    Guards against the conftest fixture silently failing to apply: hammer
    login well past the real 5/minute default and confirm none of them 429.
    """
    for _ in range(8):
        response = await async_client.post(
            "/auth/login",
            json={"email": "nobody@example.com", "password": "whatever"},
        )
        assert response.status_code == 401
