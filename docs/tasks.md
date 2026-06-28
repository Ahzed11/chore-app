# Implementation Task List — Household Chores Motivation App

**Version**: 1.0  
**Date**: 2026-06-25  
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by reading only this task description plus the referenced requirements sections. Dependency chains are explicit.

---

## TASK-001: Backend — Project Scaffolding

**Domain**: Backend  
**Depends on**: none  
**Description**: Initialise the FastAPI project with the correct directory structure, dependency management, configuration loading, and a minimal health-check endpoint. This is the foundation every other backend task builds on.

Set up the following layout:
```
backend/
  app/
    api/          # route modules
    core/         # config, security utilities
    db/           # database session, base model
    models/       # SQLAlchemy ORM models
    schemas/      # Pydantic request/response schemas
    services/     # business logic layer
    tasks/        # background jobs
  alembic/        # migration files
  tests/
  alembic.ini
  main.py
  pyproject.toml (or requirements.txt)
```

Dependencies to install: `fastapi`, `uvicorn[standard]`, `sqlalchemy[asyncio]`, `asyncpg`, `alembic`, `pydantic-settings`, `python-jose[cryptography]`, `passlib[bcrypt]`, `python-multipart`, `httpx` (for tests), `pytest`, `pytest-asyncio`.

Configuration must be loaded from environment variables using `pydantic-settings`. Required env vars: `DATABASE_URL`, `JWT_SECRET`, `JWT_ALGORITHM` (default HS256), `JWT_EXPIRY_DAYS` (default 7).

**Acceptance criteria**:
- [ ] `GET /health` returns `{"status": "ok"}` with HTTP 200.
- [ ] Application starts with `uvicorn main:app` without errors.
- [ ] All configuration is loaded from environment variables; no secrets are hardcoded.
- [ ] `pyproject.toml` (or equivalent) lists all dependencies with pinned versions.
- [ ] `tests/` directory exists with a passing smoke test that calls `GET /health`.

---

## TASK-002: Backend — Database Setup and Base Migration

**Domain**: Backend  
**Depends on**: TASK-001  
**Description**: Configure async SQLAlchemy with PostgreSQL and initialise Alembic for schema migrations. Create the SQLAlchemy declarative base that all ORM models will inherit from. The database session should be provided via FastAPI dependency injection.

An async session factory must be created using `create_async_engine` and `async_sessionmaker`. The session dependency should be a FastAPI `Depends` callable that yields an `AsyncSession` and commits/rolls back correctly.

Alembic must be configured to use the async engine (via `run_sync` pattern) and to auto-detect model changes.

**Acceptance criteria**:
- [ ] `alembic upgrade head` runs without errors against a real PostgreSQL instance.
- [ ] `alembic downgrade -1` is also tested and works.
- [ ] `AsyncSession` is injectable via `Depends(get_db)` in route handlers.
- [ ] A test verifies that a database connection can be acquired and a simple query executed.

---

## TASK-003: Backend — Database Schema and Initial Migration

**Domain**: Backend  
**Depends on**: TASK-002  
**Description**: Define all SQLAlchemy ORM models and generate the initial Alembic migration that creates the full schema. Models to create (refer to Section 7 of `requirements.md` for field-level detail):

- `User`
- `Household`
- `HouseholdMembership`
- `InviteToken`
- `ChoreDefinition`
- `ChoreInstance`
- `PointLedger`

Implementation notes:
- Use `UUID` primary keys (PostgreSQL `uuid` type, generated server-side).
- `ChoreDefinition.recurrence_rule` is a `JSONB` column.
- `ChoreDefinition.category` and `ChoreInstance.status` are PostgreSQL native enums (use SQLAlchemy `Enum` with `native_enum=True`).
- Add the unique constraint on `ChoreInstance(definition_id, due_date)`.
- Add the partial unique constraint on `HouseholdMembership(household_id, user_id)` where `is_active = true` (use a PostgreSQL partial index).
- Add indexes on: `ChoreInstance(household_id, status)`, `ChoreInstance(assignee_id)`, `PointLedger(household_id, user_id, awarded_at)`.
- `Household.rotation_pointer` must default to 0.

**Acceptance criteria**:
- [ ] `alembic upgrade head` creates all tables with correct columns, types, constraints, and indexes.
- [ ] All foreign keys have appropriate cascade rules defined.
- [ ] Models can be imported without errors.
- [ ] A migration downgrade removes all created objects cleanly.

---

## TASK-004: Backend — Authentication: Register and Login

**Domain**: Backend  
**Depends on**: TASK-003  
**Description**: Implement user registration and login endpoints. These are the only two endpoints that do not require a JWT.

**POST /auth/register**
- Body: `{ "email": str, "password": str, "display_name": str }`
- Validate email uniqueness; return HTTP 409 if taken.
- Hash password with bcrypt (cost factor >= 12).
- Insert User record.
- Return: `{ "id": uuid, "email": str, "display_name": str, "created_at": datetime }`

**POST /auth/login**
- Body: `{ "email": str, "password": str }`
- Verify credentials. Return HTTP 401 on failure.
- On success, return: `{ "access_token": str, "token_type": "bearer", "expires_in": int }`
- JWT payload must include: `sub` (user ID as string), `exp`.

Refer to FR-001 through FR-007 in `requirements.md`.

**Acceptance criteria**:
- [ ] Registering with a unique email returns HTTP 201 and a user object.
- [ ] Registering with a duplicate email returns HTTP 409 with a meaningful error message.
- [ ] Login with valid credentials returns HTTP 200 and a JWT.
- [ ] Login with invalid credentials returns HTTP 401.
- [ ] Password is never returned in any response body.
- [ ] The JWT can be decoded and the `sub` claim matches the user's ID.
- [ ] Unit tests cover all above cases.

---

## TASK-005: Backend — JWT Middleware and Auth Dependency

**Domain**: Backend  
**Depends on**: TASK-004  
**Description**: Implement a reusable FastAPI dependency `get_current_user` that:
1. Extracts the Bearer token from the `Authorization` header.
2. Verifies the JWT signature and expiry.
3. Looks up the User record from the database using the `sub` claim.
4. Returns the User ORM object, or raises HTTP 401 if the token is invalid, expired, or the user no longer exists.

This dependency is used by every protected endpoint. Also implement a `require_household_member(household_id)` dependency that additionally verifies the current user has an active membership in the given household, returning the `HouseholdMembership` record or raising HTTP 403.

Refer to FR-006 and FR-007 in `requirements.md`.

**Acceptance criteria**:
- [ ] A request to any protected endpoint without a token returns HTTP 401.
- [ ] A request with an expired token returns HTTP 401.
- [ ] A request with a valid token returns the expected response.
- [ ] A request to a household-scoped endpoint by a non-member returns HTTP 403.
- [ ] Unit tests mock the database and verify each failure mode.

---

## TASK-006: Backend — User Profile Endpoints

**Domain**: Backend  
**Depends on**: TASK-005  
**Description**: Implement the authenticated user profile endpoints.

**GET /users/me** — Returns the current user's profile (`id`, `email`, `display_name`, `created_at`).

**PATCH /users/me** — Updates the current user's `display_name`. Body: `{ "display_name": str }`. Returns the updated profile.

Refer to FR-008 through FR-010 in `requirements.md`.

**Acceptance criteria**:
- [ ] `GET /users/me` returns the correct profile for the authenticated user.
- [ ] `PATCH /users/me` updates the display name and returns the updated record.
- [ ] `PATCH /users/me` with an empty string display name returns HTTP 422.
- [ ] Both endpoints return HTTP 401 when called without a token.

---

## TASK-007: Backend — Household CRUD

**Domain**: Backend  
**Depends on**: TASK-005  
**Description**: Implement household creation, retrieval, and update endpoints.

**POST /households** — Create a new household. Body: `{ "name": str }`. The authenticated user is automatically added as an Admin member with `joined_at = now()`. The `rotation_pointer` is initialised to 0. Returns the created household.

**GET /households/{household_id}** — Returns household details (id, name, created_at, member count). Requires the requesting user to be a member.

**PATCH /households/{household_id}** — Updates household name. Admin only. Returns updated household.

**GET /households** — Returns a list of all households the current user is an active member of, including their role in each.

Refer to FR-011 through FR-014 and FR-023 in `requirements.md`.

**Acceptance criteria**:
- [ ] Creating a household returns HTTP 201 and the household object.
- [ ] The creator is automatically an Admin member of the new household.
- [ ] `GET /households` returns only households where the requesting user has an active membership.
- [ ] `PATCH /households/{id}` called by a Member (non-Admin) returns HTTP 403.
- [ ] Accessing a household the user is not a member of returns HTTP 403.
- [ ] Unit and integration tests cover all cases.

---

## TASK-008: Backend — Invite Link Generation and Join Flow

**Domain**: Backend  
**Depends on**: TASK-007  
**Description**: Implement the invite token system for adding members to a household.

**POST /households/{household_id}/invites** — Admin only. Generates a cryptographically random token (minimum 128 bits, URL-safe base64), stores it in `InviteToken` with an expiry (default 48 hours — see OQ-001; use a configurable env var `INVITE_TOKEN_TTL_HOURS` defaulting to 48). Returns: `{ "token": str, "invite_url": str, "expires_at": datetime }`. The `invite_url` is constructed as `{APP_BASE_URL}/join/{token}`.

**POST /invites/{token}/accept** — Authenticated endpoint. The requesting user joins the household as a Member. Validate: token exists, is not expired, has not been used. On success: create `HouseholdMembership`, mark token as used (`used_at = now()`), append user to rotation. If the user is already an active member of that household, return HTTP 409. Returns the household object.

Refer to FR-015 through FR-017 in `requirements.md`, BR-004, and OQ-001.

**Acceptance criteria**:
- [ ] Only Admins can generate invite tokens; Members get HTTP 403.
- [ ] The generated token is URL-safe and at least 22 characters (128-bit base64).
- [ ] Accepting a valid token adds the user as a Member with `joined_at` set to the acceptance timestamp.
- [ ] Accepting an expired token returns HTTP 410 (Gone).
- [ ] Accepting an already-used token returns HTTP 410.
- [ ] Accepting a token as an existing member returns HTTP 409.
- [ ] Tests cover the full acceptance flow and all error cases.

---

## TASK-009: Backend — Member Management (Remove, Role Change)

**Domain**: Backend  
**Depends on**: TASK-008  
**Description**: Implement member management endpoints available to Admins.

**GET /households/{household_id}/members** — Returns all active members with their role, display name, and joined_at. Available to all members (Admin and Member).

**DELETE /households/{household_id}/members/{user_id}** — Admin only. Marks the membership as inactive (`is_active = false`). Triggers chore redistribution (call the redistribution service from TASK-013). Cannot remove self if sole Admin (HTTP 409). Cannot remove the last member if that would leave the household empty with no resolution — allow it but place chores in unassigned state (BR-003).

**PATCH /households/{household_id}/members/{user_id}/role** — Admin only. Body: `{ "role": "admin" | "member" }`. Cannot demote the sole Admin to member (HTTP 409).

**POST /households/{household_id}/leave** — Allows the current user to leave the household voluntarily. If the leaving user is the sole Admin, return HTTP 409 with message directing them to promote another Admin first (temporary resolution pending OQ-002).

Refer to FR-018 through FR-022 in `requirements.md` and BR-006.

**Acceptance criteria**:
- [ ] Removing a member marks their membership inactive and does not delete the record.
- [ ] Removing a member triggers redistribution of their pending chores.
- [ ] Attempting to remove the sole Admin returns HTTP 409.
- [ ] Role change from Member to Admin succeeds and is reflected in subsequent auth checks.
- [ ] Sole Admin cannot demote themselves without a prior promotion.
- [ ] Leaving household as sole Admin returns HTTP 409.
- [ ] All endpoints return HTTP 403 to non-members.

---

## TASK-010: Backend — Assignment Engine (Pluggable Strategy)

**Domain**: Backend  
**Depends on**: TASK-003  
**Description**: Implement the assignment engine as a pluggable strategy service. This is a critical architectural component (FR-041).

Define an abstract base class (or Protocol):
```python
class AssignmentStrategy(Protocol):
    async def assign(
        self,
        household_id: UUID,
        session: AsyncSession,
    ) -> UUID | None:  # returns the user_id to assign to, or None if no members
        ...
```

Implement `RoundRobinStrategy`:
- Fetch the ordered list of active members sorted by `joined_at` ASC.
- Read `Household.rotation_pointer`.
- Select the member at index `rotation_pointer % len(members)`.
- Increment `rotation_pointer` by 1 and persist it within the same transaction (use `SELECT ... FOR UPDATE` on the Household row to prevent race conditions — NFR-007).
- Return the selected `user_id`.

Implement an `AssignmentService` that accepts a strategy and exposes:
```python
async def auto_assign(self, household_id, session) -> UUID | None
async def redistribute_chores(self, chore_ids: list[UUID], household_id, session) -> None
```

`redistribute_chores` iterates the provided chore instance IDs and calls `auto_assign` for each, updating the `assignee_id` and setting `assigned_manually = False`.

Refer to FR-037 through FR-045 and BR-001 through BR-005 in `requirements.md`.

**Acceptance criteria**:
- [ ] `RoundRobinStrategy` cycles through members in join-date order.
- [ ] With a single member, all assignments go to that member.
- [ ] With no members, `assign` returns `None`.
- [ ] The rotation pointer is updated atomically; concurrent calls cannot result in the same member being assigned twice.
- [ ] Manual assignment (chore created with explicit assignee) does NOT call the strategy and does NOT advance the pointer.
- [ ] Replacing `RoundRobinStrategy` with a mock strategy in tests works without modifying `AssignmentService`.
- [ ] Unit tests achieve 100% line coverage on this module.

---

## TASK-011: Backend — Chore CRUD (Create, Read, Update, Delete)

**Domain**: Backend  
**Depends on**: TASK-010  
**Description**: Implement chore definition management endpoints. All mutation endpoints are Admin only.

**POST /households/{household_id}/chores** — Create a chore definition and its first `ChoreInstance`.
- Body includes: `title`, `description` (optional), `category`, `effort_level`, `chore_type` (`one_off` or `recurring`), `first_due_date`, `recurrence_rule` (required if `recurring`, null if `one_off`), `assignee_id` (optional).
- If `assignee_id` is provided: set `assigned_manually = True`, do not advance rotation pointer.
- If `assignee_id` is absent: call `AssignmentService.auto_assign()`.
- Create the `ChoreDefinition` and the first `ChoreInstance`.
- If the household has no members, set `assignee_id = null` on the instance (BR-004).
- Returns the created `ChoreDefinition` with the first `ChoreInstance` embedded.

**GET /households/{household_id}/chores** — Returns all chore instances for the household. Supports query params: `status` (pending/complete/overdue/cancelled), `category`, `assignee_id`. Available to all members.

**GET /households/{household_id}/chores/{chore_id}** — Returns a single chore instance with its definition.

**PATCH /households/{household_id}/chores/{definition_id}** — Admin only. Updates the chore definition (title, description, category, effort_level, recurrence_rule). Changes apply to future instances only (FR-031).

**DELETE /households/{household_id}/chores/{definition_id}** — Admin only. Soft-deletes the definition (`is_active = false`). Sets status of all pending instances to `cancelled`. Completed instances are untouched (BR-012).

Refer to FR-024 through FR-036 in `requirements.md`.

**Acceptance criteria**:
- [ ] Creating a one-off chore without assignee auto-assigns via round-robin and advances the pointer.
- [ ] Creating a chore with explicit assignee does not advance the pointer.
- [ ] Creating a chore in a household with no members results in `assignee_id = null`.
- [ ] Recurring chores have a non-null `recurrence_rule`; one-off chores have it null.
- [ ] `GET /households/{id}/chores` with `status=pending` returns only pending instances.
- [ ] Deleting a series cancels all pending instances and leaves completed ones intact.
- [ ] Members (non-Admin) cannot create, update, or delete chores (HTTP 403).
- [ ] All listed filter combinations are tested.

---

## TASK-012: Backend — Recurring Chore Instance Generator (Background Scheduler)

**Domain**: Backend  
**Depends on**: TASK-011  
**Description**: Implement a background scheduler that generates upcoming `ChoreInstance` records for active recurring chore definitions and flags overdue instances.

Use APScheduler (or a simple asyncio periodic task at startup) to run the job once daily (configurable via env var `SCHEDULER_RUN_HOUR`, default 00:00 UTC).

**Instance generation logic**:
1. Query all `ChoreDefinition` records where `chore_type = recurring` and `is_active = true`.
2. For each definition, determine the next due date(s) up to a configurable horizon (env var `INSTANCE_GENERATION_DAYS_AHEAD`, default 7).
3. Compute due dates by applying the recurrence rule from `first_due_date` stepping forward until within the horizon.
4. For each computed due date, check if an instance with `(definition_id, due_date)` already exists. If not, create one and call `AssignmentService.auto_assign()`.
5. This operation is idempotent: running the job twice on the same day must not create duplicate instances (NFR-008).

**Overdue flagging logic**:
1. Query all `ChoreInstance` records where `status = pending` and `due_date < today`.
2. Update their status to `overdue` in a batch update.

Refer to FR-028, FR-029, FR-035, FR-036, BR-007, NFR-008 in `requirements.md`.

**Acceptance criteria**:
- [ ] Running the job creates `ChoreInstance` records for recurring chores due within the horizon.
- [ ] Running the job twice on the same day does not create duplicate instances.
- [ ] Instances past their due date and still pending are marked `overdue` after the job runs.
- [ ] Completed instances are never flagged overdue regardless of their due date.
- [ ] The job can be triggered manually via a test utility function (not an HTTP endpoint).
- [ ] Unit tests use a mocked clock to verify correct behaviour at day boundaries.

---

## TASK-013: Backend — Chore Completion Endpoint and Point Award

**Domain**: Backend  
**Depends on**: TASK-011  
**Description**: Implement the endpoint for a member to mark their assigned chore as complete. This is the most transactionally critical endpoint (NFR-012).

**POST /households/{household_id}/chores/{instance_id}/complete**
- Authenticated. The requesting user must be the `assignee_id` of the instance (HTTP 403 otherwise).
- The instance must be in `pending` or `overdue` status (HTTP 409 if already `complete` or `cancelled`).
- In a single database transaction (NFR-012, BR-013):
  1. Update `ChoreInstance.status = complete`, `completed_at = now()`, `points_awarded = effort_level_points`.
  2. Insert a `PointLedger` record with `household_id`, `user_id`, `chore_instance_id`, `points`, `awarded_at = now()`.
  3. Use a `SELECT ... FOR UPDATE` on the `ChoreInstance` row to prevent double-completion (BR-013).
- Returns the updated `ChoreInstance` with the points awarded.

Effort level point mapping (FR-025): Easy = 10, Medium = 25, Hard = 50. These values should be defined as constants in a single location (`app/core/constants.py`) so they are easy to update later.

Refer to FR-046 through FR-050, BR-008, BR-013, NFR-012 in `requirements.md`.

**Acceptance criteria**:
- [ ] A member who is the assignee can mark a pending chore complete.
- [ ] A member who is the assignee can mark an overdue chore complete.
- [ ] Completing the chore awards the correct number of points and creates a `PointLedger` entry.
- [ ] A non-assignee attempting to mark the chore complete receives HTTP 403.
- [ ] Attempting to complete an already-complete chore returns HTTP 409.
- [ ] Concurrent requests to complete the same chore result in exactly one success and one HTTP 409.
- [ ] Tests verify the transaction atomicity by mocking a mid-transaction failure and confirming no partial state.
- [ ] 100% line coverage on this endpoint and its service function.

---

## TASK-014: Backend — Leaderboard Endpoint

**Domain**: Backend  
**Depends on**: TASK-013  
**Description**: Implement the leaderboard endpoint that ranks household members by points earned within a time scope.

**GET /households/{household_id}/leaderboard?scope={all_time|this_week|this_month}**
- Available to all household members.
- `scope` defaults to `all_time` if not provided.
- Server computes the date window for `this_week` (Monday 00:00 UTC to Sunday 23:59:59 UTC of the current ISO week) and `this_month` (first to last day of the current calendar month in UTC). The client does not pass date parameters (BR-010, BR-011).
- Query: aggregate `PointLedger` by `(household_id, user_id)` within the date window. Join with `User` for `display_name`. Also count `ChoreInstance` completions in the same window.
- Apply dense ranking (`RANK() OVER (ORDER BY points DESC)` or equivalent in Python).
- Response:
```json
{
  "scope": "this_week",
  "week_start": "2026-06-22",
  "week_end": "2026-06-28",
  "entries": [
    {
      "rank": 1,
      "user_id": "...",
      "display_name": "Alice",
      "points": 85,
      "chores_completed": 4
    }
  ],
  "requesting_user_rank": 2
}
```
- Members with 0 points in the scope are still included in the response with 0 points (they should not be invisible on the leaderboard).

Refer to FR-051 through FR-055 and BR-010, BR-011 in `requirements.md`.

**Acceptance criteria**:
- [ ] `all_time` scope returns the sum of all PointLedger entries for the household with no date filter.
- [ ] `this_week` scope includes only points awarded in the current Mon–Sun UTC window.
- [ ] `this_month` scope includes only points awarded in the current calendar month UTC.
- [ ] Members with equal points share the same rank (dense ranking).
- [ ] The response includes `requesting_user_rank`.
- [ ] Members with zero points in the scope appear with `points: 0` and `rank` computed correctly.
- [ ] Invalid `scope` values return HTTP 422.
- [ ] Tests use a fixed mock clock to verify correct weekly and monthly window computation.

---

## TASK-015: Backend — Member Chore Redistribution Service

**Domain**: Backend  
**Depends on**: TASK-010, TASK-009  
**Description**: Implement the redistribution logic that runs when a member is removed from a household (called internally by the remove-member endpoint in TASK-009). This is separate from the assignment engine itself.

**Redistribution logic** (FR-042, BR-002):
1. Query all `ChoreInstance` records where `assignee_id = removed_user_id` and `household_id = household_id` and `status IN (pending, overdue)`.
2. If no remaining active members exist, set all these instances to `assignee_id = null` (BR-003).
3. Otherwise, call `AssignmentService.redistribute_chores(chore_ids, household_id, session)` which calls `auto_assign` for each instance in order (the rotation pointer continues from its current position).
4. Adjust the `rotation_pointer` if the removed member's index was at or past the current pointer position (BR-002).
5. All of the above must happen in the same transaction as the membership deactivation.

Refer to FR-042 through FR-044, BR-002, BR-003 in `requirements.md`.

**Acceptance criteria**:
- [ ] Removing a member redistributes all their pending and overdue chores.
- [ ] Completed chores are not touched by redistribution.
- [ ] If no members remain, chores are set to `assignee_id = null`.
- [ ] The rotation pointer is correctly adjusted after removal.
- [ ] Redistribution and membership deactivation happen atomically (one transaction).
- [ ] Tests cover: removal when sole member, removal of first in rotation, removal of last in rotation.

---

## TASK-016: Flutter — Project Scaffolding

**Domain**: Frontend  
**Depends on**: none  
**Description**: Initialise the Flutter project targeting Android. Set up the project structure, state management, routing, networking, and local storage layers.

```
flutter_app/
  lib/
    core/
      api/          # HTTP client, API service base
      auth/         # token storage, auth state
      config/       # environment config (base URL)
    features/
      auth/         # login, register screens + logic
      household/    # household dashboard, management
      chores/       # chore list, detail, mark complete
      leaderboard/  # leaderboard screen
    shared/
      widgets/      # reusable UI components
      theme/        # app theme, colours, typography
  test/
```

State management: use Riverpod (or Provider if already decided — use Riverpod for this project). Routing: use `go_router`. HTTP client: `dio` with an interceptor that attaches the Bearer token from secure storage. Token storage: `flutter_secure_storage`.

Minimum Android SDK: 21.

**Acceptance criteria**:
- [ ] `flutter run` launches without errors on an Android emulator or device.
- [ ] `flutter test` runs with no failures on the initial scaffold tests.
- [ ] The Dio client has an interceptor that reads the token from secure storage and attaches it as `Authorization: Bearer <token>`.
- [ ] A `401` response from the API automatically clears the stored token and redirects the user to the login screen.
- [ ] `go_router` is configured with named routes for all planned screens (even if they are placeholder screens at this stage).
- [ ] The app theme is defined centrally in `shared/theme/`.

---

## TASK-017: Flutter — Auth Screens (Login and Register)

**Domain**: Frontend  
**Depends on**: TASK-016, TASK-004  
**Description**: Implement the login and registration screens with form validation, API integration, and token storage.

**Register screen** fields: display name, email, password, confirm password. Validations: email format, password minimum length (match OQ-008 decision; default to 8 chars for MVP), passwords match. On success: store JWT in secure storage, navigate to household dashboard.

**Login screen** fields: email, password. On success: store JWT, navigate to household dashboard. On failure: show inline error.

Both screens should share a common layout/branding. Include a link to switch between login and register.

**Acceptance criteria**:
- [ ] Register form validates all fields before submission.
- [ ] Duplicate email registration shows an error message (sourced from the API 409 response).
- [ ] Successful registration navigates to the household dashboard.
- [ ] Login with valid credentials stores the JWT and navigates to the dashboard.
- [ ] Login with invalid credentials shows a clear error without crashing.
- [ ] Password field obscures input and has a toggle to reveal.
- [ ] Both screens are usable at 360dp width (minimum Android screen width).
- [ ] Widget tests cover form validation logic.

---

## TASK-018: Flutter — Household Dashboard Screen

**Domain**: Frontend  
**Depends on**: TASK-017, TASK-007  
**Description**: Implement the main screen a user sees after logging in: a list of households they belong to, with their role in each, and a button to create a new household or navigate into an existing one.

**Household list**: fetches `GET /households`. Each card shows household name, user's role (Admin / Member), and member count. Tapping a card navigates to the chore list for that household.

**Create household**: a FAB or top-bar action opens a modal/bottom sheet with a name input field. On submit, calls `POST /households` and refreshes the list.

**Empty state**: if the user belongs to no households, show an illustration and a prompt to create one or join via an invite link.

**Accepts invite**: provide a way for the user to enter an invite token manually (paste from clipboard) or scan a QR code. On success, refresh the household list.

**Acceptance criteria**:
- [ ] Household list loads and displays correctly after login.
- [ ] Each household card shows name, role, and member count.
- [ ] Creating a household via the modal adds it to the list immediately (optimistic update or refresh).
- [ ] Empty state is displayed when the user has no households.
- [ ] Tapping a household navigates to the chore list screen with the correct household ID.
- [ ] Widget tests cover list rendering and empty state.

---

## TASK-019: Flutter — Chore List Screen (All Household Chores)

**Domain**: Frontend  
**Depends on**: TASK-018, TASK-011  
**Description**: Implement the screen that shows all chores in a household. This is the primary daily-use screen.

Fetches `GET /households/{id}/chores`. Display chores in a scrollable list. Each chore card shows: title, category (icon + label), assignee display name, due date, effort level badge, and status indicator (pending / overdue / complete).

Provide a filter bar at the top with chips or a dropdown for: status, category. Provide a toggle to show "My chores only" vs. "All chores".

Overdue chores should be visually distinct (e.g. red border or warning icon).

An Admin should see a FAB to create a new chore (navigates to TASK-023 — create chore screen). An Admin should also see a long-press or swipe action on a chore card to delete it.

Pull-to-refresh to reload the list.

**Acceptance criteria**:
- [ ] All chores for the household are loaded and displayed.
- [ ] Filter by status shows only chores matching that status.
- [ ] Filter by category works correctly.
- [ ] "My chores only" toggle filters to the current user's assigned chores.
- [ ] Overdue chores are visually distinct from pending ones.
- [ ] Admin-only actions (FAB, delete) are hidden from Members.
- [ ] Pull-to-refresh triggers a fresh API call.
- [ ] Widget tests cover filter logic and role-based visibility of admin controls.

---

## TASK-020: Flutter — My Chores Screen

**Domain**: Frontend  
**Depends on**: TASK-019  
**Description**: Implement a dedicated "My Chores" tab or screen that shows only the current user's assigned chores. This is a convenience view — it reuses the same data source as TASK-019 but pre-filtered to `assignee_id = current user`.

Sort order: overdue chores first (sorted by due date ASC), then pending (sorted by due date ASC), then complete (sorted by completion date DESC).

Each chore card shows a prominent "Mark as done" button for pending and overdue chores (triggers TASK-021 flow). Completed chores show the completion date and points earned.

Show the user's total points in the current household as a summary banner at the top of the screen.

**Acceptance criteria**:
- [ ] Only chores assigned to the current user are shown.
- [ ] Overdue chores appear before pending chores.
- [ ] "Mark as done" button is visible on pending and overdue chores, not on complete ones.
- [ ] The points summary banner shows the current user's all-time points in this household.
- [ ] Completing a chore from this screen updates the list in real time (refresh or optimistic update).
- [ ] Widget tests cover sort order logic and button visibility.

---

## TASK-021: Flutter — Mark Chore Complete

**Domain**: Frontend  
**Depends on**: TASK-020, TASK-013  
**Description**: Implement the "Mark as done" interaction. This can be a button on the chore card or a confirmation dialog — use a confirmation bottom sheet to prevent accidental taps.

**Flow**:
1. User taps "Mark as done" on a chore card.
2. A confirmation bottom sheet appears showing the chore title, effort level, and points to be earned ("Complete this chore and earn 25 points?").
3. User confirms → API call `POST /households/{id}/chores/{instance_id}/complete`.
4. On success: show a brief points animation/snackbar ("You earned 25 points!"), update the chore status in the list, refresh the points summary banner.
5. On HTTP 409 (already complete): dismiss and show a snackbar "This chore was already completed."
6. On HTTP 403: show a snackbar "You are not assigned to this chore."

**Acceptance criteria**:
- [ ] Confirmation bottom sheet shows correct chore name and points to be earned.
- [ ] Successful completion shows a snackbar with the points earned.
- [ ] The chore card updates to "complete" status without requiring a full screen refresh.
- [ ] HTTP 409 and 403 errors are handled gracefully with user-facing messages.
- [ ] The points banner in the My Chores screen updates after completion.
- [ ] Widget tests cover the confirmation flow and error state rendering.

---

## TASK-022: Flutter — Leaderboard Screen

**Domain**: Frontend  
**Depends on**: TASK-018, TASK-014  
**Description**: Implement the household leaderboard screen.

Fetches `GET /households/{id}/leaderboard?scope=<scope>`. Display a ranked list of members.

UI elements:
- Scope selector at the top: three segmented tabs — "All time", "This week", "This month". Switching tabs reloads the data with the new scope parameter.
- Leaderboard entries: rank number (visually highlight rank 1, 2, 3 with gold/silver/bronze), member avatar placeholder (initials in a coloured circle for MVP), display name, points, chores completed count.
- Highlight the current user's row with a distinct background.
- Show the date range for the active scope below the tab selector (e.g. "Jun 22 – Jun 28").

**Acceptance criteria**:
- [ ] Switching between scopes reloads the leaderboard with the correct data.
- [ ] Top 3 ranks have distinct visual styling (gold/silver/bronze).
- [ ] The current user's row is visually highlighted.
- [ ] Equal-points members share the same rank number.
- [ ] Members with 0 points in scope appear in the list.
- [ ] Loading state is shown while the API call is in progress.
- [ ] Widget tests cover rank rendering, highlight logic, and scope switching.

---

## TASK-023: Flutter — Create / Edit Chore Screen (Admin Only)

**Domain**: Frontend  
**Depends on**: TASK-019, TASK-011  
**Description**: Implement the chore creation and editing form, accessible only to Admins.

**Form fields**:
- Title (text input, required)
- Description (multi-line text input, optional)
- Category (dropdown, values from the fixed list in FR-026)
- Effort level (segmented selector: Easy / Medium / Hard; display the point value next to each label)
- Chore type (radio: One-off / Recurring)
- First due date (date picker)
- Recurrence rule (shown only if type = Recurring): interval unit (Days / Weeks / Months) and N (number input, min 1)
- Assignee (optional dropdown of household members; if blank, auto-assigned)

In edit mode: pre-populate all fields from the existing definition. Show a banner "Changes apply to future instances only."

On save: call `POST /households/{id}/chores` (create) or `PATCH /households/{id}/chores/{definition_id}` (edit). On success, navigate back to the chore list and trigger a refresh.

**Acceptance criteria**:
- [ ] All required fields are validated before submission.
- [ ] Recurrence rule fields appear only when "Recurring" is selected.
- [ ] Effort level selector displays point values (Easy: 10 pts, Medium: 25 pts, Hard: 50 pts).
- [ ] Date picker enforces that the due date is not in the past.
- [ ] In create mode, submitting a valid form creates a chore and navigates back.
- [ ] In edit mode, the form is pre-populated and a "future instances only" banner is shown.
- [ ] The screen is not accessible from the navigation if the user is not an Admin.
- [ ] Widget tests cover validation logic and conditional field visibility.

---

## TASK-024: Flutter — Household Management Screen (Admin Only)

**Domain**: Frontend  
**Depends on**: TASK-018, TASK-009  
**Description**: Implement the household management screen accessible only to Admins from the household dashboard.

**Sections**:
1. **Household info**: display and edit the household name (inline edit or modal).
2. **Members list**: display all active members with their role and joined date. Each row has:
   - Role badge (Admin / Member)
   - Three-dot menu with actions: "Change to Admin / Change to Member" (toggle), "Remove from household"
   - Removing self when sole Admin shows an error dialog.
3. **Invite section**: button "Generate invite link" that calls the invite endpoint and presents the result (see TASK-025).
4. **Danger zone**: "Leave household" button with a confirmation dialog.

**Acceptance criteria**:
- [ ] Member list loads all active members with correct roles.
- [ ] Role change is reflected immediately in the list.
- [ ] Removing a member shows a confirmation dialog before calling the API.
- [ ] Attempting to remove the sole Admin shows an error dialog with a helpful message.
- [ ] Leaving the household as sole Admin shows an error dialog.
- [ ] Editing the household name persists the change via the API.
- [ ] The screen is not accessible to Members (guard in router).
- [ ] Widget tests cover list rendering and dialog logic.

---

## TASK-025: Flutter — Invite Link Share Screen

**Domain**: Frontend  
**Depends on**: TASK-024, TASK-008  
**Description**: Implement the screen or bottom sheet displayed when an Admin generates an invite link. This is triggered from the household management screen (TASK-024).

**Content**:
- The invite URL displayed as text (copyable with a tap).
- A QR code widget generated from the invite URL (use the `qr_flutter` package).
- Expiry countdown ("Expires in 47 hours").
- A "Share" button that invokes the platform share sheet (`share_plus` package) with the invite URL.
- A "Regenerate" button to create a new token (marks the old one as superseded — note: the backend currently marks tokens as used only on acceptance, so regeneration just creates a new token; document this gap for OQ-001 resolution).

**Acceptance criteria**:
- [ ] QR code is rendered and encodes the correct invite URL.
- [ ] Invite URL can be copied to clipboard with a single tap.
- [ ] Share button opens the native Android share sheet with the invite URL as text.
- [ ] Expiry time is displayed and computed correctly from `expires_at`.
- [ ] Regenerate creates a new token and updates the displayed QR code and URL.
- [ ] Widget tests verify QR code data encoding and expiry display.

---

## TASK-026: Backend — Integration Test Suite

**Domain**: Backend  
**Depends on**: TASK-015 (all backend tasks)  
**Description**: Implement an end-to-end integration test suite that exercises the full backend API using a real test database (PostgreSQL, spun up via Docker Compose or testcontainers). Tests use `httpx.AsyncClient` with the FastAPI `ASGITransport`.

Cover the following critical flows as integration tests:
1. Register → login → create household → generate invite → second user joins.
2. Admin creates recurring chore → scheduler runs → instance is generated and auto-assigned.
3. Member marks chore complete → points are awarded → leaderboard reflects the change.
4. Admin removes member → pending chores are redistributed → rotation pointer is correct.
5. Concurrent chore completion attempts result in exactly one success.

Also verify: a Member cannot create chores (403), a non-member cannot read household data (403).

**Acceptance criteria**:
- [ ] All five flows pass as integration tests against a real PostgreSQL instance.
- [ ] Tests run in CI (GitHub Actions workflow file provided) with a PostgreSQL service container.
- [ ] Overall backend line coverage is >= 80% as reported by `pytest-cov`.
- [ ] Auth, assignment engine, and completion endpoint are at 100% line coverage.
- [ ] Tests clean up after themselves (each test uses a transaction that is rolled back, or a fresh schema).

---

## TASK-027: DevOps — Docker Compose for Local Development

**Domain**: DevOps  
**Depends on**: TASK-001  
**Description**: Create a `docker-compose.yml` at the repo root that starts the full local development environment:

Services:
- `db`: PostgreSQL 16. Exposes port 5432. Persists data in a named volume.
- `api`: FastAPI backend. Mounts the `backend/` source directory as a volume for hot-reload. Runs `uvicorn main:app --reload`. Depends on `db`. Exposes port 8000.
- (Optional for MVP) `scheduler`: same image as `api` but runs the background scheduler as a standalone process.

Include a `backend/.env.example` file listing all required environment variables with placeholder values and comments.

Include a `Makefile` (or `justfile`) with common commands: `make up`, `make down`, `make migrate`, `make test`.

**Acceptance criteria**:
- [ ] `docker compose up` starts all services without manual steps.
- [ ] `make migrate` runs `alembic upgrade head` inside the `api` container successfully.
- [ ] `make test` runs the full backend test suite inside the container.
- [ ] `backend/.env.example` documents every required environment variable.
- [ ] Source code changes to the backend are reflected immediately without restarting the container.

---

## Dependency Graph Summary

```
TASK-001 (Scaffold)
  └─ TASK-002 (DB Setup)
       └─ TASK-003 (Schema + Migration)
            ├─ TASK-004 (Auth Endpoints)
            │    └─ TASK-005 (JWT Middleware)
            │         ├─ TASK-006 (User Profile)
            │         └─ TASK-007 (Household CRUD)
            │              ├─ TASK-008 (Invite Flow)
            │              │    └─ TASK-009 (Member Mgmt)
            │              │         └─ TASK-015 (Redistribution)
            │              └─ TASK-010 (Assignment Engine)
            │                   └─ TASK-011 (Chore CRUD)
            │                        ├─ TASK-012 (Scheduler)
            │                        └─ TASK-013 (Completion + Points)
            │                             └─ TASK-014 (Leaderboard)
            └─ TASK-026 (Integration Tests) [depends on all backend tasks]

TASK-016 (Flutter Scaffold)
  └─ TASK-017 (Auth Screens)
       └─ TASK-018 (Household Dashboard)
            ├─ TASK-019 (Chore List)
            │    ├─ TASK-020 (My Chores)
            │    │    └─ TASK-021 (Mark Complete)
            │    └─ TASK-023 (Create/Edit Chore)
            ├─ TASK-022 (Leaderboard)
            └─ TASK-024 (Household Management)
                 └─ TASK-025 (Invite Share Screen)

TASK-001 └─ TASK-027 (Docker Compose)
```
