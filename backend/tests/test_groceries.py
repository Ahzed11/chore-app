"""Tests for /households/{household_id}/groceries endpoints (TASK-085)."""
import uuid
from collections.abc import AsyncGenerator
from datetime import datetime, timezone

import pytest
import pytest_asyncio
from fastapi import HTTPException
from fastapi import status as fastapi_status
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user, require_household_member
from app.db.session import get_db
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from main import app
from tests.conftest import get_test_database_url as _get_test_database_url
from tests.conftest import truncate_all_tables as _truncate_all_tables

# ---------------------------------------------------------------------------
# Fake users for dependency override
# ---------------------------------------------------------------------------

_ADMIN_ID = uuid.uuid4()
_MEMBER_ID = uuid.uuid4()
_OTHER_USER_ID = uuid.uuid4()

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
fake_other_user = User(
    id=_OTHER_USER_ID,
    email="other@test.com",
    display_name="Other User",
    password_hash="x",
)

fake_membership = HouseholdMembership(
    id=uuid.uuid4(),
    household_id=uuid.uuid4(),  # placeholder, overridden per test
    user_id=_ADMIN_ID,
    role="admin",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)


def override_require_household_member() -> HouseholdMembership:
    return fake_membership


def override_get_current_user_admin() -> User:
    return fake_admin


def override_get_current_user_member() -> User:
    return fake_member


def override_get_current_user_other() -> User:
    return fake_other_user


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture()
async def async_client(_database_schema: None) -> AsyncGenerator[AsyncClient, None]:
    """AsyncClient backed by a clean test database with admin auth overrides."""
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)

    session_factory = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    await _truncate_all_tables(engine)

    # Seed the fake users so added_by_id / purchased_by_id FKs are valid.
    async with session_factory() as session:
        session.add(User(id=_ADMIN_ID, email="admin@test.com", display_name="Admin", password_hash="x"))
        session.add(User(id=_MEMBER_ID, email="member@test.com", display_name="Member", password_hash="x"))
        session.add(User(id=_OTHER_USER_ID, email="other@test.com", display_name="Other User", password_hash="x"))
        await session.commit()

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
    app.dependency_overrides[require_household_member] = override_require_household_member

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()
    await engine.dispose()


@pytest_asyncio.fixture()
async def seeded_household(
    async_client: AsyncClient,
) -> tuple[uuid.UUID, uuid.UUID]:
    """Seed a real Household row (with no memberships); return (household_id, item_id)."""
    # Create the household through the API (admin is auto-member via override).
    response = await async_client.post(
        "/households",
        json={"name": "Grocery Test Household"},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _ADMIN_ID


def _item_url(household_id: uuid.UUID, item_id: uuid.UUID | None = None) -> str:
    base = f"/households/{household_id}/groceries"
    return base if item_id is None else f"{base}/{item_id}"


async def _create_item(
    client: AsyncClient,
    household_id: uuid.UUID,
    name: str = "Milk",
    quantity: str | None = "2 cartons",
    notes: str | None = None,
) -> dict:
    body: dict = {"name": name}
    if quantity is not None:
        body["quantity"] = quantity
    if notes is not None:
        body["notes"] = notes
    response = await client.post(_item_url(household_id), json=body)
    assert response.status_code == 201, response.text
    return response.json()


# ---------------------------------------------------------------------------
# CRUD tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_add_item(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    response = await async_client.post(
        _item_url(household_id),
        json={"name": "Milk", "quantity": "2 cartons"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Milk"
    assert data["quantity"] == "2 cartons"
    assert data["is_purchased"] is False
    assert data["added_by_name"] == "Admin"
    assert data["added_by_id"] == str(_ADMIN_ID)
    assert data["purchased_by_id"] is None
    assert data["purchased_at"] is None


@pytest.mark.asyncio
async def test_list_items_ordered_newest_first(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    await _create_item(async_client, household_id, name="Milk")
    await _create_item(async_client, household_id, name="Bread")
    await _create_item(async_client, household_id, name="Eggs")

    response = await async_client.get(_item_url(household_id))
    assert response.status_code == 200
    items = response.json()
    assert [i["name"] for i in items] == ["Eggs", "Bread", "Milk"]


@pytest.mark.asyncio
async def test_update_item_name(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    item = await _create_item(async_client, household_id, name="Milk")
    response = await async_client.patch(
        _item_url(household_id, item["id"]),
        json={"name": "Oat Milk"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Oat Milk"
    assert data["quantity"] == "2 cartons"  # unchanged field survives


@pytest.mark.asyncio
async def test_update_item_quantity_and_notes(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    item = await _create_item(async_client, household_id, name="Milk")
    response = await async_client.patch(
        _item_url(household_id, item["id"]),
        json={"quantity": "1 gallon", "notes": "Organic only"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["quantity"] == "1 gallon"
    assert data["notes"] == "Organic only"


@pytest.mark.asyncio
async def test_delete_item(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    item = await _create_item(async_client, household_id, name="Milk")
    response = await async_client.delete(_item_url(household_id, item["id"]))
    assert response.status_code == 204

    list_response = await async_client.get(_item_url(household_id))
    assert list_response.json() == []


# ---------------------------------------------------------------------------
# Purchase / unpurchase tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_purchase_item(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    item = await _create_item(async_client, household_id, name="Milk")
    response = await async_client.post(f"{_item_url(household_id, item['id'])}/purchase")
    assert response.status_code == 200
    data = response.json()
    assert data["is_purchased"] is True
    assert data["purchased_by_id"] == str(_ADMIN_ID)
    assert data["purchased_by_name"] == "Admin"
    assert data["purchased_at"] is not None


@pytest.mark.asyncio
async def test_unpurchase_item(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    item = await _create_item(async_client, household_id, name="Milk")
    await async_client.post(f"{_item_url(household_id, item['id'])}/purchase")
    response = await async_client.post(f"{_item_url(household_id, item['id'])}/unpurchase")
    assert response.status_code == 200
    data = response.json()
    assert data["is_purchased"] is False
    assert data["purchased_by_id"] is None
    assert data["purchased_by_name"] is None
    assert data["purchased_at"] is None


@pytest.mark.asyncio
async def test_purchase_already_purchased_idempotent(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    item = await _create_item(async_client, household_id, name="Milk")
    first = await async_client.post(f"{_item_url(household_id, item['id'])}/purchase")
    assert first.status_code == 200
    second = await async_client.post(f"{_item_url(household_id, item['id'])}/purchase")
    assert second.status_code == 200
    assert second.json()["is_purchased"] is True


# ---------------------------------------------------------------------------
# Auth / permission tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_unauthenticated_rejected(_database_schema: None):
    """No auth dependency overrides at all → 401 from the real dependency chain."""
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    await _truncate_all_tables(engine)
    session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

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
        response = await client.get("/households/00000000-0000-0000-0000-000000000000/groceries")
        assert response.status_code == 401

    app.dependency_overrides.clear()
    await engine.dispose()


@pytest.mark.asyncio
async def test_non_member_rejected(async_client: AsyncClient, seeded_household):
    """A user who is not a member of the household gets 403."""
    household_id, _ = seeded_household
    app.dependency_overrides[get_current_user] = override_get_current_user_other

    def override_require_household_member_other() -> HouseholdMembership:
        raise HTTPException(
            status_code=fastapi_status.HTTP_403_FORBIDDEN,
            detail="Not a member of this household",
        )

    app.dependency_overrides[require_household_member] = override_require_household_member_other

    response = await async_client.get(_item_url(household_id))
    assert response.status_code == 403

    app.dependency_overrides[get_current_user] = override_get_current_user_admin
    app.dependency_overrides[require_household_member] = override_require_household_member


@pytest.mark.asyncio
async def test_wrong_household_404(async_client: AsyncClient, seeded_household):
    """A valid member querying an item from another household gets 404."""
    household_id, _ = seeded_household
    item = await _create_item(async_client, household_id, name="Milk")

    # A different household id — the item belongs to `household_id`, not this one.
    other_household_id = uuid.uuid4()
    response = await async_client.patch(
        _item_url(other_household_id, item["id"]),
        json={"name": "Ghost"},
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Validation tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_add_item_empty_name(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    response = await async_client.post(_item_url(household_id), json={"name": ""})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_update_nonexistent_item_404(async_client: AsyncClient, seeded_household):
    household_id, _ = seeded_household
    response = await async_client.patch(
        _item_url(household_id, uuid.uuid4()),
        json={"name": "Ghost"},
    )
    assert response.status_code == 404
