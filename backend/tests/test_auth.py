"""Tests for POST /auth/register and POST /auth/login."""
import pytest
from httpx import AsyncClient

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_VALID_REGISTER_PAYLOAD = {
    "email": "alice@example.com",
    "password": "securepassword",
    "display_name": "Alice",
}


async def _register(client: AsyncClient, payload: dict | None = None) -> dict:
    payload = payload or _VALID_REGISTER_PAYLOAD
    response = await client.post("/auth/register", json=payload)
    return response


# ---------------------------------------------------------------------------
# Register tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_register_success(async_client: AsyncClient) -> None:
    response = await _register(async_client)

    assert response.status_code == 201
    body = response.json()
    assert body["email"] == _VALID_REGISTER_PAYLOAD["email"]
    assert body["display_name"] == _VALID_REGISTER_PAYLOAD["display_name"]
    assert "id" in body
    assert "created_at" in body


@pytest.mark.asyncio
async def test_register_duplicate_email(async_client: AsyncClient) -> None:
    await _register(async_client)
    response = await _register(async_client)

    assert response.status_code == 409
    assert "already registered" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_register_short_password(async_client: AsyncClient) -> None:
    payload = {**_VALID_REGISTER_PAYLOAD, "password": "short"}
    response = await _register(async_client, payload)

    assert response.status_code == 422


@pytest.mark.asyncio
async def test_password_not_in_response(async_client: AsyncClient) -> None:
    response = await _register(async_client)

    assert response.status_code == 201
    body = response.json()
    assert "password" not in body
    assert "password_hash" not in body


# ---------------------------------------------------------------------------
# Login tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_login_success(async_client: AsyncClient) -> None:
    await _register(async_client)

    response = await async_client.post(
        "/auth/login",
        json={
            "email": _VALID_REGISTER_PAYLOAD["email"],
            "password": _VALID_REGISTER_PAYLOAD["password"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert "access_token" in body
    assert body["token_type"] == "bearer"
    assert isinstance(body["expires_in"], int)
    assert body["expires_in"] > 0


@pytest.mark.asyncio
async def test_login_wrong_password(async_client: AsyncClient) -> None:
    await _register(async_client)

    response = await async_client.post(
        "/auth/login",
        json={
            "email": _VALID_REGISTER_PAYLOAD["email"],
            "password": "wrongpassword",
        },
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_login_unknown_email(async_client: AsyncClient) -> None:
    response = await async_client.post(
        "/auth/login",
        json={"email": "nobody@example.com", "password": "doesntmatter"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_jwt_contains_user_id(async_client: AsyncClient) -> None:
    register_response = await _register(async_client)
    user_id = register_response.json()["id"]

    login_response = await async_client.post(
        "/auth/login",
        json={
            "email": _VALID_REGISTER_PAYLOAD["email"],
            "password": _VALID_REGISTER_PAYLOAD["password"],
        },
    )

    token = login_response.json()["access_token"]

    from app.core.security import decode_access_token

    payload = decode_access_token(token)
    assert payload["sub"] == user_id


# ---------------------------------------------------------------------------
# Helpers shared by refresh / logout tests
# ---------------------------------------------------------------------------


async def _login(client: AsyncClient) -> dict:
    """Register alice (if needed) then log in and return the response body."""
    await _register(client)
    response = await client.post(
        "/auth/login",
        json={
            "email": _VALID_REGISTER_PAYLOAD["email"],
            "password": _VALID_REGISTER_PAYLOAD["password"],
        },
    )
    assert response.status_code == 200
    return response.json()


# ---------------------------------------------------------------------------
# Refresh token tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_login_returns_refresh_token(async_client: AsyncClient) -> None:
    body = await _login(async_client)

    assert "refresh_token" in body
    assert isinstance(body["refresh_token"], str)
    assert len(body["refresh_token"]) > 0


@pytest.mark.asyncio
async def test_refresh_issues_new_tokens(async_client: AsyncClient) -> None:
    login_body = await _login(async_client)
    old_refresh = login_body["refresh_token"]
    old_access = login_body["access_token"]

    response = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": old_refresh},
    )

    assert response.status_code == 200
    body = response.json()
    assert "access_token" in body
    assert "refresh_token" in body
    assert body["token_type"] == "bearer"
    # Tokens must be fresh values.
    assert body["access_token"] != old_access
    assert body["refresh_token"] != old_refresh


@pytest.mark.asyncio
async def test_refresh_with_used_token_401(async_client: AsyncClient) -> None:
    """Replaying a consumed refresh token (rotation) must be rejected with 401."""
    login_body = await _login(async_client)
    old_refresh = login_body["refresh_token"]

    # First use — should succeed and rotate the token.
    first = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": old_refresh},
    )
    assert first.status_code == 200

    # Second use of the same (now revoked) token — must fail.
    second = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": old_refresh},
    )
    assert second.status_code == 401


@pytest.mark.asyncio
async def test_refresh_with_invalid_token_401(async_client: AsyncClient) -> None:
    response = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": "this-is-complete-garbage"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_logout_revokes_refresh_token(async_client: AsyncClient) -> None:
    """After logout the refresh token must no longer be accepted."""
    login_body = await _login(async_client)
    access_token = login_body["access_token"]
    refresh_token = login_body["refresh_token"]

    logout_response = await async_client.post(
        "/auth/logout",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert logout_response.status_code == 200

    # The refresh token issued at login should now be revoked.
    refresh_response = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert refresh_response.status_code == 401
