# Requirements Document — Household Chores Motivation App

**Version**: 1.2
**Date**: 2026-07-16 (updated; supersedes 2026-06-25)
**Status**: MVP implemented; hardening and self-hosting work mostly complete — see `docs/tasks.md`

---

## 1. Project Overview

**Purpose**: Helps cohabitants coordinate, distribute, and stay accountable for domestic
chores via structured round-robin assignment and a points/leaderboard system.

**Target users**: Flatmates, families, or any group sharing a household who want
visibility into who is doing what.

**Goals**: (1) eliminate ambiguity about chore ownership/status, (2) distribute workload
fairly via automatic round-robin, (3) motivate participation via points + leaderboard,
(4) support multiple households per user account.

**MVP platform**: Android (Flutter), backend on FastAPI + PostgreSQL, self-hosted.

---

## 2. Functional Requirements

### 2.1 Authentication

| ID | Requirement |
|----|-------------|
| FR-001 | Any visitor may register a new account with email + password. |
| FR-002 | Email uniqueness is validated at registration (case-insensitively — see Resolved Decisions); clear error if taken. |
| FR-003 | Passwords are stored as a salted bcrypt hash; plaintext is never persisted or logged. |
| FR-004 | Login authenticates via email + password, returning a signed JWT access token. |
| FR-005 | The JWT carries the user's ID and a `jti`. Access tokens expire in `JWT_EXPIRY_MINUTES` (default 30; the old `JWT_EXPIRY_DAYS` is a deprecated fallback, honored with a startup warning if explicitly set). Login also issues a rotating refresh token (`REFRESH_TOKEN_TTL_DAYS`, default 30, hash-only storage); logout revokes both the access token (`jti` blocklist) and all of the user's refresh tokens server-side. `JWT_SECRET` is validated at startup: rejected if under 32 characters or if it matches a known placeholder string. See `backend/app/core/config.py`, `app/core/security.py`, `app/api/auth.py`. |
| FR-006 | All endpoints except register/login require a valid JWT Bearer token. |
| FR-007 | HTTP 401 on missing/expired/revoked tokens; HTTP 403 on insufficient role. |

### 2.2 User Profile

| ID | Requirement |
|----|-------------|
| FR-008 | Each account stores: id, email, display name, hashed password, created_at. |
| FR-009 | A user may retrieve their own profile. |
| FR-010 | A user may update their own display name. |

### 2.3 Households

| ID | Requirement |
|----|-------------|
| FR-011 | Any authenticated user may create a household by name; creator becomes Admin. |
| FR-012 | A household stores: id, name, created_at, and a `rotation_pointer` for round-robin. |
| FR-013 | No cap on household member count. |
| FR-014 | A user may belong to multiple households, with an independent role in each. |
| FR-015 | An Admin may generate an invite link + QR code (same token). |
| FR-016 | Invite tokens are time-limited and single-use — see Resolved Decisions OQ-001. |
| FR-017 | Following a valid invite link adds the user as a Member. |
| FR-018 | An Admin may remove any member other than themselves. |
| FR-019 | An Admin may promote/demote, provided at least one Admin always remains. |
| FR-020 | An Admin sees the full member list (role, join date). |
| FR-021 | A Member sees the member list (read-only). |
| FR-022 | A user may leave voluntarily; sole-Admin leave — see Resolved Decisions OQ-002. |
| FR-023 | Household name is editable by Admins only. |

### 2.4 Chores

| ID | Requirement |
|----|-------------|
| FR-024 | An Admin creates a chore with: title, description (optional), category, effort level, assignee (optional), due date, recurrence rule. |
| FR-025 | Effort levels map to fixed points: Easy = 10, Medium = 25, Hard = 50 (not overridable). |
| FR-026 | Categories: Kitchen, Bathroom, Bedroom, Living Room, Laundry Room, Garden / Outdoor, Garage, Other / General. |
| FR-027 | A chore is **one-off** or **recurring**. |
| FR-028 | Recurrence: every N days / weeks / months (N a positive integer). |
| FR-029 | Recurring chores generate subsequent instances automatically from a first due date + rule. |
| FR-030 | A chore instance stores: id, parent chore id, household id, title, description, category, effort level, assignee, due date, status (`pending` / `complete` / `overdue` / `cancelled`), completion timestamp, points awarded. |
| FR-031 | An Admin may edit a recurring chore's definition; edits apply to future instances only. |
| FR-032 | Deleting a series cancels pending generated instances; completed instances are preserved. |
| FR-033 | All members can view all household chores, including assignees. |
| FR-034 | Members can filter by status, category, assignee. |
| FR-035 | A pending instance past its due date is flagged `overdue`; no point penalty. |
| FR-036 | Overdue chores stay with their original assignee; not auto-reassigned. |

### 2.5 Assignment Algorithm

| ID | Requirement |
|----|-------------|
| FR-037 | A chore created without an explicit assignee auto-assigns via round-robin. |
| FR-038 | Rotation order is by join date, oldest first. |
| FR-039 | A rotation pointer advances by one after each auto-assignment. |
| FR-040 | Manual assignment does NOT advance the pointer. |
| FR-041 | The assignment engine is a pluggable strategy so alternatives can be substituted later. |
| FR-042 | Removing a member redistributes their pending/overdue chores via round-robin. |
| FR-043 | With one remaining member, all chores go to that member. |
| FR-044 | With no members, pending chores become unassigned — see Resolved Decisions OQ-003. |
| FR-045 | Chores created before any member joins queue unassigned until the first member joins. |

### 2.6 Completion and Points

| ID | Requirement |
|----|-------------|
| FR-046 | Only the assigned member may mark a chore instance complete. |
| FR-047 | Completion awards the effort-level points immediately, no approval step. |
| FR-048 | Points are scoped per household-member pair; independent across households. |
| FR-049 | A completed instance cannot be un-completed (no undo) — see Open Questions OQ-004. |
| FR-050 | Completion records: timestamp, points awarded, completing user id. |

### 2.7 Leaderboard

| ID | Requirement |
|----|-------------|
| FR-051 | Each household has a leaderboard ranking members by points. |
| FR-052 | Three scopes: **All-time**, **This week** (Mon–Sun), **This month** (calendar month), computed in UTC — see Resolved Decisions OQ-007. |
| FR-053 | Each entry shows: rank, display name, points in scope, chores completed in scope. |
| FR-054 | Equal points share the same rank (dense ranking). |
| FR-055 | The response includes the requesting user's own rank. |

---

## 3. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-001 | CRUD endpoints respond within 300ms p95 under normal load (≤100 concurrent users/household). |
| NFR-002 | Leaderboard queries complete within 500ms up to 100 members / 10,000 chore records. |
| NFR-003 | Passwords hashed with bcrypt, cost factor ≥12. |
| NFR-004 | JWTs signed HS256/RS256; signing secret injected via env var, never hardcoded, and validated for strength at startup. |
| NFR-005 | Every household-scoped endpoint verifies active membership; no data leaks to non-members. |
| NFR-006 | Invite tokens are cryptographically random (≥128 bits) and invalidated after use/expiry. |
| NFR-007 | Round-robin pointer updates are serialisable (row-level lock) to prevent double-assignment. |
| NFR-008 | The scheduler's instance-generation/overdue-flagging job is idempotent. |
| NFR-009 | Primary flows (view chores, mark complete, view leaderboard) completable in ≤3 taps from home. |
| NFR-010 | Text contrast meets WCAG 2.1 AA on all screens. |
| NFR-011 | Backend ≥80% line coverage; auth, assignment engine, and points-award at 100%. Measured coverage is 95%. |
| NFR-012 | Marking complete + awarding points happens in a single DB transaction. |
| NFR-013 | API emits structured JSON logs: request id, user id (if available), endpoint, status, duration. |

---

## 4. Roles and Permissions Matrix

| Action | Admin | Member | Unauthenticated |
|--------|-------|--------|-----------------|
| Register / Login | Yes | Yes | Yes |
| View / update own profile | Yes | Yes | No |
| Create household | Yes | Yes | No |
| View household details | Yes | Yes | No |
| Edit / delete household | Yes | No | No |
| Generate invite link / QR | Yes | No | No |
| Join via invite | Yes (as Member) | Yes (as Member) | No |
| View member list | Yes | Yes | No |
| Remove member / change role | Yes | No | No |
| Leave household | Yes* | Yes | No |
| Create / edit / delete chore | Yes | No | No |
| View all household chores | Yes | Yes | No |
| Manually assign / reassign chore | Yes | No | No |
| Mark assigned chore complete | Yes** | Yes** | No |
| View leaderboard | Yes | Yes | No |
| Change own password | Yes | Yes | No |
| Delete own account | Yes*** | Yes | No |

\* An Admin may leave only if another Admin remains (sole-Admin leave is blocked — OQ-002).
\*\* Only for chores assigned to themselves.
\*\*\* Blocked (409) if sole Admin of a household with other active members — must promote someone first (TASK-078).

---

## 5. Business Rules and Edge Cases

- **BR-001** Single-member household: all auto-assignments go to that member; the pointer still advances (wraps to 0).
- **BR-002** Member removal: their rotation position is dropped; the pointer is adjusted so it doesn't skip the next eligible member (comparison is against `original_pointer % member_count`, fixing an earlier off-by bug). Redistribution continues round-robin from the current pointer.
- **BR-003** Household with no members: pending chores go unassigned; rotation restarts at index 0 when the next member joins.
- **BR-004** Chores created before any member joins queue unassigned, then process via round-robin on first join.
- **BR-005** Member rejoining: intended as a new rotation entry with points kept separate per membership period — but the implementation has no per-membership scoping on `PointLedger`, so rejoining currently merges historical and new points in leaderboard queries. See Resolved Decisions OQ-005.
- **BR-006** An Admin cannot remove themselves via the member-removal flow if sole Admin; must promote another Admin or use leave-household (OQ-002).
- **BR-007** A recurring instance generates once it's within the generation horizon (`INSTANCE_GENERATION_DAYS_AHEAD`, default 7); a backfill floor (`today - GRACE_DAYS`, default 3) caps how far past instances are generated after downtime. Idempotency is enforced via `(definition_id, due_date)` uniqueness.
- **BR-008** Completing an overdue chore awards points normally; no penalty.
- **BR-009** Effort-level points (10/25/50) are fixed constants for MVP; schema should not preclude making them configurable later.
- **BR-010** "This week" = Monday 00:00 UTC through the exclusive start of the following Monday, computed server-side in UTC.
- **BR-011** "This month" = the first calendar day 00:00 UTC through the exclusive start of the next month, computed server-side in UTC.
- **BR-012** Deleting a series cancels pending instances; completed instances are orphaned but preserved for leaderboard history. Deleting a *user's account* is different — see Resolved Decisions (TASK-078 note under OQ-009).
- **BR-013** Simultaneous completion attempts: a row-level lock on the chore instance ensures exactly one succeeds.
- **BR-014** Role changes do not affect a user's accumulated points or chore history.

---

## 6. Data Model Sketch

Sketch-level — see `backend/app/models/` and `backend/alembic/versions/` for the source of truth.

- **User**: id, email (unique, stored lowercased), display_name, password_hash, created_at.
- **Household**: id, name, created_at, rotation_pointer (default 0).
- **HouseholdMembership**: id, household_id, user_id, role (admin/member), joined_at, is_active. Partial unique index on (household_id, user_id) where is_active.
- **InviteToken**: id, household_id, created_by_id, token (unique), expires_at, used_at (nullable).
- **ChoreDefinition**: id, household_id, created_by_id (nullable, SET NULL on user delete), title, description, category, effort_level, chore_type, recurrence_rule (JSONB), first_due_date, is_active.
- **ChoreInstance**: id, definition_id (nullable, SET NULL), household_id, assignee_id (nullable, SET NULL on user delete), assigned_manually, due_date, status (pending/complete/overdue/cancelled), completed_at, points_awarded. Unique on (definition_id, due_date); indexes on due_date, definition_id, (household_id, status), assignee_id.
- **PointLedger**: id, household_id, user_id (**CASCADE** on user delete — see OQ-009 note below), chore_instance_id (nullable, SET NULL), points, awarded_at. Unique on chore_instance_id (prevents double-award). No membership scoping — see BR-005.
- **RefreshToken**: id, user_id, token_hash (SHA-256, unique), created_at, expires_at, revoked_at (nullable). Supports FR-005's refresh flow.
- **RevokedToken**: jti (PK), revoked_at, expires_at. Supports FR-005's logout/revocation; rows past `expires_at` are purged by the daily scheduler job.

Relationships: User↔Household many-to-many via HouseholdMembership; Household→ChoreDefinition→ChoreInstance one-to-many; ChoreInstance→PointLedger one-to-one; User→PointLedger one-to-many. The leaderboard is derived from `PointLedger` aggregation (no materialized view yet).

---

## 7. Out of Scope for MVP

| Feature | Notes |
|---------|-------|
| Avatar system | Customisable avatar; design allows a future `avatar_id` FK on User. |
| Cosmetics shop | Spend points on cosmetics; needs a point-spend transaction type in PointLedger. |
| Push notifications | **Scope change**: no longer FCM/APNS. Planned as a self-hosted ntfy/Gotify webhook triggered from the daily scheduler job (TASK-081, not yet implemented). |
| Admin-configurable assignment strategy | Per-household strategy selection; FR-041's pluggable interface anticipates this. |
| Photo proof on completion | Optional image attachment when completing a chore. |
| Expanded categories | Category enum should be designed for forward migration. |

---

## 8. Resolved Decisions

Verified directly against the running code on `claude/brave-ritchie-1owy48` (paths under
`backend/app/`) — supersedes the original Open Questions of the same ID.

| ID | Resolution | Evidence |
|----|------------|----------|
| OQ-001 | Invite tokens: 48h TTL by default (`INVITE_TOKEN_TTL_HOURS`, configurable), single-use (`used_at`), admin-revocable, capped at one active invite per household, and row-locked on accept (`with_for_update()`) so a token can't be redeemed twice concurrently. | `api/invites.py`, `core/config.py` |
| OQ-002 | Sole-Admin leave is **blocked** (HTTP 409, "promote another admin first"), not auto-promotion. Same rule applies to sole-Admin self-removal and to sole-Admin account deletion (TASK-078). | `api/members.py`, `services/account_deletion.py` |
| OQ-003 | Empty-household chores: instances are set `assignee_id = null` (unassigned); due dates are left untouched. Rotation restarts at index 0 on the next join. | `services/redistribution.py` |
| OQ-005 | Rejoining a household: `PointLedger` has no per-membership scoping (only household_id + user_id), so historical and new-period points are **merged** in leaderboard/points queries — not kept separate as BR-005 originally intended. Unaffected by TASK-079's UTC/window fix. No product decision has revisited this; documented as current behavior. | `models/point_ledger.py`, `api/leaderboard.py` |
| OQ-006 | Scheduler generates instances up to `INSTANCE_GENERATION_DAYS_AHEAD` (default 7) on the daily job, which now also runs once at startup (6h `misfire_grace_time`) so a missed midnight doesn't silently skip a day. Backfill after downtime is capped at `max(first_due_date, today - GRACE_DAYS)` (`GRACE_DAYS` default 3) so a stale definition can't flood the household with overdue instances (TASK-073). | `tasks/scheduler.py`, `core/config.py` |
| OQ-007 | "This week"/"this month" windows are now correctly **UTC** — `leaderboard.py`'s `_get_today()` uses `datetime.now(timezone.utc).date()`, matching the scheduler's clock — and the upper bound is an **exclusive** next-period boundary (`< next_period_start`), so an entry awarded in the final second of a period is included. Fixed by TASK-079; the earlier local-time/inclusive-bound bug no longer applies. | `api/leaderboard.py` |
| OQ-008 | Password length: 8–72 characters (`PASSWORD_MIN_LENGTH`/`PASSWORD_MAX_LENGTH` in `core/constants.py`, applied to register, login-adjacent password-change, and CLI reset; 72 is bcrypt's effective limit). | `schemas/auth.py`, `core/constants.py` |
| OQ-009 | Two distinct removal paths, both verified: **(a) removed/inactive member** (membership deactivated, `DELETE /members/{id}` or leave) — their points/completions are **hidden** from the leaderboard (the member query filters `is_active = true` before aggregation) but the underlying `PointLedger` rows are untouched. **(b) account deletion** (`DELETE /users/me`, TASK-078) — the `User` row is hard-deleted and `PointLedger.user_id` is configured `ondelete="CASCADE"`, so that user's point history is permanently **removed**, not just hidden; `ChoreInstance.assignee_id` and `ChoreDefinition.created_by_id` are `SET NULL` instead, so chore history itself survives with the reference cleared. | `api/leaderboard.py`, `services/account_deletion.py`, `models/point_ledger.py` |

---

## 9. Open Questions

| ID | Question | Impact |
|----|----------|--------|
| OQ-004 | Should Admins be able to un-complete a chore (reversing the point award)? No such endpoint exists today (FR-049 holds: no undo). | PointLedger design, completion flow |
