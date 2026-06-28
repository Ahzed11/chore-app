# Requirements Document — Household Chores Motivation App

**Version**: 1.0  
**Date**: 2026-06-25  
**Status**: Approved for MVP development

---

## 1. Project Overview

### Purpose

The household chores motivation app helps cohabitants coordinate, distribute, and stay accountable for domestic tasks. It replaces informal agreements and paper lists with a structured, gamified system that turns chore completion into a competitive but cooperative experience.

### Target Users

- Shared-housing groups (flatmates, student accommodations, co-living spaces)
- Families with multiple participating members
- Any group of people who share a physical living space and want visibility into who is doing what

### Goals

1. Eliminate ambiguity about chore ownership and status
2. Distribute household workload fairly through automatic round-robin assignment
3. Motivate sustained participation through a lightweight points-and-leaderboard system
4. Support multiple households per user account (a person may live in more than one shared space, or be an admin of one while a member of another)

### MVP Platform

Android (Flutter). Backend served via FastAPI on PostgreSQL.

---

## 2. Functional Requirements

### 2.1 Authentication

| ID | Requirement |
|----|-------------|
| FR-001 | The system shall allow any visitor to register a new account using an email address and a password. |
| FR-002 | The system shall validate that the email address is unique at registration time and return a clear error if it is already taken. |
| FR-003 | Passwords shall be stored as a salted hash (bcrypt or equivalent). Plaintext passwords must never be persisted or logged. |
| FR-004 | The system shall authenticate a registered user via email and password, returning a signed JWT access token on success. |
| FR-005 | The JWT shall carry the user's ID and have a configurable expiry (default 7 days for MVP). |
| FR-006 | All API endpoints except registration and login shall require a valid JWT in the `Authorization: Bearer <token>` header. |
| FR-007 | The system shall return HTTP 401 on missing or expired tokens and HTTP 403 on insufficient role permissions. |

### 2.2 User Profile

| ID | Requirement |
|----|-------------|
| FR-008 | Each user account shall store: unique ID, email, display name, hashed password, and account creation timestamp. |
| FR-009 | A user shall be able to retrieve their own profile via an authenticated endpoint. |
| FR-010 | A user shall be able to update their own display name. |

### 2.3 Households

| ID | Requirement |
|----|-------------|
| FR-011 | Any authenticated user shall be able to create a new household by providing a name. The creating user automatically becomes the Admin of that household. |
| FR-012 | A household shall store: unique ID, name, creation timestamp, and the ordered join-date list used by the round-robin rotation. |
| FR-013 | There is no cap on the number of members in a household. |
| FR-014 | A user may belong to multiple households simultaneously, holding an independent role in each. |
| FR-015 | An Admin shall be able to generate an invite link and a QR code (derived from the same invite token) for the household. |
| FR-016 | An invite token shall be a short-lived, single-use or time-limited token (exact TTL: open question OQ-001). |
| FR-017 | Any authenticated user who follows a valid invite link shall be added to the household as a Member. |
| FR-018 | An Admin shall be able to remove any member (other than themselves) from the household. |
| FR-019 | An Admin shall be able to promote a Member to Admin or demote an Admin to Member, provided at least one Admin always remains in the household. |
| FR-020 | An Admin shall be able to view the full member list, including each member's role and join date. |
| FR-021 | A Member shall be able to view the member list (read-only). |
| FR-022 | A user shall be able to leave a household voluntarily. If the leaving user is the sole Admin, the system shall either block the action or auto-promote the longest-standing member (see OQ-002). |
| FR-023 | Household name shall be editable by Admins only. |

### 2.4 Chores

| ID | Requirement |
|----|-------------|
| FR-024 | An Admin shall be able to create a chore with the following fields: title (required), description (optional), category (required, from fixed list), effort level (required: Easy / Medium / Hard), assignee (optional — triggers manual assignment), due date, and recurrence rule. |
| FR-025 | Effort levels shall map to fixed point values: Easy = 10 pts, Medium = 25 pts, Hard = 50 pts. These values are fixed for MVP and shall not be overridable per chore. |
| FR-026 | Categories shall be restricted to the following predefined values: Kitchen, Bathroom, Bedroom, Living Room, Laundry Room, Garden / Outdoor, Garage, Other / General. |
| FR-027 | A chore shall be one of two types: **one-off** (single instance, no recurrence) or **recurring** (repeats on a defined interval). |
| FR-028 | Recurrence intervals shall support: every N days, every N weeks, every N months, where N is a positive integer. |
| FR-029 | For recurring chores, the Admin provides a first due date and a recurrence rule. The system generates subsequent instances automatically. |
| FR-030 | A chore instance shall store: unique ID, parent chore ID (for recurring), household ID, title, description, category, effort level, assignee (user ID), due date, status (pending / complete / overdue), completion timestamp, and points awarded. |
| FR-031 | An Admin shall be able to edit the definition of a recurring chore (title, description, category, effort level, recurrence rule). Edits apply to future instances only; completed instances are immutable. |
| FR-032 | An Admin shall be able to delete a chore or a recurring chore series. Deleting a recurring series cancels future ungenerated instances and marks pending generated instances as cancelled. Completed instances are preserved as historical records. |
| FR-033 | All household members (Admin and Member) shall be able to view all chores in the household, including who is assigned to each. |
| FR-034 | Members shall be able to filter the chore list by: status (pending, complete, overdue), category, and assignee. |
| FR-035 | When a chore instance's due date passes without completion, the system shall flag its status as overdue. No point penalty is applied. |
| FR-036 | Overdue chores remain assigned to the original assignee. They are not automatically reassigned. |

### 2.5 Assignment Algorithm

| ID | Requirement |
|----|-------------|
| FR-037 | When a chore is created without an explicit assignee, the system shall auto-assign it to the next member in the household's round-robin rotation. |
| FR-038 | The round-robin rotation order is determined by join date, oldest member first. |
| FR-039 | The rotation maintains a pointer (current index) that advances by one after each auto-assignment. |
| FR-040 | Manual assignment by an Admin (explicit assignee on creation or reassignment) shall NOT advance the round-robin pointer. |
| FR-041 | The assignment engine shall be implemented as a pluggable service/strategy interface so that alternative strategies (e.g. workload balancing) can be substituted in the future without changing the calling code. |
| FR-042 | When a member is removed from a household, all their pending (incomplete) chore instances shall be redistributed to the remaining members via the round-robin algorithm. |
| FR-043 | If only one member remains in the household, all chores are assigned to that member. |
| FR-044 | If a household has no members (all removed or left), pending chores are placed in an unassigned state and assigned when the next member joins (see OQ-003). |
| FR-045 | Chores created before any member has joined the household are placed in an unassigned queue and auto-assigned when the first member joins. |

### 2.6 Completion and Points

| ID | Requirement |
|----|-------------|
| FR-046 | A member shall be able to mark a chore instance as complete only if they are the assigned member for that instance. |
| FR-047 | Completing a chore instance awards the effort-level point value to the member's score within that specific household immediately, with no admin approval step. |
| FR-048 | Points are scoped per household-member pair. A user's points in household A are entirely independent of their points in household B. |
| FR-049 | Once a chore instance is marked complete, it cannot be un-completed (no undo). See OQ-004 for potential future override. |
| FR-050 | Completing a chore instance records: completion timestamp, points awarded, and the completing user ID. |

### 2.7 Leaderboard

| ID | Requirement |
|----|-------------|
| FR-051 | Each household shall have a leaderboard ranking all members by points earned within that household. |
| FR-052 | The leaderboard shall support three time scopes selectable by the user: **All-time** (no date filter), **This week** (Monday 00:00 to Sunday 23:59 in UTC), **This month** (first day to last day of the current calendar month in UTC). |
| FR-053 | Each leaderboard entry shall display: rank, member display name, total points in scope, and number of chores completed in scope. |
| FR-054 | Members with equal points shall share the same rank (dense ranking). |
| FR-055 | The leaderboard endpoint shall return data for the requesting user's current scope so the client can highlight the requesting user's own row. |

---

## 3. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-001 | **Performance — API latency**: All CRUD endpoints shall respond within 300 ms at the 95th percentile under normal load (up to 100 concurrent users per household). |
| NFR-002 | **Performance — Leaderboard**: Leaderboard queries shall complete within 500 ms even for households with up to 100 members and 10,000 historical chore records. |
| NFR-003 | **Security — Passwords**: Passwords shall be hashed with bcrypt (cost factor >= 12) before storage. |
| NFR-004 | **Security — JWT**: JWT tokens shall be signed with HS256 or RS256. The signing secret/key shall not be hardcoded and shall be injected via environment variable. |
| NFR-005 | **Security — Authorisation**: Every API endpoint that acts on a household resource must verify that the requesting user is a member of that household. Household data must never leak to non-members. |
| NFR-006 | **Security — Invite tokens**: Invite tokens shall be cryptographically random (minimum 128 bits of entropy) and must be invalidated after use or expiry. |
| NFR-007 | **Scalability**: The database schema shall support horizontal read scaling (read replicas) without schema changes. Write operations shall be serialisable for the round-robin pointer update to prevent double-assignment. |
| NFR-008 | **Reliability — Scheduler**: The background job that generates recurring chore instances and flags overdue chores shall be idempotent. Re-running it must not create duplicate instances. |
| NFR-009 | **Usability — Mobile**: All primary user flows (view chores, mark complete, view leaderboard) shall be completable in three taps or fewer from the app's home screen. |
| NFR-010 | **Usability — Accessibility**: Text contrast ratios shall meet WCAG 2.1 AA minimum on all screens. |
| NFR-011 | **Maintainability**: Backend code shall achieve at least 80% line coverage via automated tests. Critical paths (auth, assignment engine, points award) shall be at 100% coverage. |
| NFR-012 | **Data integrity**: Awarding points and marking a chore complete shall occur in a single database transaction to prevent partial states. |
| NFR-013 | **Observability**: The API shall emit structured JSON logs including request ID, user ID (where available), endpoint, status code, and duration. |

---

## 4. Roles and Permissions Matrix

| Action | Admin | Member | Unauthenticated |
|--------|-------|--------|-----------------|
| Register account | N/A | N/A | Yes |
| Login | Yes | Yes | Yes |
| View own profile | Yes | Yes | No |
| Update own display name | Yes | Yes | No |
| Create household | Yes | Yes | No |
| View household details | Yes | Yes | No |
| Edit household name | Yes | No | No |
| Delete household | Yes | No | No |
| Generate invite link / QR | Yes | No | No |
| Join household via invite | Yes (as Member) | Yes (as Member) | No |
| View member list | Yes | Yes | No |
| Remove member | Yes | No | No |
| Change member role | Yes | No | No |
| Leave household | Yes* | Yes | No |
| Create chore | Yes | No | No |
| Edit chore definition | Yes | No | No |
| Delete chore / series | Yes | No | No |
| View all household chores | Yes | Yes | No |
| Manually assign chore | Yes | No | No |
| Mark assigned chore complete | Yes** | Yes** | No |
| View leaderboard | Yes | Yes | No |

\* An Admin may leave only if at least one other Admin remains, or if the system auto-promotes a successor (see OQ-002).  
\*\* Only for chores assigned to themselves.

---

## 5. User Stories

### Authentication

- US-001: As a new user, I want to register with my email and a password so that I can access the app.
- US-002: As a registered user, I want to log in with my email and password so that I can access my households and chores.
- US-003: As a logged-in user, I want my session to persist for at least a week so that I do not have to re-authenticate daily.

### Households

- US-004: As a user, I want to create a household and name it so that I can start organising chores for my living space.
- US-005: As an Admin, I want to generate an invite link and QR code so that I can easily onboard flatmates without needing their email addresses upfront.
- US-006: As a user, I want to join a household by tapping an invite link so that I can participate in that group's chore system.
- US-007: As an Admin, I want to remove a member who has moved out so that the chore rotation reflects the current occupants.
- US-008: As an Admin, I want to promote a trusted member to Admin so that household management responsibilities can be shared.
- US-009: As a user, I want to belong to multiple households so that I can manage chores in my flat and at a family home from the same account.

### Chores

- US-010: As an Admin, I want to create a recurring chore (e.g. "Vacuum living room" every 7 days) so that the system automatically generates and assigns it without me having to remember.
- US-011: As an Admin, I want to create a one-off chore and assign it to a specific member so that I can handle exceptions without disrupting the rotation.
- US-012: As a Member, I want to see all chores in my household (including who is responsible for each) so that I have full transparency into the workload distribution.
- US-013: As a Member, I want to filter chores by status and category so that I can quickly find what is pending in the kitchen this week.
- US-014: As an Admin, I want overdue chores to be automatically flagged so that I can follow up without manually tracking due dates.

### Assignment

- US-015: As an Admin, I want new chores to be automatically assigned in rotation so that the workload is distributed fairly without manual effort.
- US-016: As an Admin, I want manual assignment to be available so that I can override the rotation for specific situations.
- US-017: As an Admin, I want pending chores to be redistributed when I remove a member so that no task is left unowned.

### Completion and Points

- US-018: As a Member, I want to mark my assigned chore as complete and immediately see my points increase so that I feel rewarded for my contribution.
- US-019: As a Member, I want my points to be tracked separately for each household so that my score in one flat does not affect another.

### Leaderboard

- US-020: As a Member, I want to see a leaderboard of my household ranked by points so that I can gauge how I compare to my flatmates.
- US-021: As a Member, I want to switch the leaderboard between all-time, this week, and this month so that I can see both long-term and recent performance.
- US-022: As a Member, I want to see how many chores each person has completed alongside their points so that I understand the full picture of contribution.

---

## 6. Business Rules and Edge Cases

### BR-001: Round-Robin with a Single Member
If a household has only one member, all auto-assigned chores go to that member. The rotation pointer still advances (it simply wraps back to index 0), ready for when additional members join.

### BR-002: Round-Robin Pointer After Member Removal
When a member is removed, their position is removed from the rotation list. If the rotation pointer was pointing at or past the removed position, it is adjusted so it does not skip the next eligible member. The redistribution of the removed member's chores uses the standard round-robin starting from the current pointer position.

### BR-003: Household with No Members
If all members leave or are removed, the household still exists. Pending chore instances are placed in an unassigned state. When the next member joins, unassigned chores are auto-assigned starting from that member (rotation restarts from index 0).

### BR-004: Chore Created Before Any Member Has Joined
An Admin can create a household and define chores before inviting anyone. Chores created at this point are placed in an unassigned queue. When the first member joins, the queue is processed via round-robin.

### BR-005: Member Rejoining a Household
If a user leaves and rejoins the same household, they are treated as a new member for rotation purposes: they are appended to the end of the rotation order with a new join timestamp. Their historical points and completed chores from the previous membership are preserved as a separate record and are not merged with the new membership period (see OQ-005).

### BR-006: Admin Removing Themselves
An Admin cannot remove themselves via the member-removal flow if they are the sole Admin. They must either promote another member first or leave via the leave-household flow (which triggers OQ-002 resolution).

### BR-007: Recurring Chore Instance Generation Timing
A recurring chore instance is generated on the day it becomes due (or a configurable number of days in advance — see OQ-006). The background scheduler runs at least once per day. Idempotency is enforced by checking whether an instance for a given (parent chore ID, due date) already exists before inserting.

### BR-008: Completing a Chore Already Flagged Overdue
A member may still mark an overdue chore as complete. Points are awarded normally. The completion timestamp is recorded accurately; no penalty is deducted.

### BR-009: Effort Level Points Are Fixed
Point values (Easy = 10, Medium = 25, Hard = 50) are fixed constants for MVP. They must not be stored as configurable per-household or per-chore values in the MVP schema, but the schema should not make them impossible to make configurable later.

### BR-010: Leaderboard Week Boundary
"This week" is always Monday 00:00 UTC through Sunday 23:59:59 UTC of the current ISO week. The API computes the window server-side based on the request timestamp; the client does not send date parameters.

### BR-011: Leaderboard Month Boundary
"This month" spans from the first calendar day of the current month at 00:00 UTC to the last calendar day at 23:59:59 UTC, computed server-side.

### BR-012: Chore Deletion — Completed Instances Preserved
Deleting a recurring chore series removes the parent chore definition and cancels all pending instances. Completed instances are orphaned (parent ID still referenced) but remain in the database to preserve historical points and leaderboard accuracy.

### BR-013: Simultaneous Completion Attempts
If two clients attempt to mark the same chore as complete at the same time (e.g. a race condition), only the first transaction shall succeed. The database transaction with a row-level lock on the chore instance prevents double point award.

### BR-014: Role Change Does Not Affect Points
Promoting a Member to Admin or demoting an Admin to Member has no effect on that user's accumulated points or completed chore history.

---

## 7. Data Model Sketch

### User
- `id` (UUID, PK)
- `email` (string, unique, indexed)
- `display_name` (string)
- `password_hash` (string)
- `created_at` (timestamp)

### Household
- `id` (UUID, PK)
- `name` (string)
- `created_at` (timestamp)
- `rotation_pointer` (integer, default 0) — index into the ordered member list for round-robin

### HouseholdMembership
- `id` (UUID, PK)
- `household_id` (FK → Household)
- `user_id` (FK → User)
- `role` (enum: admin / member)
- `joined_at` (timestamp) — determines rotation order
- `is_active` (boolean) — false when member has left or been removed
- Unique constraint: (`household_id`, `user_id`) where `is_active = true`

### InviteToken
- `id` (UUID, PK)
- `household_id` (FK → Household)
- `token` (string, unique, cryptographically random)
- `created_by` (FK → User)
- `created_at` (timestamp)
- `expires_at` (timestamp)
- `used_at` (timestamp, nullable) — null if still valid

### ChoreDefinition (parent for recurring chores; also used for one-off)
- `id` (UUID, PK)
- `household_id` (FK → Household)
- `title` (string)
- `description` (string, nullable)
- `category` (enum: kitchen / bathroom / bedroom / living_room / laundry_room / garden_outdoor / garage / other_general)
- `effort_level` (enum: easy / medium / hard)
- `chore_type` (enum: one_off / recurring)
- `recurrence_rule` (JSONB, nullable) — stores interval unit (days/weeks/months) and N value
- `first_due_date` (date)
- `created_by` (FK → User)
- `created_at` (timestamp)
- `is_active` (boolean) — false when series is deleted

### ChoreInstance
- `id` (UUID, PK)
- `definition_id` (FK → ChoreDefinition)
- `household_id` (FK → Household, denormalised for query performance)
- `assignee_id` (FK → User, nullable — null = unassigned)
- `assigned_manually` (boolean)
- `due_date` (date)
- `status` (enum: pending / complete / overdue / cancelled)
- `completed_at` (timestamp, nullable)
- `points_awarded` (integer, nullable)
- `created_at` (timestamp)
- Unique constraint: (`definition_id`, `due_date`) — prevents duplicate recurring instances

### PointLedger
- `id` (UUID, PK)
- `household_id` (FK → Household)
- `user_id` (FK → User)
- `chore_instance_id` (FK → ChoreInstance)
- `points` (integer)
- `awarded_at` (timestamp)

> Note: The leaderboard is derived from `PointLedger` aggregated by time scope. A materialised view or cache may be added later for performance, but raw aggregation is acceptable for MVP.

### Relationships Summary
- User ←→ Household: many-to-many via HouseholdMembership
- Household → ChoreDefinition: one-to-many
- ChoreDefinition → ChoreInstance: one-to-many
- ChoreInstance → PointLedger: one-to-one (at most one ledger entry per completed instance)
- User → PointLedger: one-to-many

---

## 8. Out of Scope for MVP

The following features have been explicitly identified as post-MVP. They must be documented here so the data model and architecture do not inadvertently prevent them, but no implementation work shall be done:

| Feature | Notes |
|---------|-------|
| Avatar system | Each user selects a customisable cute-animal avatar. Design should allow a future `avatar_id` FK on User. |
| Cosmetics shop | Spend points on hats, accessories, backgrounds for avatars. Requires a point-spend transaction type in PointLedger. |
| Push notifications | Alerts for upcoming and overdue chores. Requires a device token registry. |
| Admin-configurable assignment strategy | Per-household selection of round-robin vs. workload-balancing or other strategies. The pluggable strategy interface in FR-041 anticipates this. |
| Photo proof on completion | Optional image attachment when marking a chore complete. |
| Expanded categories | Category list may grow based on user feedback. The enum should be designed for forward migration. |

---

## 9. Open Questions

| ID | Question | Impact | Owner |
|----|----------|--------|-------|
| OQ-001 | What is the TTL for invite tokens? Should they be single-use, time-limited, or both? | Affects InviteToken schema and security posture | Product |
| OQ-002 | When the sole Admin leaves a household, should the system block the action and force promotion first, or auto-promote the longest-standing active member? | Affects leave-household flow and error messaging | Product |
| OQ-003 | When all members leave a household, should pending chores retain their due dates or be suspended until a new member joins? | Affects overdue flagging logic for empty households | Product |
| OQ-004 | Should Admins have the ability to un-complete a chore (e.g. to correct a mistaken tap)? This would require reversing the point award. | Affects PointLedger design and completion flow | Product |
| OQ-005 | When a user rejoins a household, should their historical points from the previous membership be visible on the leaderboard or treated as a separate membership record? | Affects leaderboard query and HouseholdMembership schema | Product |
| OQ-006 | How far in advance should the scheduler generate upcoming recurring chore instances? (e.g. generate next instance immediately upon completion, or generate N days ahead on a daily job) | Affects scheduler design and user experience (can members see upcoming chores?) | Product |
| OQ-007 | Should the "This week" leaderboard scope use the server's UTC week or the user's local time zone? | Affects leaderboard query logic and potential timezone storage on User | Product |
| OQ-008 | Is there a minimum password length or complexity requirement? | Affects FR-001 validation and error messaging | Product |
| OQ-009 | Should a removed member's completed chores appear in the leaderboard historical view, or be hidden? | Affects leaderboard query join conditions | Product |
