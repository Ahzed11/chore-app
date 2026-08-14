"""Tests for POST /households/{household_id}/chores/{instance_id}/complete (TASK-013)."""
import uuid
from collections.abc import AsyncGenerator
from datetime import date, datetime, timezone

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user, require_household_member
from app.db.session import get_db
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.point_ledger import PointLedger
from app.models.user import User
from main import app
from tests.conftest import get_test_database_url as _get_test_database_url
from tests.conftest import truncate_all_tables as _truncate_all_tables


def _get_session_factory() -> async_sessionmaker:
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    return async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)


# ---------------------------------------------------------------------------
# Fake users / memberships
# ---------------------------------------------------------------------------

_ASSIGNEE_ID = uuid.uuid4()
_NON_ASSIGNEE_ID = uuid.uuid4()
_ADMIN_ID = uuid.uuid4()

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

fake_admin = User(
    id=_ADMIN_ID,
    email="admin@test.com",
    display_name="Admin",
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
    household_id=uuid.uuid4(),  # placeholder; ignored when overriding
    user_id=_NON_ASSIGNEE_ID,
    role="member",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)

fake_admin_membership = HouseholdMembership(
    id=uuid.uuid4(),
    household_id=uuid.uuid4(),  # placeholder; ignored when overriding
    user_id=_ADMIN_ID,
    role="admin",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)


def _override_current_user_assignee() -> User:
    return fake_assignee


def _override_current_user_non_assignee() -> User:
    return fake_non_assignee


def _override_current_user_admin() -> User:
    return fake_admin


def _override_require_member_assignee() -> HouseholdMembership:
    return fake_assignee_membership


def _override_require_member_non_assignee() -> HouseholdMembership:
    return fake_non_assignee_membership


def _override_require_member_admin() -> HouseholdMembership:
    return fake_admin_membership


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture()
async def async_client(_database_schema: None) -> AsyncGenerator[AsyncClient, None]:
    """AsyncClient backed by a clean test database.

    Default auth: the assignee user.  Individual tests can swap overrides as
    needed and must restore them in a finally block.
    """
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    session_factory = async_sessionmaker(
        bind=engine, class_=AsyncSession, expire_on_commit=False
    )

    await _truncate_all_tables(engine)

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
    """Create a Household plus the fake users and their memberships.

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
        admin_user = User(
            id=_ADMIN_ID,
            email="admin@test.com",
            display_name="Admin",
            password_hash="x",
        )
        session.add_all([household, assignee_user, non_assignee_user, admin_user])
        await session.flush()

        for user_id, role in (
            (_ASSIGNEE_ID, "member"),
            (_NON_ASSIGNEE_ID, "member"),
            (_ADMIN_ID, "admin"),
        ):
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
    unassigned: bool = False,
) -> tuple[uuid.UUID, uuid.UUID]:
    """Create a ChoreDefinition and ChoreInstance; return (definition_id, instance_id).

    Defaults to assigning the instance to ``_ASSIGNEE_ID``; pass
    ``unassigned=True`` to seed a truly unassigned instance (``assignee_id``
    NULL — e.g. member removed after assignment).
    """
    if not unassigned and assignee_id is None:
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
# Tests: dismiss — zero points, no PointLedger row (TASK-102)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_assignee_dismisses_own_pending_chore(async_client: AsyncClient) -> None:
    """Assignee dismissing their own pending chore: closed with zero points.

    The instance must not get a PointLedger row, so leaderboard totals are
    unchanged.
    """
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, effort_level="hard", status="pending"
    )

    response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/dismiss"
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["status"] == "dismissed"
    assert data["points_awarded"] is None
    assert data["completed_at"] is not None

    # No PointLedger row for the instance — leaderboard totals unchanged.
    async with sf() as session:
        ledger_result = await session.execute(
            select(PointLedger).where(PointLedger.chore_instance_id == instance_id)
        )
        assert ledger_result.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_admin_dismisses_members_chore(async_client: AsyncClient) -> None:
    """An admin can dismiss a member's chore on their behalf; still zero points."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, status="pending"
    )

    app.dependency_overrides[get_current_user] = _override_current_user_admin
    app.dependency_overrides[require_household_member] = _override_require_member_admin
    try:
        response = await async_client.post(
            f"/households/{household_id}/chores/{instance_id}/dismiss"
        )
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["status"] == "dismissed"
        assert data["points_awarded"] is None
    finally:
        app.dependency_overrides[get_current_user] = _override_current_user_assignee
        app.dependency_overrides[require_household_member] = (
            _override_require_member_assignee
        )

    async with sf() as session:
        ledger_result = await session.execute(
            select(PointLedger).where(PointLedger.chore_instance_id == instance_id)
        )
        assert ledger_result.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_non_assignee_non_admin_cannot_dismiss_chore(
    async_client: AsyncClient,
) -> None:
    """A household member who is neither assignee nor admin receives HTTP 403."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, status="pending"
    )

    app.dependency_overrides[get_current_user] = _override_current_user_non_assignee
    app.dependency_overrides[require_household_member] = (
        _override_require_member_non_assignee
    )
    try:
        response = await async_client.post(
            f"/households/{household_id}/chores/{instance_id}/dismiss"
        )
        assert response.status_code == 403, response.text
    finally:
        app.dependency_overrides[get_current_user] = _override_current_user_assignee
        app.dependency_overrides[require_household_member] = (
            _override_require_member_assignee
        )


@pytest.mark.asyncio
@pytest.mark.parametrize("status", ["complete", "cancelled", "dismissed"])
async def test_dismiss_terminal_instance_returns_409(
    async_client: AsyncClient, status: str
) -> None:
    """Dismissing an already-terminal instance (complete/cancelled/dismissed) → 409."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, status=status
    )

    response = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/dismiss"
    )
    assert response.status_code == 409, response.text


# ---------------------------------------------------------------------------
# Tests: admin completes on the assignee's behalf (TASK-102)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_admin_completes_members_chore_credits_assignee(
    async_client: AsyncClient,
) -> None:
    """Admin completing a member's chore awards points to the assignee, not admin."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, effort_level="medium", status="pending"
    )

    app.dependency_overrides[get_current_user] = _override_current_user_admin
    app.dependency_overrides[require_household_member] = _override_require_member_admin
    try:
        response = await async_client.post(
            f"/households/{household_id}/chores/{instance_id}/complete"
        )
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["status"] == "complete"
        assert data["points_awarded"] == 25  # medium = 25
        assert data["assignee_name"] == "Assignee"
    finally:
        app.dependency_overrides[get_current_user] = _override_current_user_assignee
        app.dependency_overrides[require_household_member] = (
            _override_require_member_assignee
        )

    # The PointLedger row is credited to the assignee, never the admin.
    async with sf() as session:
        assignee_ledger = await session.execute(
            select(PointLedger).where(
                PointLedger.chore_instance_id == instance_id,
                PointLedger.user_id == _ASSIGNEE_ID,
            )
        )
        ledger = assignee_ledger.scalar_one_or_none()
        assert ledger is not None, "Assignee should have received the points"
        assert ledger.points == 25

        admin_ledger = await session.execute(
            select(PointLedger).where(
                PointLedger.chore_instance_id == instance_id,
                PointLedger.user_id == _ADMIN_ID,
            )
        )
        assert admin_ledger.scalar_one_or_none() is None, (
            "Admin must never be credited for a chore they completed on "
            "someone's behalf"
        )


@pytest.mark.asyncio
async def test_admin_completes_unassigned_chore_awards_nothing(
    async_client: AsyncClient,
) -> None:
    """Admin completing a chore whose assignee was removed: closes with no points.

    ``assignee_id`` is NULL (member removed after assignment); the instance is
    completed but no PointLedger row is created (the user FK is non-nullable)
    and ``points_awarded`` stays NULL.
    """
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _def_id, instance_id = await _seed_chore_instance(
        sf, household_id, status="pending", unassigned=True
    )

    app.dependency_overrides[get_current_user] = _override_current_user_admin
    app.dependency_overrides[require_household_member] = _override_require_member_admin
    try:
        response = await async_client.post(
            f"/households/{household_id}/chores/{instance_id}/complete"
        )
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["status"] == "complete"
        assert data["points_awarded"] is None
        assert data["assignee_name"] is None
    finally:
        app.dependency_overrides[get_current_user] = _override_current_user_assignee
        app.dependency_overrides[require_household_member] = (
            _override_require_member_assignee
        )

    async with sf() as session:
        ledger_result = await session.execute(
            select(PointLedger).where(PointLedger.chore_instance_id == instance_id)
        )
        assert ledger_result.scalar_one_or_none() is None


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
