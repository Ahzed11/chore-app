"""Tests for household CRUD endpoints (TASK-007)."""
import uuid
from datetime import datetime, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.models.household_membership import HouseholdMembership
from tests.conftest import get_test_database_url as _get_test_database_url

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _register_and_login(
    client: AsyncClient,
    email: str,
    display_name: str = "Test User",
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


async def _create_household(client: AsyncClient, token: str, name: str = "Test House") -> dict:
    resp = await client.post(
        "/households",
        json={"name": name},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# POST /households
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_household_returns_201(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")

    response = await async_client.post(
        "/households",
        json={"name": "Sunny Apartment"},
        headers=_auth(token),
    )

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Sunny Apartment"
    assert "rotation_pointer" not in body
    assert "id" in body
    assert "created_at" in body


@pytest.mark.asyncio
async def test_create_household_makes_creator_admin(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, token, "Alice's Place")
    household_id = household["id"]

    list_resp = await async_client.get("/households", headers=_auth(token))
    assert list_resp.status_code == 200
    households = list_resp.json()
    assert len(households) == 1
    assert households[0]["id"] == household_id
    assert households[0]["role"] == "admin"


@pytest.mark.asyncio
async def test_create_household_requires_auth(async_client: AsyncClient) -> None:
    response = await async_client.post("/households", json={"name": "Ghost House"})
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_create_household_name_too_long_returns_422(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    response = await async_client.post(
        "/households",
        json={"name": "x" * 101},
        headers=_auth(token),
    )
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# GET /households
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_households_returns_only_user_households(async_client: AsyncClient) -> None:
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")
    token_bob = await _register_and_login(async_client, "bob@example.com", "Bob")

    await _create_household(async_client, token_alice, "Alice's House")
    await _create_household(async_client, token_bob, "Bob's House")

    alice_resp = await async_client.get("/households", headers=_auth(token_alice))
    assert alice_resp.status_code == 200
    alice_list = alice_resp.json()
    assert len(alice_list) == 1
    assert alice_list[0]["name"] == "Alice's House"

    bob_resp = await async_client.get("/households", headers=_auth(token_bob))
    assert bob_resp.status_code == 200
    bob_list = bob_resp.json()
    assert len(bob_list) == 1
    assert bob_list[0]["name"] == "Bob's House"


@pytest.mark.asyncio
async def test_list_households_includes_member_count(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    await _create_household(async_client, token)

    resp = await async_client.get("/households", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["member_count"] == 1


@pytest.mark.asyncio
async def test_list_households_empty_for_new_user(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    resp = await async_client.get("/households", headers=_auth(token))
    assert resp.status_code == 200
    assert resp.json() == []


# ---------------------------------------------------------------------------
# GET /households/{household_id}
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_get_household_detail_returns_member_count(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, token)
    household_id = household["id"]

    resp = await async_client.get(f"/households/{household_id}", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == household_id
    assert body["name"] == "Test House"
    assert body["member_count"] == 1


@pytest.mark.asyncio
async def test_get_household_non_member_gets_403(async_client: AsyncClient) -> None:
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")
    token_bob = await _register_and_login(async_client, "bob@example.com", "Bob")

    household = await _create_household(async_client, token_alice)
    household_id = household["id"]

    response = await async_client.get(
        f"/households/{household_id}",
        headers=_auth(token_bob),
    )
    assert response.status_code == 403


# ---------------------------------------------------------------------------
# PATCH /households/{household_id}
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_patch_household_admin_succeeds(async_client: AsyncClient) -> None:
    token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, token)
    household_id = household["id"]

    response = await async_client.patch(
        f"/households/{household_id}",
        json={"name": "Renamed House"},
        headers=_auth(token),
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Renamed House"


@pytest.mark.asyncio
async def test_patch_household_non_admin_gets_403(async_client: AsyncClient) -> None:
    """A member with role='member' cannot PATCH the household name."""
    token_alice = await _register_and_login(async_client, "alice@example.com", "Alice")
    token_bob = await _register_and_login(async_client, "bob@example.com", "Bob")

    household = await _create_household(async_client, token_alice)
    household_id = household["id"]

    # Get Bob's user ID via the profile endpoint
    bob_profile = await async_client.get("/users/me", headers=_auth(token_bob))
    bob_id = bob_profile.json()["id"]

    # Seed Bob as a regular 'member' (not admin) via a direct DB write
    engine = create_async_engine(_get_test_database_url(), echo=False, pool_pre_ping=True)
    sf = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    async with sf() as session:
        membership = HouseholdMembership(
            id=uuid.uuid4(),
            household_id=uuid.UUID(household_id),
            user_id=uuid.UUID(bob_id),
            role="member",
            joined_at=datetime.now(timezone.utc),
            is_active=True,
        )
        session.add(membership)
        await session.commit()
    await engine.dispose()

    response = await async_client.patch(
        f"/households/{household_id}",
        json={"name": "Should Not Change"},
        headers=_auth(token_bob),
    )
    assert response.status_code == 403
