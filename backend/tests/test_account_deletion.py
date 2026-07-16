"""Tests for DELETE /households/{id} and DELETE /users/me (TASK-078)."""
import uuid
from datetime import date

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.invite_token import InviteToken
from app.models.point_ledger import PointLedger
from app.models.user import User
from tests.conftest import get_test_database_url as _get_test_database_url

_PASSWORD = "securepassword"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _session_factory() -> async_sessionmaker:
    engine = create_async_engine(_get_test_database_url(), echo=False, pool_pre_ping=True)
    return async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)


async def _register_and_login(client: AsyncClient, email: str, name: str = "User") -> dict:
    await client.post(
        "/auth/register",
        json={"email": email, "password": _PASSWORD, "display_name": name},
    )
    resp = await client.post("/auth/login", json={"email": email, "password": _PASSWORD})
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _create_household(client: AsyncClient, token: str, name: str = "Test House") -> str:
    resp = await client.post("/households", json={"name": name}, headers=_auth(token))
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _get_user_id(client: AsyncClient, token: str) -> str:
    resp = await client.get("/users/me", headers=_auth(token))
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


async def _invite_and_join(
    client: AsyncClient,
    admin_token: str,
    household_id: str,
    email: str,
    name: str = "Member",
) -> dict:
    invite_resp = await client.post(
        f"/households/{household_id}/invites", headers=_auth(admin_token)
    )
    assert invite_resp.status_code == 200, invite_resp.text
    invite_token = invite_resp.json()["token"]

    login_body = await _register_and_login(client, email, name)
    accept = await client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(login_body["access_token"]),
    )
    assert accept.status_code == 200, accept.text
    return login_body


async def _seed_chore(
    household_id: str,
    assignee_id: str,
    status: str = "pending",
    points: int | None = None,
) -> str:
    """Insert a definition + instance (and optional ledger row); return instance id."""
    sf = _session_factory()
    instance_id = uuid.uuid4()
    async with sf() as session:
        defn = ChoreDefinition(
            id=uuid.uuid4(),
            household_id=uuid.UUID(household_id),
            title="Seeded Chore",
            category="kitchen",
            effort_level="easy",
            chore_type="one_off",
            first_due_date=date.today(),
            is_active=True,
        )
        session.add(defn)
        await session.flush()
        session.add(
            ChoreInstance(
                id=instance_id,
                definition_id=defn.id,
                household_id=uuid.UUID(household_id),
                assignee_id=uuid.UUID(assignee_id),
                assigned_manually=True,
                due_date=date.today(),
                status=status,
            )
        )
        if points is not None:
            session.add(
                PointLedger(
                    id=uuid.uuid4(),
                    household_id=uuid.UUID(household_id),
                    user_id=uuid.UUID(assignee_id),
                    chore_instance_id=instance_id,
                    points=points,
                )
            )
        await session.commit()
    return str(instance_id)


async def _count(model, **filters) -> int:
    sf = _session_factory()
    async with sf() as session:
        stmt = select(func.count()).select_from(model)
        for attr, value in filters.items():
            stmt = stmt.where(getattr(model, attr) == value)
        result = await session.execute(stmt)
        return result.scalar_one()


# ---------------------------------------------------------------------------
# DELETE /households/{household_id}
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delete_household_requires_matching_confirmation(
    async_client: AsyncClient,
) -> None:
    body = await _register_and_login(async_client, "admin@example.com", "Admin")
    hh_id = await _create_household(async_client, body["access_token"], "My House")

    resp = await async_client.delete(
        f"/households/{hh_id}",
        params={"confirm": "Wrong Name"},
        headers=_auth(body["access_token"]),
    )
    assert resp.status_code == 400
    assert await _count(Household, id=uuid.UUID(hh_id)) == 1


@pytest.mark.asyncio
async def test_delete_household_missing_confirmation_returns_422(
    async_client: AsyncClient,
) -> None:
    body = await _register_and_login(async_client, "admin@example.com", "Admin")
    hh_id = await _create_household(async_client, body["access_token"], "My House")

    resp = await async_client.delete(
        f"/households/{hh_id}", headers=_auth(body["access_token"])
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_delete_household_non_admin_gets_403(async_client: AsyncClient) -> None:
    admin = await _register_and_login(async_client, "admin@example.com", "Admin")
    hh_id = await _create_household(async_client, admin["access_token"], "My House")
    member = await _invite_and_join(
        async_client, admin["access_token"], hh_id, "member@example.com"
    )

    resp = await async_client.delete(
        f"/households/{hh_id}",
        params={"confirm": "My House"},
        headers=_auth(member["access_token"]),
    )
    assert resp.status_code == 403
    assert await _count(Household, id=uuid.UUID(hh_id)) == 1


@pytest.mark.asyncio
async def test_delete_household_cascades_all_related_rows(
    async_client: AsyncClient,
) -> None:
    admin = await _register_and_login(async_client, "admin@example.com", "Admin")
    token = admin["access_token"]
    hh_id = await _create_household(async_client, token, "My House")
    admin_id = await _get_user_id(async_client, token)
    await _invite_and_join(async_client, token, hh_id, "member@example.com")
    await _seed_chore(hh_id, admin_id, status="complete", points=10)

    resp = await async_client.delete(
        f"/households/{hh_id}",
        params={"confirm": "My House"},
        headers=_auth(token),
    )
    assert resp.status_code == 204, resp.text

    hh_uuid = uuid.UUID(hh_id)
    assert await _count(Household, id=hh_uuid) == 0
    assert await _count(HouseholdMembership, household_id=hh_uuid) == 0
    assert await _count(InviteToken, household_id=hh_uuid) == 0
    assert await _count(ChoreDefinition, household_id=hh_uuid) == 0
    assert await _count(ChoreInstance, household_id=hh_uuid) == 0
    assert await _count(PointLedger, household_id=hh_uuid) == 0
    # The users themselves survive.
    assert await _count(User, id=uuid.UUID(admin_id)) == 1


@pytest.mark.asyncio
async def test_delete_household_not_found_returns_403_for_non_member(
    async_client: AsyncClient,
) -> None:
    body = await _register_and_login(async_client, "admin@example.com", "Admin")
    resp = await async_client.delete(
        f"/households/{uuid.uuid4()}",
        params={"confirm": "whatever"},
        headers=_auth(body["access_token"]),
    )
    # require_admin -> require_household_member fires first: 403.
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# DELETE /users/me
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delete_account_wrong_password_returns_403(async_client: AsyncClient) -> None:
    body = await _register_and_login(async_client, "alice@example.com", "Alice")

    resp = await async_client.request(
        "DELETE",
        "/users/me",
        json={"current_password": "totallywrong"},
        headers=_auth(body["access_token"]),
    )
    assert resp.status_code == 403
    assert await _count(User, email="alice@example.com") == 1


@pytest.mark.asyncio
async def test_delete_account_sole_admin_with_other_members_returns_409(
    async_client: AsyncClient,
) -> None:
    admin = await _register_and_login(async_client, "admin@example.com", "Admin")
    hh_id = await _create_household(async_client, admin["access_token"], "Shared House")
    await _invite_and_join(async_client, admin["access_token"], hh_id, "member@example.com")

    resp = await async_client.request(
        "DELETE",
        "/users/me",
        json={"current_password": _PASSWORD},
        headers=_auth(admin["access_token"]),
    )
    assert resp.status_code == 409
    assert "admin" in resp.json()["detail"].lower()
    # Nothing was deleted or deactivated.
    assert await _count(User, email="admin@example.com") == 1
    assert await _count(Household, id=uuid.UUID(hh_id)) == 1
    assert await _count(
        HouseholdMembership, household_id=uuid.UUID(hh_id), is_active=True
    ) == 2


@pytest.mark.asyncio
async def test_delete_account_sole_member_household_is_deleted(
    async_client: AsyncClient,
) -> None:
    body = await _register_and_login(async_client, "solo@example.com", "Solo")
    hh_id = await _create_household(async_client, body["access_token"], "Solo House")

    resp = await async_client.request(
        "DELETE",
        "/users/me",
        json={"current_password": _PASSWORD},
        headers=_auth(body["access_token"]),
    )
    assert resp.status_code == 204, resp.text

    assert await _count(User, email="solo@example.com") == 0
    assert await _count(Household, id=uuid.UUID(hh_id)) == 0
    assert await _count(HouseholdMembership, household_id=uuid.UUID(hh_id)) == 0


@pytest.mark.asyncio
async def test_delete_account_member_redistributes_pending_chores(
    async_client: AsyncClient,
) -> None:
    admin = await _register_and_login(async_client, "admin@example.com", "Admin")
    hh_id = await _create_household(async_client, admin["access_token"], "Shared House")
    admin_id = await _get_user_id(async_client, admin["access_token"])
    member = await _invite_and_join(
        async_client, admin["access_token"], hh_id, "member@example.com"
    )
    member_id = await _get_user_id(async_client, member["access_token"])

    pending_id = await _seed_chore(hh_id, member_id, status="pending")
    complete_id = await _seed_chore(hh_id, member_id, status="complete", points=10)

    resp = await async_client.request(
        "DELETE",
        "/users/me",
        json={"current_password": _PASSWORD},
        headers=_auth(member["access_token"]),
    )
    assert resp.status_code == 204, resp.text

    # User row gone; membership rows gone (user FK cascade); household intact.
    assert await _count(User, id=uuid.UUID(member_id)) == 0
    assert await _count(Household, id=uuid.UUID(hh_id)) == 1

    sf = _session_factory()
    async with sf() as session:
        pending = (
            await session.execute(
                select(ChoreInstance).where(ChoreInstance.id == uuid.UUID(pending_id))
            )
        ).scalar_one()
        # The pending chore was redistributed to the remaining member (admin).
        assert pending.assignee_id == uuid.UUID(admin_id)
        assert pending.status == "pending"

        complete = (
            await session.execute(
                select(ChoreInstance).where(ChoreInstance.id == uuid.UUID(complete_id))
            )
        ).scalar_one()
        # Completed chore history is preserved with assignee cleared (SET NULL).
        assert complete.status == "complete"
        assert complete.assignee_id is None


@pytest.mark.asyncio
async def test_delete_account_revokes_tokens(async_client: AsyncClient) -> None:
    body = await _register_and_login(async_client, "alice@example.com", "Alice")
    access_token = body["access_token"]
    refresh_token = body["refresh_token"]

    resp = await async_client.request(
        "DELETE",
        "/users/me",
        json={"current_password": _PASSWORD},
        headers=_auth(access_token),
    )
    assert resp.status_code == 204, resp.text

    # The refresh token can no longer be exchanged.
    refresh_resp = await async_client.post(
        "/auth/refresh", json={"refresh_token": refresh_token}
    )
    assert refresh_resp.status_code == 401

    # The access token no longer resolves to a user.
    me_resp = await async_client.get("/users/me", headers=_auth(access_token))
    assert me_resp.status_code == 401


@pytest.mark.asyncio
async def test_delete_account_admin_with_second_admin_succeeds(
    async_client: AsyncClient,
) -> None:
    admin = await _register_and_login(async_client, "admin@example.com", "Admin")
    hh_id = await _create_household(async_client, admin["access_token"], "Shared House")
    admin_id = await _get_user_id(async_client, admin["access_token"])
    member = await _invite_and_join(
        async_client, admin["access_token"], hh_id, "member@example.com"
    )
    member_id = await _get_user_id(async_client, member["access_token"])

    # Promote the member to admin so the original admin can leave.
    promote = await async_client.patch(
        f"/households/{hh_id}/members/{member_id}/role",
        json={"role": "admin"},
        headers=_auth(admin["access_token"]),
    )
    assert promote.status_code == 200, promote.text

    resp = await async_client.request(
        "DELETE",
        "/users/me",
        json={"current_password": _PASSWORD},
        headers=_auth(admin["access_token"]),
    )
    assert resp.status_code == 204, resp.text

    assert await _count(User, id=uuid.UUID(admin_id)) == 0
    assert await _count(Household, id=uuid.UUID(hh_id)) == 1
    assert await _count(
        HouseholdMembership, household_id=uuid.UUID(hh_id), is_active=True
    ) == 1
