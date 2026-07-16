"""Tests for case-insensitive email handling on register/login (TASK-079)."""
import pytest
from httpx import AsyncClient

_PASSWORD = "securepassword"


async def _register(client: AsyncClient, email: str) -> object:
    return await client.post(
        "/auth/register",
        json={"email": email, "password": _PASSWORD, "display_name": "Alice"},
    )


@pytest.mark.asyncio
async def test_register_stores_lowercased_email(async_client: AsyncClient) -> None:
    resp = await _register(async_client, "Alice@Example.COM")
    assert resp.status_code == 201, resp.text
    assert resp.json()["email"] == "alice@example.com"


@pytest.mark.asyncio
async def test_register_duplicate_differing_only_by_case_returns_409(
    async_client: AsyncClient,
) -> None:
    first = await _register(async_client, "alice@example.com")
    assert first.status_code == 201

    second = await _register(async_client, "ALICE@example.com")
    assert second.status_code == 409


@pytest.mark.asyncio
async def test_login_with_different_case_succeeds(async_client: AsyncClient) -> None:
    resp = await _register(async_client, "alice@example.com")
    assert resp.status_code == 201

    login = await async_client.post(
        "/auth/login",
        json={"email": "Alice@EXAMPLE.com", "password": _PASSWORD},
    )
    assert login.status_code == 200, login.text
    assert "access_token" in login.json()


@pytest.mark.asyncio
async def test_login_after_mixed_case_registration(async_client: AsyncClient) -> None:
    resp = await _register(async_client, "Bob@Example.Com")
    assert resp.status_code == 201

    login = await async_client.post(
        "/auth/login",
        json={"email": "bob@example.com", "password": _PASSWORD},
    )
    assert login.status_code == 200, login.text
