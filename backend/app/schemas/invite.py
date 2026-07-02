"""Pydantic v2 schemas for invite token endpoints."""
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class InviteTokenResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    token_preview: str  # first 8 chars + "***"
    created_at: datetime
    expires_at: datetime
