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
