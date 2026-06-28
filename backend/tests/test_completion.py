"""Tests for POST /households/{household_id}/chores/{instance_id}/complete (TASK-013)."""
import os
import uuid
from collections.abc import AsyncGenerator
from datetime import date, datetime, timezone
from typing import Any

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user, require_household_member
from app.db.base import Base
from app.db.session import get_db
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.point_ledger import PointLedger
from app.models.user import User
from main import app


# ---------------------------------------------------------------------------
# Database URL helper
# ---------------------------------------------------------------------------

def _get_test_database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        raise RuntimeError("TEST_DATABASE_URL environment variable is not set.")
    return url


def _get_session_factory() -> async_sessionmaker:
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    return async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)


# ---------------------------------------------------------------------------
# Fake users / memberships
# ---------------------------------------------------------------------------

_ASSIGNEE_ID = uuid.uuid4()
_NON_ASSIGNEE_ID = uuid.uuid4()

fake_assignee = User(
    id=_ASSIGNEE_ID,
    email="assignee@test.com",
    display_name="Assignee",
    password_hash="x",
)

fake_non_assignee = User(
    id=_NON_ASSIGNEE_ID,
    email="non_assignee@test.com",
    display_name="NonAssignee",
    password_hash="x",
)

fake_assignee_membership = HouseholdMembership(
    id=uuid.uuid4(),
    household_id=uuid.uuid4(),  # placeholder; ignored when overriding
    user_id=_ASSIGNEE_ID,
    role="member",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)

fake_non_assignee_membership = HouseholdMembership(
    id=uuid.uuid4(),
    household_id=uuid.uuid4(),
    user_id=_NON_ASSIGNEE_ID,
    role="member",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)


def _override_current_user_assignee() -> User:
    return fake_assignee


def _override_current_user_non_assignee() -> User:
    return fake_non_assignee


def _override_require_member_assignee() -> HouseholdMembership:
    return fake_assignee_membership


def _override_require_member_non_assignee() -> HouseholdMembership:
    return fake_non_assignee_membership


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture()
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    """AsyncClient backed by a clean test database.

    Default auth: the assignee user.  Individual tests can swap overrides as
    needed and must restore them in a finally block.
    """
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    session_factory = async_sessionmaker(
        bind=engine, class_=AsyncSession, expire_on_commit=False
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
    app.dependency_overrides[get_current_user] = _override_current_user_assignee
    app.dependency_overrides[require_household_member] = _override_require_member_assignee

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()
    await engine.dispose()


# ---------------------------------------------------------------------------
# Seed helpers
# ---------------------------------------------------------------------------

async def _seed_household_and_users(sf: async_sessionmaker) -> uuid.UUID:
    """Create a Household plus both fake users and their memberships.

    Returns the household_id.
    """
    household_id = uuid.uuid4()
    async with sf() as session:
        household = Household(id=household_id, name="Test HH", rotation_pointer=0)
        assignee_user = User(
            id=_ASSIGNEE_ID,
            email="assignee@test.com",
            display_name="Assignee",
            password_hash="x",
        )
        non_assignee_user = User(
            id=_NON_ASSIGNEE_ID,
            email="non_assignee@test.com",
            display_name="NonAssignee",
            password_hash="x",
        )
        session.add_all([household, assignee_user, non_assignee_user])
        await session.flush()

        for user_id, role in ((_ASSIGNEE_ID, "member"), (_NON_ASSIGNEE_ID, "member")):
            session.add(
                HouseholdMembership(
                    id=uuid.uuid4(),
                    household_id=household_id,
                    user_id=user_id,
                    role=role,
                    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
                    is_active=True,
                )
            )
        await session.commit()
    return household_id


async def _seed_chore_instance(
    sf: async_sessionmaker,
    household_id: uuid.UUID,
    *,
    effort_level: str = "easy",
    assignee_id: uuid.UUID | None = None,
    status: str = "pending",
) -> tuple[uuid.UUID, uuid.UUID]:
    """Create a ChoreDefinition and ChoreInstance; return (definition_id, instance_id)."""
    if assignee_id is None:
        assignee_id = _ASSIGNEE_ID

    async with sf() as session:
        definition = ChoreDefinition(
            id=uuid.uuid4(),
            household_id=household_id,
            title="Test Chore",
            description=None,
            category="kitchen",
            effort_level=effort_level,
            chore_type="one_off",
            recurrence_rule=None,
            first_due_date=date.today(),
            is_active=True,
        )
        session.add(definition)
        await session.flush()

        instance = ChoreInstance(
            id=uuid.uuid4(),
            definition_id=definition.id,
            household_id=household_id,
            assignee_id=assignee_id,
            assigned_manually=True,
            due_date=date.today(),
            status=status,
        )
        session.add(instance)
        await session.commit()
        return definition.id, instance.id


# ---------------------------------------------------------------------------
# Tests: assignee can complete pending/overdue chores
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_assignee_completes_pending_chore(async_client: AsyncClient) -> None:
    """Assignee completing a pending chore returns 200 with correct points.

    A PointLedger entry must also be persisted.
    """
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, effort_level="easy", status="pending"
    )

    response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete"
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["status"] == "complete"
    assert data["points_awarded"] == 10  # easy = 10
    assert data["completed_at"] is not None

    # Verify a PointLedger entry was created.
    async with sf() as session:
        ledger_result = await session.execute(
            select(PointLedger).where(
                PointLedger.chore_instance_id == instance_id,
                PointLedger.user_id == _ASSIGNEE_ID,
                PointLedger.household_id == household_id,
            )
        )
        ledger = ledger_result.scalar_one_or_none()
        assert ledger is not None, "Expected a PointLedger entry to be created"
        assert ledger.points == 10


@pytest.mark.asyncio
async def test_assignee_completes_overdue_chore(async_client: AsyncClient) -> None:
    """Assignee completing an overdue chore returns 200."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, effort_level="medium", status="overdue"
    )

    response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete"
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["status"] == "complete"
    assert data["points_awarded"] == 25  # medium = 25


@pytest.mark.asyncio
async def test_hard_chore_awards_50_points(async_client: AsyncClient) -> None:
    """Hard chores award 50 points."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, effort_level="hard", status="pending"
    )

    response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete"
    )

    assert response.status_code == 200, response.text
    assert response.json()["points_awarded"] == 50


# ---------------------------------------------------------------------------
# Tests: authorization
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_non_assignee_cannot_complete_chore(async_client: AsyncClient) -> None:
    """A household member who is not the assignee receives HTTP 403."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    # Chore is assigned to _ASSIGNEE_ID but request comes from non-assignee.
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, assignee_id=_ASSIGNEE_ID, status="pending"
    )

    app.dependency_overrides[get_current_user] = _override_current_user_non_assignee
    app.dependency_overrides[require_household_member] = _override_require_member_non_assignee
    try:
        response = await async_client.post(
            f"/households/{household_id}/chores/{instance_id}/complete"
        )
        assert response.status_code == 403, response.text
    finally:
        app.dependency_overrides[get_current_user] = _override_current_user_assignee
        app.dependency_overrides[require_household_member] = _override_require_member_assignee


# ---------------------------------------------------------------------------
# Tests: status conflicts
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_completing_already_complete_chore_returns_409(
    async_client: AsyncClient,
) -> None:
    """Attempting to complete an already-complete instance returns HTTP 409."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, status="complete"
    )
    # Mark it complete in the DB directly (bypassing the endpoint).
    async with sf() as session:
        result = await session.execute(
            select(ChoreInstance).where(ChoreInstance.id == instance_id)
        )
        inst = result.scalar_one()
        inst.completed_at = datetime.now(timezone.utc)
        inst.points_awarded = 10
        await session.commit()

    response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete"
    )
    assert response.status_code == 409, response.text


@pytest.mark.asyncio
async def test_completing_cancelled_chore_returns_409(
    async_client: AsyncClient,
) -> None:
    """Attempting to complete a cancelled instance returns HTTP 409."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, status="cancelled"
    )

    response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete"
    )
    assert response.status_code == 409, response.text


# ---------------------------------------------------------------------------
# Tests: concurrent (sequential) completion
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_sequential_concurrent_completion_idempotency(
    async_client: AsyncClient,
) -> None:
    """Two sequential completion requests: first succeeds (200), second gets 409.

    This exercises the guard that prevents double-completion, which in
    production is enforced by SELECT FOR UPDATE on the row.
    """
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, status="pending"
    )

    first_response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete"
    )
    assert first_response.status_code == 200, first_response.text

    second_response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete"
    )
    assert second_response.status_code == 409, second_response.text

    # Verify only one PointLedger entry exists.
    async with sf() as session:
        ledger_result = await session.execute(
            select(PointLedger).where(
                PointLedger.chore_instance_id == instance_id
            )
        )
        ledger_rows = ledger_result.scalars().all()
        assert len(ledger_rows) == 1, "Expected exactly one PointLedger entry"


# ---------------------------------------------------------------------------
# Tests: 404
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_complete_nonexistent_instance_returns_404(
    async_client: AsyncClient,
) -> None:
    """Completing a nonexistent instance returns 404."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    bogus_id = uuid.uuid4()

    response = await async_client.post(
        f"/households/{household_id}/chores/{bogus_id}/complete"
    )
    assert response.status_code == 404, response.text
