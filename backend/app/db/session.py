from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import settings

async_engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    pool_pre_ping=True,
    # Hygiene for long-lived processes: recycle pooled connections every 30
    # minutes. NOTE — the 2026-08-18 "register 201 → login 401" incident was
    # NOT a pool issue: FastAPI runs yield-dependency teardown (the commit
    # below) AFTER the response is sent, so a client acting immediately on a
    # write response can race the commit. Write endpoints whose responses
    # trigger immediate client follow-ups commit EXPLICITLY before returning
    # (TASK-114: auth register, create household, create chore). Keep that
    # convention for new write endpoints.
    pool_recycle=1800,
)

# Backwards-compatible alias kept for any code that referenced ``engine`` directly.
engine = async_engine

AsyncSessionLocal = async_sessionmaker(
    bind=async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency that yields an ``AsyncSession``.

    Commits on success and rolls back on any unhandled exception so that
    callers never have to manage the transaction themselves.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
