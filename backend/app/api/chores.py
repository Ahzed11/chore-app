"""Chore CRUD endpoints.

All routes are scoped to a household:
    /households/{household_id}/chores
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_admin, require_household_member
from app.core.constants import EFFORT_POINTS
from app.db.session import get_db
from app.models.chore_definition import ChoreDefinition
from app.models.chore_instance import ChoreInstance
from app.models.household_membership import HouseholdMembership
from app.models.point_ledger import PointLedger
from app.models.user import User
from app.schemas.chore import (
    ChoreCategory,
    ChoreCreate,
    ChoreDefinitionResponse,
    ChoreInstanceResponse,
    ChoreInstanceStatus,
    ChoreReassignRequest,
    ChoreTemplateResponse,
    ChoreUpdate,
    PaginatedChoreResponse,
)
from app.services.assignment import AssignmentService, get_assignment_service

router = APIRouter(prefix="/households/{household_id}/chores", tags=["chores"])
logger = structlog.get_logger()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _instance_response_from_row(
    instance: ChoreInstance,
    definition: ChoreDefinition,
    assignee_name: Optional[str],
) -> ChoreInstanceResponse:
    """Build a ChoreInstanceResponse from ORM objects + joined display_name."""
    return ChoreInstanceResponse(
        id=instance.id,
        definition_id=instance.definition_id,
        household_id=instance.household_id,
        assignee_id=instance.assignee_id,
        assignee_name=assignee_name,
        assigned_manually=instance.assigned_manually,
        created_at=instance.created_at,  # TASK-111
        due_date=instance.due_date,
        status=instance.status,
        completed_at=instance.completed_at,
        points_awarded=instance.points_awarded,
        title=definition.title,
        description=definition.description,
        category=definition.category,
        effort_level=definition.effort_level,
        chore_type=definition.chore_type,
    )


# ---------------------------------------------------------------------------
# POST /households/{household_id}/chores  — admin only
# ---------------------------------------------------------------------------

@router.post(
    "",
    response_model=ChoreDefinitionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_chore(
    household_id: uuid.UUID,
    body: ChoreCreate,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_admin),
    assignment_service: AssignmentService = Depends(get_assignment_service),
) -> ChoreDefinitionResponse:
    """Create a ChoreDefinition and its first ChoreInstance."""
    # Validate: recurring chores must have a recurrence_rule
    if body.chore_type == "recurring" and body.recurrence_rule is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="recurrence_rule is required when chore_type is 'recurring'",
        )

    # Create the definition — _membership.user_id is the authenticated admin's ID.
    definition = ChoreDefinition(
        household_id=household_id,
        created_by_id=_membership.user_id,
        title=body.title,
        description=body.description,
        category=body.category,
        effort_level=body.effort_level,
        chore_type=body.chore_type,
        recurrence_rule=body.recurrence_rule.model_dump() if body.recurrence_rule else None,
        first_due_date=body.first_due_date,
        is_active=True,
    )
    db.add(definition)
    await db.flush()  # Populate definition.id before referencing it

    # Determine assignee
    if body.assignee_id is not None:
        # Validate that the requested assignee is an active member of this household
        member_check = await db.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.household_id == household_id,
                HouseholdMembership.user_id == body.assignee_id,
                HouseholdMembership.is_active == True,  # noqa: E712
            )
        )
        if member_check.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="assignee_id is not an active member of this household",
            )
        # Manual assignment: use provided assignee, do NOT advance rotation pointer
        assignee_id = body.assignee_id
        assigned_manually = True
    else:
        # Auto-assign via round-robin strategy (advances pointer internally)
        assignee_id = await assignment_service.auto_assign(household_id, db)
        assigned_manually = False

    # Create first instance
    instance = ChoreInstance(
        definition_id=definition.id,
        household_id=household_id,
        assignee_id=assignee_id,
        assigned_manually=assigned_manually,
        due_date=body.first_due_date,
        status="pending",
    )
    db.add(instance)
    await db.flush()
    await db.refresh(instance)
    await db.refresh(definition)

    # Resolve assignee display name for the embedded instance
    assignee_name: Optional[str] = None
    if assignee_id is not None:
        user_result = await db.execute(select(User).where(User.id == assignee_id))
        user = user_result.scalar_one_or_none()
        if user is not None:
            assignee_name = user.display_name

    first_instance_resp = _instance_response_from_row(instance, definition, assignee_name)

    # COMMIT EXPLICITLY (TASK-114): get_db's teardown commit runs after the
    # response is sent; the app refetches the chore list the moment it gets
    # this 201, so an uncommitted row would race the refetch. Commit first.
    await db.commit()

    return ChoreDefinitionResponse(
        id=definition.id,
        household_id=definition.household_id,
        title=definition.title,
        description=definition.description,
        category=definition.category,
        effort_level=definition.effort_level,
        chore_type=definition.chore_type,
        recurrence_rule=definition.recurrence_rule,
        first_due_date=definition.first_due_date,
        is_active=definition.is_active,
        created_at=definition.created_at,
        first_instance=first_instance_resp,
    )


# ---------------------------------------------------------------------------
# GET /households/{household_id}/chores  — any member
# ---------------------------------------------------------------------------

@router.get(
    "",
    response_model=PaginatedChoreResponse,
)
async def list_chores(
    household_id: uuid.UUID,
    status_filter: Optional[ChoreInstanceStatus] = None,
    category: Optional[ChoreCategory] = None,
    assignee_id: Optional[uuid.UUID] = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> PaginatedChoreResponse:
    """List ChoreInstances for a household, with optional filters and pagination."""
    # Build shared filter conditions applied to both the data query and COUNT.
    base_filters = [
        ChoreInstance.household_id == household_id,
        ChoreDefinition.is_active.is_(True),
    ]
    if status_filter is not None:
        base_filters.append(ChoreInstance.status == status_filter)
    if category is not None:
        base_filters.append(ChoreDefinition.category == category)
    if assignee_id is not None:
        base_filters.append(ChoreInstance.assignee_id == assignee_id)

    # COUNT query — same joins and filters, no ordering or pagination.
    count_stmt = (
        select(func.count())
        .select_from(ChoreInstance)
        .join(ChoreDefinition, ChoreInstance.definition_id == ChoreDefinition.id)
        .where(*base_filters)
    )
    total: int = (await db.scalar(count_stmt)) or 0

    # Data query with pagination applied.
    stmt = (
        select(ChoreInstance, ChoreDefinition, User.display_name)
        .join(ChoreDefinition, ChoreInstance.definition_id == ChoreDefinition.id)
        .outerjoin(User, ChoreInstance.assignee_id == User.id)
        .where(*base_filters)
        .order_by(ChoreInstance.created_at.desc(), ChoreInstance.id.desc())
        .limit(limit)
        .offset(offset)
    )
    result = await db.execute(stmt)
    rows = result.all()

    instances = [
        _instance_response_from_row(instance, definition, display_name)
        for instance, definition, display_name in rows
    ]
    return PaginatedChoreResponse(items=instances, total=total, limit=limit, offset=offset)


# ---------------------------------------------------------------------------
# GET /households/{household_id}/chores/templates  — admin only
#
# TASK-106: active definitions usable as "start from a previous task"
# suggestions on the create form. MUST be declared before the
# /{instance_id} route below — FastAPI matches in declaration order and
# "/templates" would otherwise be captured as a UUID path param (422).
# ---------------------------------------------------------------------------

@router.get(
    "/templates",
    response_model=list[ChoreTemplateResponse],
)
async def list_chore_templates(
    household_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_admin),
) -> list[ChoreTemplateResponse]:
    """Active chore definitions usable as create-form templates, newest first.

    Definitions hidden via ``POST .../hide`` are excluded; hiding does not
    affect the chore list itself.
    """
    result = await db.execute(
        select(ChoreDefinition)
        .where(
            ChoreDefinition.household_id == household_id,
            ChoreDefinition.is_active.is_(True),
            ChoreDefinition.hidden_from_suggestions.is_(False),
        )
        .order_by(ChoreDefinition.created_at.desc())
    )
    definitions = result.scalars().all()
    return [ChoreTemplateResponse.model_validate(d) for d in definitions]


# ---------------------------------------------------------------------------
# POST /households/{household_id}/chores/{definition_id}/hide  — admin only
# ---------------------------------------------------------------------------

@router.post(
    "/{definition_id}/hide",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def hide_chore_template(
    household_id: uuid.UUID,
    definition_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_admin),
) -> None:
    """Stop showing a definition as a create-form template (admin only).

    Sets ``hidden_from_suggestions``; the chore and its instances are
    untouched.
    """
    result = await db.execute(
        select(ChoreDefinition).where(
            ChoreDefinition.id == definition_id,
            ChoreDefinition.household_id == household_id,
            ChoreDefinition.is_active.is_(True),
        )
    )
    definition = result.scalar_one_or_none()

    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chore definition not found",
        )

    definition.hidden_from_suggestions = True


# ---------------------------------------------------------------------------
# GET /households/{household_id}/chores/{instance_id}  — any member
# ---------------------------------------------------------------------------

@router.get(
    "/{instance_id}",
    response_model=ChoreInstanceResponse,
)
async def get_chore_instance(
    household_id: uuid.UUID,
    instance_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> ChoreInstanceResponse:
    """Return a single ChoreInstance with definition data embedded."""
    stmt = (
        select(ChoreInstance, ChoreDefinition, User.display_name)
        .join(ChoreDefinition, ChoreInstance.definition_id == ChoreDefinition.id)
        .outerjoin(User, ChoreInstance.assignee_id == User.id)
        .where(
            ChoreInstance.id == instance_id,
            ChoreInstance.household_id == household_id,
        )
    )
    result = await db.execute(stmt)
    row = result.one_or_none()

    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chore instance not found",
        )

    instance, definition, display_name = row
    return _instance_response_from_row(instance, definition, display_name)


# ---------------------------------------------------------------------------
# POST /households/{household_id}/chores/{instance_id}/complete|dismiss
# — assignee, or admin acting on the assignee's behalf
# ---------------------------------------------------------------------------

_TERMINAL_STATUSES = {"complete", "cancelled", "dismissed"}


async def _load_instance_for_terminal_transition(
    db: AsyncSession,
    household_id: uuid.UUID,
    instance_id: uuid.UUID,
    *,
    current_user: User,
    membership: HouseholdMembership,
    forbidden_detail: str,
    terminal_verb: str,
) -> ChoreInstance:
    """Lock an instance and enforce the rules shared by terminal transitions.

    Shared prologue for the ``complete``/``dismiss`` endpoints — the single
    source of truth for their permission model:

    - 404 when the instance is not in this household.
    - 403 unless the caller is the assignee or a household admin. Admins act
      on the assignee's behalf; any points awarded go to the assignee.
    - 409 when the instance is already in a terminal status.

    Returns the locked instance.
    """
    lock_result = await db.execute(
        select(ChoreInstance)
        .where(
            ChoreInstance.id == instance_id,
            ChoreInstance.household_id == household_id,
        )
        .with_for_update()
    )
    instance = lock_result.scalar_one_or_none()

    if instance is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chore instance not found",
        )

    is_assignee = (
        instance.assignee_id is not None and instance.assignee_id == current_user.id
    )
    is_admin = membership.role == "admin"
    if not (is_assignee or is_admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=forbidden_detail,
        )

    if instance.status in _TERMINAL_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Chore instance is already '{instance.status}' "
                f"and cannot be {terminal_verb}"
            ),
        )

    return instance


async def _definition_or_422(
    db: AsyncSession, instance: ChoreInstance
) -> ChoreDefinition:
    """Fetch the definition backing ``instance``; 422 when it no longer exists."""
    def_result = await db.execute(
        select(ChoreDefinition).where(ChoreDefinition.id == instance.definition_id)
    )
    definition = def_result.scalar_one_or_none()
    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Chore definition no longer exists",
        )
    return definition


async def _resolve_assignee_name(
    db: AsyncSession, assignee_id: Optional[uuid.UUID]
) -> Optional[str]:
    """Display name for the instance's assignee, or None when unassigned."""
    if assignee_id is None:
        return None
    user_result = await db.execute(select(User).where(User.id == assignee_id))
    user = user_result.scalar_one_or_none()
    return user.display_name if user is not None else None


@router.post(
    "/{instance_id}/complete",
    response_model=ChoreInstanceResponse,
)
async def complete_chore_instance(
    household_id: uuid.UUID,
    instance_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> ChoreInstanceResponse:
    """Mark a ChoreInstance as complete, award points, and record a PointLedger entry.

    The assignee may complete their own instance; an admin may complete any
    instance **on the assignee's behalf** — points are always credited to the
    assignee, never the admin. Attempting to complete an already-terminal
    instance returns HTTP 409.

    Edge case: if ``assignee_id`` is NULL (member removed after assignment),
    the instance is completed without a PointLedger row and ``points_awarded``
    stays NULL (the ``PointLedger.user_id`` FK is non-nullable).
    """
    instance = await _load_instance_for_terminal_transition(
        db,
        household_id,
        instance_id,
        current_user=current_user,
        membership=_membership,
        forbidden_detail="Only the assigned user may complete this chore",
        terminal_verb="completed",
    )

    definition = await _definition_or_422(db, instance)

    now = datetime.now(timezone.utc)
    instance.status = "complete"
    instance.completed_at = now

    if instance.assignee_id is not None:
        points_awarded = EFFORT_POINTS[definition.effort_level]
        instance.points_awarded = points_awarded
        ledger_entry = PointLedger(
            household_id=household_id,
            user_id=instance.assignee_id,
            chore_instance_id=instance_id,
            points=points_awarded,
            awarded_at=now,
        )
        db.add(ledger_entry)
        logger.info(
            "chore.completed",
            chore_instance_id=str(instance_id),
            user_id=str(instance.assignee_id),
            points=points_awarded,
        )
    else:
        # Assignee removed after assignment — close the instance without
        # awarding points (PointLedger.user_id is non-nullable).
        instance.points_awarded = None
        logger.info(
            "chore.completed_without_assignee",
            chore_instance_id=str(instance_id),
            household_id=str(household_id),
        )

    assignee_name = await _resolve_assignee_name(db, instance.assignee_id)
    return _instance_response_from_row(instance, definition, assignee_name)


@router.post(
    "/{instance_id}/dismiss",
    response_model=ChoreInstanceResponse,
)
async def dismiss_chore_instance(
    household_id: uuid.UUID,
    instance_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> ChoreInstanceResponse:
    """Close a ChoreInstance as done WITHOUT awarding points.

    Distinct from ``complete`` (awards points) and ``cancelled`` (series
    deleted): dismissing records that the task was closed but earns the
    assignee zero points — no PointLedger row is created. The assignee may
    dismiss their own instance; an admin may dismiss any instance on the
    assignee's behalf.
    """
    instance = await _load_instance_for_terminal_transition(
        db,
        household_id,
        instance_id,
        current_user=current_user,
        membership=_membership,
        forbidden_detail="Only the assigned user may dismiss this chore",
        terminal_verb="dismissed",
    )

    definition = await _definition_or_422(db, instance)

    now = datetime.now(timezone.utc)
    instance.status = "dismissed"
    instance.completed_at = now
    instance.points_awarded = None
    logger.info(
        "chore.dismissed",
        chore_instance_id=str(instance_id),
        household_id=str(household_id),
        user_id=str(current_user.id),
    )

    assignee_name = await _resolve_assignee_name(db, instance.assignee_id)
    return _instance_response_from_row(instance, definition, assignee_name)


# ---------------------------------------------------------------------------
# PATCH /households/{household_id}/chores/{instance_id}/assignee  — admin only
# ---------------------------------------------------------------------------

@router.patch(
    "/{instance_id}/assignee",
    response_model=ChoreInstanceResponse,
)
async def reassign_chore(
    household_id: uuid.UUID,
    instance_id: uuid.UUID,
    body: ChoreReassignRequest,
    _membership: HouseholdMembership = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
    assignment_service: AssignmentService = Depends(get_assignment_service),
) -> ChoreInstanceResponse:
    """Manually reassign a ChoreInstance to a specific member or trigger auto-assignment.

    Passing ``assignee_id=null`` re-runs round-robin auto-assignment and clears
    the manual flag.  Passing a valid member UUID sets the assignee directly and
    marks the instance as manually assigned.
    """
    # 1. Fetch the instance, verifying it belongs to the requested household.
    instance_result = await db.execute(
        select(ChoreInstance).where(
            ChoreInstance.id == instance_id,
            ChoreInstance.household_id == household_id,
        )
    )
    instance = instance_result.scalar_one_or_none()
    if instance is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chore instance not found",
        )

    # Terminal instances (complete/cancelled) cannot be reassigned.
    if instance.status in _TERMINAL_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Chore instance is '{instance.status}' and cannot be reassigned",
        )

    if body.assignee_id is not None:
        # 2. Verify the target user is an active member of this household.
        member_check = await db.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.household_id == household_id,
                HouseholdMembership.user_id == body.assignee_id,
                HouseholdMembership.is_active == True,  # noqa: E712
            )
        )
        if member_check.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="assignee_id is not an active member of this household",
            )
        # 4. Manual assignment.
        instance.assignee_id = body.assignee_id
        instance.assigned_manually = True
    else:
        # 3. Auto-assign via round-robin strategy.
        new_assignee_id = await assignment_service.auto_assign(household_id, db)
        instance.assignee_id = new_assignee_id
        instance.assigned_manually = False

    await db.flush()

    # Fetch the definition and assignee name for the response.
    def_result = await db.execute(
        select(ChoreDefinition).where(ChoreDefinition.id == instance.definition_id)
    )
    definition = def_result.scalar_one_or_none()
    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Chore definition no longer exists",
        )

    assignee_name: Optional[str] = None
    if instance.assignee_id is not None:
        user_result = await db.execute(
            select(User).where(User.id == instance.assignee_id)
        )
        assignee = user_result.scalar_one_or_none()
        if assignee is not None:
            assignee_name = assignee.display_name

    return _instance_response_from_row(instance, definition, assignee_name)


# ---------------------------------------------------------------------------
# PATCH /households/{household_id}/chores/{definition_id}  — admin only
# ---------------------------------------------------------------------------

@router.patch(
    "/{definition_id}",
    response_model=ChoreDefinitionResponse,
)
async def update_chore_definition(
    household_id: uuid.UUID,
    definition_id: uuid.UUID,
    body: ChoreUpdate,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_admin),
) -> ChoreDefinitionResponse:
    """Update mutable fields on a ChoreDefinition (does not touch existing instances)."""
    result = await db.execute(
        select(ChoreDefinition).where(
            ChoreDefinition.id == definition_id,
            ChoreDefinition.household_id == household_id,
            ChoreDefinition.is_active.is_(True),
        )
    )
    definition = result.scalar_one_or_none()

    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chore definition not found",
        )

    # Apply only provided fields.  model_dump() already converts any nested
    # RecurrenceRule model to a plain dict suitable for JSONB storage.
    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(definition, field, value)

    await db.flush()
    await db.refresh(definition)

    return ChoreDefinitionResponse(
        id=definition.id,
        household_id=definition.household_id,
        title=definition.title,
        description=definition.description,
        category=definition.category,
        effort_level=definition.effort_level,
        chore_type=definition.chore_type,
        recurrence_rule=definition.recurrence_rule,
        first_due_date=definition.first_due_date,
        is_active=definition.is_active,
        created_at=definition.created_at,
        first_instance=None,
    )


# ---------------------------------------------------------------------------
# DELETE /households/{household_id}/chores/{definition_id}  — admin only
# ---------------------------------------------------------------------------

@router.delete(
    "/{definition_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_chore_definition(
    household_id: uuid.UUID,
    definition_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_admin),
) -> None:
    """Soft-delete a ChoreDefinition; cancel all pending instances."""
    result = await db.execute(
        select(ChoreDefinition).where(
            ChoreDefinition.id == definition_id,
            ChoreDefinition.household_id == household_id,
        )
    )
    definition = result.scalar_one_or_none()

    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chore definition not found",
        )

    # Soft-delete the definition
    definition.is_active = False

    # Cancel all pending instances; leave completed/cancelled untouched
    await db.execute(
        update(ChoreInstance)
        .where(
            ChoreInstance.definition_id == definition_id,
            ChoreInstance.status == "pending",
        )
        .values(status="cancelled")
    )

    await db.flush()
