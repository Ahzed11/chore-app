"""normalize_email_case

Lowercase all existing user emails so email uniqueness and login become
case-insensitive (TASK-079), and add a functional unique index on
lower(email) as defense-in-depth for any future write path that bypasses
the application-layer normalization added in app/schemas/auth.py.

Revision ID: b7c1d4e9f2a3
Revises: a1b2c3d4e5f6
Create Date: 2026-07-15 00:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "b7c1d4e9f2a3"
down_revision: Union[str, Sequence[str], None] = "a1b2c3d4e5f6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Lowercase every ``users.email`` value and enforce case-insensitive uniqueness.

    Fails loudly (raises ``RuntimeError``) if two accounts differ only by
    letter case — e.g. ``Alex@gmail.com`` and ``alex@gmail.com`` — since the
    migration cannot know which one to keep. An operator must resolve the
    collision manually (merge, rename, or delete one of the accounts) and
    re-run the migration.
    """
    connection = op.get_bind()

    collisions = connection.execute(
        sa.text(
            """
            SELECT lower(email) AS normalized, array_agg(email ORDER BY email) AS variants
            FROM users
            GROUP BY lower(email)
            HAVING count(*) > 1
            """
        )
    ).fetchall()

    if collisions:
        details = "; ".join(
            f"{row.normalized!r} <- {list(row.variants)}" for row in collisions
        )
        raise RuntimeError(
            "Cannot lowercase user emails: the following accounts collide only by "
            "case and must be resolved manually (merge/rename/delete one of each "
            f"pair) before re-running this migration: {details}"
        )

    connection.execute(
        sa.text("UPDATE users SET email = lower(email) WHERE email <> lower(email)")
    )

    op.create_index(
        "ix_users_email_lower",
        "users",
        [sa.text("lower(email)")],
        unique=True,
    )


def downgrade() -> None:
    """Drop the functional unique index.

    Email values are left lowercased — the original mixed case is not
    recoverable and downgrading is not expected to restore it.
    """
    op.drop_index("ix_users_email_lower", table_name="users")
