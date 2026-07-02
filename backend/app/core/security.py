"""
Security utilities: password hashing and JWT token management.
"""
import uuid
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from jwt.exceptions import InvalidTokenError

from app.core.config import settings


# ---------------------------------------------------------------------------
# Password helpers
# ---------------------------------------------------------------------------


def hash_password(plain: str) -> str:
    """Return a bcrypt hash of *plain*."""
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt(rounds=12)).decode()


def verify_password(plain: str, hashed: str) -> bool:
    """Return True if *plain* matches *hashed*."""
    return bcrypt.checkpw(plain.encode(), hashed.encode())


# ---------------------------------------------------------------------------
# JWT helpers
# ---------------------------------------------------------------------------


def create_access_token(subject: str) -> str:
    """Return a signed JWT encoding *subject* as the ``sub`` claim."""
    expire = datetime.now(timezone.utc) + timedelta(days=settings.JWT_EXPIRY_DAYS)
    payload = {
        "sub": subject,
        "exp": expire,
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> dict | None:
    """Decode and return the JWT payload, or None if the token is invalid."""
    try:
        return jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM],
        )
    except InvalidTokenError:
        return None
