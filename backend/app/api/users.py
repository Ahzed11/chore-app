"""User profile endpoints."""
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import UserResponse

router = APIRouter(prefix="/users", tags=["users"])


class UpdateProfileRequest(BaseModel):
    display_name: str = Field(min_length=1)


@router.get("/me", response_model=UserResponse)
async def get_current_profile(
    current_user: User = Depends(get_current_user),
) -> User:
    """Return the authenticated user's profile."""
    return current_user


@router.patch("/me", response_model=UserResponse)
async def update_profile(
    body: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Update the current user's display name."""
    current_user.display_name = body.display_name
    await db.flush()
    await db.refresh(current_user)
    return current_user
