"""Authentication endpoints: register, login, logout, and token refresh."""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy import update as sql_update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.refresh_token import RefreshToken
from app.models.revoked_token import RevokedToken
from app.models.user import User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse, UserResponse

router = APIRouter(prefix="/auth", tags=["auth"])
logger = structlog.get_logger()


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)) -> User:
    """Register a new user account.

    Returns the created user.  Raises 409 if the email is already taken.
    """
    result = await db.execute(select(User).where(User.email == body.email))
    existing = result.scalar_one_or_none()
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    user = User(
        email=body.email,
        display_name=body.display_name,
        password_hash=hash_password(body.password),
    )
    db.add(user)
    await db.flush()   # populate user.id and server-side defaults without committing
    await db.refresh(user)
    return user


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    """Authenticate a user and return a signed JWT plus a refresh token.

    Returns 401 for both unknown email and wrong password so that callers
    cannot distinguish which field was incorrect (enumeration hardening).
    """
    result = await db.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not verify_password(body.password, user.password_hash):
        masked = body.email[0] + "***@" + body.email.split("@")[-1]
        logger.warning("user.login_failed", email=masked)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    expires_delta = timedelta(days=settings.JWT_EXPIRY_DAYS)
    access_token = create_access_token(
        subject=str(user.id),
        expires_delta=expires_delta,
    )
    expires_in = int(expires_delta.total_seconds())

    # Issue a refresh token and persist its hash.
    raw_refresh = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_refresh.encode()).hexdigest()
    now = datetime.now(timezone.utc)
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=token_hash,
            created_at=now,
            expires_at=now + timedelta(days=settings.REFRESH_TOKEN_TTL_DAYS),
        )
    )
    await db.flush()

    logger.info("user.login", user_id=str(user.id))
    return TokenResponse(
        access_token=access_token,
        expires_in=expires_in,
        refresh_token=raw_refresh,
    )


class RefreshRequest(BaseModel):
    refresh_token: str


@router.post("/refresh")
async def refresh_token(
    body: RefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Exchange a valid refresh token for a new access token and rotated refresh token.

    The supplied refresh token is immediately revoked (rotation), and a fresh
    pair is returned.  Replaying the old refresh token yields 401.
    """
    token_hash = hashlib.sha256(body.refresh_token.encode()).hexdigest()
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.expires_at > now,
            RefreshToken.revoked_at == None,  # noqa: E711
        )
    )
    stored = result.scalar_one_or_none()
    if stored is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    # Rotate: revoke the consumed token, issue a fresh one.
    stored.revoked_at = now

    new_raw = secrets.token_urlsafe(32)
    new_hash = hashlib.sha256(new_raw.encode()).hexdigest()
    db.add(
        RefreshToken(
            user_id=stored.user_id,
            token_hash=new_hash,
            created_at=now,
            expires_at=now + timedelta(days=settings.REFRESH_TOKEN_TTL_DAYS),
        )
    )
    await db.flush()

    new_access = create_access_token(str(stored.user_id))
    return {"access_token": new_access, "refresh_token": new_raw, "token_type": "bearer"}


@router.post("/logout", status_code=200)
async def logout(
    credentials: HTTPAuthorizationCredentials | None = Depends(
        HTTPBearer(auto_error=False)
    ),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Revoke the supplied JWT and all active refresh tokens for the user.

    Inserts the token's ``jti`` into the ``revoked_tokens`` table and marks
    every non-revoked ``RefreshToken`` row for this user as revoked.
    Subsequent calls to ``get_current_user`` with this token will receive HTTP 401.
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
        )

    payload = decode_access_token(credentials.credentials)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )

    jti = payload.get("jti")
    exp = payload.get("exp")
    if jti and exp:
        expires_at = datetime.fromtimestamp(exp, tz=timezone.utc)
        db.add(
            RevokedToken(
                jti=jti,
                revoked_at=datetime.now(timezone.utc),
                expires_at=expires_at,
            )
        )
        await db.flush()

    # Revoke all active refresh tokens for this user.
    await db.execute(
        sql_update(RefreshToken)
        .where(
            RefreshToken.user_id == uuid.UUID(payload["sub"]),
            RefreshToken.revoked_at == None,  # noqa: E711
        )
        .values(revoked_at=datetime.now(timezone.utc))
    )

    return {"message": "Logged out successfully"}
