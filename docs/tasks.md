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

## TASK-028: Backend — Security: Purge Committed Credentials

**Domain**: Backend / DevOps  
**Priority**: CRITICAL — do before any deployment  
**Depends on**: none  
**Source**: `docs/backend-report.md` SEC-001, SEC-002

`backend/.env` is committed to git (it is absent from `.gitignore`) and contains a live `DATABASE_URL` and a `JWT_SECRET`. `docker-compose.yml` also hardcodes credentials inline. Both secrets are low-entropy human-readable strings.

**Steps**:
1. Add `.env` to `backend/.gitignore`.
2. Use BFG Repo-Cleaner or `git filter-branch` to remove `.env` from the full git history.
3. Rotate the PostgreSQL password and generate a new `JWT_SECRET` with `python -c "import secrets; print(secrets.token_hex(32))"`.
4. Replace inline secrets in `docker-compose.yml` with `env_file: ./backend/.env` so no credentials live in a tracked file.
5. Add a startup validation in `app/core/config.py` that raises on startup if `JWT_SECRET` is shorter than 32 characters or matches any known placeholder string.
6. Add `trufflehog` or `git-secrets` as a pre-commit hook or CI step to block future leaks.

**Acceptance criteria**:
- [ ] `.env` is excluded from git and absent from git history.
- [ ] `docker-compose.yml` contains no hardcoded passwords or secrets.
- [ ] App startup fails fast with a clear error if `JWT_SECRET` does not meet minimum entropy requirements.
- [ ] CI pipeline rejects commits containing known secret patterns.

---

## TASK-029: Backend — Security: Fix IDOR on Chore Read Endpoints

**Domain**: Backend  
**Priority**: CRITICAL — do before any deployment  
**Depends on**: TASK-011, TASK-005  
**Source**: `docs/backend-report.md` SEC-003

`GET /households/{household_id}/chores` (`chores.py:164`) and `GET /households/{household_id}/chores/{instance_id}` (`chores.py:203`) use `Depends(get_current_user)` instead of `Depends(require_household_member)`. Any authenticated user who knows a household UUID can enumerate all its chore instances and assignees, regardless of membership.

All write endpoints on the same router already use the correct dependency. This is an inconsistency introduced during implementation.

**Steps**:
1. In `app/api/chores.py`, replace the `_current_user: User = Depends(get_current_user)` parameter in `list_chores` and `get_chore_instance` with `_membership: HouseholdMembership = Depends(require_household_member)`.
2. Add a test case in `tests/test_chores.py` that asserts a non-member receives HTTP 403 when calling both read endpoints.

**Acceptance criteria**:
- [ ] `GET /households/{id}/chores` returns HTTP 403 for an authenticated user who is not a member of that household.
- [ ] `GET /households/{id}/chores/{instance_id}` returns HTTP 403 for a non-member.
- [ ] Existing tests for members continue to pass.
- [ ] New non-member test cases are added and pass.

---

## TASK-030: Backend — Fix Recurrence Rule Key Mismatch

**Domain**: Backend  
**Priority**: High — breaks recurring chore creation  
**Depends on**: TASK-012  
**Source**: `docs/backend-report.md` (implementation completeness section)

`RecurrenceRule` in `app/schemas/chore.py` defines `interval_unit` and `interval_n` as required fields. Several tests (including `test_integration.py:318` and `test_chores.py`) send `unit` and `interval` instead. In Pydantic v2 with default `extra="ignore"`, the correct fields are treated as missing and the request returns HTTP 422. The scheduler also silently falls back to defaults when the stored JSONB does not contain the expected keys.

**Steps**:
1. Decide on canonical field names. The schema (`interval_unit`, `interval_n`) should be the source of truth.
2. Update all test payloads that use `unit`/`interval` to use `interval_unit`/`interval_n`.
3. Optionally add Pydantic `Field(alias=...)` or a `model_validator` to accept both forms and raise a deprecation warning — only if a migration path is needed.
4. Verify the scheduler's `_compute_due_dates` reads `interval_unit` and `interval_n` from the JSONB (it does — confirm the keys match).
5. Run the full test suite and confirm `test_integration.py` passes.

**Acceptance criteria**:
- [ ] `POST /households/{id}/chores` with `chore_type: recurring` and a valid `recurrence_rule` returns HTTP 201.
- [ ] The integration test that creates a recurring chore and runs the scheduler passes end-to-end.
- [ ] No test sends `unit` or `interval` as recurrence rule keys.

---

## TASK-031: Backend — Add Rate Limiting on Auth Endpoints

**Domain**: Backend  
**Priority**: High  
**Depends on**: TASK-004  
**Source**: `docs/backend-report.md` SEC-004

`POST /auth/login` and `POST /auth/register` are open to unlimited requests, enabling brute-force and credential-stuffing attacks. bcrypt's cost factor slows individual attempts but does not substitute for per-IP rate limits.

**Steps**:
1. Add `slowapi` to `pyproject.toml` dependencies.
2. Initialise a `Limiter` keyed on `get_remote_address` in `main.py` and attach it to `app.state`.
3. Add the `SlowAPIMiddleware` to the app.
4. Apply a limit of `5/minute` to `POST /auth/login` per IP.
5. Apply a limit of `10/hour` to `POST /auth/register` per IP.
6. Return HTTP 429 with a `Retry-After` header when the limit is exceeded.
7. Add a test that verifies the 429 response is returned after the limit threshold.

**Acceptance criteria**:
- [ ] More than 5 login attempts per minute from the same IP returns HTTP 429.
- [ ] More than 10 register attempts per hour from the same IP returns HTTP 429.
- [ ] Requests below the limit continue to work correctly.
- [ ] `Retry-After` header is present on 429 responses.

---

## TASK-032: Backend — Harden Dockerfile

**Domain**: DevOps  
**Priority**: High  
**Depends on**: TASK-027  
**Source**: `docs/backend-report.md` SEC-005, deployment readiness section

The `backend/Dockerfile` runs the uvicorn process as root (no `USER` directive), has no `HEALTHCHECK` instruction, and installs test dependencies in the production image because they are in `[project]` rather than an optional group.

**Steps**:
1. Move `pytest`, `pytest-asyncio`, `pytest-cov`, and `httpx` from `[project]` to `[project.optional-dependencies]` under a `test` group in `pyproject.toml`.
2. Rewrite the Dockerfile to use a multi-stage build:
   - Stage 1 (`builder`): install dependencies with `uv sync --frozen --no-dev`.
   - Stage 2 (`runtime`): copy only the venv and source; create a non-root system user; switch to that user before the `CMD`.
3. Add a `HEALTHCHECK` instruction that calls `GET /health`.
4. Set `PYTHONDONTWRITEBYTECODE=1` and `PYTHONUNBUFFERED=1`.
5. Update `docker-compose.yml` to use separate `command` overrides for dev (with `--reload`) vs. production, and remove `--reload` from the default `CMD`.
6. Add `--proxy-headers` to the uvicorn `CMD` for correct client IP forwarding behind a reverse proxy.

**Acceptance criteria**:
- [ ] `docker build` produces an image where `whoami` inside the container returns a non-root user.
- [ ] The built image does not contain `pytest` or `httpx` (verify with `pip show pytest` inside the container).
- [ ] `docker inspect` shows a `HEALTHCHECK` defined.
- [ ] `uv sync --no-dev` does not install test packages.

---

## TASK-033: Backend — JWT Revocation and Logout Endpoint

**Domain**: Backend  
**Priority**: High  
**Depends on**: TASK-005  
**Source**: `docs/backend-report.md` SEC-006

JWTs are currently valid for 7 days with no revocation mechanism. There is no logout endpoint. A stolen token cannot be invalidated.

**Steps**:
1. Add a `jti` (UUID) claim to every JWT issued in `app/core/security.py:create_access_token`.
2. Add a token blocklist backed by a simple database table (or Redis if available). For the MVP, a `RevokedToken` SQLAlchemy model with columns `jti (PK)`, `revoked_at`, `expires_at` is sufficient.
3. In `get_current_user` (`app/api/deps.py`), after decoding the JWT, check whether the `jti` exists in the blocklist. If it does, raise HTTP 401.
4. Add `POST /auth/logout` that reads the current bearer token's `jti` and inserts it into the blocklist.
5. Add a background cleanup job (or a lazy cleanup on each login) that removes expired entries from the blocklist table.
6. Reduce `JWT_EXPIRY_DAYS` default to `1` and document a `REFRESH_TOKEN_TTL_DAYS` env var for the future refresh-token flow.

**Acceptance criteria**:
- [ ] `POST /auth/logout` with a valid token returns HTTP 200 and the token is added to the blocklist.
- [ ] Subsequent requests using the logged-out token return HTTP 401.
- [ ] Tokens not in the blocklist continue to work normally.
- [ ] The blocklist cleanup removes entries whose `expires_at` is in the past.

---

## TASK-034: Backend — Fix Enum Validation in Chore Schemas

**Domain**: Backend  
**Priority**: High  
**Depends on**: TASK-011  
**Source**: `docs/backend-report.md` SEC-007, type safety section

`category`, `effort_level`, `chore_type`, and `interval_unit` are plain `str` in `app/schemas/chore.py`. Invalid values pass Pydantic validation, reach the database, and cause a PostgreSQL constraint error that surfaces as HTTP 500 instead of a clean HTTP 422.

**Steps**:
1. Define `Literal` types (or `StrEnum`) for each field in `app/schemas/chore.py`:
   - `category`: all values from `app/core/constants.py` (or define them there and import).
   - `effort_level`: `Literal["easy", "medium", "hard"]`.
   - `chore_type`: `Literal["one_off", "recurring"]`.
   - `RecurrenceRule.interval_unit`: `Literal["days", "weeks", "months"]`.
2. Add `le=365` upper bound to `RecurrenceRule.interval_n`.
3. Add `max_length=72` and a complexity `@field_validator` to `RegisterRequest.password` in `app/schemas/auth.py` (72 is bcrypt's effective truncation limit).
4. Add `max_length=100` to `UpdateProfileRequest.display_name` in `app/api/users.py`.
5. Add a global `IntegrityError` / `UniqueViolationError` exception handler in `main.py` to convert any remaining DB constraint errors to HTTP 409 instead of 500.
6. Add tests for each invalid-value case to confirm HTTP 422 is returned.

**Acceptance criteria**:
- [ ] `POST /chores` with `effort_level: "extreme"` returns HTTP 422, not 500.
- [ ] `POST /chores` with `interval_unit: "fortnights"` returns HTTP 422.
- [ ] `POST /auth/register` with a 200-character password returns HTTP 422.
- [ ] `PATCH /users/me` with a 200-character display name returns HTTP 422.
- [ ] A database `UniqueViolationError` that is not caught by business logic returns HTTP 409.

---

## TASK-035: Backend — Deep Health Check and API Docs Access Control

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-001, TASK-002  
**Source**: `docs/backend-report.md` deployment readiness, SEC-009

`GET /health` returns `{"status": "ok"}` without probing the database. Kubernetes readiness probes cannot distinguish a healthy pod from one with a broken DB connection. Additionally, `/docs`, `/redoc`, and `/openapi.json` are exposed unconditionally in all environments, disclosing the full API surface to unauthenticated users in production.

**Steps**:
1. Update `app/api/health.py` to execute `SELECT 1` against the database. Return HTTP 200 on success and HTTP 503 if the database is unreachable.
2. Add `DEBUG: bool = False` to `app/core/config.py` `Settings`.
3. In `main.py`, conditionally set `docs_url`, `redoc_url`, and `openapi_url` to `None` when `settings.DEBUG` is `False`.
4. Update `backend/.env.example` to document `DEBUG=true` for local development.
5. Update the `docker-compose.yml` `api` service to pass `DEBUG=true`.

**Acceptance criteria**:
- [ ] `GET /health` returns HTTP 200 and `{"status": "ok"}` when the DB is reachable.
- [ ] `GET /health` returns HTTP 503 when the DB connection fails.
- [ ] `/docs` returns HTTP 404 when `DEBUG=false`.
- [ ] `/docs` returns HTTP 200 when `DEBUG=true`.

---

## TASK-036: Backend — Consolidate Test Fixtures

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-026  
**Source**: `docs/backend-report.md` test coverage section

`_get_test_database_url()` is duplicated across 9 test files. The `async_client` fixture (engine setup, schema drop/create, override injection) is duplicated across ~8 files. This makes fixture maintenance error-prone and inflates the test suite by ~300 lines.

**Steps**:
1. Move `_get_test_database_url()` into `tests/conftest.py` (it already exists there — remove all copies from individual test files).
2. Create a single session-scoped `async_engine` fixture and a function-scoped `async_client` fixture in `conftest.py` that handles schema creation, dependency overrides, and teardown.
3. Delete all duplicate fixture definitions from `test_auth.py`, `test_chores.py`, `test_completion.py`, `test_households.py`, `test_invites.py`, `test_leaderboard.py`, `test_members.py`, `test_integration.py`, and `test_auth_middleware.py`.
4. Add `addopts = "--cov=app --cov-report=term-missing --cov-fail-under=80"` to `[tool.pytest.ini_options]` in `pyproject.toml` to enforce coverage measurement.
5. Remove the dead `_recurring_payload` fixture from `test_chores.py:205`.
6. Remove the unused `_COMPLETABLE_STATUSES` constant from `app/api/chores.py:233`.

**Acceptance criteria**:
- [ ] `_get_test_database_url()` appears only once in the codebase.
- [ ] `async_client` fixture appears only in `conftest.py`.
- [ ] Full test suite passes after the consolidation.
- [ ] `pytest --cov=app` reports coverage and fails if below 80%.
- [ ] No dead code (`_recurring_payload`, `_COMPLETABLE_STATUSES`) remains.

---

## TASK-037: Backend — Security Headers, CORS, and Minor Input Validation

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-001  
**Source**: `docs/backend-report.md` SEC-010, SEC-011, SEC-012, SEC-013, SEC-023

Several small but impactful security hardening items that do not warrant individual tasks.

**Steps**:
1. **Remove PostgreSQL port binding**: In `docker-compose.yml`, change the `db` service `ports` mapping from `"5432:5432"` to `"127.0.0.1:5432:5432"` so the database is not reachable from outside the host.
2. **Security headers middleware**: Add a `SecurityHeadersMiddleware` in `main.py` that sets `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and `Strict-Transport-Security: max-age=63072000; includeSubDomains` on every response.
3. **CORS middleware**: Add `CORSMiddleware` with `allow_origins=settings.CORS_ALLOWED_ORIGINS` (a `list[str]` env var defaulting to `[]`). Never use `allow_origins=["*"]` with `allow_credentials=True`.
4. **Invite token cap**: In `app/api/invites.py:create_invite`, before inserting a new token, expire any existing non-used, non-expired tokens for the same household by setting their `expires_at = now()`.
5. **Assignee membership check**: In `app/api/chores.py:create_chore`, when `body.assignee_id` is provided, verify the target user has an active membership in the household. Return HTTP 422 if not.
6. **Remove `rotation_pointer` from response schemas**: Remove the field from `HouseholdResponse`, `HouseholdWithRoleResponse`, and `HouseholdDetailResponse` in `app/schemas/household.py`.

**Acceptance criteria**:
- [ ] All responses include `X-Content-Type-Options` and `X-Frame-Options` headers.
- [ ] PostgreSQL is not reachable on `0.0.0.0:5432`.
- [ ] Generating a second invite invalidates the previous active token for the same household.
- [ ] Creating a chore with an `assignee_id` that is not a member of the household returns HTTP 422.
- [ ] `rotation_pointer` does not appear in any API response.
- [ ] `GET /households` and `GET /households/{id}` responses do not include `rotation_pointer`.

---

## TASK-038: Backend — JWT Token Refresh Endpoint

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-033  
**Source**: `docs/backend-report.md` missing features section

After TASK-033 reduces the access token lifetime to 1 day, clients need a way to obtain a new access token without forcing the user to log in again. This task adds a refresh token model and the corresponding endpoint.

**Steps**:
1. Add a `RefreshToken` model: `id (UUID PK)`, `user_id (FK)`, `token_hash (str)`, `created_at`, `expires_at`, `revoked_at (nullable)`.
2. On successful login (`POST /auth/login`), generate and store a refresh token (long-lived, default 30 days via `REFRESH_TOKEN_TTL_DAYS` env var). Return it in the login response as `refresh_token`.
3. Add `POST /auth/refresh` that accepts `{ "refresh_token": str }`, validates the token (exists, not expired, not revoked), issues a new access token, and rotates the refresh token (marks old as revoked, issues a new one).
4. On logout (`POST /auth/logout` from TASK-033), also revoke the refresh token associated with the session.

**Acceptance criteria**:
- [ ] Successful login returns both `access_token` and `refresh_token`.
- [ ] `POST /auth/refresh` with a valid refresh token returns a new `access_token` and a new `refresh_token`.
- [ ] Using a revoked or expired refresh token returns HTTP 401.
- [ ] Logout revokes both access token (blocklist) and refresh token.

---

## TASK-039: Backend — Chore Reassignment and Pagination

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-011, TASK-010  
**Source**: `docs/backend-report.md` missing features section

Two feature gaps on the chore endpoints: there is no way to manually reassign a chore, and `GET /chores` returns an unbounded result set with no pagination.

**Steps**:
1. **Reassignment endpoint**: Add `PATCH /households/{household_id}/chores/{instance_id}/assignee` (Admin only). Body: `{ "assignee_id": uuid | null }`. If `assignee_id` is provided, validate that the user is an active household member. Update `ChoreInstance.assignee_id` and set `assigned_manually = True`. If `null`, call `auto_assign()` and set `assigned_manually = False`.
2. **Pagination**: Add `limit: int = Query(50, ge=1, le=200)` and `offset: int = Query(0, ge=0)` parameters to `GET /households/{household_id}/chores`. Apply `.limit(limit).offset(offset)` to the query and return a response envelope `{ "items": [...], "total": int, "limit": int, "offset": int }`.
3. Update `ChoreListResponse` schema to match the paginated envelope.
4. Update Flutter API client (or document the breaking change) if the app is already consuming this endpoint.

**Acceptance criteria**:
- [ ] `PATCH /chores/{instance_id}/assignee` with a valid member ID updates the assignee and returns the updated instance.
- [ ] `PATCH /chores/{instance_id}/assignee` with a non-member ID returns HTTP 422.
- [ ] `GET /chores?limit=10&offset=0` returns at most 10 results and a `total` count.
- [ ] A Member (non-Admin) calling the reassign endpoint receives HTTP 403.

---

## TASK-040: Backend — Invite Management Endpoints

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-008  
**Source**: `docs/backend-report.md` missing features section

There is no way for admins to list or revoke active invite tokens for their household.

**Steps**:
1. Add `GET /households/{household_id}/invites` (Admin only) — returns all non-expired, non-used tokens for the household: `[ { "token": str, "created_at": datetime, "expires_at": datetime } ]`. Do not return the raw token — return only the first 8 characters and replace the rest with `***` for display, plus the `id`.
2. Add `DELETE /households/{household_id}/invites/{invite_id}` (Admin only) — sets `expires_at = now()` on the token, effectively revoking it. Returns HTTP 204.
3. Accepting a revoked token (one whose `expires_at` is in the past) already returns HTTP 410 via existing logic — confirm this is covered.

**Acceptance criteria**:
- [ ] `GET /invites` returns only active (non-expired, non-used) tokens.
- [ ] `DELETE /invites/{id}` marks the token as expired and subsequent accept attempts return HTTP 410.
- [ ] A Member (non-Admin) receives HTTP 403 for both endpoints.
- [ ] Tests cover both endpoints and the accept-after-revoke flow.

---

## TASK-041: Backend — Fix Performance: N+1 Queries

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-012, TASK-015  
**Source**: `docs/backend-report.md` maintainability section

Two N+1 query patterns exist that will degrade performance at scale.

**Steps**:
1. **Scheduler (`app/tasks/scheduler.py`)**: Replace the per-definition `SELECT due_date WHERE definition_id = ?` loop with a single query that fetches all `(definition_id, due_date)` pairs for all active definitions in one round-trip. Build a `set[tuple[UUID, date]]` of existing pairs and check membership in Python.
2. **Redistribution (`app/services/redistribution.py`)**: Replace the per-chore `SELECT FOR UPDATE` on the household row (one lock acquisition per chore) with a single `SELECT FOR UPDATE` at the start of the redistribution loop. Fetch active members once. Cycle through members in Python. Issue a single `UPDATE households SET rotation_pointer = ?` at the end.
3. Add a missing index on `ChoreInstance.due_date` and on `ChoreInstance.definition_id` via a new Alembic migration (these columns are queried frequently but have no index).
4. Add a `UniqueConstraint("chore_instance_id")` on `PointLedger` via the same migration to prevent double-ledger entries at the database level.

**Acceptance criteria**:
- [ ] The scheduler generates instances for N definitions in exactly 2 database round-trips (one for definitions, one for existing pairs), not N+2.
- [ ] Redistribution of M chores against a household acquires the `FOR UPDATE` lock exactly once.
- [ ] Alembic migration adds the two missing indexes and the `PointLedger` unique constraint.
- [ ] All scheduler and redistribution tests continue to pass.

---

## TASK-042: Backend — Replace Unmaintained Dependencies

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-001  
**Source**: `docs/backend-report.md` maintainability section (F-M2, F-M3)

`passlib` (last release 2022) and `python-jose` (last release 2022, known CVEs) are unmaintained. The `bcrypt<4.0.0` version cap blocks security patches.

**Steps**:
1. Replace `passlib[bcrypt]` with direct `bcrypt>=4.0.0` usage in `app/core/security.py`:
   ```python
   import bcrypt
   def hash_password(plain: str) -> str:
       return bcrypt.hashpw(plain.encode(), bcrypt.gensalt(rounds=12)).decode()
   def verify_password(plain: str, hashed: str) -> bool:
       return bcrypt.checkpw(plain.encode(), hashed.encode())
   ```
2. Replace `python-jose[cryptography]` with `PyJWT[crypto]` in `pyproject.toml` and update `app/core/security.py` to use `jwt.encode` / `jwt.decode` from the `PyJWT` API (the call signatures differ slightly).
3. Remove `passlib`, `python-jose`, and the `bcrypt<4.0.0` pin from `pyproject.toml`. Add `bcrypt>=4.0.0` and `PyJWT[crypto]`.
4. Run `uv lock` to regenerate `uv.lock`.
5. Run the full test suite to confirm no regressions.

**Acceptance criteria**:
- [ ] `passlib` and `python-jose` are absent from `pyproject.toml` and `uv.lock`.
- [ ] `bcrypt>=4.0.0` and `PyJWT` are present.
- [ ] Login, register, and JWT middleware tests all pass.
- [ ] `pip show passlib python-jose` inside the Docker image returns "not found".

---

## TASK-043: Backend — Fix Scheduler Timezone and Structured Logging

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-012  
**Source**: `docs/backend-report.md` SEC-016, F-M4

Two maintenance issues in `app/tasks/scheduler.py`: the `_today()` helper uses local time (`date.today()`) while APScheduler runs in UTC, causing off-by-one errors near midnight in non-UTC server timezones. Additionally, route handlers emit no log output, making incident investigation difficult.

**Steps**:
1. **Timezone fix**: In `app/tasks/scheduler.py:37`, replace `return date.today()` with `return datetime.now(timezone.utc).date()`.
2. **Structured logging**: Add `structlog` to `pyproject.toml`. Configure it in `main.py` with a JSON renderer in production and a console renderer in development (`DEBUG=true`). Each log entry should include `request_id`, `user_id` (if available), and `household_id` (if available) via context variables or middleware.
3. **Request ID middleware**: Add a middleware that generates a `request_id` (UUID) per request, attaches it to the structlog context, and returns it in the response as `X-Request-ID`.
4. **Audit log entries**: Add `logger.info` calls for: successful login, failed login (with masked email), member removed, role changed, chore completed, member joined via invite.

**Acceptance criteria**:
- [ ] `_today()` returns UTC date regardless of server timezone.
- [ ] Scheduler tests that monkeypatch `_today()` continue to pass.
- [ ] Log output in production is valid JSON with `request_id`, `level`, `timestamp`, and `event` fields.
- [ ] Failed login attempts are logged with the email (masked, e.g. `a***@example.com`).
- [ ] `X-Request-ID` header is present in all responses.

---

## TASK-044: Backend — Scheduler Multi-Worker Safety

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-012  
**Source**: `docs/backend-report.md` deployment readiness section

`AsyncIOScheduler` runs inside the uvicorn process. With multiple workers or container replicas, every worker runs its own scheduler copy, and the daily job fires N times. While `generate_chore_instances` is idempotent, the rotation pointer is advanced N times and audit logs are duplicated.

**Steps**:
1. Add a PostgreSQL advisory lock inside `run_daily_job` in `app/tasks/scheduler.py` using `pg_try_advisory_xact_lock`. If the lock is not acquired, log "skipping — another worker holds the lock" and return immediately.
   ```python
   result = await session.execute(text("SELECT pg_try_advisory_xact_lock(:id)"), {"id": 99_001})
   if not result.scalar():
       logger.info("daily_job.skipped", reason="lock_held_by_another_worker")
       return
   ```
2. Document in `README` / deployment notes that the lock is PostgreSQL-specific and will not work if the scheduler is ever moved to a different backend.
3. Add an integration test that runs two scheduler invocations concurrently and asserts that chore instances are created exactly once.

**Acceptance criteria**:
- [ ] Running the scheduler job concurrently from two workers produces exactly one set of chore instances, not two.
- [ ] The second worker logs a "skipped" message and exits without error.
- [ ] Existing scheduler tests are unaffected.

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
