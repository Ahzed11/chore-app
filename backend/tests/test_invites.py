"""Tests for invite token generation and household join flow (TASK-008)."""
import os
from collections.abc import AsyncGenerator
from datetime import datetime, timedelta, timezone

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.base import Base
from app.db.session import get_db
from app.models.invite_token import InviteToken
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
    email: str,
    display_name: str = "User",
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


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _create_household(client: AsyncClient, token: str, name: str = "Test House") -> str:
    resp = await client.post(
        "/households",
        json={"name": name},
        headers=_auth(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _generate_invite(client: AsyncClient, token: str, household_id: str) -> str:
    """Generate an invite token and return the raw token string."""
    resp = await client.post(
        f"/households/{household_id}/invites",
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["token"]


# ---------------------------------------------------------------------------
# POST /households/{household_id}/invites
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_admin_generates_invite_token(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "admin@example.com", "Admin")
    household_id = await _create_household(async_client, token)

    response = await async_client.post(
        f"/households/{household_id}/invites",
        headers=_auth(token),
    )

    assert response.status_code == 200
    body = response.json()
    assert "token" in body
    assert "invite_url" in body
    assert "expires_at" in body
    # token_urlsafe(16) produces 22 characters
    assert len(body["token"]) >= 20
    assert body["token"] in body["invite_url"]


@pytest.mark.asyncio
async def test_member_cannot_generate_invite(async_client: AsyncClient) -> None:
    """A non-member (or non-admin) cannot generate invite tokens — returns 403."""
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")
    token_bob = await _register_and_login(async_client, "bob@example.com", "Bob")

    household_id = await _create_household(async_client, token_alice)

    response = await async_client.post(
        f"/households/{household_id}/invites",
        headers=_auth(token_bob),
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_generate_invite_requires_auth(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household_id = await _create_household(async_client, token)

    response = await async_client.post(f"/households/{household_id}/invites")
    assert response.status_code == 401


# ---------------------------------------------------------------------------
# POST /invites/{token}/accept
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_accept_valid_invite_creates_membership(async_client: AsyncClient) -> None:
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")
    token_bob = await _register_and_login(async_client, "bob@example.com", "Bob")

    household_id = await _create_household(async_client, token_alice)
    invite_token = await _generate_invite(async_client, token_alice, household_id)

    accept_resp = await async_client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(token_bob),
    )
    assert accept_resp.status_code == 200
    body = accept_resp.json()
    assert body["id"] == household_id

    # Bob should now see the household in their list
    list_resp = await async_client.get("/households", headers=_auth(token_bob))
    assert list_resp.status_code == 200
    household_ids = [h["id"] for h in list_resp.json()]
    assert household_id in household_ids


@pytest.mark.asyncio
async def test_expired_token_returns_410(async_client: AsyncClient) -> None:
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")
    token_bob = await _register_and_login(async_client, "bob@example.com", "Bob")

    household_id = await _create_household(async_client, token_alice)
    invite_token = await _generate_invite(async_client, token_alice, household_id)

    # Directly expire the token in the database
    engine = create_async_engine(_get_test_database_url(), echo=False, pool_pre_ping=True)
    sf = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    async with sf() as session:
        result = await session.execute(
            select(InviteToken).where(InviteToken.token == invite_token)
        )
        invite = result.scalar_one()
        invite.expires_at = datetime.now(timezone.utc) - timedelta(hours=1)
        await session.commit()
    await engine.dispose()

    response = await async_client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(token_bob),
    )
    assert response.status_code == 410


@pytest.mark.asyncio
async def test_used_token_returns_410(async_client: AsyncClient) -> None:
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")
    token_bob = await _register_and_login(async_client, "bob@example.com", "Bob")
    token_carol = await _register_and_login(async_client, "carol@example.com", "Carol")

    household_id = await _create_household(async_client, token_alice)
    invite_token = await _generate_invite(async_client, token_alice, household_id)

    # Bob consumes the token
    first_resp = await async_client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(token_bob),
    )
    assert first_resp.status_code == 200

    # Carol tries to reuse the same token
    second_resp = await async_client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(token_carol),
    )
    assert second_resp.status_code == 410


@pytest.mark.asyncio
async def test_nonexistent_token_returns_410(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    response = await async_client.post(
        "/invites/nonexistent-token/accept",
        headers=_auth(token),
    )
    assert response.status_code == 410


@pytest.mark.asyncio
async def test_already_member_accept_returns_409(async_client: AsyncClient) -> None:
    """A user who is already an active member of the household gets 409."""
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")

    household_id = await _create_household(async_client, token_alice)
    invite_token = await _generate_invite(async_client, token_alice, household_id)

    # Alice tries to accept her own invite (she's already admin member)
    response = await async_client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(token_alice),
    )
    assert response.status_code == 409
