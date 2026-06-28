from typing import Protocol, runtime_checkable
import uuid
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.household import Household
from app.models.household_membership import HouseholdMembership

@runtime_checkable
class AssignmentStrategy(Protocol):
    async def assign(
        self,
        household_id: uuid.UUID,
        session: AsyncSession,
    ) -> uuid.UUID | None:
        """Return the user_id to assign to, or None if no active members."""
        ...


class RoundRobinStrategy:
    async def assign(
        self,
        household_id: uuid.UUID,
        session: AsyncSession,
    ) -> uuid.UUID | None:
        # 1. Lock the Household row to prevent concurrent pointer updates
        #    SELECT * FROM households WHERE id = household_id FOR UPDATE
        result = await session.execute(
            select(Household)
            .where(Household.id == household_id)
            .with_for_update()
        )
        household = result.scalar_one_or_none()
        if household is None:
            return None

        # 2. Fetch active members ordered by joined_at ASC (rotation order)
        members_result = await session.execute(
            select(HouseholdMembership.user_id)
            .where(
                HouseholdMembership.household_id == household_id,
                HouseholdMembership.is_active == True,
            )
            .order_by(HouseholdMembership.joined_at.asc())
        )
        member_ids = members_result.scalars().all()

        if not member_ids:
            return None

        # 3. Pick member at current pointer position (modulo for wrap-around)
        pointer = household.rotation_pointer % len(member_ids)
        selected_user_id = member_ids[pointer]

        # 4. Advance the pointer atomically (already locked above)
        household.rotation_pointer = household.rotation_pointer + 1
        # session.add(household) not needed — already tracked
        # commit happens at route level via get_db

        return selected_user_id


class AssignmentService:
    def __init__(self, strategy: AssignmentStrategy):
        self.strategy = strategy

    async def auto_assign(
        self,
        household_id: uuid.UUID,
        session: AsyncSession,
    ) -> uuid.UUID | None:
        """Auto-assign using the configured strategy. Does NOT advance pointer for manual assignments."""
        return await self.strategy.assign(household_id, session)

    async def redistribute_chores(
        self,
        chore_instance_ids: list[uuid.UUID],
        household_id: uuid.UUID,
        session: AsyncSession,
    ) -> dict[uuid.UUID, uuid.UUID | None]:
        """
        Reassign a list of chore instances via round-robin.
        Returns mapping of {chore_instance_id: new_assignee_id}.
        Each call to auto_assign advances the pointer by 1.
        """
        assignments: dict[uuid.UUID, uuid.UUID | None] = {}
        for instance_id in chore_instance_ids:
            new_assignee = await self.strategy.assign(household_id, session)
            assignments[instance_id] = new_assignee
        return assignments


def get_assignment_service() -> AssignmentService:
    """FastAPI dependency: returns AssignmentService with RoundRobinStrategy."""
    return AssignmentService(strategy=RoundRobinStrategy())
