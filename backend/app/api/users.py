"""User profile endpoints."""
from datetime import datetime, timezone

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import update as sql_update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.security import hash_password, verify_password
from app.db.session import get_db
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.auth import AccountDeleteRequest, PasswordChangeRequest, UserResponse
from app.services.account_deletion import delete_user_account

router = APIRouter(prefix="/users", tags=["users"])
logger = structlog.get_logger()


class UpdateProfileRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=100)


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


@router.post("/me/password", status_code=status.HTTP_200_OK)
async def change_password(
    body: PasswordChangeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Change the current user's password (TASK-077).

    Verifies ``current_password`` against the stored hash (403 on mismatch),
    applies the same strength constraints as registration to
    ``new_password`` (enforced by the request schema), and — on success —
    revokes every outstanding refresh token for the account so any other
    logged-in session must re-authenticate.
    """
    if not verify_password(body.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Current password is incorrect",
        )

    current_user.password_hash = hash_password(body.new_password)
    await db.flush()

    await db.execute(
        sql_update(RefreshToken)
        .where(
            RefreshToken.user_id == current_user.id,
            RefreshToken.revoked_at == None,  # noqa: E711
        )
        .values(revoked_at=datetime.now(timezone.utc))
    )

    logger.info("user.password_changed", user_id=str(current_user.id))
    return {"message": "Password updated successfully"}


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    body: AccountDeleteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Permanently delete the current user's account (TASK-078).

    Requires the current password in the body. See
    ``app.services.account_deletion.delete_user_account`` for the household
    membership rules (sole-admin guard, sole-member household deletion,
    redistribution of open chores) applied before the user row is removed.
    """
    if not verify_password(body.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Current password is incorrect",
        )

    await delete_user_account(current_user, db)
    logger.info("user.account_deleted", user_id=str(current_user.id))
