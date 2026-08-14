# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**100 tasks complete, 4 pending (TASK-101 … TASK-104).** Completed task bodies
live in `docs/archive/tasks-completed.md`; the ledger below is the authoritative
history. New work: append tasks here as TASK-101+ following the same format
(self-contained body, acceptance criteria, ledger row).

---

## Status Ledger (updated 2026-07-16)

| Range | Status |
|---|---|
| TASK-001 … TASK-027 | ✅ Done (initial MVP build-out) — archived |
| TASK-028 … TASK-030 | ✅ Done (credential purge, IDOR fix, recurrence keys) — archived |
| TASK-031 | ✅ Done 2026-07-16 — slowapi rate limiting on `/auth/login` (5/min), `/auth/register` (10/h), `/auth/refresh` (30/min) per client IP; 429 + `Retry-After`; configurable via `RATE_LIMIT_*` settings; disabled suite-wide in tests with dedicated enable-and-assert tests. |
| TASK-032 … TASK-044 | ✅ Done (Dockerfile hardening, logout/revocation, enum validation, health probe, fixtures, headers/CORS, refresh endpoint, reassignment+pagination, invite mgmt, N+1, deps, scheduler UTC/lock) — archived. ⚠️ TASK-042's login regression was fixed by TASK-068 (archived). |
| TASK-045 … TASK-051 | ✅ Done, with follow-up defects fixed by TASK-054+ — archived (TASK-047's logout call was defeated by a caller bug, TASK-050 missed the refresh Dio, TASK-051 only fixed the banner) |
| TASK-052, TASK-053 | ✅ Done 2026-07-16 — admin chore reassignment UI (member-picker sheet, pending/overdue only) and invite management (list active invites with expiry, revoke, admin-gated) — archived. |
| TASK-054, TASK-055, TASK-056 | ✅ Done 2026-07-15 — INTERNET permission + cleartext network-security-config; logout ordering fixed; refresh interceptor hardened (retry marker, `/auth/` exclusion, shared-future queueing for concurrent 401s, timeouts) — archived. |
| TASK-057 | ✅ Done 2026-07-17 — runtime server URL: first-run setup screen with health-check test, secure-storage persistence, per-request baseUrl injection (no restart needed), change-server entry points on login/dashboard (logs out on change) — archived. |
| TASK-058, TASK-059, TASK-064 | ✅ Done 2026-07-17 — chores fetch pages until complete (limit=100, 10-page guard); mutations invalidate related providers (leaderboards, members, chores); post-completion UI shows server pointsAwarded — archived. |
| TASK-060, TASK-061, TASK-062 | ✅ Done 2026-07-17 — "Edit series" wired into the admin menu (past-date edits saveable); invite deep links via `choreapp:///join/<token>` QR + `/join/:token` route with logged-out stash-then-join; shared `friendlyErrorMessage` used by AppErrorWidget and all snackbars, rename flow error-handled — archived. |
| TASK-063 | ✅ Done 2026-07-17 — real applicationId (dev.ahzed11.choreapp — existing installs won't upgrade in place), "ChoreApp" label, keystore signing via key.properties/env with debug fallback, CI signing via ANDROID_KEYSTORE_* secrets, versionCode from CI run number — archived. |
| TASK-065, TASK-066, TASK-067 | ✅ Done 2026-07-17 — ~750 lines dead code removed, constants/avatar/confirm-complete dedup, `householdByIdProvider`/`isAdminProvider`; accessibility pass (semantic labels, 48dp targets via AccessibleTap); chore detail sheet, splash route, bundled Outfit font (google_fonts dropped), copyWith sentinel, single user-ID source, misc guards. Analyzer now clean with zero infos — CI runs strict `flutter analyze` — archived. |
| TASK-068, TASK-069 | ✅ Done 2026-07-15 — login fixed (`expires_delta` restored), stale integration test fixed; CI runs on all branches; ruff in CI; real coverage 95% against the 75% gate. 137/137 tests pass — archived. |
| TASK-070, TASK-071, TASK-072 | ✅ Done 2026-07-15 — `JWT_EXPIRY_MINUTES=30` (deprecated `JWT_EXPIRY_DAYS` fallback) + `JWT_SECRET` strength validation; chores list ORDER BY + 422 on bad filter params + reassign status guard; idempotent logout, daily expired-token cleanup, refresh-replay revokes the token family, typed `/auth/refresh` response — archived. |
| TASK-073, TASK-080 | ✅ Done 2026-07-16 — scheduler runs at startup + 6h misfire grace; backfill capped at `GRACE_DAYS` (default 3); one rotation lock per household per run; rotation-pointer modulo bug fixed; invite-accept row lock; test suite 2:46 → ~1:10 — archived. |
| TASK-074, TASK-075, TASK-076 | ✅ Done 2026-07-16 — `docker-compose.prod.yml` (GHCR image, migrations-on-start entrypoint); daily `pg_dump` backup sidecar + `make backup`/`make restore`; root `README.md` self-hosting guide — archived. ⚠️ Not runtime-verified (no container runtime in the review session). |
| TASK-077, TASK-078, TASK-079 | ✅ Done 2026-07-15 — `POST /users/me/password` + operator reset CLI; `DELETE /households/{id}` + `DELETE /users/me` (sole-admin guard, redistribution, token revocation, cascade-deletes the user's `PointLedger` rows); email lowercase normalization + `lower(email)` unique index; leaderboard UTC + exclusive window bounds — archived. |
| TASK-081 | ✅ Done 2026-07-17 — nightly per-household reminder summaries (due today + newly overdue, with assignees) via ntfy or Gotify; off unless `NOTIFY_URL` set; delivery failures never break the job; README setup section — archived. |
| TASK-082 | ✅ Done 2026-07-18 — multi-arch backend image: CI publishes a linux/amd64 + linux/arm64 manifest to GHCR (QEMU + buildx `platforms`), so ARM NAS/Raspberry Pi hosts pull a native variant — archived. |
| TASK-083 | ✅ Done 2026-08-05 — GroceryItem model + Alembic migration + Pydantic schemas — archived. |
| TASK-084 | ✅ Done 2026-08-05 — Groceries API router: CRUD + purchase/unpurchase (any member) — archived. |
| TASK-085 | ✅ Done 2026-08-05 — Router registered in main.py; 13 integration tests pass; suite 240/240 @ 97.3% — archived. |
| TASK-086 | ✅ Done 2026-08-05 — Flutter grocery model, API endpoint constants, Riverpod provider — archived. |
| TASK-087 | ✅ Done 2026-08-05 — Flutter grocery list screen, 4th bottom-nav tab, router route, widget tests — archived. |
| TASK-088 | ✅ Done 2026-08-05 — `.hermes.md` project context file created (repo map, test commands, Hermes-specific env notes: podman DB, uv path, Flutter path) — archived. |
| TASK-089 | ✅ Done 2026-08-05 — Claude-specific artifacts removed: CLAUDE.md, .claude/ dir, .gitignore Claude entries; .hermes.md is now the sole project context file — archived. |
|| TASK-090, TASK-091, TASK-092 | ✅ Done 2026-08-06 — grocery list polish: AppBar replaced with inline header matching other tabs (_darkText title); back-arrow button removed (regression test added); GroceriesNotifier add/update/delete now update state directly from API responses so the list refreshes immediately — archived. |
|| TASK-093, TASK-094, TASK-095, TASK-096 | ✅ Done 2026-08-07 — F-Droid auto-publishing pipeline: signed release APK published as a GitHub Release on main pushes (tag derived from pubspec versionName, duplicate-tag guard); chore-app-fdroid repo created from the xarantolus/fdroid template with apps.yaml + keystore/config stored as repo secrets; deterministic versionCode (MAJOR*10000+MINOR*100+PATCH) in pubspec + CI; README F-Droid install docs with repo URL + fingerprint — archived. |
| TASK-097 | ✅ Done 2026-08-07 — shared `AppBottomNavBar` widget replaces the four per-screen bottom-nav copies (single source of truth for icons/labels/order/navigation, `Key('bottom_nav_bar')` preserved); Leaderboard destination uses the trophy icon (`emoji_events_rounded`) on every tab; All Chores standardized on `checklist_rounded`; current-tab tap is a no-op — archived. |
| TASK-098 | ✅ Done 2026-08-07 — grocery screen header title is now the static "Groceries" instead of the household name; dead `householdsNotifierProvider` watch + import removed; regression test added (header shows "Groceries", household name absent); 217/217 tests pass, analyzer clean — archived. |
| TASK-099 | ✅ Done 2026-08-07 — release signing pinned: `Verify APK signing certificate` CI step fails on any signer drift or missing `ANDROID_APK_CERT_SHA256` (robust digest extraction, works with old & new apksigner output formats); releases fail-closed without a keystore (dedicated error step on main, release gated on keystore presence) — debug-signed releases are now impossible; permanent keystore generated (backup `~/.hermes/keystores/choreapp-release.jks`) and all 5 signing secrets set; v1.0.2 published as the first permanent-key release and its APK cert verified end-to-end — archived. |
| TASK-100 | ✅ Done 2026-08-07 — fdroid repo hardened: `check_signatures.py` guard in `update.sh` aborts (exit 3, no push) if any version's signer differs from the newest; it caught the push-triggered CI run resurrecting v1.0.0/v1.0.1 (metascoop indexes ALL GitHub releases — the broken releases were the poison source); those releases + tags deleted; index purged to only real-key 1.0.2; dispatched workflow green, live index shows exactly one signer — archived. |

---

## TASK-101: Backend — add a `dismissed` chore status (model, migration, schema)

**Domain**: Backend — chores data model
**Depends on**: none
**Branch**: `feat/dismiss-and-admin-complete` (shared with TASK-102..104)

**What & why**: "Dismissing" a task means closing it as done *without* awarding
points. `cancelled` already exists but carries a different meaning (the series
was deleted / no longer needed), and conflating the two would be a shortcut that
loses information later (e.g. leaders asking "how much was forgiven vs.
cancelled"). Add a distinct terminal status `dismissed` so the UI, leaderboard,
and future analytics can all tell "completed with points" apart from "closed,
no points".

**How to implement**:

1. `backend/app/models/chore_instance.py` — add `"dismissed"` to the
   `ChoreStatusEnum = Enum("pending", "complete", "overdue", "cancelled", ...)`
   (the enum's DB name is `chore_status`).
2. New Alembic migration (mirror the style of existing files under
   `backend/alembic/versions/`):
   `op.execute("ALTER TYPE chore_status ADD VALUE 'dismissed'")`.
   The project pins `postgres:16`, so adding an enum value is transaction-safe
   (PG ≥ 12). Downgrade is a no-op with a comment — PostgreSQL cannot remove
   enum values; document it as irreversible (standard for enum additions).
3. `backend/app/schemas/chore.py` — add `"dismissed"` to the
   `ChoreInstanceStatus` Literal (this is the `status_filter` query type on
   `GET /chores`). The response schema already uses `status: str`, no change.
4. `backend/app/api/chores.py` — add `"dismissed"` to `_TERMINAL_STATUSES` so
   the complete/reassign guards return 409 for dismissed instances too.
5. Audit touchpoints (no code change expected, but verify): `app/tasks/scheduler.py`
   only transitions `pending → overdue`, so dismissed instances are naturally
   left alone; `app/services/redistribution.py` and `account_deletion.py` act on
   pending/overdue only.

**Acceptance criteria**:
- `ChoreInstance.status` accepts `dismissed` end-to-end (DB enum + schema Literal).
- A migration applies cleanly with `alembic upgrade head`.
- `_TERMINAL_STATUSES` includes `dismissed`; existing complete/reassign 409
  behaviour is unchanged for the other statuses.
- `pytest tests/ -v` and `ruff check .` pass (no new failures from the enum
  addition).

---

## TASK-102: Backend — `dismiss` endpoint + admin-completes-for-assignee

**Domain**: Backend — chores API
**Depends on**: TASK-101
**Branch**: `feat/dismiss-and-admin-complete`

**What & why**:
- `POST /households/{household_id}/chores/{instance_id}/dismiss` — closes a
  chore as done with **zero points** (no `PointLedger` row).
- `POST /households/{household_id}/chores/{instance_id}/complete` — additionally
  allowed for **admins**, so an admin can mark a task done on behalf of the
  assignee; the points are credited to the **assignee**, never the admin.

**How to implement** (in `backend/app/api/chores.py`):

1. **Refactor the shared terminal-transition logic.** `complete_chore_instance`
   currently does: `SELECT … FOR UPDATE` → 404 if missing → 403 if
   `assignee_id != current_user.id` → 409 if terminal → compute points → update
   row → insert ledger → respond. Extract the lock/404/409 prologue into a small
   helper so `dismiss` and `complete` share it (avoid copy-paste drift).
2. **Permission rule (both endpoints):** allow when
   `instance.assignee_id == current_user.id` **or** `_membership.role == "admin"`.
   The endpoint already receives the membership via `require_household_member`,
   so read `.role` from it. Non-assignee, non-admin → 403 (keep the existing
   message for the complete endpoint; mirror it for dismiss).
3. **`complete` points go to the assignee:** change
   `PointLedger(user_id=current_user.id, …)` to
   `PointLedger(user_id=instance.assignee_id, …)`. For the assignee completing
   their own chore this is identical to today (assignee_id == current_user.id).
   **Edge case:** if `assignee_id` is `None` (member removed after assignment),
   complete the instance but skip the ledger row and leave `points_awarded`
   `NULL` (the `PointLedger.user_id` FK is non-nullable). Document this in the
   docstring.
4. **`dismiss` endpoint:** same prologue; set `status="dismissed"`,
   `completed_at=now`, `points_awarded=None`, insert **no** `PointLedger` row.
   Use `logger.info("chore.dismissed", …)`. Return `ChoreInstanceResponse` like
   `complete` does.
5. **Frontend-facing contracts:** add `choreDismiss` to
   `flutter_app/lib/core/api/api_endpoints.dart`
   (`/households/$hId/chores/$cId/dismiss`). No change to `complete`'s path.
6. **Integration tests** (extend `backend/tests/test_completion.py`, following
   its existing fixtures):
   - assignee dismisses own pending chore → 200, `status=dismissed`,
     `points_awarded is null`, and `point_ledger` has **no** row for the
     instance (leaderboard totals unchanged).
   - admin dismisses a member's chore → 200, same assertions.
   - non-assignee non-admin dismisses → 403.
   - dismiss an already-complete/cancelled instance → 409.
   - admin completes a member's chore → 200, `points_awarded == EFFORT_POINTS[...]`,
     and the `PointLedger` row's `user_id == assignee_id` (not the admin).
   - assignee completes their own → unchanged behaviour (points to self).
   - non-assignee non-admin completes → still 403.

**Acceptance criteria**: all tests above pass; `pytest` + `ruff` green; the
existing 97% coverage gate is not regressed (dismiss path and admin-complete
path are both exercised).

---

## TASK-103: Flutter — model, API constants, and provider support for dismiss + admin-complete

**Domain**: Flutter frontend — chores data layer
**Depends on**: TASK-102 (endpoints must exist)
**Branch**: `feat/dismiss-and-admin-complete`

**How to implement**:

1. `lib/core/api/api_endpoints.dart` — add `choreDismiss(hId, cId)` (done in
   TASK-102, verify it's present).
2. `lib/features/chores/models/chore_model.dart`:
   - `statusColor` switch: add `case 'dismissed':` → grey (reuse the cancelled
     grey `0xFF9E9E9E`, or a distinct muted tone — decide and be consistent).
   - `fromJson`/`toJson` already pass `status` through as a String; no new field
     needed. `pointsAwarded` is already nullable.
   - Audit `isOverdue`: it keys off `status == 'overdue'` (or pending + past
     due); dismissed must not read as overdue (verify, no change expected).
3. `lib/features/chores/providers/chores_provider.dart`:
   - Add `dismissChore(String instanceId)` mirroring `completeChore`: optimistic
     update (`status: 'dismissed'`, `completedAt: now`, `pointsAwarded: null`),
     `POST` to `choreDismiss`, replace with the authoritative server response on
     success, revert on failure. **Do not** invalidate the leaderboard providers
     (dismiss awards nothing); *do* leave the chores list provider state correct.
   - `completeChore` already posts to `complete`; add no new provider method for
     admin-complete — the admin UI reuses `completeChore` (the backend now
     authorizes admins and credits the assignee). Ensure the success snackbar
     shows the *assignee's* name when an admin completed it (UI concern, see
     TASK-104).

**Acceptance criteria**: `flutter analyze` clean; existing widget tests still
pass (no behaviour change for the complete path). A unit test for
`ChoreModel.fromJson` with `status: "dismissed"` and `points_awarded: null`
round-trips correctly.

---

## TASK-104: Flutter — UI: dismiss action + admin "mark done for X"

**Domain**: Flutter frontend — chores UI
**Depends on**: TASK-103
**Branch**: `feat/dismiss-and-admin-complete`

**How to implement** (all under `lib/features/chores/`):

1. **Chore card** (`widgets/chore_card.dart`):
   - Long-press currently opens the admin menu only for admins. Give **every**
     assignee a way to dismiss their own task: either a long-press menu for
     assignees too, or a secondary "dismiss" affordance on the card (decide and
     keep it discoverable but not noisy). The admin long-press menu gains two
     new entries:
     - `Mark done for {assigneeName}` (disabled/hidden when `assigneeId` is null)
     - `Dismiss` (no points)
   - Points pill (`_PointsPill(points: chore.pointsAwarded ?? chore.pointValue)`):
     for `status == 'dismissed'` render "No points" (or "0 pts") — do **not**
     fall back to `pointValue`, which would falsely show a dismissed task as
     worth points.
   - Complete button: hide/disable it for `dismissed` chores (it's terminal).
2. **Confirmation sheet** — add a `showChoreDismissSheet` (mirror
   `showChoreCompleteSheet`), but the info box reads
   "Complete this task without awarding points?" (no star/points callout), and
   the confirm button says "Dismiss". On confirm, call `dismissChore` and show a
   "Task dismissed — no points awarded" snackbar (with a distinct error path for
   403/409).
3. **Admin mark-done flow** — reuse `confirmCompleteChore`; when the current user
   is not the assignee, the success snackbar must say
   "Marked done for {assigneeName} — {points} points" instead of
   "You earned {points} points". The server response carries `assignee_name`.
4. **Lists / filters / counts** (`screens/chore_list_screen.dart`,
   `screens/my_chores_screen.dart`):
   - `_applyFilter`: `case 'done'` → `c.status == 'complete' || c.status == 'dismissed'`;
     the leading `if (c.status == 'cancelled') return false;` stays (dismissed
     remains visible under 'all' and 'done').
   - Pending count: exclude `dismissed` alongside `cancelled`/`complete`.
   - My Chores: exclude `dismissed` from the "todo" list (`status != 'cancelled'
     && status != 'dismissed'`); include it in the "done" tab; the weekly-points
     banner must count dismissed chores as **0** points
     (`c.status == 'dismissed' ? 0 : (c.pointsAwarded ?? c.pointValue)`).
5. **Widget tests** — extend `test/features/chores/*_test.dart`: dismiss shows
   "No points" and moves to done; admin menu shows both new actions; admin
   mark-done-for-assignee shows the correct snackbar and the assignee's name.
6. **Release note / version**: bump `flutter_app/pubspec.yaml` version
   (patch: `1.0.3+10003`) before merging — the F-Droid update flow depends on it.

**Acceptance criteria**: `flutter analyze` clean; `flutter test` green with the
new widget tests; a dismissed task never awards points anywhere in the UI; an
admin can complete any pending/overdue task on the assignee's behalf and the
assignee is credited on the leaderboard.

---