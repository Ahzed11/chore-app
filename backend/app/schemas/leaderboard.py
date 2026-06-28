"""Pydantic v2 schemas for leaderboard endpoints."""
import uuid
from datetime import date
from typing import Optional

from pydantic import BaseModel, ConfigDict


class LeaderboardEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    rank: int
    user_id: uuid.UUID
    display_name: str
    points: int
    chores_completed: int


class LeaderboardResponse(BaseModel):
    scope: str
    # date fields for this_week scope
    week_start: Optional[date] = None
    week_end: Optional[date] = None
    # date fields for this_month scope
    month_start: Optional[date] = None
    month_end: Optional[date] = None
    entries: list[LeaderboardEntry]
    requesting_user_rank: Optional[int] = None
