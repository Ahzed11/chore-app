import logging

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)

# Substrings that indicate JWT_SECRET was left at (or copied from) a
# documentation/placeholder value instead of being replaced with a real secret.
_PLACEHOLDER_SECRET_MARKERS = (
    "change-me",
    "change_me",
    "changeme",
    "replace_with",
    "replace-with",
    "replaceme",
    "your-secret",
    "your_secret",
    "example-secret",
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Database
    DATABASE_URL: str

    # JWT
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    # Access tokens are short-lived by design — a stolen access token should
    # stay valid for minutes, not days. Long-lived sessions are handled by the
    # rotated refresh-token flow instead.
    JWT_EXPIRY_MINUTES: int = 30
    # Deprecated: superseded by JWT_EXPIRY_MINUTES. Kept only so existing .env
    # files that still set this don't break; if explicitly set, it is honored
    # (converted to minutes) and a deprecation warning is logged at startup.
    JWT_EXPIRY_DAYS: int | None = None

    # Refresh tokens
    REFRESH_TOKEN_TTL_DAYS: int = 30

    # Application
    APP_BASE_URL: str = "http://localhost:8000"

    # Invite tokens
    INVITE_TOKEN_TTL_HOURS: int = 48

    # Scheduler
    SCHEDULER_RUN_HOUR: int = 0

    # Chore instance generation
    INSTANCE_GENERATION_DAYS_AHEAD: int = 7

    # Debug / development
    DEBUG: bool = False

    # CORS
    CORS_ALLOWED_ORIGINS: list[str] = []

    @field_validator("JWT_SECRET")
    @classmethod
    def _validate_jwt_secret(cls, value: str) -> str:
        """Reject short or placeholder JWT secrets so the app fails fast at startup."""
        if len(value) < 32:
            raise ValueError(
                "JWT_SECRET must be at least 32 characters long. Generate one with: "
                'python -c "import secrets; print(secrets.token_hex(32))"'
            )
        normalized = value.strip().lower()
        for marker in _PLACEHOLDER_SECRET_MARKERS:
            if marker in normalized:
                raise ValueError(
                    "JWT_SECRET looks like a placeholder copied from .env.example. "
                    "Set a real random secret before starting the application."
                )
        return value

    @model_validator(mode="after")
    def _apply_deprecated_jwt_expiry_days(self) -> "Settings":
        """Honor an explicitly-set JWT_EXPIRY_DAYS as a fallback, with a warning."""
        if self.JWT_EXPIRY_DAYS is not None:
            effective_minutes = self.JWT_EXPIRY_DAYS * 24 * 60
            logger.warning(
                "JWT_EXPIRY_DAYS is deprecated and will be removed in a future release; "
                "use JWT_EXPIRY_MINUTES instead. Honoring JWT_EXPIRY_DAYS=%s "
                "(%s minutes) for backward compatibility.",
                self.JWT_EXPIRY_DAYS,
                effective_minutes,
            )
            self.JWT_EXPIRY_MINUTES = effective_minutes
        return self


settings = Settings()
