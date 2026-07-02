"""add_missing_indexes_and_constraints

Revision ID: c4f2e8a19b3d
Revises: e3fadfdb700e
Create Date: 2026-07-02 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'c4f2e8a19b3d'
down_revision: Union[str, Sequence[str], None] = 'e3fadfdb700e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add performance indexes and a 1:1 uniqueness constraint."""
    # Index on chore_instances.due_date for the overdue-flagging query
    # (WHERE status = 'pending' AND due_date < :today).
    op.create_index("ix_chore_instances_due_date", "chore_instances", ["due_date"])

    # Index on chore_instances.definition_id — FK columns are not auto-indexed
    # in PostgreSQL; this index is used by the bulk existing-pair query in the
    # scheduler and by any JOIN against chore_definitions.
    op.create_index("ix_chore_instances_definition_id", "chore_instances", ["definition_id"])

    # Unique constraint on point_ledger.chore_instance_id to enforce the 1:1
    # relationship between a PointLedger entry and a ChoreInstance at the DB level.
    op.create_unique_constraint(
        "uq_point_ledger_chore_instance", "point_ledger", ["chore_instance_id"]
    )


def downgrade() -> None:
    """Remove the indexes and constraint added by this migration."""
    op.drop_constraint("uq_point_ledger_chore_instance", "point_ledger", type_="unique")
    op.drop_index("ix_chore_instances_definition_id", table_name="chore_instances")
    op.drop_index("ix_chore_instances_due_date", table_name="chore_instances")
