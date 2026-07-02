"""Invite token generation and household join-flow endpoints."""
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select, update as sql_update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_admin
from app.core.config import settings
from app.db.session import get_db
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.invite_token import InviteToken
from app.models.user import User
from app.schemas.household import HouseholdResponse
from app.schemas.invite import InviteTokenResponse

router = APIRouter(tags=["invites"])
logger = structlog.get_logger()


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

    # Expire any existing active (non-expired, non-used) tokens for this household
    await db.execute(
        sql_update(InviteToken)
        .where(
            InviteToken.household_id == household_id,
            InviteToken.used_at == None,  # noqa: E711
            InviteToken.expires_at > datetime.now(timezone.utc),
        )
        .values(expires_at=datetime.now(timezone.utc))
    )

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
    logger.info(
        "member.joined",
        household_id=str(invite.household_id),
        user_id=str(current_user.id),
    )

    household_result = await db.execute(
        select(Household).where(Household.id == invite.household_id)
    )
    household = household_result.scalar_one()

    return HouseholdResponse(
        id=household.id,
        name=household.name,
        created_at=household.created_at,
    )


@router.get(
    "/households/{household_id}/invites",
    response_model=list[InviteTokenResponse],
    status_code=status.HTTP_200_OK,
)
async def list_invites(
    household_id: uuid.UUID,
    _membership: HouseholdMembership = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> list[InviteTokenResponse]:
    """List all active (non-expired, non-used) invite tokens for a household (admin only)."""
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(InviteToken)
        .where(
            InviteToken.household_id == household_id,
            InviteToken.used_at == None,  # noqa: E711
            InviteToken.expires_at > now,
        )
        .order_by(InviteToken.created_at.desc())
    )
    tokens = result.scalars().all()
    return [
        InviteTokenResponse(
            id=t.id,
            token_preview=t.token[:8] + "***",
            created_at=t.created_at,
            expires_at=t.expires_at,
        )
        for t in tokens
    ]


@router.delete(
    "/households/{household_id}/invites/{invite_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def revoke_invite(
    household_id: uuid.UUID,
    invite_id: uuid.UUID,
    _membership: HouseholdMembership = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Revoke an invite token by expiring it immediately (admin only)."""
    result = await db.execute(
        select(InviteToken).where(
            InviteToken.id == invite_id,
            InviteToken.household_id == household_id,
        )
    )
    token = result.scalar_one_or_none()
    if token is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invite not found")
    token.expires_at = datetime.now(timezone.utc)
    await db.flush()
