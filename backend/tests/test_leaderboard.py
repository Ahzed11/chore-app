"""Tests for GET /households/{household_id}/leaderboard (TASK-014)."""
import uuid
from collections.abc import AsyncGenerator
from datetime import date, datetime, timezone
from unittest.mock import patch

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user
from app.db.base import Base
from app.db.session import get_db
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.point_ledger import PointLedger
from app.models.user import User
from main import app
from tests.conftest import get_test_database_url as _get_test_database_url


def _get_session_factory() -> async_sessionmaker:
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    return async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)


# ---------------------------------------------------------------------------
# Stable fake user IDs (shared across all leaderboard tests)
# ---------------------------------------------------------------------------

_USER_A_ID = uuid.uuid4()  # "Alice"
_USER_B_ID = uuid.uuid4()  # "Bob"
_USER_C_ID = uuid.uuid4()  # "Carol"  — used in some tests


def _make_user(uid: uuid.UUID, name: str, email: str) -> User:
    return User(id=uid, email=email, display_name=name, password_hash="x")


# ---------------------------------------------------------------------------
# async_client fixture
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture()
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    """AsyncClient with a clean DB.

    get_current_user is overridden to return User A.
    require_household_member is NOT overridden — it uses the real DB lookup so
    that the membership check exercises real SQL (and non-member tests work).
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

    def override_get_current_user() -> User:
        return _make_user(_USER_A_ID, "Alice", "alice@test.com")

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()
    await engine.dispose()


# ---------------------------------------------------------------------------
# Seed helpers
# ---------------------------------------------------------------------------

async def _seed_household_with_members(
    sf: async_sessionmaker,
    member_ids: list[uuid.UUID],
    member_names: list[str],
) -> uuid.UUID:
    """Create a Household plus the requested users and their active memberships."""
    household_id = uuid.uuid4()
    async with sf() as session:
        session.add(Household(id=household_id, name="LB Household", rotation_pointer=0))
        await session.flush()
        for uid, name in zip(member_ids, member_names):
            session.add(
                User(
                    id=uid,
                    email=f"{name.lower()}@test.com",
                    display_name=name,
                    password_hash="x",
                )
            )
        await session.flush()
        for uid in member_ids:
            session.add(
                HouseholdMembership(
                    id=uuid.uuid4(),
                    household_id=household_id,
                    user_id=uid,
                    role="member",
                    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
                    is_active=True,
                )
            )
        await session.commit()
    return household_id


async def _add_ledger_entry(
    sf: async_sessionmaker,
    household_id: uuid.UUID,
    user_id: uuid.UUID,
    points: int,
    awarded_at: datetime,
) -> None:
    """Insert a single PointLedger row with an explicit awarded_at timestamp."""
    async with sf() as session:
        session.add(
            PointLedger(
                id=uuid.uuid4(),
                household_id=household_id,
                user_id=user_id,
                chore_instance_id=None,
                points=points,
                awarded_at=awarded_at,
            )
        )
        await session.commit()


async def _add_chore_instance(
    sf: async_sessionmaker,
    household_id: uuid.UUID,
    assignee_id: uuid.UUID,
    completed_at: datetime,
) -> None:
    """Insert a complete ChoreInstance with an explicit completed_at timestamp."""
    async with sf() as session:
        # We need a definition first.
        defn = ChoreDefinition(
            id=uuid.uuid4(),
            household_id=household_id,
            title="Seeded Chore",
            description=None,
            category="kitchen",
            effort_level="easy",
            chore_type="one_off",
            recurrence_rule=None,
            first_due_date=date.today(),
            is_active=True,
        )
        session.add(defn)
        await session.flush()

        session.add(
            ChoreInstance(
                id=uuid.uuid4(),
                definition_id=defn.id,
                household_id=household_id,
                assignee_id=assignee_id,
                assigned_manually=True,
                due_date=date.today(),
                status="complete",
                completed_at=completed_at,
                points_awarded=10,
            )
        )
        await session.commit()


# ---------------------------------------------------------------------------
# Tests: scope=all_time
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_all_time_returns_sum_of_all_points(async_client: AsyncClient) -> None:
    """all_time scope sums all PointLedger entries regardless of date."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(
        sf, [_USER_A_ID, _USER_B_ID], ["Alice", "Bob"]
    )

    # User A: 10 + 25 = 35 pts across two different months.
    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 10, datetime(2025, 1, 5, tzinfo=timezone.utc))
    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 25, datetime(2025, 12, 20, tzinfo=timezone.utc))
    # User B: 50 pts.
    await _add_ledger_entry(sf, hh_id, _USER_B_ID, 50, datetime(2025, 6, 10, tzinfo=timezone.utc))

    response = await async_client.get(f"/households/{hh_id}/leaderboard?scope=all_time")
    assert response.status_code == 200, response.text
    data = response.json()

    assert data["scope"] == "all_time"
    assert data["week_start"] is None
    assert data["week_end"] is None

    entries_by_user = {e["user_id"]: e for e in data["entries"]}
    assert entries_by_user[str(_USER_A_ID)]["points"] == 35
    assert entries_by_user[str(_USER_B_ID)]["points"] == 50

    # User B has more points → rank 1, Alice → rank 2.
    assert entries_by_user[str(_USER_B_ID)]["rank"] == 1
    assert entries_by_user[str(_USER_A_ID)]["rank"] == 2


@pytest.mark.asyncio
async def test_all_time_chores_completed_count(async_client: AsyncClient) -> None:
    """all_time scope counts completed ChoreInstances per user."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(
        sf, [_USER_A_ID, _USER_B_ID], ["Alice", "Bob"]
    )

    await _add_chore_instance(
        sf, hh_id, _USER_A_ID, datetime(2025, 3, 1, tzinfo=timezone.utc)
    )
    await _add_chore_instance(
        sf, hh_id, _USER_A_ID, datetime(2025, 4, 1, tzinfo=timezone.utc)
    )
    await _add_chore_instance(
        sf, hh_id, _USER_B_ID, datetime(2025, 3, 15, tzinfo=timezone.utc)
    )

    response = await async_client.get(f"/households/{hh_id}/leaderboard?scope=all_time")
    assert response.status_code == 200, response.text
    entries_by_user = {e["user_id"]: e for e in response.json()["entries"]}
    assert entries_by_user[str(_USER_A_ID)]["chores_completed"] == 2
    assert entries_by_user[str(_USER_B_ID)]["chores_completed"] == 1


# ---------------------------------------------------------------------------
# Tests: scope=this_week
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_this_week_filters_correctly(async_client: AsyncClient) -> None:
    """this_week scope only counts entries within the current ISO week."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(
        sf, [_USER_A_ID, _USER_B_ID], ["Alice", "Bob"]
    )

    # Freeze today to 2026-06-26 (Friday).
    # Week: Monday 2026-06-22 … Sunday 2026-06-28.
    frozen_today = date(2026, 6, 26)

    # In-window: 2026-06-24 (Wednesday).
    in_window = datetime(2026, 6, 24, 12, 0, 0, tzinfo=timezone.utc)
    # Out-of-window: 2026-06-20 (previous Saturday).
    out_of_window = datetime(2026, 6, 20, 12, 0, 0, tzinfo=timezone.utc)

    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 25, in_window)   # counted
    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 50, out_of_window)  # NOT counted
    await _add_ledger_entry(sf, hh_id, _USER_B_ID, 10, in_window)   # counted

    with patch("app.api.leaderboard._get_today", return_value=frozen_today):
        response = await async_client.get(
            f"/households/{hh_id}/leaderboard?scope=this_week"
        )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["scope"] == "this_week"
    assert data["week_start"] == "2026-06-22"
    assert data["week_end"] == "2026-06-28"
    assert data["month_start"] is None

    entries_by_user = {e["user_id"]: e for e in data["entries"]}
    assert entries_by_user[str(_USER_A_ID)]["points"] == 25   # only in-window entry
    assert entries_by_user[str(_USER_B_ID)]["points"] == 10


@pytest.mark.asyncio
async def test_this_week_boundary_conditions(async_client: AsyncClient) -> None:
    """Entries exactly on Monday 00:00 UTC and Sunday 23:59:59 UTC are included."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(sf, [_USER_A_ID], ["Alice"])

    frozen_today = date(2026, 6, 26)  # Friday; week: Mon 22 – Sun 28
    monday_start = datetime(2026, 6, 22, 0, 0, 0, tzinfo=timezone.utc)
    sunday_end = datetime(2026, 6, 28, 23, 59, 59, tzinfo=timezone.utc)

    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 10, monday_start)
    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 15, sunday_end)

    with patch("app.api.leaderboard._get_today", return_value=frozen_today):
        response = await async_client.get(
            f"/households/{hh_id}/leaderboard?scope=this_week"
        )

    assert response.status_code == 200, response.text
    entries = response.json()["entries"]
    assert entries[0]["points"] == 25  # both boundary entries counted


# ---------------------------------------------------------------------------
# Tests: scope=this_month
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_this_month_filters_correctly(async_client: AsyncClient) -> None:
    """this_month scope only counts entries in the current calendar month."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(
        sf, [_USER_A_ID, _USER_B_ID], ["Alice", "Bob"]
    )

    frozen_today = date(2026, 6, 15)  # June 2026

    in_june = datetime(2026, 6, 10, tzinfo=timezone.utc)
    in_may = datetime(2026, 5, 28, tzinfo=timezone.utc)

    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 30, in_june)   # counted
    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 20, in_may)    # NOT counted
    await _add_ledger_entry(sf, hh_id, _USER_B_ID, 10, in_june)   # counted

    with patch("app.api.leaderboard._get_today", return_value=frozen_today):
        response = await async_client.get(
            f"/households/{hh_id}/leaderboard?scope=this_month"
        )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["scope"] == "this_month"
    assert data["month_start"] == "2026-06-01"
    assert data["month_end"] == "2026-06-30"
    assert data["week_start"] is None

    entries_by_user = {e["user_id"]: e for e in data["entries"]}
    assert entries_by_user[str(_USER_A_ID)]["points"] == 30  # only June entry
    assert entries_by_user[str(_USER_B_ID)]["points"] == 10


# ---------------------------------------------------------------------------
# Tests: ranking
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_equal_points_share_same_rank(async_client: AsyncClient) -> None:
    """Members with identical points share the same dense rank."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(
        sf, [_USER_A_ID, _USER_B_ID, _USER_C_ID], ["Alice", "Bob", "Carol"]
    )

    ts = datetime(2026, 1, 1, tzinfo=timezone.utc)
    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 50, ts)
    await _add_ledger_entry(sf, hh_id, _USER_B_ID, 50, ts)  # tie with A
    await _add_ledger_entry(sf, hh_id, _USER_C_ID, 25, ts)  # rank 2 (dense)

    response = await async_client.get(f"/households/{hh_id}/leaderboard?scope=all_time")
    assert response.status_code == 200, response.text
    entries_by_user = {e["user_id"]: e for e in response.json()["entries"]}

    assert entries_by_user[str(_USER_A_ID)]["rank"] == 1
    assert entries_by_user[str(_USER_B_ID)]["rank"] == 1
    assert entries_by_user[str(_USER_C_ID)]["rank"] == 2  # dense: not 3


@pytest.mark.asyncio
async def test_members_with_zero_points_appear(async_client: AsyncClient) -> None:
    """Members with no PointLedger entries still appear with 0 points."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(
        sf, [_USER_A_ID, _USER_B_ID], ["Alice", "Bob"]
    )

    # Only give User A some points; User B has none.
    await _add_ledger_entry(
        sf, hh_id, _USER_A_ID, 20, datetime(2025, 5, 1, tzinfo=timezone.utc)
    )

    response = await async_client.get(f"/households/{hh_id}/leaderboard?scope=all_time")
    assert response.status_code == 200, response.text
    entries = response.json()["entries"]
    assert len(entries) == 2  # both members present

    entries_by_user = {e["user_id"]: e for e in entries}
    assert entries_by_user[str(_USER_B_ID)]["points"] == 0
    assert entries_by_user[str(_USER_B_ID)]["chores_completed"] == 0


# ---------------------------------------------------------------------------
# Tests: requesting_user_rank
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_requesting_user_rank_is_returned(async_client: AsyncClient) -> None:
    """requesting_user_rank matches the current user's rank in the leaderboard."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(
        sf, [_USER_A_ID, _USER_B_ID], ["Alice", "Bob"]
    )

    ts = datetime(2026, 1, 1, tzinfo=timezone.utc)
    await _add_ledger_entry(sf, hh_id, _USER_A_ID, 10, ts)
    await _add_ledger_entry(sf, hh_id, _USER_B_ID, 50, ts)  # User B is rank 1

    # The fixture sets current user = Alice (User A).
    response = await async_client.get(f"/households/{hh_id}/leaderboard?scope=all_time")
    assert response.status_code == 200, response.text
    data = response.json()
    # Alice has fewer points → rank 2.
    assert data["requesting_user_rank"] == 2


# ---------------------------------------------------------------------------
# Tests: validation and authorization
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_invalid_scope_returns_422(async_client: AsyncClient) -> None:
    """An unknown scope value returns HTTP 422 (FastAPI enum validation)."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(sf, [_USER_A_ID], ["Alice"])

    response = await async_client.get(
        f"/households/{hh_id}/leaderboard?scope=last_year"
    )
    assert response.status_code == 422, response.text


@pytest.mark.asyncio
async def test_non_member_cannot_access_leaderboard(async_client: AsyncClient) -> None:
    """A user who is not a household member receives HTTP 403.

    require_household_member is NOT overridden, so the real DB lookup fires.
    The current user (Alice / _USER_A_ID) is deliberately not added as a member.
    """
    sf = _get_session_factory()
    # Create a household with NO members for Alice.
    household_id = uuid.uuid4()
    async with sf() as session:
        # Add Alice as a User but NOT as a member.
        session.add(Household(id=household_id, name="Exclusive HH", rotation_pointer=0))
        session.add(
            User(
                id=_USER_A_ID,
                email="alice@test.com",
                display_name="Alice",
                password_hash="x",
            )
        )
        await session.commit()

    response = await async_client.get(f"/households/{household_id}/leaderboard")
    assert response.status_code == 403, response.text


@pytest.mark.asyncio
async def test_default_scope_is_all_time(async_client: AsyncClient) -> None:
    """Omitting the scope query param defaults to all_time."""
    sf = _get_session_factory()
    hh_id = await _seed_household_with_members(sf, [_USER_A_ID], ["Alice"])

    response = await async_client.get(f"/households/{hh_id}/leaderboard")
    assert response.status_code == 200, response.text
    assert response.json()["scope"] == "all_time"
