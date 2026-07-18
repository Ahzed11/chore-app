"""Tests for app/core/config.py Settings validation (TASK-070).

Covers:
- JWT_EXPIRY_MINUTES defaults to 30 when JWT_EXPIRY_DAYS is not set.
- An explicitly-set JWT_EXPIRY_DAYS is honored as a deprecated fallback and
  converted to minutes.
- JWT_SECRET shorter than 32 characters is rejected at construction time.
- Known placeholder JWT_SECRET values are rejected even if long enough.
- A valid, non-placeholder JWT_SECRET of sufficient length is accepted.
"""
import pytest
from pydantic import ValidationError

from app.core.config import Settings

_VALID_SECRET = "a_perfectly_ordinary_random_secret_value_1234"  # >= 32 chars, no placeholder markers
_BASE_KWARGS = {
    "DATABASE_URL": "postgresql+asyncpg://user:pass@localhost:5432/db",
}


def test_jwt_expiry_minutes_defaults_to_30_without_days_override() -> None:
    settings = Settings(**_BASE_KWARGS, JWT_SECRET=_VALID_SECRET, JWT_EXPIRY_DAYS=None)
    assert settings.JWT_EXPIRY_MINUTES == 30


def test_jwt_expiry_days_explicit_fallback_converts_to_minutes() -> None:
    settings = Settings(**_BASE_KWARGS, JWT_SECRET=_VALID_SECRET, JWT_EXPIRY_DAYS=7)
    assert settings.JWT_EXPIRY_MINUTES == 7 * 24 * 60


def test_jwt_expiry_minutes_explicit_value_respected() -> None:
    settings = Settings(
        **_BASE_KWARGS, JWT_SECRET=_VALID_SECRET, JWT_EXPIRY_MINUTES=45, JWT_EXPIRY_DAYS=None
    )
    assert settings.JWT_EXPIRY_MINUTES == 45


def test_jwt_secret_too_short_rejected() -> None:
    with pytest.raises(ValidationError):
        Settings(**_BASE_KWARGS, JWT_SECRET="too-short")


@pytest.mark.parametrize(
    "secret",
    [
        "change-me-to-a-random-64-char-hex-string",
        "replace_with_a_64_char_hex_string_padding",
        "CHANGE-ME-SOMETHING-LONG-ENOUGH-TO-PASS-LENGTH-CHECK",
    ],
)
def test_jwt_secret_placeholder_rejected(secret: str) -> None:
    """Known .env.example placeholder patterns must fail startup, not just length checks."""
    assert len(secret) >= 32  # sanity: these fail on the placeholder check, not length
    with pytest.raises(ValidationError):
        Settings(**_BASE_KWARGS, JWT_SECRET=secret)


def test_jwt_secret_valid_value_accepted() -> None:
    settings = Settings(**_BASE_KWARGS, JWT_SECRET=_VALID_SECRET)
    assert settings.JWT_SECRET == _VALID_SECRET
