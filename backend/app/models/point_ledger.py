import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.db.base import Base


class PointLedger(Base):
    __tablename__ = "point_ledger"
    __table_args__ = (
        Index("ix_point_ledger_household_user_awarded", "household_id", "user_id", "awarded_at"),
        UniqueConstraint("chore_instance_id", name="uq_point_ledger_chore_instance"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    chore_instance_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("chore_instances.id", ondelete="SET NULL"), nullable=True
    )
    points: Mapped[int] = mapped_column(Integer, nullable=False)
    awarded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    # relationships
    household: Mapped["Household"] = relationship()
    user: Mapped["User"] = relationship(back_populates="point_ledger_entries")
    chore_instance: Mapped["ChoreInstance"] = relationship(back_populates="ledger_entry")
