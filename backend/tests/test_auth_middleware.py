"""Tests for JWT authentication middleware and reusable FastAPI dependencies.

A lightweight test-only router is mounted on the app for these tests so that
there is no need to touch main.py.
"""
import uuid
from datetime import timedelta

import pytest
from fastapi import APIRouter, Depends
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user, require_household_member
from app.core.security import create_access_token
from app.models.household import Household
from app.models.household_membership import HouseholdMembership
from app.models.user import User
from main import app
from tests.conftest import get_test_database_url as _get_test_database_url

# ---------------------------------------------------------------------------
# Test-only router — not included in main.py
# ---------------------------------------------------------------------------

test_router = APIRouter()


@test_router.get("/test/protected")
async def protected_route(user: User = Depends(get_current_user)):
    return {"user_id": str(user.id)}


@test_router.get("/test/member/{household_id}")
async def member_only_route(membership: HouseholdMembership = Depends(require_household_member)):
    return {"role": membership.role}


app.include_router(test_router)


# ---------------------------------------------------------------------------
# Shared setup helpers
# ---------------------------------------------------------------------------

_USER_PAYLOAD = {
    "email": "testuser@example.com",
    "password": "strongpassword",
    "display_name": "Test User",
}


async def _register_and_login(client: AsyncClient, payload: dict | None = None) -> dict:
    """Register a user, log in, and return {'user_id': ..., 'token': ...}."""
    payload = payload or _USER_PAYLOAD
    reg = await client.post("/auth/register", json=payload)
    assert reg.status_code == 201, reg.text
    user_id = reg.json()["id"]

    login = await client.post(
        "/auth/login",
        json={"email": payload["email"], "password": payload["password"]},
    )
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    return {"user_id": user_id, "token": token}


# ---------------------------------------------------------------------------
# Tests: get_current_user
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_no_token_returns_401(async_client: AsyncClient) -> None:
    """Requests without an Authorization header must be rejected with 401."""
    response = await async_client.get("/test/protected")
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_invalid_token_returns_401(async_client: AsyncClient) -> None:
    """A malformed / garbage Bearer token must be rejected with 401."""
    response = await async_client.get(
        "/test/protected",
        headers={"Authorization": "Bearer this.is.garbage"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_expired_token_returns_401(async_client: AsyncClient) -> None:
    """A token with a past expiry must be rejected with 401."""
    # Register so there is a real user_id in the DB.
    reg = await async_client.post("/auth/register", json=_USER_PAYLOAD)
    assert reg.status_code == 201
    user_id = reg.json()["id"]

    expired_token = create_access_token(
        subject=user_id,
        expires_delta=timedelta(seconds=-1),  # already expired
    )

    response = await async_client.get(
        "/test/protected",
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_valid_token_returns_user(async_client: AsyncClient) -> None:
    """A valid JWT must grant access and return the correct user_id."""
    creds = await _register_and_login(async_client)

    response = await async_client.get(
        "/test/protected",
        headers={"Authorization": f"Bearer {creds['token']}"},
    )
    assert response.status_code == 200
    assert response.json()["user_id"] == creds["user_id"]


# ---------------------------------------------------------------------------
# Tests: require_household_member
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_non_member_household_returns_403(async_client: AsyncClient) -> None:
    """A valid token for a user who is not a member of the household must get 403."""
    creds = await _register_and_login(async_client)

    # Use a random household_id — the user is definitely not a member.
    random_household_id = str(uuid.uuid4())
    response = await async_client.get(
        f"/test/member/{random_household_id}",
        headers={"Authorization": f"Bearer {creds['token']}"},
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_member_can_access_household_endpoint(async_client: AsyncClient) -> None:
    """An active household member must get 200 and have their role returned."""
    creds = await _register_and_login(async_client)

    # Directly insert a Household and a HouseholdMembership via a second DB
    # connection so that the rows are committed before the HTTP request.
    url = _get_test_database_url()
    engine = create_async_engine(url, echo=False, pool_pre_ping=True)
    session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    household_id: uuid.UUID
    async with session_factory() as session:
        household = Household(name="Test Household")
        session.add(household)
        await session.flush()
        household_id = household.id

        membership = HouseholdMembership(
            household_id=household_id,
            user_id=uuid.UUID(creds["user_id"]),
            role="member",
            is_active=True,
        )
        session.add(membership)
        await session.commit()

    await engine.dispose()

    response = await async_client.get(
        f"/test/member/{household_id}",
        headers={"Authorization": f"Bearer {creds['token']}"},
    )
    assert response.status_code == 200
    assert response.json()["role"] == "member"
