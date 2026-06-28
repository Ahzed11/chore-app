"""Tests for POST /auth/register and POST /auth/login."""
import os
from collections.abc import AsyncGenerator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.base import Base
from app.db.session import get_db
from main import app


def _get_test_database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        raise RuntimeError(
            "TEST_DATABASE_URL environment variable is not set. "
            "Please provide a PostgreSQL URL before running the test suite."
        )
    return url


@pytest_asyncio.fixture()
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    """Yield an AsyncClient wired to a fresh test database.

    A new engine is created for each test.  All tables are dropped and
    recreated so every test starts from a clean schema state.  The
    ``get_db`` dependency is overridden to use that engine.
    """
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)

    session_factory = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    # Fresh schema for each test.
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
        async with session_factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = override_get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()
    await engine.dispose()


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
