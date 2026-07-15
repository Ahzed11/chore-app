# Implementation Task List — Household Chores Motivation App

**Version**: 1.0  
**Date**: 2026-06-25  
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by reading only this task description plus the referenced requirements sections. Dependency chains are explicit.

---

## Status Ledger (updated 2026-07-15)

| Range | Status |
|---|---|
| TASK-001 … TASK-027 | ✅ Done (initial MVP build-out) |
| TASK-028 … TASK-030 | ✅ Done (credential purge, IDOR fix, recurrence keys) |
| TASK-031 | ❌ **Open — never implemented.** No rate limiting exists in the codebase (no `slowapi`, no limiter middleware). Still required before internet exposure. |
| TASK-032 … TASK-044 | ✅ Done (Dockerfile hardening, logout/revocation, enum validation, health probe, fixtures, headers/CORS, refresh endpoint, reassignment+pagination, invite mgmt, N+1, deps, scheduler UTC/lock). ⚠️ **TASK-042 introduced a regression that breaks every login** — fix is TASK-068, do it first. |
| TASK-045 … TASK-051 | ✅ Done, with follow-up defects — see TASK-054+ (notably: TASK-047's logout call is defeated by a caller bug; TASK-050 missed the refresh Dio; TASK-051 only fixed the banner) |
| TASK-052, TASK-053 | ❌ **Open — not implemented** (reassignment UI, invite management UI) |
| TASK-054 … TASK-067 | ⏳ Open — Flutter tasks from the 2026-07-15 re-review (`docs/frontend-report.md`) |
| TASK-068 | ✅ Done 2026-07-15 — login fixed (`expires_delta` restored on `create_access_token`), stale integration test fixed; 137/137 tests pass. Coverage gate (68% vs 75%) remains → TASK-069. |
| TASK-069 … TASK-081 | ⏳ Open — Backend/DevOps tasks from the 2026-07-15 re-review (`docs/backend-report.md`). **Start with TASK-069 (CI on all branches + coverage gate).** |

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

## TASK-045: Flutter — Fix Paginated Chores Response (Breaking)

**Domain**: Flutter  
**Priority**: Critical  
**Depends on**: TASK-039 (backend pagination)  
**Source**: `docs/frontend-report.md` §1, §4

`chores_provider.dart:84` calls `dio.get<List<dynamic>>()` and then casts `response.data` directly to a list. After TASK-039, the backend returns `{"items": [...], "total": N, "limit": 50, "offset": 0}`. The cast will throw a `TypeError` at runtime and the chores screen will be stuck in an error state.

**Steps**:
1. Change the Dio call to `get<Map<String, dynamic>>()` in `_fetchChores`.
2. Extract `response.data!['items'] as List<dynamic>` and map to `ChoreModel` objects.
3. The `total`, `limit`, and `offset` fields are available if pagination UI is ever added; ignore them for now (the backend defaults `limit=50` which covers all typical household sizes).
4. Run `flutter test` to verify `chore_list_screen_test.dart` still passes (the fake notifier returns the list directly so tests are unaffected).

**Acceptance criteria**:
- [ ] Chores screen loads correctly against the updated backend without runtime errors.
- [ ] Existing widget tests are green.
- [ ] Response envelope fields `total`, `limit`, `offset` are not silently discarded in a way that would break incremental pagination later (e.g., leave room to extend `_fetchChores` to accept a `limit`/`offset` param).

---

## TASK-046: Flutter — Implement Refresh Token Flow

**Domain**: Flutter  
**Priority**: High  
**Depends on**: TASK-033 (backend logout/refresh endpoints), TASK-038 (backend refresh endpoint)  
**Source**: `docs/frontend-report.md` §1, §2

The backend `POST /auth/login` response includes `refresh_token`, but `auth_provider.dart` only saves `access_token` to secure storage. When the access token expires, the user is silently logged out with no opportunity to refresh. The auth interceptor in `api_client.dart` calls `clearOnUnauthorized()` on any 401 instead of attempting a refresh first.

**Steps**:
1. Add `authRefresh` and `authLogout` constants to `api_endpoints.dart`.
2. In `auth_state.dart`, extend `AuthStorage` to also store and retrieve `refresh_token` alongside `auth_token` (add a second key `refresh_token`).
3. Extend `AuthNotifier` with a `refresh()` method that:
   - Reads the stored refresh token.
   - Calls `POST /auth/refresh` with `{"refresh_token": "..."}`.
   - On success: saves the new `access_token` and `refresh_token`, updates `state`.
   - On 401/error: calls `clearOnUnauthorized()` (forces re-login).
4. Update `auth_provider.dart` (`AuthFormNotifier.login`) to save the `refresh_token` from the login response.
5. Update the Dio error interceptor in `api_client.dart` to:
   - On 401: call `authNotifier.refresh()`.
   - If refresh succeeds: retry the original request with the new token.
   - If refresh fails: call `clearOnUnauthorized()`.
   - Guard against infinite loops with a "already retrying" flag.
6. Add widget/integration tests covering: expired access token → refresh succeeds → request retried; expired access token → refresh fails → user logged out.

**Acceptance criteria**:
- [ ] Login response `refresh_token` is persisted to secure storage.
- [ ] A 401 response triggers a refresh attempt before logging the user out.
- [ ] Successful refresh causes the original request to be retried transparently.
- [ ] Failed refresh causes `clearOnUnauthorized()` and navigation to login.
- [ ] Refresh token is cleared from storage on logout.

---

## TASK-047: Flutter — Call POST /auth/logout on Logout

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: TASK-033 (backend logout endpoint), TASK-046  
**Source**: `docs/frontend-report.md` §1, §4

`AuthNotifier.logout()` in `auth_state.dart` currently only clears local secure storage. The backend's JWT blocklist (`RevokedToken` table) is never populated from the client, so the old access token remains valid on the server until its natural expiry.

**Steps**:
1. Add `ApiEndpoints.authLogout` constant (shared with TASK-046).
2. In `AuthNotifier.logout()`, call `POST /auth/logout` with the current access token in the `Authorization: Bearer` header before clearing local storage.
3. Also send the stored `refresh_token` in the request body so the backend can revoke it as well.
4. Swallow network errors silently — if the server is unreachable, local logout should still complete.
5. Clear both `auth_token` and `refresh_token` from secure storage after the API call (or on error).

**Acceptance criteria**:
- [ ] Logout calls `POST /auth/logout` before clearing tokens.
- [ ] Network errors during logout do not block the local logout.
- [ ] After logout, `GET /users/me` with the old token returns 401.
- [ ] Refresh token is also cleared.

---

## TASK-048: Flutter — Fix Stale Widget Test Assertions in chore_list_screen_test.dart

**Domain**: Flutter  
**Priority**: High  
**Source**: `docs/frontend-report.md` §3

`test/features/chores/chore_list_screen_test.dart` references widget keys, widget types, and text strings that no longer match the actual `ChoreListScreen` implementation. These tests will fail. The screen uses plain `GestureDetector` text tabs (not `FilterChip` widgets), and the empty state text differs from what the tests expect.

**Stale assertions to fix**:
- Line 225: `find.byKey(Key('overdue_warning_icon'))` — `_StatusCircle` has no key on its `Icon`. Add `key: const Key('overdue_warning_icon')` to the `Icon(Icons.priority_high, ...)` in `chore_card.dart`.
- Lines 253–259: `find.byKey(Key('status_chip_All'))` etc. — The screen uses `GestureDetector` text tabs, not `FilterChip`. Either:
  - Add `Key('filter_tab_all')`, `Key('filter_tab_pending')`, etc. to the `GestureDetector` containers in `_ChoreFilterTabs`, **or**
  - Rewrite tests to `find.text('All')`, `find.text('Pending')` etc.
- Line 269: `tester.widget<FilterChip>(...)` — Replace with the actual widget type used in the tab.
- Line 295: `find.byKey(Key('my_chores_chip'))` — "My Chores" is a bottom nav item, not a chip. Remove or replace with `find.text('My Chores')`.
- Line 395: `find.text('No chores found')` — Actual text is `'All clear!'`. Update assertion.
- Line 424: `find.text('Something went wrong')` — Verify the actual `AppErrorWidget` text and update.

**Acceptance criteria**:
- [ ] `flutter test test/features/chores/chore_list_screen_test.dart` passes with zero failures.
- [ ] No test assertions are removed without a replacement — coverage must not decrease.

---

## TASK-049: Flutter — Add Missing ApiEndpoints Constants

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: none (pure refactor enabling other tasks)  
**Source**: `docs/frontend-report.md` §4

`api_endpoints.dart` is missing constants for endpoints that exist in the backend but are not yet called from Flutter. Adding them now prevents future hardcoded URL strings.

**Add the following static methods/constants**:
```dart
static String authLogout() => '/auth/logout';
static String authRefresh() => '/auth/refresh';
static String householdInvites(String householdId) =>
    '/households/$householdId/invites';
static String revokeInvite(String householdId, String inviteId) =>
    '/households/$householdId/invites/$inviteId';
static String choreAssignee(String householdId, String instanceId) =>
    '/households/$householdId/chores/$instanceId/assignee';
```

Also fix the existing hardcoded URL in `chores_provider.dart:182`:
```dart
// Before
await dio.delete<void>('/households/$householdId/chores/$definitionId');
// After
await dio.delete<void>(ApiEndpoints.choreDefinition(householdId, definitionId));
```

**Acceptance criteria**:
- [ ] All five endpoint strings are added as named methods on `ApiEndpoints`.
- [ ] `deleteChore` uses `ApiEndpoints.choreDefinition(...)` instead of a hardcoded string.
- [ ] Existing tests are unaffected.

---

## TASK-050: Flutter — Configure Dio Request Timeouts

**Domain**: Flutter  
**Priority**: Medium  
**Source**: `docs/frontend-report.md` §2

The `Dio` instance in `api_client.dart` is created without connection or receive timeout options. If the server is unreachable (e.g., the local backend is not running), requests will hang indefinitely and the UI will be stuck in a loading state.

**Steps**:
1. In `api_client.dart`, set `BaseOptions` when creating the Dio instance:
   ```dart
   Dio(BaseOptions(
     connectTimeout: const Duration(seconds: 10),
     receiveTimeout: const Duration(seconds: 15),
   ))
   ```
2. The timeout values should match the self-hosted nature of the app (local network, so 10s connect / 15s receive is generous).
3. Ensure error-state widgets still render correctly when a `DioExceptionType.connectionTimeout` is thrown (test with a fake server URL if needed).

**Acceptance criteria**:
- [ ] Requests time out and surface an error widget within 15 seconds when the server is unreachable.
- [ ] Existing tests that use fake notifiers are unaffected (they never reach Dio).

---

## TASK-051: Flutter — Use `pointsAwarded` for Weekly Points Calculation

**Domain**: Flutter  
**Priority**: Low  
**Source**: `docs/frontend-report.md` §1

`my_chores_screen.dart:115` computes weekly points with:
```dart
.fold(0, (sum, c) => sum + c.pointValue);
```
`pointValue` is a client-derived getter (`effortPoints[effortLevel] ?? 10`). The authoritative value is `pointsAwarded` from the server, stored as `ChoreModel.pointsAwarded`. These diverge if the backend ever awards bonus points or changes the effort-level mapping.

**Steps**:
1. In `my_chores_screen.dart`, change the fold to use `c.pointsAwarded ?? c.pointValue`.
2. This falls back to the effort-based value if `pointsAwarded` is null (e.g., for chores completed before the field was added).

**Acceptance criteria**:
- [ ] Weekly points shown in the banner use `pointsAwarded` when available.
- [ ] Falls back gracefully to `pointValue` when `pointsAwarded` is null.

---

## TASK-052: Flutter — Chore Reassignment UI (Admin)

**Domain**: Flutter  
**Priority**: Low  
**Depends on**: TASK-039 (backend reassignment endpoint), TASK-049  
**Source**: `docs/frontend-report.md` §1

The backend `PATCH /households/{id}/chores/{iid}/assignee` endpoint lets admins reassign a chore instance to any household member. There is no Flutter UI for this. The admin long-press menu on `ChoreCard` currently only has "Delete series".

**Steps**:
1. Add a `reassignChore(instanceId, assigneeId)` method to `ChoresNotifier` that calls `PATCH` on `ApiEndpoints.choreAssignee(householdId, instanceId)`.
2. In `ChoreCard._showAdminMenu`, add a second `ListTile` — "Reassign chore" — that opens a bottom sheet with a list of household members to choose from.
3. The member list can be passed as a parameter to `ChoreCard` (already available from the parent screen via `membersNotifierProvider`).
4. On selection, call `notifier.reassignChore(chore.id, selectedMemberId)`.
5. Show a `SnackBar` on success or failure.

**Acceptance criteria**:
- [ ] Admin long-press on a pending chore shows "Reassign chore" in the action sheet.
- [ ] Selecting a member sends `PATCH /households/{id}/chores/{iid}/assignee` with `{"assignee_id": "..."}`.
- [ ] The chore card updates to show the new assignee name after reassignment.
- [ ] Non-admin users do not see the reassign option.

---

## TASK-053: Flutter — Invite Management in Household Management Screen

**Domain**: Flutter  
**Priority**: Low  
**Depends on**: TASK-040 (backend invite management endpoints), TASK-049  
**Source**: `docs/frontend-report.md` §1

The backend now supports listing active invite tokens (`GET /households/{id}/invites`) and revoking them (`DELETE /households/{id}/invites/{inviteId}`). The household management screen (`household_management_screen.dart`) shows a QR code and share button for the active invite, but does not show previously generated tokens or allow revocation.

**Steps**:
1. Create an `invitesProvider` (FutureProvider.family keyed by householdId) that calls `GET /households/{id}/invites` and returns `List<InviteTokenResponse>`.
2. In the invite accordion section of `HouseholdManagementScreen`, below the current QR code, display a list of active invite tokens (masked preview from `token_preview`).
3. Add a delete icon next to each token that calls `DELETE /households/{id}/invites/{inviteId}` and refreshes the invite list.
4. Show an empty state ("No active invites") if the list is empty.

**Acceptance criteria**:
- [ ] Admin can see a list of active invite tokens with masked previews.
- [ ] Admin can revoke any invite token.
- [ ] List refreshes after revocation.
- [ ] Non-admin members do not see this section.

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

## TASK-054: Flutter — Fix Release Android Config: INTERNET Permission and Cleartext Traffic

**Domain**: Flutter  
**Priority**: CRITICAL — release APK is non-functional without this  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-3

Only `android/app/src/debug/AndroidManifest.xml` and `src/profile/AndroidManifest.xml` declare `android.permission.INTERNET`. The main manifest (`android/app/src/main/AndroidManifest.xml`) does not, so the release APK built by CI (`.github/workflows/flutter.yml`) cannot make any network request. Additionally, the default `API_BASE_URL` is plain `http://`, and Android 9+ blocks cleartext HTTP by default, so even with the permission a self-hosted LAN server over HTTP is unreachable.

**Steps**:
1. Add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml`.
2. Add a network security config (`android/app/src/main/res/xml/network_security_config.xml`) that permits cleartext traffic (self-hosted users commonly run plain HTTP on a LAN), and reference it via `android:networkSecurityConfig` on the `<application>` element. Document in a comment that HTTPS via reverse proxy is the recommended setup.
3. Verify the debug/profile manifests do not need changes (they already declare the permission).

**Acceptance criteria**:
- [ ] `flutter build apk --release` produces an APK whose merged manifest contains the INTERNET permission (verify with `aapt dump permissions` or by checking the merged manifest in `build/`).
- [ ] The release app can call an `http://` server on Android 9+.

---

## TASK-055: Flutter — Fix Logout Ordering Bug (Server-Side Revocation Never Happens)

**Domain**: Flutter  
**Priority**: CRITICAL — one-line fix  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-2

`household_dashboard_screen.dart:78-81` calls `AuthStorage.clearToken()` **before** `ref.read(authNotifierProvider.notifier).logout()`. `logout()` reads the stored token to send `POST /auth/logout`; since the token is already cleared, it reads null and skips the server call. The backend blocklist is never populated — TASK-047 is silently defeated.

**Steps**:
1. In `_logout` in `household_dashboard_screen.dart`, remove the `await AuthStorage.clearToken();` line. `AuthNotifier.logout()` already clears both tokens after calling the server.
2. Add a widget/unit test asserting that tapping logout results in a `POST /auth/logout` request (mock Dio adapter) before local tokens are cleared.

**Acceptance criteria**:
- [ ] After logout, the old access token is rejected by the backend (401 from `GET /users/me`).
- [ ] A test covers the logout → server-call ordering.

---

## TASK-056: Flutter — Harden the Token Refresh Interceptor

**Domain**: Flutter  
**Priority**: High  
**Depends on**: TASK-046  
**Source**: `docs/frontend-report.md` F-1, F-4, F-5, F-20

The refresh interceptor in `lib/core/api/api_client.dart:37-63` has three defects:
1. **Infinite retry loop**: `isRefreshing` is reset before `dio.fetch(opts)` retries the original request. If the retry 401s again, the cycle repeats forever (backend rotates refresh tokens, so each refresh succeeds). No per-request retry marker exists. The interceptor also runs for 401s from `/auth/login` and `/auth/register`.
2. **Concurrent 401s dropped**: when several requests 401 at once, only the first is retried; the rest surface as user-visible errors even though the refresh succeeded.
3. **Network failure logs the user out**: `AuthNotifier.refresh()` (`auth_state.dart:141-144`) catches all errors and calls `clearOnUnauthorized()`, so a timeout or server reboot wipes tokens. The refresh Dio (`auth_state.dart:130`) also has no connect/receive timeouts.

**Steps**:
1. Mark retried requests: set `error.requestOptions.extra['retried'] = true` before re-dispatch; skip the refresh branch when the flag is present or when `requestOptions.path` starts with `/auth/`.
2. Replace the `isRefreshing` bool with a shared `Completer<bool>` (or `Future<bool>?`): the first 401 starts the refresh, subsequent 401s await the same future, then all retry with the new token on success.
3. In `AuthNotifier.refresh()`: only call `clearOnUnauthorized()` when the refresh endpoint returns 401/403; on `DioException` of network type (timeout, connection error), return `false` without clearing tokens so the caller can surface a transient error.
4. Add connect/receive timeouts to the refresh Dio, matching `api_client.dart`.
5. Use `ApiEndpoints.authRefresh()` / `ApiEndpoints.authLogout()` in `auth_state.dart:104,132` instead of hardcoded strings (finishes TASK-049).
6. Add unit tests with a mock Dio adapter covering: 401 → refresh → retry succeeds; retry 401s again → no loop, user logged out; three concurrent 401s → one refresh, three retries; refresh timeout → tokens NOT cleared; 401 from `/auth/login` → no refresh attempt.

**Acceptance criteria**:
- [ ] No infinite loop when the server persistently 401s after refresh.
- [ ] Concurrent 401s all succeed transparently after a single refresh.
- [ ] Transient network failure during refresh does not log the user out.
- [ ] Wrong-password login does not trigger a refresh attempt.
- [ ] All new interceptor tests pass.

---

## TASK-057: Flutter — Runtime Server URL Configuration

**Domain**: Flutter  
**Priority**: High — headline feature for self-hosting  
**Depends on**: TASK-054  
**Source**: `docs/frontend-report.md` F-7

`lib/core/config/app_config.dart:4-7` reads `API_BASE_URL` at compile time (`String.fromEnvironment`), defaulting to the Android emulator's `http://10.0.2.2:8000`. A user installing the CI-built APK has no way to point the app at their own server — every household would need a custom build.

**Steps**:
1. Create a `ServerConfig` storage (e.g. `shared_preferences` or reuse `flutter_secure_storage`) holding the base URL; fall back to the compile-time value when unset.
2. Add a "Server" setup screen shown on first run when no URL is stored (before login), with a text field, and a "Test connection" action that calls `GET /health` (`ApiEndpoints.health` already exists, currently unused) and shows success/failure.
3. Make `dioProvider` (and the auxiliary Dio instances in `auth_state.dart`) derive `baseUrl` from a `serverUrlProvider` so changing the URL takes effect without an app restart.
4. Add an entry point to change the server URL later (e.g. from the login screen's overflow menu or a settings row on the dashboard). Changing it should log the user out (tokens are server-specific).
5. Validate input: require scheme, strip trailing slash.
6. Widget tests: first-run shows the setup screen; valid health check proceeds to login; invalid URL shows an error.

**Acceptance criteria**:
- [ ] Fresh install prompts for a server URL before login.
- [ ] URL persists across restarts and is used by all API calls including refresh/logout.
- [ ] Connection test gives clear success/failure feedback.
- [ ] The URL can be changed later without reinstalling.

---

## TASK-058: Flutter — Fetch All Chore Pages (List Truncated at 50)

**Domain**: Flutter  
**Priority**: High  
**Depends on**: TASK-045  
**Source**: `docs/frontend-report.md` F-6

`_fetchChores` (`lib/features/chores/providers/chores_provider.dart:84-93`) sends no `limit`/`offset` and ignores the `total` field; the backend defaults to `limit=50` (`backend/app/api/chores.py:182`). Households with recurring chores exceed 50 instances quickly: older items silently vanish from the list, the "Done" tab is incomplete, and the client-side weekly-points sum (`my_chores_screen.dart:111-115`) is quietly wrong.

**Steps**:
1. In `_fetchChores`, loop: request with `limit=100` and increasing `offset`, accumulating `items`, until the accumulated count reaches `total`. Guard with a sane max (e.g. 10 pages) to avoid pathological loops.
2. Keep the return type `List<ChoreModel>` so screens are unaffected.
3. Unit-test the pagination loop with a mocked Dio returning two pages.

**Acceptance criteria**:
- [ ] A household with >50 chore instances shows all of them.
- [ ] Exactly ⌈total/100⌉ requests are made.
- [ ] Existing widget tests remain green.

---

## TASK-059: Flutter — Invalidate Related Providers After Mutations

**Domain**: Flutter  
**Priority**: High  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-11

Several mutations leave sibling providers stale:
- `completeChore` (`chores_provider.dart:101-147`) never invalidates `leaderboardProvider` / `weeklyLeaderboardProvider` — the rank pill on My Chores and the Leaderboard tab show pre-completion data.
- `removeMember` / `changeRole` don't invalidate `choresNotifierProvider` — assignee names go stale after redistribution.
- `leaveHousehold` / `joinByToken` don't invalidate the members/chores families.
- The My Chores `RefreshIndicator` (`my_chores_screen.dart:156-159`) refreshes only the chores provider, not the weekly leaderboard.

**Steps**:
1. After a successful `completeChore`, call `ref.invalidate(leaderboardProvider(householdId))` and `ref.invalidate(weeklyLeaderboardProvider(householdId))` (match the actual provider family arguments).
2. After `removeMember`/`changeRole`, invalidate the chores family for that household.
3. After `leaveHousehold`/`joinByToken`, invalidate members and chores families.
4. Include the weekly leaderboard in the My Chores pull-to-refresh.
5. Add provider-level tests asserting invalidation (listen to the providers with a `ProviderContainer` and assert refetch).

**Acceptance criteria**:
- [ ] Completing a chore updates the rank pill and leaderboard without a manual refresh.
- [ ] Removing a member refreshes chore assignee names.
- [ ] Tests cover at least the completeChore → leaderboard invalidation path.

---

## TASK-060: Flutter — Wire Up Chore Editing (Currently Unreachable)

**Domain**: Flutter  
**Priority**: High  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-8

`CreateChoreScreen` fully supports edit mode via `ChoreFormInitData`, but nothing in the app ever constructs it: no navigation passes it as `extra`, and the admin long-press menu on a chore card (`chore_card.dart:215-252`) only offers "Delete series". Chore editing effectively does not exist. Additionally the due-date validator (`create_chore_screen.dart:455-464`) rejects past dates even in edit mode, so a chore whose date already passed could not be saved unchanged.

**Steps**:
1. Add an "Edit series" item to `_showAdminMenu` in `chore_card.dart`, constructing `ChoreFormInitData` from the chore's definition fields and navigating to the create/edit route with it as `extra`.
2. In edit mode, skip (or relax) the "due date must not be in the past" validation when the date is unchanged.
3. On successful save, refresh the chores list (existing behavior for create should already do this — verify for edit).
4. Widget tests: admin menu shows "Edit series"; screen opens pre-populated; saving calls `PATCH /households/{id}/chores/{definitionId}`.

**Acceptance criteria**:
- [ ] An admin can edit an existing chore definition end-to-end.
- [ ] Members do not see the edit action.
- [ ] Editing a chore with a past due date does not trap the user in validation errors.

---

## TASK-061: Flutter — Invite Deep Links

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: TASK-057  
**Source**: `docs/frontend-report.md` F-10

Invite QR codes and share links encode the backend `invite_url` (`{APP_BASE_URL}/join/{token}`), but the app registers no intent-filter and no matching route — scanning the QR opens a browser pointed at the API server. Joining currently requires manually copy-pasting the token into the dashboard dialog.

**Steps**:
1. Add a GoRouter route `/join/:token` that calls the existing `joinByToken` flow and navigates to the household on success.
2. Register an Android intent-filter (App Links or a custom scheme such as `choreapp://join/{token}` — if using a custom scheme, change what the QR encodes accordingly; the URL scheme choice should be documented in the task PR).
3. Handle the logged-out case: stash the pending token, complete login/registration, then join and clear the stash.
4. Widget tests for the route: logged-in user joining; logged-out user redirected to login then joined.

**Acceptance criteria**:
- [ ] Scanning an invite QR on a device with the app installed opens the app and joins the household (after login if needed).
- [ ] Invalid/expired tokens show the existing error handling.

---

## TASK-062: Flutter — Friendly API Error Messages

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-12, F-13

`AppErrorWidget` (`shared/widgets/error_widget.dart:38`) and ~10 call sites render `error.toString()`, which for a `DioException` dumps the full request URL and Dio boilerplate at the user. `_extractMessage` (`auth_provider.dart:112`) is a partial solution but is auth-only and renders FastAPI 422 validation lists as raw JSON. Separately, the household rename flow (`household_management_screen.dart:230-238`) has no error handling at all — failures leave the edit UI open with no feedback.

**Steps**:
1. Create a shared `String friendlyErrorMessage(Object error)` helper in `lib/core/api/` that maps: connection/timeout errors → "Can't reach the server"; 401/403 → permission message; 409/410/422 → extract `detail` from the response body, flattening FastAPI validation error lists into readable text; anything else → generic message.
2. Use it in `AppErrorWidget` (accept the raw error, not a pre-stringified message) and in all snackbar `catch` blocks.
3. Wrap `updateHouseholdName` in try/catch in the management screen; show a snackbar on failure and keep the previous name.
4. Unit tests for the mapper covering each branch, including a FastAPI 422 body.

**Acceptance criteria**:
- [ ] No screen ever displays a raw `DioException` string.
- [ ] FastAPI `detail` messages (e.g. "You are not assigned to this chore") pass through verbatim.
- [ ] Failed household rename shows feedback and does not corrupt UI state.

---

## TASK-063: Flutter — Real Release Signing, Application ID, and Versioning

**Domain**: Flutter / DevOps  
**Priority**: Medium  
**Depends on**: TASK-054  
**Source**: `docs/frontend-report.md` F-14

`android/app/build.gradle.kts` still signs release builds with the **debug keystore** (template TODO comment), `applicationId` is the Flutter template placeholder, the launcher label is `chore_app`, and `pubspec.yaml` is pinned at `1.0.0+1` with no version bumping — so users cannot cleanly upgrade between CI builds.

**Steps**:
1. Choose a real `applicationId` (e.g. `dev.ahzed11.choreapp`) and set the launcher label to "ChoreApp" in the main manifest.
2. Add release keystore support: read keystore path/passwords from `key.properties` (gitignored) or environment variables; fall back to debug signing only when absent, with a build-time warning.
3. In `.github/workflows/flutter.yml`, decode a base64 keystore from a GitHub secret and pass signing env vars; document the required secrets in the workflow file comments.
4. Derive `versionCode` in CI (e.g. `--build-number=$GITHUB_RUN_NUMBER`) so each APK upgrade-installs over the previous one.

**Acceptance criteria**:
- [ ] CI-built APK is signed with the release keystore when secrets are configured.
- [ ] Two successive CI APKs install as an upgrade (increasing versionCode) without uninstalling.
- [ ] `applicationId` and app label are no longer template values. NOTE: changing applicationId means existing installs will not upgrade in place — call this out in the commit message.

---

## TASK-064: Flutter — Show Server-Awarded Points Everywhere

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: TASK-051  
**Source**: `docs/frontend-report.md` §1 (TASK-051 verification), F-24

TASK-051 fixed the weekly-points banner, but the completion snackbars (`chore_list_screen.dart:130`, `my_chores_screen.dart:220`), the confirmation sheet (`chore_card.dart:532`), and the completed-card points pill (`chore_card.dart:187`) still display client-derived `pointValue` instead of the server's authoritative `pointsAwarded`, which the `completeChore` response already contains.

**Steps**:
1. Have `completeChore` in `chores_provider.dart` return the updated chore (with `pointsAwarded`) and use that value in the success snackbars.
2. Use `pointsAwarded ?? pointValue` in the completed-card pill.
3. The pre-completion confirmation sheet may keep the derived value (the award hasn't happened yet) — but source it from a single shared constant map (see TASK-065's dedup) rather than a screen-local copy.

**Acceptance criteria**:
- [ ] Post-completion UI shows the server's awarded points.
- [ ] If the backend ever changes the point mapping, no stale client value is displayed after completion.

---

## TASK-065: Flutter — Dead Code Removal and Constant Deduplication

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-15, F-16

~750 lines of dead code and several drifting duplicates:
- `lib/features/household/screens/invite_screen.dart` (355 lines) + route `AppRoutes.invite` + its test file: never navigated to (the management screen's inline accordion replaced it). Delete all three.
- `lib/features/household/widgets/member_tile.dart` and `lib/features/leaderboard/widgets/leaderboard_entry_tile.dart`: never imported. Delete.
- `ChoreFilter`/`ChoreFilterNotifier` (`chores_provider.dart:11-54, 202-232`): never read by any screen (filtering is client-side local state). Delete, or wire to server-side filter params — deleting is fine for MVP.
- `riverpod_annotation`, `riverpod_generator`, `build_runner` in `pubspec.yaml`: no codegen exists. Remove.
- Category labels duplicated with diverging text (`chore_model.dart:18-27` "Laundry"/"Garden" vs `create_chore_screen.dart:18-27` "Laundry Room"/"Garden / Outdoor") and effort-point maps duplicated (`chore_model.dart:41-45` vs `create_chore_screen.dart:30-34`): consolidate into a single `lib/core/constants/chore_constants.dart`.
- `_confirmComplete` duplicated verbatim in `chore_list_screen.dart:117-150` and `my_chores_screen.dart:202-241`: extract a shared helper.
- Avatar color palette + `_avatarColor` duplicated in 4 files: extract to `shared/`.
- "find my household / isAdmin" lookup duplicated in 5 widgets: add `householdByIdProvider(id)` / `isAdminProvider(id)`.

**Acceptance criteria**:
- [ ] `flutter analyze` clean; all tests green after deletions.
- [ ] Category labels and effort points exist in exactly one place.
- [ ] No behavioral change visible to users (except now-consistent category labels — pick the `create_chore_screen` wording).

---

## TASK-066: Flutter — Accessibility Pass

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-19

Most tap targets are bare `GestureDetector`s with no semantics: circle icon buttons (`chore_list_screen.dart:389-415`), filter tabs (`:534`), the leaderboard period picker (`leaderboard_screen.dart:276`), the copy-invite button (`household_management_screen.dart:471`). The chore-complete status circle is a 30px target (`chore_card.dart:85-90`), below the 48dp minimum. Overdue/complete state is conveyed by color alone in several places. Only 8 `tooltip`/`Semantics` usages exist in the whole lib.

**Steps**:
1. Replace bare `GestureDetector` buttons with `IconButton`/`InkWell` or wrap in `Semantics(button: true, label: ...)`.
2. Enlarge the status-circle hit area to >=48dp (padding or `Material` + `InkWell` with a bigger `customBorder`).
3. Add non-color signals for overdue (icon already exists on cards — ensure a semantic label too) and completed states.
4. Run `flutter analyze` and the existing widget tests; add semantics-based finders in tests where practical.

**Acceptance criteria**:
- [ ] TalkBack announces meaningful labels for all interactive elements on the four main screens.
- [ ] All tap targets are >=48dp.

---

## TASK-067: Flutter — Low-Priority Fix Batch

**Domain**: Flutter  
**Priority**: Low  
**Depends on**: none  
**Source**: `docs/frontend-report.md` F-17, F-21, F-22, F-23, F-25, F-26, F-27, F-28

Small independent fixes, safe to do in one PR:
1. **Chore description is write-only** (F-17): show it — e.g. tap a chore card to expand or open a detail bottom sheet displaying description, category, assignee, due date, recurrence.
2. **`AuthState.copyWith` token trap** (F-21, `auth_state.dart:60-65`): `token ?? this.token` makes clearing impossible; use the sentinel pattern already used in `ChoreFilter.copyWith`.
3. **Two sources of current-user ID** (F-22): standardize on `currentUserProvider` (`GET /users/me`); remove the client-side JWT decode in `leaderboard_provider.dart:19-45` and the usage in `chore_list_screen.dart:179`.
4. **Empty displayName crash** (F-23): guard `displayName[0]` at `household_management_screen.dart:869,1022` like the other avatar widgets do.
5. **Cold-start login flash** (F-25): add a splash/loading route while auth status is `unknown` (`app_router.dart:86-88`).
6. **Bundle the Outfit font** (F-26): add font assets and `GoogleFonts.config.allowRuntimeFetching = false` so LAN-only installs render correctly on first run.
7. **Pull-to-refresh on management screen** (F-27): wrap the `SingleChildScrollView` at `household_management_screen.dart:216` in a `RefreshIndicator` invalidating the members provider.
8. **Dependency bumps** (F-28): raise `flutter_lints`, `go_router`, `intl`, `share_plus` to current majors; fix any resulting deprecations.
9. **`test/widget_test.dart` uses real `FlutterSecureStorage`** (F-20): `_initialize()` throws `MissingPluginException` in the test environment (`auth_state.dart:79-86` has no try/catch). Override the storage/auth provider in the test, and add a try/catch around storage reads in `_initialize` so a broken keystore degrades to logged-out instead of crashing.

**Acceptance criteria**:
- [ ] Each numbered item verified individually; `flutter analyze` and `flutter test` green.
- [ ] Chore description is visible somewhere in the UI.

---

## TASK-068: Backend — Fix Broken Login (500 on Every Request) and Stale Integration Test

**Domain**: Backend  
**Priority**: CRITICAL — login is completely non-functional on this branch  
**Depends on**: none  
**Source**: `docs/backend-report.md` C1, H6

TASK-042 (commit `b231179`) removed the `expires_delta` parameter from `create_access_token` in `app/core/security.py:34`, but `app/api/auth.py:78-81` still passes `expires_delta=...`. Every `POST /auth/login` raises `TypeError` → HTTP 500. **68 of 137 tests currently fail** on this. `tests/test_auth_middleware.py:101` also calls the removed kwarg. Separately, `tests/test_integration.py:283-285` still treats `GET /chores` as a bare list even though TASK-039 changed it to a `{items, total, limit, offset}` envelope — that test fails once login is fixed.

**Steps**:
1. Restore `expires_delta: timedelta | None = None` on `create_access_token` in `app/core/security.py` (when None, fall back to `JWT_EXPIRY_DAYS` as today), OR remove the kwarg from both call sites (`app/api/auth.py:78-81`, `tests/test_auth_middleware.py:101`). Restoring the parameter is preferred — tests use it to mint short-lived tokens.
2. Fix `tests/test_integration.py:283-285`: `instances = chores_resp.json()["items"]`.
3. Run the full suite against PostgreSQL: expect 137/137 passing (coverage gate issues are handled separately in TASK-069).

**Acceptance criteria**:
- [ ] `POST /auth/login` returns 200 with a token pair.
- [ ] Full test suite passes (ignore the coverage threshold for this task if needed via `--no-cov`).

---

## TASK-069: DevOps — Run CI on All Branches and Fix the Coverage Gate

**Domain**: DevOps  
**Priority**: High — the reason TASK-068's regression shipped  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` H4

`.github/workflows/ci.yml` and `.github/workflows/flutter.yml` trigger only on push/PR to `main`/`master`. All development happens on `claude/*` branches merged locally, so CI never ran on the branch that broke login. Additionally, actual backend coverage is **68.1%** against the `--cov-fail-under=75` gate in `backend/pyproject.toml`, so the next master push fails even with all tests green.

**Steps**:
1. In both workflows, change the `push` trigger to all branches (`branches: ['**']`) while keeping PR triggers; keep the GHCR image push job restricted to the default branch (it already checks `github.event_name == 'push'` — tighten to `github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master'`).
2. Address the coverage gap: add tests for the least-covered modules (`app/services/redistribution.py` is at ~25%; logout/refresh paths in `app/api/auth.py`) until >=75%, or lower the gate to the measured value and add a comment to ratchet it up.
3. Add a backend lint step: add `ruff` to the `test` optional dependencies, a `[tool.ruff]` config (with SQLAlchemy-friendly ignores for string annotations), and a `uv run ruff check` step in CI. Fix or noqa existing findings (~9 real ones: unused imports, unused `_COMPLETABLE_STATUSES` in `chores.py:269`, dead `hasattr(value, "model_dump")` branch at `chores.py:487-489`).

**Acceptance criteria**:
- [ ] Pushing to any branch runs backend tests + lint and the Flutter analyze/test/build.
- [ ] Image publishing still happens only from the default branch.
- [ ] CI is green on this branch after TASK-068.

---

## TASK-070: Backend — Short-Lived Access Tokens and JWT Secret Validation

**Domain**: Backend  
**Priority**: High  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` H2, M12

Access tokens live 7 days (`app/core/config.py:13`) even though rotated 30-day refresh tokens exist and the Flutter app implements the refresh flow — a stolen access token stays valid for a week, and the `revoked_tokens` blocklist only helps on explicit logout. Also, `JWT_SECRET` accepts any string, including the `.env.example` placeholder.

**Steps**:
1. Add `JWT_EXPIRY_MINUTES: int = 30` to `Settings`; use it in `create_access_token` and in login/refresh `expires_in` responses. Keep `JWT_EXPIRY_DAYS` temporarily as a deprecated fallback (if explicitly set, honor it and log a warning) so existing `.env` files don't break.
2. Update `.env.example` (both root and backend) accordingly.
3. Add a `field_validator` on `JWT_SECRET` in `Settings`: require >=32 characters and reject known placeholders (`change-me…`, `replace_with…`). Fail fast at startup with a clear message.
4. Update tests that assume 7-day expiry; add a test for the validator (placeholder secret → startup error).

**Acceptance criteria**:
- [ ] New tokens expire in minutes, not days; `expires_in` reflects it.
- [ ] The Flutter refresh flow keeps sessions alive across expiry (manual or integration check).
- [ ] Startup fails with a clear error on a short or placeholder `JWT_SECRET`.

---

## TASK-071: Backend — chores.py Correctness Fixes (Pagination Order, Query Param 422, Reassignment Guard)

**Domain**: Backend  
**Priority**: High  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` H3, H5, L3

Three small correctness bugs in `app/api/chores.py`:
1. The paginated list query (`chores.py:210-217`) has no ORDER BY — PostgreSQL gives no ordering guarantee with LIMIT/OFFSET, so pages can repeat or skip rows.
2. `status_filter` and `category` query params (`chores.py:179-180`) are plain `str`; invalid values reach the native PG enum comparison and return HTTP 500 (verified live).
3. `PATCH /chores/{iid}/assignee` (`chores.py:372-449`) happily reassigns `complete`/`cancelled` instances.

**Steps**:
1. Add `.order_by(ChoreInstance.due_date, ChoreInstance.id)` to both the count-consistent data query and any related listing.
2. Type the query params with the existing `Literal` aliases from `app/schemas/chore.py` (status also needs `overdue`/`cancelled` values — reuse the instance-status type) so FastAPI returns 422.
3. In the reassignment endpoint, return 409 when the instance status is `complete` or `cancelled`.
4. Tests: page stability (create 3 instances, fetch limit=2/offset=0 and offset=2, assert no overlap), `?status_filter=bogus` → 422, reassigning a completed instance → 409.

**Acceptance criteria**:
- [ ] Pagination is deterministic (ordered by due date, then id).
- [ ] Invalid filter values return 422, not 500.
- [ ] Terminal instances cannot be reassigned.

---

## TASK-072: Backend — Auth Token Hygiene: Idempotent Logout, Table Cleanup, Replay Hardening

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` M1, M2, M10

Three related issues:
1. Logging out twice with the same token returns 409: `auth.py:184-193` inserts the `jti` into `revoked_tokens` unconditionally; the duplicate-PK `IntegrityError` is swallowed by the blanket handler in `main.py:95-98`.
2. `revoked_tokens` and `refresh_tokens` grow forever — the cleanup job promised in both model docstrings doesn't exist, and every login adds a refresh-token row with no per-user cap.
3. Refresh-token replay (reuse of a rotated/revoked token) returns 401 but isn't treated as theft; and `/auth/refresh` returns an untyped bare dict without `expires_in` while login returns `TokenResponse`.

**Steps**:
1. Make logout idempotent: check for the `jti` first or use `INSERT ... ON CONFLICT DO NOTHING`; return 200 either way.
2. In `run_daily_job` (`app/tasks/scheduler.py`), delete rows from `revoked_tokens` and `refresh_tokens` whose `expires_at` is in the past.
3. On refresh with a token that exists but is already revoked/rotated, revoke **all** refresh tokens for that user (standard reuse-detection) and return 401.
4. Declare `response_model=TokenResponse` on `/auth/refresh` and include `expires_in`.
5. Consider scoping down the blanket IntegrityError→409 handler (log the constraint name; it currently masks real bugs).
6. Tests: double logout → 200/200; cleanup removes only expired rows; replay revokes the family; refresh response shape matches login.

**Acceptance criteria**:
- [ ] Double logout is idempotent.
- [ ] Expired token rows are purged daily.
- [ ] Rotated-token replay revokes all of the user's refresh tokens.

---

## TASK-073: Backend — Scheduler Resilience: Run on Startup, Misfire Grace, Backfill Cap, Bulk Assignment

**Domain**: Backend  
**Priority**: Medium — directly affects self-hosted reliability  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` M3, M11

Two self-hosting-relevant scheduler problems (`app/tasks/scheduler.py`):
1. If the server isn't running at 00:00 UTC (reboot, power cut — common for home servers), the daily job silently skips: no instances generated, nothing flagged overdue, until the next midnight. There is no `misfire_grace_time` and nothing runs at startup.
2. Instance generation starts from `first_due_date` unbounded (`scheduler.py:130-134`): after extended downtime or a definition created with an old date, a daily chore floods the household with dozens of instantly-overdue instances, each advancing the rotation pointer. Assignment also remains an N+1 (`scheduler.py:140-142` — one `SELECT FOR UPDATE` per new instance).

**Steps**:
1. In the app lifespan startup, invoke `run_daily_job()` once (it is idempotent and advisory-locked, so multi-worker startup is safe). Also set `misfire_grace_time` (e.g. 6 hours) on the cron trigger.
2. Cap backfill: start generation at `max(first_due_date, today - GRACE_DAYS)` with `GRACE_DAYS` configurable (default e.g. 3), or track a `last_generated_until` date column on `ChoreDefinition` (requires a migration) — the cap approach is simpler and adequate.
3. Batch-assign new instances using the single-lock pattern from `AssignmentService.redistribute_chores_bulk` instead of per-instance `auto_assign`.
4. Tests: startup runs the job once; a definition with `first_due_date` 30 days ago generates only capped instances; assignment acquires the household lock once per household per run.

**Acceptance criteria**:
- [ ] Restarting the app after missed midnights immediately generates/flags correctly.
- [ ] No overdue-instance flood after downtime.
- [ ] One rotation-lock acquisition per household per scheduler run.

---

## TASK-074: DevOps — Production Docker Compose with Startup Migrations

**Domain**: DevOps  
**Priority**: High for self-hosting  
**Depends on**: none  
**Source**: `docs/backend-report.md` M4; old SEC-020/SEC-022

The repo's only `docker-compose.yml` is a dev config: `--reload`, `DEBUG: "true"`, and a bind mount `./backend:/app` that hides the hardened image contents. There is no `env_file:` (so `REFRESH_TOKEN_TTL_DAYS`, `CORS_ALLOWED_ORIGINS`, `SCHEDULER_RUN_HOUR`, `INVITE_TOKEN_TTL_HOURS` can't be set without editing YAML), and migrations must be run manually via `make migrate`. Meanwhile CI already publishes an image to GHCR that nothing references.

**Steps**:
1. Add `docker-compose.prod.yml` (or a `prod` profile): `api` uses `image: ghcr.io/<owner>/chore-app-api:latest` (documented override for a pinned tag), no source mount, no `--reload`, `DEBUG=false`, `env_file: .env`, `restart: unless-stopped`; `db` unchanged but without the host port mapping (or keep `127.0.0.1:` binding).
2. Add an entrypoint script to the backend image that runs `alembic upgrade head` before starting uvicorn (single-instance self-host makes this safe). Keep the raw uvicorn CMD usable for dev.
3. Wire the remaining Settings env vars into the compose environment via `env_file` and document them in the root `.env.example`.
4. Add `make prod-up` / `make prod-down` targets (and make `podman compose` configurable: `COMPOSE ?= podman compose`).
5. Verify: `docker compose -f docker-compose.prod.yml up` on a clean machine reaches a healthy API with migrated schema using only `.env`.

**Acceptance criteria**:
- [ ] Production compose runs the published image with no source mount, no reload, docs disabled.
- [ ] Fresh deployment migrates automatically and serves `/health` → 200.
- [ ] All Settings-known env vars are settable via `.env` without YAML edits.

---

## TASK-075: DevOps — Database Backup and Restore

**Domain**: DevOps  
**Priority**: High for self-hosting  
**Depends on**: TASK-074  
**Source**: `docs/backend-report.md` M5

The Postgres volume holds the household's entire data and nothing backs it up. For a self-hosted family app, data loss is the worst realistic failure.

**Steps**:
1. Add a backup service to the production compose (e.g. `prodrigestivill/postgres-backup-local`) with a daily schedule, 7 daily / 4 weekly retention, writing to a host-mounted `./backups` directory. Alternatively (or additionally) add `make backup` / `make restore FILE=...` targets wrapping `pg_dump -Fc` / `pg_restore`.
2. Document restore steps in the README (TASK-076): stop api → restore dump → start api.
3. Test the full cycle: create data, back up, wipe the volume, restore, verify data intact.

**Acceptance criteria**:
- [ ] Automatic daily dumps land in a host directory with retention.
- [ ] A documented, tested restore procedure exists.

---

## TASK-076: Docs — Root README and Self-Hosting Guide

**Domain**: Docs  
**Priority**: High for self-hosting  
**Depends on**: TASK-074 (references the prod compose), TASK-075 (restore docs)  
**Source**: `docs/backend-report.md` R1

The repository has no root README — only `flutter_app/README.md` (the Flutter template). A self-hosted-only project needs deployment documentation.

**Steps**:
1. Write `README.md` at the repo root covering: what the app is (screenshots optional), architecture overview (FastAPI + PostgreSQL + Flutter Android app), quick start for production (clone → copy `.env.example` → generate `JWT_SECRET` → `docker compose -f docker-compose.prod.yml up -d`), how to get the APK (CI artifact) and point it at your server (references the server-URL screen from TASK-057), HTTPS guidance (reverse proxy example with Caddy or nginx — note uvicorn's `--proxy-headers` and the need for `--forwarded-allow-ips` when proxied from another container), backup/restore (from TASK-075), development setup (`make dev`, running tests), and a pointer to `docs/` for requirements/reports/tasks.
2. Fix `backend/.env.example:52`: the test DB note references a nonexistent `docker-compose.test.yml` and port 5433 while CI/Makefile use 5432 — align the docs with reality.

**Acceptance criteria**:
- [ ] A newcomer can deploy the stack and connect the app following only the README.
- [ ] No references to files or ports that don't exist.

---

## TASK-077: Backend — Password Change and Admin Reset

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` M6

A forgotten password is currently unrecoverable without raw psql. Email-based reset is overkill for self-host (no SMTP assumption); provide the two flows that work without email.

**Steps**:
1. Add `POST /users/me/password` with body `{ "current_password": str, "new_password": str }` (new password: same min/max constraints as registration). Verify the current password; on success, update the hash and **revoke all of the user's refresh tokens** (and optionally all outstanding JWTs via a `password_changed_at` claim check — refresh revocation alone is acceptable given TASK-070's short access tokens).
2. Add a management CLI (e.g. `python -m app.cli reset-password <email>`) that prompts for a new password and updates the hash directly — documented in the README as the "forgot password" recovery path for self-hosters.
3. Tests: wrong current password → 403; success → old refresh token rejected; CLI updates the hash.

**Acceptance criteria**:
- [ ] Users can change their password in-app (Flutter UI can follow later).
- [ ] The server operator can reset any account's password from the host.
- [ ] Password change invalidates existing refresh tokens.

---

## TASK-078: Backend — Account Deletion and Household Deletion

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` M7

Neither `DELETE /users/me` nor `DELETE /households/{id}` exists. FK cascade rules are already defined on the models, so the work is mostly authorization and edge-case semantics.

**Steps**:
1. `DELETE /households/{household_id}` — admin only; require a confirmation body or `?confirm=<household name>`; hard-delete the household (cascades to memberships, invites, chores, ledger). Return 204.
2. `DELETE /users/me` — require the current password in the body. Rules: if the user is the sole admin of a household with other active members → 409 directing them to promote someone first; sole member households are deleted outright; otherwise the membership is deactivated and pending chores redistributed (reuse the removal/redistribution service). Then delete the user row (PointLedger rows: decide keep-with-SET NULL vs cascade — check the existing FK and keep history if `SET NULL` is already configured).
3. Revoke all tokens for the deleted user.
4. Tests: cascade coverage, sole-admin guard, redistribution on self-delete, token invalidation.

**Acceptance criteria**:
- [ ] A household can be deleted by its admin with explicit confirmation.
- [ ] A user can delete their account; remaining households stay consistent.
- [ ] No orphaned rows violate FK constraints after either operation.

---

## TASK-079: Backend — Email Case Normalization and Leaderboard Window Fixes

**Domain**: Backend  
**Priority**: Medium  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` M8, M9

Two small correctness items:
1. Emails are case-sensitive (`auth.py:32,58`): `Alex@gmail.com` and `alex@gmail.com` register as distinct accounts, and login must match registration case exactly.
2. Leaderboard windows: `leaderboard.py:32-34` uses local `date.today()` (inconsistent with the UTC scheduler; wrong week/month boundaries on non-UTC hosts) and `:54,62` cap the window at `23:59:59`, excluding points awarded in the final second of the period.

**Steps**:
1. Normalize emails to lowercase on register and login. Add an Alembic migration lowercasing existing rows; guard against collisions (if two accounts differ only by case, fail the migration with a clear message — operator resolves manually). Optionally add a functional unique index on `lower(email)`.
2. In the leaderboard, compute "today" as `datetime.now(timezone.utc).date()` and make window upper bounds exclusive (`awarded_at < next_period_start`) instead of `<= 23:59:59`.
3. Tests: mixed-case login succeeds; duplicate-case registration → 409; a ledger entry at `23:59:59.5` on the period's last day counts.

**Acceptance criteria**:
- [ ] Email uniqueness and login are case-insensitive.
- [ ] Weekly/monthly windows are UTC-correct and include the entire final second.

---

## TASK-080: Backend — Low-Priority Fix Batch

**Domain**: Backend  
**Priority**: Low  
**Depends on**: TASK-068  
**Source**: `docs/backend-report.md` L1, L2, L4, L5, L8, L9

Small independent fixes, one PR:
1. **Rotation-pointer adjustment bug** (L1): `redistribution.py:121-130` compares `removed_index` (0..N-1) against the raw unbounded pointer (`assignment.py:55` stores `pointer+1` unmodded), so the decrement fires almost always. Compare against `original_pointer % member_count` (count including the removed member), or store the pointer modulo N. Add regression tests for removal before/at/after the pointer with a pointer > N.
2. **Invite-accept race** (L2): add `with_for_update()` to the invite-token select in `invites.py:84-117` so a single-use token can't be redeemed twice concurrently.
3. **Dead code** (L4): remove `_COMPLETABLE_STATUSES` (`chores.py:269`), the dead `hasattr(value, "model_dump")` branch (`chores.py:487-489`), and unused imports (`app/services/assignment.py:3`, `app/db/base.py:1`, test files). (Covered by the lint step if TASK-069 lands first.)
4. **Test suite speed** (L5): replace the per-test schema drop/create in `conftest.py:78-80` with a session-scoped schema + per-test truncation or transaction rollback. Target: full suite < 1 minute.
5. **Architecture** (L8, optional if time permits): extract `complete_chore_instance` and `create_chore` orchestration into a `ChoreService` in `app/services/` — do this before implementing notifications.
6. **Minor endpoints** (L9, optional): `GET /households/{id}/chores/definitions` (list) and `GET .../definitions/{definition_id}` for edit UIs.

**Acceptance criteria**:
- [ ] Rotation regression tests pass; concurrent invite acceptance yields exactly one member.
- [ ] Test suite runtime is measurably reduced.
- [ ] No behavior changes except the fixed bugs.

---

## TASK-081: Backend — Chore Reminder Notifications via ntfy/Gotify Webhook

**Domain**: Backend  
**Priority**: Low (next feature milestone)  
**Depends on**: TASK-073  
**Source**: `docs/backend-report.md` L10

Nothing notifies assignees of due or overdue chores — `flag_overdue_instances` changes a status nobody sees until they open the app. For a self-hosted stack, push via a self-hostable notification service (ntfy or Gotify) or a generic webhook is a much better fit than FCM/APNS (no Google dependency, works with the existing infra).

**Steps**:
1. Add optional settings: `NOTIFY_URL` (e.g. an ntfy topic URL or Gotify endpoint), `NOTIFY_TOKEN` (optional auth header). Feature is disabled when unset.
2. In `run_daily_job`, after generation/flagging, send one summary notification per household (or per user if per-user topics are configured — keep MVP simple: one topic): chores due today and newly overdue chores, with assignee display names.
3. Use `httpx` with a short timeout; failures are logged, never fail the job.
4. Document setup in the README (run ntfy alongside via compose, subscribe from the phone app).
5. Tests: notification payload construction; disabled when unset; delivery failure doesn't break the job.

**Acceptance criteria**:
- [ ] With `NOTIFY_URL` set, the daily job posts a summary of due/overdue chores.
- [ ] Unset config = no behavior change.
- [ ] Notification failure never aborts instance generation.

---
