"""Alembic environment — async engine via run_sync pattern."""
import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import create_async_engine

from alembic import context

# ---------------------------------------------------------------------------
# Alembic config
# ---------------------------------------------------------------------------
config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# ---------------------------------------------------------------------------
# Import Base so autogenerate can detect all registered models.
# Additional model modules must be imported here (or inside app/db/base.py)
# so that their tables appear in Base.metadata.
# ---------------------------------------------------------------------------
import app.models  # noqa: E402,F401  — triggers model registration
from app.db.base import Base  # noqa: E402

target_metadata = Base.metadata

# ---------------------------------------------------------------------------
# Read the database URL from settings (which reads it from the environment /
# .env file) rather than from alembic.ini.
# ---------------------------------------------------------------------------
from app.core.config import settings  # noqa: E402

DATABASE_URL = settings.DATABASE_URL


# ---------------------------------------------------------------------------
# Offline migrations (no live connection, emits SQL to stdout)
# ---------------------------------------------------------------------------


def run_migrations_offline() -> None:
    context.configure(
        url=DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


# ---------------------------------------------------------------------------
# Online migrations (async engine via run_sync)
# ---------------------------------------------------------------------------


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    engine = create_async_engine(DATABASE_URL, poolclass=pool.NullPool)
    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await engine.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
