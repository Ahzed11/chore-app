"""Leaderboard endpoint.

GET /households/{household_id}/leaderboard?scope={all_time|this_week|this_month}
"""
import calendar
import uuid
from datetime import date, datetime, time, timedelta, timezone
from enum import Enum
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_household_member
from app.db.session import get_db
from app.models.chore_instance import ChoreInstance
from app.models.household_membership import HouseholdMembership
from app.models.point_ledger import PointLedger
from app.models.user import User
from app.schemas.leaderboard import LeaderboardEntry, LeaderboardResponse

router = APIRouter(tags=["leaderboard"])


class LeaderboardScope(str, Enum):
    all_time = "all_time"
    this_week = "this_week"
    this_month = "this_month"


def _get_today() -> date:
    """Return today's date in UTC.  Extracted for easy mocking in tests.

    Uses the UTC calendar date (not the host's local timezone) so that
    leaderboard windows line up with the UTC-based nightly scheduler
    (TASK-079).
    """
    return datetime.now(timezone.utc).date()


def _compute_window(
    scope: LeaderboardScope,
) -> tuple[
    Optional[datetime],  # window_start (inclusive)
    Optional[datetime],  # window_end (exclusive)
    Optional[date],      # week_start (response field, this_week only)
    Optional[date],      # week_end   (response field, this_week only)
    Optional[date],      # month_start (response field, this_month only)
    Optional[date],      # month_end   (response field, this_month only)
]:
    """Compute the UTC datetime window and response-level date fields for a scope.

    ``window_end`` is the *exclusive* upper bound — the instant the next
    period begins — rather than the last second of the period, so an entry
    awarded at e.g. 23:59:59.5 on the period's final day is still included
    (TASK-079).
    """
    today = _get_today()

    if scope == LeaderboardScope.this_week:
        week_start = today - timedelta(days=today.weekday())  # Monday
        week_end = week_start + timedelta(days=6)             # Sunday
        window_start = datetime.combine(week_start, time.min, tzinfo=timezone.utc)
        window_end = datetime.combine(
            week_start + timedelta(days=7), time.min, tzinfo=timezone.utc
        )
        return window_start, window_end, week_start, week_end, None, None

    if scope == LeaderboardScope.this_month:
        month_start = date(today.year, today.month, 1)
        last_day = calendar.monthrange(today.year, today.month)[1]
        month_end = date(today.year, today.month, last_day)
        next_month_start = month_end + timedelta(days=1)
        window_start = datetime.combine(month_start, time.min, tzinfo=timezone.utc)
        window_end = datetime.combine(next_month_start, time.min, tzinfo=timezone.utc)
        return window_start, window_end, None, None, month_start, month_end

    # all_time — no filter
    return None, None, None, None, None, None


@router.get(
    "/households/{household_id}/leaderboard",
    response_model=LeaderboardResponse,
)
async def get_leaderboard(
    household_id: uuid.UUID,
    scope: LeaderboardScope = LeaderboardScope.all_time,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
    current_user: User = Depends(get_current_user),
) -> LeaderboardResponse:
    """Return a ranked leaderboard of household members for the given scope.

    Members with zero points still appear.  Dense ranking is applied: tied
    members share the same rank and the next distinct group's rank is
    immediately incremented by one (not by the size of the tied group).
    """
    window_start, window_end, week_start, week_end, month_start, month_end = (
        _compute_window(scope)
    )

    # ------------------------------------------------------------------
    # 1. Fetch all active members of the household.
    # ------------------------------------------------------------------
    members_stmt = (
        select(User)
        .join(HouseholdMembership, HouseholdMembership.user_id == User.id)
        .where(
            HouseholdMembership.household_id == household_id,
            HouseholdMembership.is_active == True,  # noqa: E712
        )
        .order_by(User.display_name)  # stable ordering for tie-break consistency
    )
    members_result = await db.execute(members_stmt)
    members = members_result.scalars().all()

    # Pre-populate maps with zero values so members with no points/chores appear.
    user_points: dict[uuid.UUID, int] = {m.id: 0 for m in members}
    user_chores: dict[uuid.UUID, int] = {m.id: 0 for m in members}

    # ------------------------------------------------------------------
    # 2. Sum PointLedger.points per user within the window.
    # ------------------------------------------------------------------
    points_stmt = (
        select(
            PointLedger.user_id,
            func.coalesce(func.sum(PointLedger.points), 0).label("total_points"),
        )
        .where(PointLedger.household_id == household_id)
    )
    if window_start is not None:
        points_stmt = points_stmt.where(PointLedger.awarded_at >= window_start)
    if window_end is not None:
        points_stmt = points_stmt.where(PointLedger.awarded_at < window_end)
    points_stmt = points_stmt.group_by(PointLedger.user_id)

    points_result = await db.execute(points_stmt)
    for row_user_id, total in points_result.all():
        if row_user_id in user_points:
            user_points[row_user_id] = int(total)

    # ------------------------------------------------------------------
    # 3. Count completed ChoreInstances per assignee within the window.
    # ------------------------------------------------------------------
    chores_stmt = (
        select(
            ChoreInstance.assignee_id,
            func.count(ChoreInstance.id).label("chore_count"),
        )
        .where(
            ChoreInstance.household_id == household_id,
            ChoreInstance.status == "complete",
        )
    )
    if window_start is not None:
        chores_stmt = chores_stmt.where(ChoreInstance.completed_at >= window_start)
    if window_end is not None:
        chores_stmt = chores_stmt.where(ChoreInstance.completed_at < window_end)
    chores_stmt = chores_stmt.group_by(ChoreInstance.assignee_id)

    chores_result = await db.execute(chores_stmt)
    for row_user_id, count in chores_result.all():
        if row_user_id in user_chores:
            user_chores[row_user_id] = int(count)

    # ------------------------------------------------------------------
    # 4. Sort by points descending and apply dense ranking in Python.
    # ------------------------------------------------------------------
    sorted_members = sorted(members, key=lambda m: user_points[m.id], reverse=True)

    entries: list[LeaderboardEntry] = []
    current_rank = 1
    for i, member in enumerate(sorted_members):
        if i > 0 and user_points[member.id] < user_points[sorted_members[i - 1].id]:
            current_rank += 1
        entries.append(
            LeaderboardEntry(
                rank=current_rank,
                user_id=member.id,
                display_name=member.display_name,
                points=user_points[member.id],
                chores_completed=user_chores[member.id],
            )
        )

    # ------------------------------------------------------------------
    # 5. Locate the requesting user's rank.
    # ------------------------------------------------------------------
    requesting_user_rank: Optional[int] = None
    for entry in entries:
        if entry.user_id == current_user.id:
            requesting_user_rank = entry.rank
            break

    return LeaderboardResponse(
        scope=scope.value,
        week_start=week_start,
        week_end=week_end,
        month_start=month_start,
        month_end=month_end,
        entries=entries,
        requesting_user_rank=requesting_user_rank,
    )
