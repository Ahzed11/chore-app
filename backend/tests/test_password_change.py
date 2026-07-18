"""Tests for POST /users/me/password (TASK-077)."""
import pytest
from httpx import AsyncClient

_EMAIL = "alice@example.com"
_PASSWORD = "securepassword"


async def _register_and_login(
    client: AsyncClient,
    email: str = _EMAIL,
    password: str = _PASSWORD,
    display_name: str = "Alice",
) -> dict:
    """Register a user and return the full login response body (tokens)."""
    await client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": display_name},
    )
    resp = await client.post("/auth/login", json={"email": email, "password": password})
    assert resp.status_code == 200, resp.text
    return resp.json()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# Success path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_change_password_success(async_client: AsyncClient) -> None:
    login_body = await _register_and_login(async_client)
    access_token = login_body["access_token"]

    response = await async_client.post(
        "/users/me/password",
        json={"current_password": _PASSWORD, "new_password": "newsecurepassword"},
        headers=_auth(access_token),
    )
    assert response.status_code == 200, response.text

    # Old password no longer works.
    old_login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    assert old_login.status_code == 401

    # New password works.
    new_login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": "newsecurepassword"}
    )
    assert new_login.status_code == 200


@pytest.mark.asyncio
async def test_change_password_revokes_existing_refresh_token(async_client: AsyncClient) -> None:
    login_body = await _register_and_login(async_client)
    access_token = login_body["access_token"]
    old_refresh_token = login_body["refresh_token"]

    response = await async_client.post(
        "/users/me/password",
        json={"current_password": _PASSWORD, "new_password": "newsecurepassword"},
        headers=_auth(access_token),
    )
    assert response.status_code == 200, response.text

    # The refresh token issued before the password change must now be rejected.
    refresh_response = await async_client.post(
        "/auth/refresh", json={"refresh_token": old_refresh_token}
    )
    assert refresh_response.status_code == 401


# ---------------------------------------------------------------------------
# Failure paths
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_change_password_wrong_current_password_returns_403(
    async_client: AsyncClient,
) -> None:
    login_body = await _register_and_login(async_client)
    access_token = login_body["access_token"]

    response = await async_client.post(
        "/users/me/password",
        json={"current_password": "totallywrong", "new_password": "newsecurepassword"},
        headers=_auth(access_token),
    )
    assert response.status_code == 403

    # Original password still works — nothing was changed.
    login = await async_client.post(
        "/auth/login", json={"email": _EMAIL, "password": _PASSWORD}
    )
    assert login.status_code == 200


@pytest.mark.asyncio
async def test_change_password_too_short_returns_422(async_client: AsyncClient) -> None:
    login_body = await _register_and_login(async_client)
    access_token = login_body["access_token"]

    response = await async_client.post(
        "/users/me/password",
        json={"current_password": _PASSWORD, "new_password": "short"},
        headers=_auth(access_token),
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_change_password_requires_auth(async_client: AsyncClient) -> None:
    response = await async_client.post(
        "/users/me/password",
        json={"current_password": _PASSWORD, "new_password": "newsecurepassword"},
    )
    assert response.status_code == 401
