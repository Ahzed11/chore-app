"""Shared pytest fixtures for the backend test suite."""
import os
from collections.abc import AsyncGenerator

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.db.base import Base
from app.db.session import get_db
from main import app


def get_test_database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        raise RuntimeError(
            "TEST_DATABASE_URL environment variable is not set. "
            "Please provide a PostgreSQL URL before running the test suite."
        )
    return url


@pytest_asyncio.fixture()
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """Yield a transactional ``AsyncSession`` backed by a real PostgreSQL database.

    Each test gets its own engine and connection, which avoids event-loop
    cross-contamination between tests when using pytest-asyncio in auto mode.
    The connection is rolled back after each test so that the database is left
    clean for the next test.
    """
    url = get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)

    # Ensure all tables exist before the test runs.
    async with engine.begin() as setup_conn:
        await setup_conn.run_sync(Base.metadata.create_all)

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
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    """Yield an AsyncClient wired to a fresh test database.

    Drops and recreates all tables before each test so every test starts from
    a clean schema state.  The ``get_db`` dependency is overridden to use the
    test engine.  No auth dependency overrides are applied — tests that need
    them must define their own local ``async_client`` fixture.
    """
    url = get_test_database_url()
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
