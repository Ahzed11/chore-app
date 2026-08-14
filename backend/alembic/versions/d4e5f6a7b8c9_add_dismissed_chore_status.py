"""add_dismissed_chore_status

Revision ID: d4e5f6a7b8c9
Revises: acbea2cfd78c
Create Date: 2026-08-14 09:00:00.000000

Add the ``dismissed`` value to the ``chore_status`` PostgreSQL enum so a
chore can be closed as done *without* awarding points — distinct from
``cancelled`` (series deleted) and ``complete`` (points awarded).

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'd4e5f6a7b8c9'
down_revision: Union[str, Sequence[str], None] = 'acbea2cfd78c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add the 'dismissed' value to the chore_status enum.

    The project pins postgres:16, so ``ALTER TYPE ... ADD VALUE`` runs inside
    the migration transaction (transaction-safe since PostgreSQL 12).
    """
    op.execute("ALTER TYPE chore_status ADD VALUE 'dismissed'")


def downgrade() -> None:
    """Irreversible — PostgreSQL cannot remove enum values.

    A real downgrade would require rewriting any ``dismissed`` rows to another
    status first and then re-creating the type; documented as a no-op by
    design (standard practice for enum additions).
    """
    pass
