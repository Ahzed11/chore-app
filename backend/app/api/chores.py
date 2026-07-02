"""Chore CRUD endpoints.

All routes are scoped to a household:
    /households/{household_id}/chores
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, update
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
    ChoreCreate,
    ChoreDefinitionResponse,
    ChoreInstanceResponse,
    ChoreUpdate,
)
from app.services.assignment import AssignmentService, get_assignment_service

router = APIRouter(prefix="/households/{household_id}/chores", tags=["chores"])


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
    response_model=list[ChoreInstanceResponse],
)
async def list_chores(
    household_id: uuid.UUID,
    status_filter: Optional[str] = None,
    category: Optional[str] = None,
    assignee_id: Optional[uuid.UUID] = None,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> list[ChoreInstanceResponse]:
    """List ChoreInstances for a household, with optional filters."""
    stmt = (
        select(ChoreInstance, ChoreDefinition, User.display_name)
        .join(ChoreDefinition, ChoreInstance.definition_id == ChoreDefinition.id)
        .outerjoin(User, ChoreInstance.assignee_id == User.id)
        .where(ChoreInstance.household_id == household_id)
        .where(ChoreDefinition.is_active == True)
    )

    if status_filter is not None:
        stmt = stmt.where(ChoreInstance.status == status_filter)
    if category is not None:
        stmt = stmt.where(ChoreDefinition.category == category)
    if assignee_id is not None:
        stmt = stmt.where(ChoreInstance.assignee_id == assignee_id)

    result = await db.execute(stmt)
    rows = result.all()

    return [
        _instance_response_from_row(instance, definition, display_name)
        for instance, definition, display_name in rows
    ]


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
# POST /households/{household_id}/chores/{instance_id}/complete  — assignee only
# ---------------------------------------------------------------------------

_COMPLETABLE_STATUSES = {"pending", "overdue"}
_TERMINAL_STATUSES = {"complete", "cancelled"}


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

    Only the assigned user may complete the instance.  Attempting to complete an
    already-complete or cancelled instance returns HTTP 409.
    """
    # Lock the row to prevent concurrent double-completion.
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

    # Only the assignee may complete the instance.
    if instance.assignee_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the assigned user may complete this chore",
        )

    # Guard against double-completion or completing a cancelled chore.
    if instance.status in _TERMINAL_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Chore instance is already '{instance.status}' and cannot be completed",
        )

    # Fetch the definition to read effort_level.
    def_result = await db.execute(
        select(ChoreDefinition).where(ChoreDefinition.id == instance.definition_id)
    )
    definition = def_result.scalar_one_or_none()
    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Chore definition no longer exists; cannot determine points",
        )

    points_awarded = EFFORT_POINTS[definition.effort_level]
    now = datetime.now(timezone.utc)

    # Update the instance within the same transaction.
    instance.status = "complete"
    instance.completed_at = now
    instance.points_awarded = points_awarded

    # Insert a PointLedger record.
    ledger_entry = PointLedger(
        household_id=household_id,
        user_id=current_user.id,
        chore_instance_id=instance_id,
        points=points_awarded,
        awarded_at=now,
    )
    db.add(ledger_entry)

    # Resolve assignee display name for the response.
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
            ChoreDefinition.is_active == True,
        )
    )
    definition = result.scalar_one_or_none()

    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chore definition not found",
        )

    # Apply only provided fields
    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if field == "recurrence_rule" and value is not None:
            # RecurrenceRule object → dict for JSONB storage
            if hasattr(value, "model_dump"):
                value = value.model_dump()
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
