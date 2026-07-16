"""Tests for the operator management CLI (python -m app.cli, TASK-077)."""
from unittest.mock import patch

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.cli import _reset_password, main
from tests.conftest import get_test_database_url as _get_test_database_url

_EMAIL = "alice@example.com"
_PASSWORD = "securepassword"


def _make_reader(*answers: str):
    """Return a fake getpass-style reader yielding *answers* in order."""
    answer_iter = iter(answers)

    def reader(prompt: str) -> str:
        return next(answer_iter)

    return reader


async def _register_and_login(client: AsyncClient) -> dict:
    await client.post(
        "/auth/register",
        json={"email": _EMAIL, "password": _PASSWORD, "display_name": "Alice"},
    )
    resp = await client.post("/auth/login", json={"email": _EMAIL, "password": _PASSWORD})
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _run_reset(email: str, *answers: str) -> int:
    """Run _reset_password against the test database with canned prompt answers."""
    engine = create_async_engine(_get_test_database_url(), echo=False, pool_pre_ping=True)
    session_factory = async_sessionmaker(
        bind=engine, class_=AsyncSession, expire_on_commit=False
    )
    try:
        with patch("app.cli.AsyncSessionLocal", session_factory):
            return await _reset_password(email, password_reader=_make_reader(*answers))
    finally:
        await engine.dispose()


# ---------------------------------------------------------------------------
# reset-password
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cli_reset_password_updates_hash(async_client: AsyncClient) -> None:
    await _register_and_login(async_client)

    exit_code = await _run_reset(_EMAIL, "brandnewpassword", "brandnewpassword")
    assert exit_code == 0

    # Old password rejected, new password accepted.
    old_login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    assert old_login.status_code == 401

    new_login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": "brandnewpassword"}
    )
    assert new_login.status_code == 200, new_login.text


@pytest.mark.asyncio
async def test_cli_reset_password_revokes_refresh_tokens(async_client: AsyncClient) -> None:
    login_body = await _register_and_login(async_client)
    refresh_token = login_body["refresh_token"]

    exit_code = await _run_reset(_EMAIL, "brandnewpassword", "brandnewpassword")
    assert exit_code == 0

    refresh_resp = await async_client.post(
        "/auth/refresh", json={"refresh_token": refresh_token}
    )
    assert refresh_resp.status_code == 401


@pytest.mark.asyncio
async def test_cli_reset_password_unknown_email_fails(async_client: AsyncClient) -> None:
    exit_code = await _run_reset("nobody@example.com", "brandnewpassword", "brandnewpassword")
    assert exit_code == 1


@pytest.mark.asyncio
async def test_cli_reset_password_mismatched_confirmation_fails(
    async_client: AsyncClient,
) -> None:
    await _register_and_login(async_client)

    exit_code = await _run_reset(_EMAIL, "brandnewpassword", "somethingelse")
    assert exit_code == 1

    # Original password still works.
    login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    assert login.status_code == 200


@pytest.mark.asyncio
async def test_cli_reset_password_too_short_fails(async_client: AsyncClient) -> None:
    await _register_and_login(async_client)

    exit_code = await _run_reset(_EMAIL, "short", "short")
    assert exit_code == 1

    login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    assert login.status_code == 200


@pytest.mark.asyncio
async def test_cli_reset_password_normalizes_email_case(async_client: AsyncClient) -> None:
    await _register_and_login(async_client)

    exit_code = await _run_reset("ALICE@Example.com", "brandnewpassword", "brandnewpassword")
    assert exit_code == 0

    new_login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": "brandnewpassword"}
    )
    assert new_login.status_code == 200, new_login.text


# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------


def test_cli_requires_a_command() -> None:
    with pytest.raises(SystemExit):
        main([])


def test_cli_reset_password_requires_email() -> None:
    with pytest.raises(SystemExit):
        main(["reset-password"])
