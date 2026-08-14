"""Tests for chore-template endpoints (TASK-106)."""
import uuid
from collections.abc import AsyncGenerator
from datetime import date, datetime, timezone

import pytest
import pytest_asyncio
from fastapi import HTTPException, status
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user, require_admin
from app.db.session import get_db
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
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
    household_id=uuid.uuid4(),  # placeholder; ignored when overriding
    user_id=_ADMIN_ID,
    role="admin",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)

fake_member_membership = HouseholdMembership(
    id=uuid.uuid4(),
    household_id=uuid.uuid4(),  # placeholder; ignored when overriding
    user_id=_MEMBER_ID,
    role="member",
    joined_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    is_active=True,
)


def _override_current_user_admin() -> User:
    return fake_admin


def _override_require_admin() -> HouseholdMembership:
    return fake_admin_membership


def _override_require_admin_forbidden() -> HouseholdMembership:
    # Mirrors the real require_admin dependency's behaviour for non-admins.
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Admin role required",
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture()
async def async_client(_database_schema: None) -> AsyncGenerator[AsyncClient, None]:
    """AsyncClient backed by a clean test database. Default auth: the admin."""
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
    app.dependency_overrides[get_current_user] = _override_current_user_admin
    app.dependency_overrides[require_admin] = _override_require_admin

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()
    await engine.dispose()


# ---------------------------------------------------------------------------
# Seed helpers
# ---------------------------------------------------------------------------

async def _seed_household_and_users(sf: async_sessionmaker) -> uuid.UUID:
    """Create a Household plus admin and member users with memberships."""
    household_id = uuid.uuid4()
    async with sf() as session:
        household = Household(id=household_id, name="Test HH", rotation_pointer=0)
        admin_user = User(
            id=_ADMIN_ID,
            email="admin@test.com",
            display_name="Admin",
            password_hash="x",
        )
        member_user = User(
            id=_MEMBER_ID,
            email="member@test.com",
            display_name="Member",
            password_hash="x",
        )
        session.add_all([household, admin_user, member_user])
        await session.flush()

        for user_id, role in ((_ADMIN_ID, "admin"), (_MEMBER_ID, "member")):
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


async def _seed_definition(
    sf: async_sessionmaker,
    household_id: uuid.UUID,
    *,
    title: str,
    created_at: datetime,
    effort_level: str = "medium",
    category: str = "kitchen",
    hidden: bool = False,
    with_instance: bool = True,
) -> uuid.UUID:
    """Create a ChoreDefinition (+ optional first instance); return definition_id.

    ``created_at`` is set explicitly so template ordering is deterministic
    (Postgres ``now()`` is transaction-stable, so two rows in one commit
    would otherwise tie).
    """
    async with sf() as session:
        definition = ChoreDefinition(
            id=uuid.uuid4(),
            household_id=household_id,
            title=title,
            description=f"desc-{title}",
            category=category,
            effort_level=effort_level,
            chore_type="one_off",
            recurrence_rule=None,
            first_due_date=date(2026, 12, 31),
            is_active=True,
            hidden_from_suggestions=hidden,
            created_at=created_at,
        )
        session.add(definition)
        await session.flush()

        if with_instance:
            session.add(
                ChoreInstance(
                    id=uuid.uuid4(),
                    definition_id=definition.id,
                    household_id=household_id,
                    assignee_id=_ADMIN_ID,
                    assigned_manually=True,
                    due_date=date(2026, 12, 31),
                    status="pending",
                )
            )
        await session.commit()
        return definition.id


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_admin_lists_active_templates_newest_first(
    async_client: AsyncClient,
) -> None:
    """GET /templates returns active definitions, newest first, template fields only."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    _old = await _seed_definition(
        sf,
        household_id,
        title="Old task",
        effort_level="easy",
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    _new = await _seed_definition(
        sf,
        household_id,
        title="New task",
        effort_level="hard",
        created_at=datetime(2026, 2, 1, tzinfo=timezone.utc),
    )

    response = await async_client.get(f"/households/{household_id}/chores/templates")

    assert response.status_code == 200, response.text
    data = response.json()
    assert [d["id"] for d in data] == [str(_new), str(_old)]

    first = data[0]
    assert first["title"] == "New task"
    assert first["description"] == "desc-New task"
    assert first["category"] == "kitchen"
    assert first["effort_level"] == "hard"
    # Exactly the template fields — no definition internals leak through.
    assert set(first.keys()) == {"id", "title", "description", "category", "effort_level"}


@pytest.mark.asyncio
async def test_hidden_definition_excluded_from_templates_but_instances_remain(
    async_client: AsyncClient,
) -> None:
    """Hiding only affects templates — the chore list still shows its instances."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    def_id = await _seed_definition(
        sf,
        household_id,
        title="Hidden chore",
        hidden=True,
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )

    templates = await async_client.get(f"/households/{household_id}/chores/templates")
    assert templates.status_code == 200, templates.text
    assert all(d["id"] != str(def_id) for d in templates.json())

    chores = await async_client.get(f"/households/{household_id}/chores")
    assert chores.status_code == 200, chores.text
    assert any(
        i["definition_id"] == str(def_id) for i in chores.json()["items"]
    ), "Hidden definition's instance must still appear in the chore list"


@pytest.mark.asyncio
async def test_admin_hides_template_and_it_disappears(
    async_client: AsyncClient,
) -> None:
    """POST hide → 204; a follow-up GET /templates no longer includes it."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    def_id = await _seed_definition(
        sf,
        household_id,
        title="To hide",
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )

    response = await async_client.post(
        f"/households/{household_id}/chores/{def_id}/hide"
    )
    assert response.status_code == 204, response.text

    templates = await async_client.get(f"/households/{household_id}/chores/templates")
    assert templates.status_code == 200
    assert templates.json() == []


@pytest.mark.asyncio
async def test_hide_nonexistent_definition_returns_404(
    async_client: AsyncClient,
) -> None:
    """Hiding a definition that doesn't exist (or isn't active) → 404."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)

    response = await async_client.post(
        f"/households/{household_id}/chores/{uuid.uuid4()}/hide"
    )
    assert response.status_code == 404, response.text


@pytest.mark.asyncio
async def test_member_cannot_list_or_hide_templates(
    async_client: AsyncClient,
) -> None:
    """Both endpoints are admin-gated: a member gets 403."""
    sf = _get_session_factory()
    household_id = await _seed_household_and_users(sf)
    def_id = await _seed_definition(
        sf,
        household_id,
        title="Admin only",
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )

    app.dependency_overrides[require_admin] = _override_require_admin_forbidden
    try:
        response = await async_client.get(
            f"/households/{household_id}/chores/templates"
        )
        assert response.status_code == 403, response.text

        response = await async_client.post(
            f"/households/{household_id}/chores/{def_id}/hide"
        )
        assert response.status_code == 403, response.text
    finally:
        app.dependency_overrides[require_admin] = _override_require_admin
