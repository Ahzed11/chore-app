import uuid

from sqlalchemy import Integer, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin


class Household(Base, TimestampMixin):
    __tablename__ = "households"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    rotation_pointer: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # relationships
    memberships: Mapped[list["HouseholdMembership"]] = relationship(back_populates="household")
    chore_definitions: Mapped[list["ChoreDefinition"]] = relationship(back_populates="household")
    invite_tokens: Mapped[list["InviteToken"]] = relationship(back_populates="household")
