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

    async def redistribute_chores_bulk(
        self,
        chore_instance_ids: list[uuid.UUID],
        household_id: uuid.UUID,
        session: AsyncSession,
    ) -> dict[uuid.UUID, uuid.UUID | None]:
        """Bulk reassign chore instances via round-robin using a single lock acquisition.

        Acquires SELECT FOR UPDATE on the household row once, cycles through active
        members in Python using the current rotation_pointer, then writes the updated
        pointer once after the loop — O(1) lock acquisitions instead of O(N).

        Returns a mapping of {chore_instance_id: new_assignee_id}.
        """
        if not chore_instance_ids:
            return {}

        # 1. Single SELECT FOR UPDATE — acquire the row lock once for the whole batch.
        result = await session.execute(
            select(Household)
            .where(Household.id == household_id)
            .with_for_update()
        )
        household = result.scalar_one_or_none()
        if household is None:
            return {cid: None for cid in chore_instance_ids}

        # 2. Fetch active members ordered by joined_at ASC (same ordering as
        #    RoundRobinStrategy.assign so rotation behaviour is identical).
        members_result = await session.execute(
            select(HouseholdMembership.user_id)
            .where(
                HouseholdMembership.household_id == household_id,
                HouseholdMembership.is_active == True,  # noqa: E712
            )
            .order_by(HouseholdMembership.joined_at.asc())
        )
        member_ids = members_result.scalars().all()

        if not member_ids:
            return {cid: None for cid in chore_instance_ids}

        # 3. Cycle through members in Python.
        assignments: dict[uuid.UUID, uuid.UUID | None] = {}
        pointer = household.rotation_pointer
        for instance_id in chore_instance_ids:
            assignments[instance_id] = member_ids[pointer % len(member_ids)]
            pointer += 1

        # 4. Write the updated pointer once (single UPDATE on commit).
        household.rotation_pointer = pointer

        return assignments


def get_assignment_service() -> AssignmentService:
    """FastAPI dependency: returns AssignmentService with RoundRobinStrategy."""
    return AssignmentService(strategy=RoundRobinStrategy())
