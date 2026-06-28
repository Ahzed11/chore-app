"""Tests for GET /users/me and PATCH /users/me (TASK-006)."""
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
    """AsyncClient backed by a fresh test database."""
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    session_factory = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

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
