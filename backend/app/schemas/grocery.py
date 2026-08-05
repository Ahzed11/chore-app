"""Pydantic v2 schemas for grocery item endpoints."""
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class GroceryItemCreate(BaseModel):
    """Payload for adding a new item to the grocery list."""

    name: str = Field(min_length=1, max_length=200)
    quantity: Optional[str] = Field(None, max_length=100)
    notes: Optional[str] = None


class GroceryItemUpdate(BaseModel):
    """Payload for editing an existing item's details."""

    name: Optional[str] = Field(None, min_length=1, max_length=200)
    quantity: Optional[str] = Field(None, max_length=100)
    notes: Optional[str] = None


class GroceryItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    household_id: uuid.UUID
    added_by_id: Optional[uuid.UUID]
    added_by_name: Optional[str]  # joined from User.display_name
    name: str
    quantity: Optional[str]
    notes: Optional[str]
    is_purchased: bool
    purchased_by_id: Optional[uuid.UUID]
    purchased_by_name: Optional[str]  # joined from User.display_name
    purchased_at: Optional[datetime]
    created_at: datetime
