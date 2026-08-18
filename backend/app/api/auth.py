"""Authentication endpoints: register, login, logout, and token refresh."""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import structlog
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy import update as sql_update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.rate_limit import limiter
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
@limiter.limit(lambda: settings.RATE_LIMIT_REGISTER)
async def register(
    request: Request,
    response: Response,
    body: RegisterRequest,
    db: AsyncSession = Depends(get_db),
) -> User:
    """Register a new user account.

    Returns the created user.  Raises 409 if the email is already taken.

    Rate limited per client IP (default ``settings.RATE_LIMIT_REGISTER``,
    10/hour) — see TASK-031.  Exceeding it returns 429 with a Retry-After
    header before the request reaches this function body.

    The unused ``response`` parameter is required so slowapi can attach
    rate-limit headers to the outgoing response: this endpoint returns a
    ``User`` ORM object (serialized via ``response_model``) rather than a
    ``Response`` instance directly, so slowapi needs FastAPI's
    dependency-injected ``Response`` to write headers onto.
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
    # COMMIT EXPLICITLY: FastAPI runs yield-dependency teardown (get_db's
    # commit) AFTER the response is sent, so a client that acts immediately
    # on this 201 — the app's auto-login — can race the commit and get a 401
    # (user not yet visible). Commit before returning so the row is durable
    # before the response leaves the server. See TASK-114.
    await db.commit()
    return user


@router.post("/login", response_model=TokenResponse)
@limiter.limit(lambda: settings.RATE_LIMIT_LOGIN)
async def login(
    request: Request,
    response: Response,
    body: LoginRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Authenticate a user and return a signed JWT plus a refresh token.

    Returns 401 for both unknown email and wrong password so that callers
    cannot distinguish which field was incorrect (enumeration hardening).

    Rate limited per client IP (default ``settings.RATE_LIMIT_LOGIN``,
    5/minute) — see TASK-031 — to slow brute-force/credential-stuffing
    attempts. Exceeding it returns 429 with a Retry-After header.

    The unused ``response`` parameter lets slowapi attach rate-limit headers
    to the outgoing response (this endpoint returns a ``TokenResponse``
    model rather than a ``Response`` instance directly).
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

    expires_delta = timedelta(minutes=settings.JWT_EXPIRY_MINUTES)
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


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit(lambda: settings.RATE_LIMIT_REFRESH)
async def refresh_token(
    request: Request,
    response: Response,
    body: RefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Exchange a valid refresh token for a new access token and rotated refresh token.

    The supplied refresh token is immediately revoked (rotation), and a fresh
    pair is returned.  Replaying the old refresh token yields 401.

    Reuse detection: if the supplied token is found but has *already* been
    revoked (either by a prior rotation or by logout), that is treated as a
    signal the refresh-token family may have been stolen — every refresh
    token for the user is revoked (standard reuse/theft mitigation) and the
    request still fails with 401.

    Rate limited per client IP (default ``settings.RATE_LIMIT_REFRESH``,
    30/minute) — see TASK-031. This endpoint is unauthenticated and
    credential-bearing (accepts a raw refresh token), so it is rate limited
    alongside login/register, just with a looser cap since it's also hit by
    legitimate token-refresh traffic.

    The unused ``response`` parameter lets slowapi attach rate-limit headers
    to the outgoing response (this endpoint returns a ``TokenResponse``
    model rather than a ``Response`` instance directly).
    """
    token_hash = hashlib.sha256(body.refresh_token.encode()).hexdigest()
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    )
    stored = result.scalar_one_or_none()

    if stored is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    if stored.revoked_at is not None:
        # Replay of a rotated/revoked token: possible theft. Revoke the whole
        # family so a stolen token (or its already-rotated successors) can't
        # be used either.
        logger.warning("auth.refresh_reuse_detected", user_id=str(stored.user_id))
        await db.execute(
            sql_update(RefreshToken)
            .where(
                RefreshToken.user_id == stored.user_id,
                RefreshToken.revoked_at == None,  # noqa: E711
            )
            .values(revoked_at=now)
        )
        # Commit explicitly: the get_db dependency rolls back on the
        # HTTPException below, which would otherwise undo the revocation.
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    if stored.expires_at <= now:
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

    expires_delta = timedelta(minutes=settings.JWT_EXPIRY_MINUTES)
    new_access = create_access_token(str(stored.user_id), expires_delta=expires_delta)
    return TokenResponse(
        access_token=new_access,
        expires_in=int(expires_delta.total_seconds()),
        refresh_token=new_raw,
    )


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

    Idempotent: logging out twice with the same access token returns 200 both
    times (the second call is a no-op for the already-revoked ``jti``) rather
    than surfacing a duplicate-key conflict.
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
        # INSERT ... ON CONFLICT DO NOTHING makes repeat logout calls with the
        # same token idempotent instead of tripping the duplicate-PK
        # IntegrityError (previously surfaced as a spurious 409).
        insert_stmt = pg_insert(RevokedToken).values(
            jti=jti,
            revoked_at=datetime.now(timezone.utc),
            expires_at=expires_at,
        ).on_conflict_do_nothing(index_elements=["jti"])
        await db.execute(insert_stmt)
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
