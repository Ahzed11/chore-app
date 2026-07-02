"""Pydantic v2 schemas for household endpoints."""
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class HouseholdCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class HouseholdUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class HouseholdResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    created_at: datetime


class HouseholdWithRoleResponse(BaseModel):
    """Household summary including the requesting user's role and active member count."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    created_at: datetime
    role: str
    member_count: int


class HouseholdDetailResponse(BaseModel):
    """Household detail including active member count (no role field)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    created_at: datetime
    member_count: int
