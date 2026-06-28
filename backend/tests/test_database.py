"""Verify that the async database infrastructure is wired correctly."""
import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


@pytest.mark.asyncio
async def test_database_connection(db_session: AsyncSession) -> None:
    """A real PostgreSQL connection can be acquired and queried."""
    result = await db_session.execute(text("SELECT 1"))
    assert result.scalar() == 1


@pytest.mark.asyncio
async def test_database_session_is_async_session(db_session: AsyncSession) -> None:
    """The fixture yields an AsyncSession instance (injectable via Depends)."""
    assert isinstance(db_session, AsyncSession)


@pytest.mark.asyncio
async def test_database_rollback_on_error(db_session: AsyncSession) -> None:
    """Verify that executing a bad query raises and does not silently swallow errors."""
    with pytest.raises(Exception):
        await db_session.execute(text("SELECT * FROM table_that_does_not_exist_xyz"))
