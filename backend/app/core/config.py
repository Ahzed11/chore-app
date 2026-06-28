from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Database
    DATABASE_URL: str

    # JWT
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRY_DAYS: int = 7

    # Application
    APP_BASE_URL: str = "http://localhost:8000"

    # Invite tokens
    INVITE_TOKEN_TTL_HOURS: int = 48

    # Scheduler
    SCHEDULER_RUN_HOUR: int = 0

    # Chore instance generation
    INSTANCE_GENERATION_DAYS_AHEAD: int = 7


settings = Settings()
