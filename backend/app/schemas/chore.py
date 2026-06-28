"""Pydantic v2 schemas for chore endpoints."""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class RecurrenceRule(BaseModel):
    interval_unit: str  # "days" | "weeks" | "months"
    interval_n: int = Field(ge=1)


class ChoreCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: Optional[str] = None
    category: str  # validated against enum values
    effort_level: str  # "easy" | "medium" | "hard"
    chore_type: str  # "one_off" | "recurring"
    first_due_date: date
    recurrence_rule: Optional[RecurrenceRule] = None
    assignee_id: Optional[uuid.UUID] = None


class ChoreUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = None
    effort_level: Optional[str] = None
    recurrence_rule: Optional[RecurrenceRule] = None


class ChoreInstanceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    definition_id: Optional[uuid.UUID]
    household_id: uuid.UUID
    assignee_id: Optional[uuid.UUID]
    assignee_name: Optional[str]  # joined from User.display_name
    assigned_manually: bool
    due_date: date
    status: str
    completed_at: Optional[datetime]
    points_awarded: Optional[int]
    title: str  # from ChoreDefinition
    description: Optional[str]
    category: str
    effort_level: str
    chore_type: str


class ChoreDefinitionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    household_id: uuid.UUID
    title: str
    description: Optional[str]
    category: str
    effort_level: str
    chore_type: str
    recurrence_rule: Optional[dict]
    first_due_date: date
    is_active: bool
    created_at: datetime
    first_instance: Optional[ChoreInstanceResponse] = None
