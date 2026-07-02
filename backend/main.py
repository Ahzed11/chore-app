from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError

from app.api import auth, health
from app.api.chores import router as chores_router
from app.api.households import router as households_router
from app.api.invites import router as invites_router
from app.api.leaderboard import router as leaderboard_router
from app.api.members import router as members_router
from app.api.users import router as users_router
from app.core.config import settings
from app.tasks.scheduler import start_scheduler, stop_scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_scheduler()
    yield
    stop_scheduler()


docs_url = "/docs" if settings.DEBUG else None
redoc_url = "/redoc" if settings.DEBUG else None
openapi_url = "/openapi.json" if settings.DEBUG else None

app = FastAPI(
    title="ChoreApp API",
    version="0.1.0",
    lifespan=lifespan,
    docs_url=docs_url,
    redoc_url=redoc_url,
    openapi_url=openapi_url,
)


@app.exception_handler(IntegrityError)
async def integrity_error_handler(request: Request, exc: IntegrityError) -> JSONResponse:
    """Convert any unhandled DB IntegrityError (unique/FK violations) to HTTP 409."""
    return JSONResponse(status_code=409, content={"detail": "Resource conflict"})

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(chores_router)
app.include_router(users_router)
app.include_router(households_router)
app.include_router(invites_router)
app.include_router(leaderboard_router)
app.include_router(members_router)
