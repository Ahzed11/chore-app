"""Tests for member management endpoints (TASK-009) and redistribution (TASK-015)."""
import os
import uuid
from collections.abc import AsyncGenerator
from datetime import date

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.base import Base
from app.db.session import get_db
from app.models.chore_instance import ChoreInstance
from app.models.household_membership import HouseholdMembership
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
    """AsyncClient backed by a fresh test database with dependency override for get_db."""
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
# Shared helpers
# ---------------------------------------------------------------------------


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


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
        headers=_auth(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _get_user_id(client: AsyncClient, token: str) -> str:
    resp = await client.get("/users/me", headers=_auth(token))
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


async def _invite_and_join(
    client: AsyncClient,
    admin_token: str,
    household_id: str,
    user_email: str,
    display_name: str = "Member User",
) -> str:
    """Invite user_email to the household and return their JWT after accepting."""
    invite_resp = await client.post(
        f"/households/{household_id}/invites",
        headers=_auth(admin_token),
    )
    assert invite_resp.status_code == 200, invite_resp.text
    invite_token = invite_resp.json()["token"]

    user_token = await _register_and_login(client, user_email, display_name)

    accept_resp = await client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(user_token),
    )
    assert accept_resp.status_code == 200, accept_resp.text
    return user_token


async def _create_chore(
    client: AsyncClient,
    admin_token: str,
    household_id: str,
    assignee_id: str | None = None,
    title: str = "Test Chore",
) -> dict:
    """Create a one-off chore and return the full API response body."""
    body: dict = {
        "title": title,
        "category": "kitchen",
        "effort_level": "easy",
        "chore_type": "one_off",
        "first_due_date": str(date.today()),
    }
    if assignee_id is not None:
        body["assignee_id"] = assignee_id
    resp = await client.post(
        f"/households/{household_id}/chores",
        json=body,
        headers=_auth(admin_token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# GET /households/{household_id}/members
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_get_members_returns_all_active_members(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    await _invite_and_join(async_client, alice_token, household_id, "bob@example.com", "Bob")

    resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 200
    members = resp.json()
    assert len(members) == 2
    names = {m["display_name"] for m in members}
    assert names == {"Alice", "Bob"}


@pytest.mark.asyncio
async def test_get_members_non_member_returns_403(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    charlie_token = await _register_and_login(async_client, "charlie@example.com", "Charlie")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(charlie_token),
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_get_members_only_shows_active(async_client: AsyncClient) -> None:
    """Members who left should not appear in the list."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )

    # Bob leaves
    leave_resp = await async_client.post(
        f"/households/{household_id}/leave",
        headers=_auth(bob_token),
    )
    assert leave_resp.status_code == 204

    resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 200
    members = resp.json()
    assert len(members) == 1
    assert members[0]["display_name"] == "Alice"


@pytest.mark.asyncio
async def test_get_members_response_fields(async_client: AsyncClient) -> None:
    """Each member entry exposes user_id, display_name, role, joined_at."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 200
    member = resp.json()[0]
    assert "user_id" in member
    assert "display_name" in member
    assert "role" in member
    assert "joined_at" in member
    assert member["role"] == "admin"
    assert member["display_name"] == "Alice"


# ---------------------------------------------------------------------------
# DELETE /households/{household_id}/members/{user_id}
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_remove_member_returns_204(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    resp = await async_client.delete(
        f"/households/{household_id}/members/{bob_id}",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_remove_member_marks_them_inactive(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    await async_client.delete(
        f"/households/{household_id}/members/{bob_id}",
        headers=_auth(alice_token),
    )

    # Bob should no longer appear in the members list
    members_resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(alice_token),
    )
    assert members_resp.status_code == 200
    member_ids = {m["user_id"] for m in members_resp.json()}
    assert bob_id not in member_ids


@pytest.mark.asyncio
async def test_remove_member_not_found_returns_404(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    resp = await async_client.delete(
        f"/households/{household_id}/members/{uuid.uuid4()}",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_remove_sole_admin_self_returns_409(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    resp = await async_client.delete(
        f"/households/{household_id}/members/{alice_id}",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 409
    assert "sole admin" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_remove_self_when_two_admins_returns_204(async_client: AsyncClient) -> None:
    """Admin can remove themselves when another admin exists."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    # Promote Bob to admin first
    promote_resp = await async_client.patch(
        f"/households/{household_id}/members/{bob_id}/role",
        json={"role": "admin"},
        headers=_auth(alice_token),
    )
    assert promote_resp.status_code == 200

    # Alice removes herself — Bob is also admin so this is allowed
    resp = await async_client.delete(
        f"/households/{household_id}/members/{alice_id}",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_remove_member_requires_admin_role(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    charlie_token = await _invite_and_join(
        async_client, alice_token, household_id, "charlie@example.com", "Charlie"
    )
    charlie_id = await _get_user_id(async_client, charlie_token)

    # Bob (member, not admin) tries to remove Charlie → 403
    resp = await async_client.delete(
        f"/households/{household_id}/members/{charlie_id}",
        headers=_auth(bob_token),
    )
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# PATCH /households/{household_id}/members/{user_id}/role
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_promote_member_to_admin(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    resp = await async_client.patch(
        f"/households/{household_id}/members/{bob_id}/role",
        json={"role": "admin"},
        headers=_auth(alice_token),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["role"] == "admin"
    assert body["user_id"] == bob_id
    assert body["display_name"] == "Bob"


@pytest.mark.asyncio
async def test_demote_admin_to_member(async_client: AsyncClient) -> None:
    """Admin can demote another admin to member as long as another admin remains."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    # Promote Bob first
    await async_client.patch(
        f"/households/{household_id}/members/{bob_id}/role",
        json={"role": "admin"},
        headers=_auth(alice_token),
    )

    # Now demote Bob back — Alice is still admin so this is allowed
    demote_resp = await async_client.patch(
        f"/households/{household_id}/members/{bob_id}/role",
        json={"role": "member"},
        headers=_auth(alice_token),
    )
    assert demote_resp.status_code == 200
    assert demote_resp.json()["role"] == "member"


@pytest.mark.asyncio
async def test_demote_sole_admin_self_returns_409(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    resp = await async_client.patch(
        f"/households/{household_id}/members/{alice_id}/role",
        json={"role": "member"},
        headers=_auth(alice_token),
    )
    assert resp.status_code == 409
    assert "sole admin" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_update_role_not_found_returns_404(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    resp = await async_client.patch(
        f"/households/{household_id}/members/{uuid.uuid4()}/role",
        json={"role": "member"},
        headers=_auth(alice_token),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_update_role_requires_admin(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )

    # Bob (member) tries to change Alice's role → 403
    resp = await async_client.patch(
        f"/households/{household_id}/members/{alice_id}/role",
        json={"role": "member"},
        headers=_auth(bob_token),
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_update_role_invalid_value_returns_422(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    resp = await async_client.patch(
        f"/households/{household_id}/members/{alice_id}/role",
        json={"role": "superuser"},
        headers=_auth(alice_token),
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /households/{household_id}/leave
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_leave_as_member_returns_204(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )

    resp = await async_client.post(
        f"/households/{household_id}/leave",
        headers=_auth(bob_token),
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_leave_as_sole_admin_returns_409(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    resp = await async_client.post(
        f"/households/{household_id}/leave",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 409
    assert "sole admin" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_leave_as_non_sole_admin_returns_204(async_client: AsyncClient) -> None:
    """An admin may leave when another admin exists."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    # Promote Bob so Alice is no longer the sole admin
    await async_client.patch(
        f"/households/{household_id}/members/{bob_id}/role",
        json={"role": "admin"},
        headers=_auth(alice_token),
    )

    resp = await async_client.post(
        f"/households/{household_id}/leave",
        headers=_auth(alice_token),
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_leave_marks_membership_inactive(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    await async_client.post(f"/households/{household_id}/leave", headers=_auth(bob_token))

    # Bob should no longer appear in the household member list
    members_resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(alice_token),
    )
    assert members_resp.status_code == 200
    member_ids = {m["user_id"] for m in members_resp.json()}
    assert bob_id not in member_ids


@pytest.mark.asyncio
async def test_leave_non_member_returns_403(async_client: AsyncClient) -> None:
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    charlie_token = await _register_and_login(async_client, "charlie@example.com", "Charlie")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    # Charlie is not a member of this household
    resp = await async_client.post(
        f"/households/{household_id}/leave",
        headers=_auth(charlie_token),
    )
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# Redistribution: chore reassignment on member removal/leave (TASK-015)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_remove_member_redistributes_pending_chores(async_client: AsyncClient) -> None:
    """Removing Bob reassigns Bob's pending chores to remaining members."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    # Create a chore manually assigned to Bob
    chore_data = await _create_chore(
        async_client, alice_token, household_id, assignee_id=bob_id
    )
    instance_id = chore_data["first_instance"]["id"]

    # Admin removes Bob
    remove_resp = await async_client.delete(
        f"/households/{household_id}/members/{bob_id}",
        headers=_auth(alice_token),
    )
    assert remove_resp.status_code == 204

    # Bob's pending chore must now be assigned to a different (active) member
    chore_resp = await async_client.get(
        f"/households/{household_id}/chores/{instance_id}",
        headers=_auth(alice_token),
    )
    assert chore_resp.status_code == 200
    updated = chore_resp.json()
    # With only Alice remaining the round-robin must assign it to Alice
    assert updated["assignee_id"] == alice_id


@pytest.mark.asyncio
async def test_remove_member_does_not_touch_completed_chores(
    async_client: AsyncClient,
) -> None:
    """Completed chores must not be reassigned when a member is removed."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    chore_data = await _create_chore(
        async_client, alice_token, household_id, assignee_id=bob_id
    )
    instance_id = chore_data["first_instance"]["id"]

    # Bob completes the chore
    complete_resp = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete",
        headers=_auth(bob_token),
    )
    assert complete_resp.status_code == 200
    assert complete_resp.json()["status"] == "complete"

    # Admin removes Bob
    await async_client.delete(
        f"/households/{household_id}/members/{bob_id}",
        headers=_auth(alice_token),
    )

    # Completed chore must remain assigned to Bob and still be 'complete'
    chore_resp = await async_client.get(
        f"/households/{household_id}/chores/{instance_id}",
        headers=_auth(alice_token),
    )
    assert chore_resp.status_code == 200
    chore = chore_resp.json()
    assert chore["status"] == "complete"
    assert chore["assignee_id"] == bob_id  # unchanged


@pytest.mark.asyncio
async def test_leave_redistributes_pending_chores(async_client: AsyncClient) -> None:
    """When Bob leaves, his pending chores are redistributed to remaining members."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    chore_data = await _create_chore(
        async_client, alice_token, household_id, assignee_id=bob_id
    )
    instance_id = chore_data["first_instance"]["id"]

    # Bob leaves
    leave_resp = await async_client.post(
        f"/households/{household_id}/leave",
        headers=_auth(bob_token),
    )
    assert leave_resp.status_code == 204

    # Bob's pending chore must now be assigned to Alice (sole remaining member)
    chore_resp = await async_client.get(
        f"/households/{household_id}/chores/{instance_id}",
        headers=_auth(alice_token),
    )
    assert chore_resp.status_code == 200
    assert chore_resp.json()["assignee_id"] == alice_id


@pytest.mark.asyncio
async def test_remove_member_multiple_pending_chores_all_redistributed(
    async_client: AsyncClient,
) -> None:
    """All of Bob's pending chores get reassigned when he is removed."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    # Create two chores assigned to Bob
    chore1 = await _create_chore(
        async_client, alice_token, household_id, assignee_id=bob_id, title="Chore 1"
    )
    chore2 = await _create_chore(
        async_client, alice_token, household_id, assignee_id=bob_id, title="Chore 2"
    )
    instance_id_1 = chore1["first_instance"]["id"]
    instance_id_2 = chore2["first_instance"]["id"]

    # Remove Bob
    await async_client.delete(
        f"/households/{household_id}/members/{bob_id}",
        headers=_auth(alice_token),
    )

    # Both chores must now be assigned to someone other than Bob
    for instance_id in (instance_id_1, instance_id_2):
        chore_resp = await async_client.get(
            f"/households/{household_id}/chores/{instance_id}",
            headers=_auth(alice_token),
        )
        assert chore_resp.status_code == 200
        updated = chore_resp.json()
        assert updated["assignee_id"] != bob_id
        assert updated["assignee_id"] is not None


@pytest.mark.asyncio
async def test_remove_last_member_sets_assignee_to_none(async_client: AsyncClient) -> None:
    """When no members remain after removal, pending chores get assignee_id=None (BR-003)."""
    # Setup: Alice (admin) creates household, Bob joins
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    # Create a chore assigned to Bob
    chore_data = await _create_chore(
        async_client, alice_token, household_id, assignee_id=bob_id
    )
    instance_id = chore_data["first_instance"]["id"]

    # Deactivate Alice's membership directly in the DB so that when Bob later
    # leaves, no active members remain (simulating the BR-003 edge case).
    engine = create_async_engine(_get_test_database_url(), echo=False, pool_pre_ping=True)
    sf = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    async with sf() as session:
        result = await session.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.household_id == uuid.UUID(household_id),
                HouseholdMembership.user_id == uuid.UUID(alice_id),
                HouseholdMembership.is_active == True,  # noqa: E712
            )
        )
        alice_membership = result.scalar_one_or_none()
        if alice_membership is not None:
            alice_membership.is_active = False
            await session.commit()
    await engine.dispose()

    # Bob leaves — he is the sole remaining active member (role='member', not sole admin)
    # so the endpoint must permit this and clear chore assignees.
    leave_resp = await async_client.post(
        f"/households/{household_id}/leave",
        headers=_auth(bob_token),
    )
    assert leave_resp.status_code == 204

    # The chore should now have assignee_id=None because no members remain.
    # Alice's JWT is still valid (her User record exists); the GET /chores endpoint
    # only requires get_current_user (not household membership).
    chore_resp = await async_client.get(
        f"/households/{household_id}/chores/{instance_id}",
        headers=_auth(alice_token),
    )
    assert chore_resp.status_code == 200
    assert chore_resp.json()["assignee_id"] is None


@pytest.mark.asyncio
async def test_redistribution_ignores_overdue_vs_pending_distinction(
    async_client: AsyncClient,
) -> None:
    """Both pending and overdue chores are reassigned; completed chores are not."""
    alice_token = await _register_and_login(async_client, "alice@example.com", "Alice")
    household = await _create_household(async_client, alice_token)
    household_id = household["id"]
    alice_id = await _get_user_id(async_client, alice_token)

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@example.com", "Bob"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    # Create a pending chore for Bob via API
    chore_data = await _create_chore(
        async_client, alice_token, household_id, assignee_id=bob_id, title="Pending Chore"
    )
    pending_instance_id = chore_data["first_instance"]["id"]

    # Directly set one instance to 'overdue' status in the DB
    engine = create_async_engine(_get_test_database_url(), echo=False, pool_pre_ping=True)
    sf = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    async with sf() as session:
        result = await session.execute(
            select(ChoreInstance).where(
                ChoreInstance.id == uuid.UUID(pending_instance_id)
            )
        )
        chore_instance = result.scalar_one()
        chore_instance.status = "overdue"
        await session.commit()
    await engine.dispose()

    # Admin removes Bob
    await async_client.delete(
        f"/households/{household_id}/members/{bob_id}",
        headers=_auth(alice_token),
    )

    # The overdue chore must now be reassigned to Alice
    chore_resp = await async_client.get(
        f"/households/{household_id}/chores/{pending_instance_id}",
        headers=_auth(alice_token),
    )
    assert chore_resp.status_code == 200
    assert chore_resp.json()["assignee_id"] == alice_id
