"""Shared pytest fixtures for the backend test suite."""
import asyncio
import os
from collections.abc import AsyncGenerator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.rate_limit import limiter
from app.db.base import Base
from app.db.session import get_db
from main import app


@pytest.fixture(scope="session", autouse=True)
def _disable_rate_limiting_by_default() -> None:
    """TASK-031: keep the shared slowapi limiter off for the whole test session.

    ``limiter`` (app/core/rate_limit.py) defaults to
    ``Settings.RATE_LIMIT_ENABLED`` (True in production). Left on, the 200+
    existing tests that log in/register repeatedly against the same client IP
    would start flaking against the 5/minute login and 10/hour register caps.
    Dedicated rate-limit tests (tests/test_rate_limit.py) flip ``limiter.enabled``
    back on locally, with tight test-only limits, to assert the 429 behavior.
    """
    limiter.enabled = False


@pytest.fixture(scope="session", autouse=True)
def _fast_password_hashing():
    """Drop the bcrypt work factor from 12 to 4 rounds for the test session.

    Registration/login-heavy tests spend most of their wall time inside
    bcrypt at production cost (~0.25s per hash/verify).  Real bcrypt is still
    used — hash format and verify_password semantics are unchanged, only the
    cost parameter differs — so all correctness assertions keep working.
    """
    import bcrypt

    from app.api import auth as auth_module

    original = auth_module.hash_password

    def fast_hash_password(plain: str) -> str:
        return bcrypt.hashpw(plain.encode(), bcrypt.gensalt(rounds=4)).decode()

    # auth.py binds the name at import time, so patch it there.
    auth_module.hash_password = fast_hash_password
    yield
    auth_module.hash_password = original


def get_test_database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        raise RuntimeError(
            "TEST_DATABASE_URL environment variable is not set. "
            "Please provide a PostgreSQL URL before running the test suite."
        )
    return url


# ---------------------------------------------------------------------------
# Schema lifecycle (TASK-080 L5)
#
# The schema is dropped and recreated ONCE per test session instead of once
# per test.  Individual tests are isolated either by transaction rollback
# (``db_session``) or by truncating all tables at test setup (``async_client``
# and the local client fixtures in test_chores/test_completion/test_leaderboard).
# ---------------------------------------------------------------------------


async def _recreate_schema() -> None:
    engine = create_async_engine(get_test_database_url(), echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    await engine.dispose()


@pytest.fixture(scope="session")
def _database_schema() -> None:
    """Session-scoped, synchronous fixture that (re)creates the schema once.

    It is synchronous on purpose: pytest-asyncio's default fixture loop scope
    is function-scoped, so a session-scoped *async* fixture would run on a
    different event loop than the tests.  ``asyncio.run`` gives the setup its
    own short-lived loop, and the engine is disposed before it closes.
    """
    asyncio.run(_recreate_schema())


async def truncate_all_tables(engine: AsyncEngine) -> None:
    """Remove all rows from every ORM-mapped table (schema must already exist).

    Used at test setup so each test starts from empty tables regardless of
    what previous tests committed.  Much faster than drop_all/create_all.
    """
    table_names = ", ".join(t.name for t in Base.metadata.sorted_tables)
    async with engine.begin() as conn:
        await conn.execute(text(f"TRUNCATE TABLE {table_names} CASCADE"))


@pytest_asyncio.fixture()
async def db_session(_database_schema: None) -> AsyncGenerator[AsyncSession, None]:
    """Yield a transactional ``AsyncSession`` backed by a real PostgreSQL database.

    Each test gets its own engine and connection, which avoids event-loop
    cross-contamination between tests when using pytest-asyncio in auto mode.
    The connection is rolled back after each test so that the database is left
    clean for the next test.
    """
    url = get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)

    session_factory = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    async with engine.connect() as conn:
        # Wrap everything in a transaction that will be rolled back.
        async with conn.begin():
            async with session_factory(bind=conn) as session:
                yield session
            # The outer transaction is rolled back here, undoing all test writes.
            await conn.rollback()

    await engine.dispose()


@pytest_asyncio.fixture()
async def async_client(_database_schema: None) -> AsyncGenerator[AsyncClient, None]:
    """Yield an AsyncClient wired to a fresh test database.

    All tables are truncated before each test so every test starts from a
    clean data state (the schema itself is created once per session).  The
    ``get_db`` dependency is overridden to use the test engine.  No auth
    dependency overrides are applied — tests that need them must define their
    own local ``async_client`` fixture.
    """
    url = get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    session_factory = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    await truncate_all_tables(engine)

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
