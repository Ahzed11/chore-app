"""Invite token generation and household join-flow endpoints."""
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_admin
from app.core.config import settings
from app.db.session import get_db
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.invite_token import InviteToken
from app.models.user import User
from app.schemas.household import HouseholdResponse

router = APIRouter(tags=["invites"])


class InviteResponse(BaseModel):
    token: str
    invite_url: str
    expires_at: datetime


@router.post(
    "/households/{household_id}/invites",
    response_model=InviteResponse,
    status_code=status.HTTP_200_OK,
)
async def create_invite(
    household_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_admin),
) -> InviteResponse:
    """Generate an invite token for a household (admin only)."""
    token = secrets.token_urlsafe(16)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=settings.INVITE_TOKEN_TTL_HOURS)

    invite = InviteToken(
        household_id=household_id,
        created_by_id=current_user.id,
        token=token,
        expires_at=expires_at,
    )
    db.add(invite)
    await db.flush()

    invite_url = f"{settings.APP_BASE_URL}/join/{token}"
    return InviteResponse(token=token, invite_url=invite_url, expires_at=expires_at)


@router.post(
    "/invites/{token}/accept",
    response_model=HouseholdResponse,
    status_code=status.HTTP_200_OK,
)
async def accept_invite(
    token: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HouseholdResponse:
    """Accept an invite token and join the associated household as a member."""
    now = datetime.now(timezone.utc)

    result = await db.execute(select(InviteToken).where(InviteToken.token == token))
    invite = result.scalar_one_or_none()

    if invite is None or invite.expires_at < now or invite.used_at is not None:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Invite token is invalid, expired, or already used",
        )

    # Check for existing active membership
    existing = await db.execute(
        select(HouseholdMembership).where(
            HouseholdMembership.household_id == invite.household_id,
            HouseholdMembership.user_id == current_user.id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Already a member of this household",
        )

    # Create membership and mark invite as used — single transaction via flush
    membership = HouseholdMembership(
        household_id=invite.household_id,
        user_id=current_user.id,
        role="member",
        joined_at=now,
        is_active=True,
    )
    db.add(membership)
    invite.used_at = now
    await db.flush()

    household_result = await db.execute(
        select(Household).where(Household.id == invite.household_id)
    )
    household = household_result.scalar_one()

    return HouseholdResponse(
        id=household.id,
        name=household.name,
        rotation_pointer=household.rotation_pointer,
        created_at=household.created_at,
    )
