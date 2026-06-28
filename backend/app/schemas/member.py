"""Pydantic v2 schemas for member management endpoints."""
import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict


class MemberResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: uuid.UUID
    display_name: str
    role: str
    joined_at: datetime


class RoleUpdateRequest(BaseModel):
    role: Literal["admin", "member"]
