import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Enum, ForeignKey, Index, Integer, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin

ChoreStatusEnum = Enum("pending", "complete", "overdue", "cancelled", name="chore_status")


class ChoreInstance(Base, TimestampMixin):
    __tablename__ = "chore_instances"
    __table_args__ = (
        UniqueConstraint("definition_id", "due_date", name="uq_chore_instance_definition_due_date"),
        Index("ix_chore_instances_household_status", "household_id", "status"),
        Index("ix_chore_instances_assignee", "assignee_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    definition_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("chore_definitions.id", ondelete="SET NULL"), nullable=True
    )
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    assignee_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    assigned_manually: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    due_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(ChoreStatusEnum, nullable=False, default="pending")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    points_awarded: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # relationships
    definition: Mapped["ChoreDefinition"] = relationship(back_populates="instances")
    household: Mapped["Household"] = relationship()
    assignee: Mapped["User"] = relationship()
    ledger_entry: Mapped["PointLedger | None"] = relationship(
        back_populates="chore_instance", uselist=False
    )
