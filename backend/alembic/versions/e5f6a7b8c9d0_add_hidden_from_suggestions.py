"""add_hidden_from_suggestions

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-08-14 15:00:00.000000

Add ``chore_definitions.hidden_from_suggestions`` — hides a definition from
the create-form template suggestions (TASK-106) without touching the chore
itself or its instances.

"""
from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'e5f6a7b8c9d0'
down_revision: Union[str, Sequence[str], None] = 'd4e5f6a7b8c9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add the hidden_from_suggestions flag (default false for existing rows)."""
    op.add_column(
        'chore_definitions',
        sa.Column(
            'hidden_from_suggestions',
            sa.Boolean(),
            nullable=False,
            server_default=sa.text('false'),
        ),
    )


def downgrade() -> None:
    """Drop the column."""
    op.drop_column('chore_definitions', 'hidden_from_suggestions')
