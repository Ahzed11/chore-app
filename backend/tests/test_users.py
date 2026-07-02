"""Tests for GET /users/me and PATCH /users/me (TASK-006)."""
import pytest
from httpx import AsyncClient


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _register_and_login(
    client: AsyncClient,
    email: str = "alice@example.com",
    display_name: str = "Alice",
) -> str:
    """Register a user and return their JWT access token."""
    await client.post(
        "/auth/register",
        json={"email": email, "password": "securepassword", "display_name": display_name},
    )
    resp = await client.post(
        "/auth/login",
        json={"email": email, "password": "securepassword"},
    )
    return resp.json()["access_token"]


# ---------------------------------------------------------------------------
# GET /users/me
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_get_profile_returns_correct_data(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client)

    response = await async_client.get(
        "/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "alice@example.com"
    assert body["display_name"] == "Alice"
    assert "id" in body
    assert "created_at" in body
    assert "password" not in body
    assert "password_hash" not in body


@pytest.mark.asyncio
async def test_get_profile_without_token_returns_401(async_client: AsyncClient) -> None:
    response = await async_client.get("/users/me")
    assert response.status_code == 401


# ---------------------------------------------------------------------------
# PATCH /users/me
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_patch_profile_updates_display_name(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client)

    response = await async_client.patch(
        "/users/me",
        json={"display_name": "Alice Renamed"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["display_name"] == "Alice Renamed"
    assert body["email"] == "alice@example.com"

    # Verify persistence — subsequent GET reflects the update
    get_resp = await async_client.get(
        "/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert get_resp.json()["display_name"] == "Alice Renamed"


@pytest.mark.asyncio
async def test_patch_profile_empty_string_returns_422(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client)

    response = await async_client.patch(
        "/users/me",
        json={"display_name": ""},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 422
