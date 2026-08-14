import uuid
from datetime import date

from sqlalchemy import Boolean, Date, Enum, ForeignKey, String, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin

# Enums (defined once, reused across models)
CategoryEnum = Enum(
    "kitchen",
    "bathroom",
    "bedroom",
    "living_room",
    "laundry_room",
    "garden_outdoor",
    "garage",
    "other_general",
    name="chore_category",
)
EffortLevelEnum = Enum("easy", "medium", "hard", name="effort_level")
ChoreTypeEnum = Enum("one_off", "recurring", name="chore_type")


class ChoreDefinition(Base, TimestampMixin):
    __tablename__ = "chore_definitions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str] = mapped_column(CategoryEnum, nullable=False)
    effort_level: Mapped[str] = mapped_column(EffortLevelEnum, nullable=False)
    chore_type: Mapped[str] = mapped_column(ChoreTypeEnum, nullable=False)
    recurrence_rule: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    first_due_date: Mapped[date] = mapped_column(Date, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    # TASK-106: hides the definition from the create-form "start from a
    # previous task" template list only — the chore and its instances are
    # unaffected (hiding is NOT deleting).
    hidden_from_suggestions: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )

    # relationships
    household: Mapped["Household"] = relationship(back_populates="chore_definitions")
    created_by: Mapped["User"] = relationship()
    instances: Mapped[list["ChoreInstance"]] = relationship(back_populates="definition")
