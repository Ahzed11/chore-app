"""Tests for /households/{household_id}/chores endpoints (TASK-011)."""
import os
import uuid
from collections.abc import AsyncGenerator
from datetime import date, datetime, timedelta, timezone
from typing import Any

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user, require_admin
from app.db.base import Base
from app.db.session import get_db
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from main import app


# ---------------------------------------------------------------------------
# Database URL helper
# ---------------------------------------------------------------------------

def _get_test_database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        raise RuntimeError(
            "TEST_DATABASE_URL environment variable is not set."
        )
    return url


# ---------------------------------------------------------------------------
# Fake users for dependency override
# ---------------------------------------------------------------------------

_ADMIN_ID = uuid.uuid4()
_MEMBER_ID = uuid.uuid4()

fake_admin = User(
    id=_ADMIN_ID,
    email="admin@test.com",
    display_name="Admin",
    password_hash="x",
)
fake_member = User(
    id=_MEMBER_ID,
    email="member@test.com",
    display_name="Member",
    password_hash="x",
)

fake_admin_membership = HouseholdMembership(
    id=uuid.uuid4(),
    household_id=uuid.uuid4(),  # placeholder, overridden per test
    user_id=_ADMIN_ID,
    role="admin",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)

fake_member_membership = HouseholdMembership(
    id=uuid.uuid4(),
    household_id=uuid.uuid4(),  # placeholder
    user_id=_MEMBER_ID,
    role="member",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)


def override_require_admin() -> HouseholdMembership:
    return fake_admin_membership


def override_get_current_user_admin() -> User:
    return fake_admin


def override_get_current_user_member() -> User:
    return fake_member


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture()
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    """AsyncClient backed by a clean test database.

    Provides admin auth overrides by default.
    Each test clears dependency_overrides after use via the fixture teardown.
    """
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
    # Default: admin auth
    app.dependency_overrides[get_current_user] = override_get_current_user_admin
    app.dependency_overrides[require_admin] = override_require_admin

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()
    await engine.dispose()


async def _seed_household_with_member(
    session_factory: async_sessionmaker,
) -> tuple[uuid.UUID, uuid.UUID]:
    """Create a Household and one admin User/Membership; return (household_id, user_id)."""
    user_id = uuid.uuid4()
    household_id = uuid.uuid4()
    async with session_factory() as session:
        user = User(
            id=user_id,
            email=f"seed-{user_id}@test.com",
            display_name="Seed User",
            password_hash="x",
        )
        household = Household(
            id=household_id,
            name="Test Household",
            rotation_pointer=0,
        )
        session.add(user)
        session.add(household)
        await session.flush()

        membership = HouseholdMembership(
            id=uuid.uuid4(),
            household_id=household_id,
            user_id=user_id,
            role="admin",
            joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
            is_active=True,
        )
        session.add(membership)
        await session.commit()
    return household_id, user_id


async def _seed_household_empty(session_factory: async_sessionmaker) -> uuid.UUID:
    """Create a Household with no members; return household_id."""
    household_id = uuid.uuid4()
    async with session_factory() as session:
        household = Household(
            id=household_id,
            name="Empty Household",
            rotation_pointer=0,
        )
        session.add(household)
        await session.commit()
    return household_id


def _get_session_factory() -> async_sessionmaker:
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    return async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)


def _one_off_payload(
    household_id: uuid.UUID,
    overrides: dict | None = None,
    due_date: date | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "title": "Wash dishes",
        "description": "Use hot water",
        "category": "kitchen",
        "effort_level": "easy",
        "chore_type": "one_off",
        "first_due_date": str(due_date or date.today().isoformat()),
    }
    if overrides:
        payload.update(overrides)
    return payload


def _recurring_payload(
    overrides: dict | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "title": "Vacuum living room",
        "category": "living_room",
        "effort_level": "medium",
        "chore_type": "recurring",
        "first_due_date": str(date.today().isoformat()),
        "recurrence_rule": {"unit": "weeks", "interval": 1},
    }
    if overrides:
        payload.update(overrides)
    return payload


# ---------------------------------------------------------------------------
# POST tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_create_one_off_chore_auto_assigned(async_client: AsyncClient) -> None:
    """POST creates a ChoreDefinition + first instance with an auto-assigned member."""
    sf = _get_session_factory()
    household_id, user_id = await _seed_household_with_member(sf)

    payload = _one_off_payload(household_id)
    response = await async_client.post(
        f"/households/{household_id}/chores",
        json=payload,
    )

    assert response.status_code == 201, response.text
    data = response.json()
    assert data["title"] == "Wash dishes"
    assert data["chore_type"] == "one_off"
    assert data["is_active"] is True

    first_instance = data["first_instance"]
    assert first_instance is not None
    assert first_instance["assignee_id"] == str(user_id)
    assert first_instance["assigned_manually"] is False
    assert first_instance["status"] == "pending"
    assert first_instance["title"] == "Wash dishes"
    assert first_instance["category"] == "kitchen"


@pytest.mark.asyncio
async def test_create_chore_manual_assignment(async_client: AsyncClient) -> None:
    """Explicit assignee_id is set without advancing the rotation pointer."""
    sf = _get_session_factory()
    household_id, user_id = await _seed_household_with_member(sf)

    # Verify the pointer starts at 0
    async with sf() as session:
        from sqlalchemy import select as sa_select
        result = await session.execute(sa_select(Household).where(Household.id == household_id))
        hh = result.scalar_one()
        initial_pointer = hh.rotation_pointer

    payload = _one_off_payload(household_id, overrides={"assignee_id": str(user_id)})
    response = await async_client.post(
        f"/households/{household_id}/chores",
        json=payload,
    )

    assert response.status_code == 201, response.text
    data = response.json()
    first_instance = data["first_instance"]
    assert first_instance["assignee_id"] == str(user_id)
    assert first_instance["assigned_manually"] is True

    # Rotation pointer must NOT have advanced
    async with sf() as session:
        from sqlalchemy import select as sa_select
        result = await session.execute(sa_select(Household).where(Household.id == household_id))
        hh = result.scalar_one()
        assert hh.rotation_pointer == initial_pointer


@pytest.mark.asyncio
async def test_create_recurring_chore_requires_recurrence_rule(async_client: AsyncClient) -> None:
    """Recurring chore without recurrence_rule returns 422."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    payload = {
        "title": "Weekly vacuum",
        "category": "living_room",
        "effort_level": "medium",
        "chore_type": "recurring",
        "first_due_date": str(date.today().isoformat()),
        # recurrence_rule intentionally omitted
    }
    response = await async_client.post(
        f"/households/{household_id}/chores",
        json=payload,
    )
    assert response.status_code == 422, response.text


@pytest.mark.asyncio
async def test_create_chore_no_members_assignee_null(async_client: AsyncClient) -> None:
    """When household has no members, the first instance has assignee_id = null."""
    sf = _get_session_factory()
    household_id = await _seed_household_empty(sf)

    payload = _one_off_payload(household_id)
    response = await async_client.post(
        f"/households/{household_id}/chores",
        json=payload,
    )
    assert response.status_code == 201, response.text
    data = response.json()
    first_instance = data["first_instance"]
    assert first_instance["assignee_id"] is None
    assert first_instance["assigned_manually"] is False


# ---------------------------------------------------------------------------
# GET list tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_chores(async_client: AsyncClient) -> None:
    """GET returns a list of chore instances."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    # Create two chores
    for title in ("Chore A", "Chore B"):
        await async_client.post(
            f"/households/{household_id}/chores",
            json=_one_off_payload(household_id, overrides={"title": title}),
        )

    response = await async_client.get(f"/households/{household_id}/chores")
    assert response.status_code == 200, response.text
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 2
    titles = {item["title"] for item in data}
    assert titles == {"Chore A", "Chore B"}


@pytest.mark.asyncio
async def test_filter_chores_by_status(async_client: AsyncClient) -> None:
    """status_filter=pending returns only pending instances."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    await async_client.post(
        f"/households/{household_id}/chores",
        json=_one_off_payload(household_id, overrides={"title": "Pending Chore"}),
    )

    response = await async_client.get(
        f"/households/{household_id}/chores",
        params={"status_filter": "pending"},
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert len(data) >= 1
    for item in data:
        assert item["status"] == "pending"


@pytest.mark.asyncio
async def test_filter_chores_by_category(async_client: AsyncClient) -> None:
    """category=kitchen returns only kitchen chores."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    # Create a kitchen chore
    await async_client.post(
        f"/households/{household_id}/chores",
        json=_one_off_payload(household_id, overrides={"title": "Kitchen Chore", "category": "kitchen"}),
    )
    # Create a bathroom chore
    await async_client.post(
        f"/households/{household_id}/chores",
        json=_one_off_payload(household_id, overrides={"title": "Bathroom Chore", "category": "bathroom"}),
    )

    response = await async_client.get(
        f"/households/{household_id}/chores",
        params={"category": "kitchen"},
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert len(data) == 1
    assert data[0]["category"] == "kitchen"
    assert data[0]["title"] == "Kitchen Chore"


# ---------------------------------------------------------------------------
# GET single instance tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_chore_instance(async_client: AsyncClient) -> None:
    """GET /{instance_id} returns a single ChoreInstanceResponse with definition data."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    create_resp = await async_client.post(
        f"/households/{household_id}/chores",
        json=_one_off_payload(household_id),
    )
    assert create_resp.status_code == 201
    instance_id = create_resp.json()["first_instance"]["id"]

    response = await async_client.get(
        f"/households/{household_id}/chores/{instance_id}"
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["id"] == instance_id
    assert data["title"] == "Wash dishes"
    assert data["category"] == "kitchen"
    assert data["status"] == "pending"


@pytest.mark.asyncio
async def test_get_chore_instance_wrong_household_returns_404(async_client: AsyncClient) -> None:
    """GET /{instance_id} with wrong household returns 404."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)
    other_household_id = uuid.uuid4()

    create_resp = await async_client.post(
        f"/households/{household_id}/chores",
        json=_one_off_payload(household_id),
    )
    assert create_resp.status_code == 201
    instance_id = create_resp.json()["first_instance"]["id"]

    response = await async_client.get(
        f"/households/{other_household_id}/chores/{instance_id}"
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# PATCH tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_update_chore_definition(async_client: AsyncClient) -> None:
    """PATCH updates ChoreDefinition fields and does not touch existing instances."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    create_resp = await async_client.post(
        f"/households/{household_id}/chores",
        json=_one_off_payload(household_id),
    )
    assert create_resp.status_code == 201
    definition_id = create_resp.json()["id"]
    instance_id = create_resp.json()["first_instance"]["id"]

    patch_resp = await async_client.patch(
        f"/households/{household_id}/chores/{definition_id}",
        json={"title": "Updated Dish Washing"},
    )
    assert patch_resp.status_code == 200, patch_resp.text
    patch_data = patch_resp.json()
    assert patch_data["title"] == "Updated Dish Washing"
    assert patch_data["id"] == definition_id

    # The existing instance title (denormalized via join) should still work
    # but the instance itself was NOT updated — check via GET instance
    get_resp = await async_client.get(
        f"/households/{household_id}/chores/{instance_id}"
    )
    # Instance title comes from the definition join, so it reflects the updated definition
    assert get_resp.status_code == 200
    # The instance record itself is unchanged (no direct status change)
    assert get_resp.json()["status"] == "pending"


# ---------------------------------------------------------------------------
# DELETE tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_delete_chore_cancels_pending(async_client: AsyncClient) -> None:
    """DELETE soft-deletes definition and cancels pending instances; completed untouched."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    # Create a chore — produces a pending instance
    create_resp = await async_client.post(
        f"/households/{household_id}/chores",
        json=_one_off_payload(household_id),
    )
    assert create_resp.status_code == 201
    definition_id = create_resp.json()["id"]
    instance_id = create_resp.json()["first_instance"]["id"]

    # Manually mark the instance as "complete" in the DB so we can also test
    # that a second (pending) instance is cancelled but the complete one is not.
    # We do that by creating a second chore of the same definition via direct DB manipulation.
    from sqlalchemy import select as sa_select
    from app.models.chore_instance import ChoreInstance

    async with sf() as session:
        # Mark the existing instance as complete
        result = await session.execute(
            sa_select(ChoreInstance).where(ChoreInstance.id == uuid.UUID(instance_id))
        )
        inst = result.scalar_one()
        inst.status = "complete"
        inst.completed_at = datetime.now(timezone.utc)

        # Add a new pending instance for the same definition
        from app.models.chore_definition import ChoreDefinition
        result2 = await session.execute(
            sa_select(ChoreDefinition).where(ChoreDefinition.id == uuid.UUID(definition_id))
        )
        defn = result2.scalar_one()
        pending_inst = ChoreInstance(
            definition_id=defn.id,
            household_id=household_id,
            assignee_id=None,
            assigned_manually=False,
            due_date=date.today() + timedelta(days=7),
            status="pending",
        )
        session.add(pending_inst)
        await session.commit()
        pending_inst_id = pending_inst.id

    # Now DELETE the definition
    delete_resp = await async_client.delete(
        f"/households/{household_id}/chores/{definition_id}"
    )
    assert delete_resp.status_code == 204, delete_resp.text

    # Verify pending instance is now cancelled
    async with sf() as session:
        result = await session.execute(
            sa_select(ChoreInstance).where(ChoreInstance.id == pending_inst_id)
        )
        cancelled_inst = result.scalar_one()
        assert cancelled_inst.status == "cancelled"

        # Verify completed instance is untouched
        result2 = await session.execute(
            sa_select(ChoreInstance).where(ChoreInstance.id == uuid.UUID(instance_id))
        )
        completed_inst = result2.scalar_one()
        assert completed_inst.status == "complete"

    # Verify definition is now inactive
    async with sf() as session:
        from app.models.chore_definition import ChoreDefinition
        result = await session.execute(
            sa_select(ChoreDefinition).where(ChoreDefinition.id == uuid.UUID(definition_id))
        )
        defn = result.scalar_one()
        assert defn.is_active is False


# ---------------------------------------------------------------------------
# Authorization tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_member_cannot_create_chore(async_client: AsyncClient) -> None:
    """Non-admin members receive 403 when attempting to create a chore."""
    sf = _get_session_factory()
    household_id, _ = await _seed_household_with_member(sf)

    # Override require_admin to raise 403 (simulating a member, not admin)
    from fastapi import HTTPException, status as http_status

    def override_require_admin_forbidden():
        raise HTTPException(
            status_code=http_status.HTTP_403_FORBIDDEN,
            detail="Admin role required",
        )

    app.dependency_overrides[require_admin] = override_require_admin_forbidden

    try:
        response = await async_client.post(
            f"/households/{household_id}/chores",
            json=_one_off_payload(household_id),
        )
        assert response.status_code == 403, response.text
    finally:
        # Restore admin override for any subsequent tests sharing the client
        app.dependency_overrides[require_admin] = override_require_admin
