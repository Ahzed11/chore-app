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
    # Recycle pooled connections every 30 minutes. Observed 2026-08-18
    # (TASK-113): after ~15 min of uptime a long-lived uvicorn started
    # returning EMPTY results for every SELECT while INSERTs still worked
    # (register 201 → login 401, duplicate-check SELECTs saw no rows) — a
    # fresh process behaved correctly. Root cause not fully pinned (no DB
    # errors, code proven correct in-process); recycling bounds the blast
    # radius of any such stale-connection state. If login starts returning
    # "Invalid credentials" while the DB is fine, restart uvicorn.
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
