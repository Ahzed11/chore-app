from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request as StarletteRequest

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


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: StarletteRequest, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
        return response


app = FastAPI(
    title="ChoreApp API",
    version="0.1.0",
    lifespan=lifespan,
    docs_url=docs_url,
    redoc_url=redoc_url,
    openapi_url=openapi_url,
)

# Middleware is applied in reverse registration order (last added = outermost).
# SecurityHeadersMiddleware is registered first (inner layer).
# CORSMiddleware is registered last (outermost layer) so it handles preflight
# before any other middleware runs.
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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
