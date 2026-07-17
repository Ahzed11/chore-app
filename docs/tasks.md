# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

Completed task bodies (TASK-001–059, 063, 064, 068–080 — 74 tasks) have been moved to
`docs/archive/tasks-completed.md` to keep this file scannable. Only open work is
detailed below; the ledger covers the full history.

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
| TASK-060, TASK-061, TASK-062 | ⏳ Open — chore edit wiring, invite deep links, friendly error messages |
| TASK-063 | ✅ Done 2026-07-17 — real applicationId (dev.ahzed11.choreapp — existing installs won't upgrade in place), "ChoreApp" label, keystore signing via key.properties/env with debug fallback, CI signing via ANDROID_KEYSTORE_* secrets, versionCode from CI run number — archived. |
| TASK-065, TASK-066, TASK-067 | ⏳ Open — dedup/dead code, accessibility pass, low-priority fix batch |
| TASK-068, TASK-069 | ✅ Done 2026-07-15 — login fixed (`expires_delta` restored), stale integration test fixed; CI runs on all branches; ruff in CI; real coverage 95% against the 75% gate. 137/137 tests pass — archived. |
| TASK-070, TASK-071, TASK-072 | ✅ Done 2026-07-15 — `JWT_EXPIRY_MINUTES=30` (deprecated `JWT_EXPIRY_DAYS` fallback) + `JWT_SECRET` strength validation; chores list ORDER BY + 422 on bad filter params + reassign status guard; idempotent logout, daily expired-token cleanup, refresh-replay revokes the token family, typed `/auth/refresh` response — archived. |
| TASK-073, TASK-080 | ✅ Done 2026-07-16 — scheduler runs at startup + 6h misfire grace; backfill capped at `GRACE_DAYS` (default 3); one rotation lock per household per run; rotation-pointer modulo bug fixed; invite-accept row lock; test suite 2:46 → ~1:10 — archived. |
| TASK-074, TASK-075, TASK-076 | ✅ Done 2026-07-16 — `docker-compose.prod.yml` (GHCR image, migrations-on-start entrypoint); daily `pg_dump` backup sidecar + `make backup`/`make restore`; root `README.md` self-hosting guide — archived. ⚠️ Not runtime-verified (no container runtime in the review session). |
| TASK-077, TASK-078, TASK-079 | ✅ Done 2026-07-15 — `POST /users/me/password` + operator reset CLI; `DELETE /households/{id}` + `DELETE /users/me` (sole-admin guard, redistribution, token revocation, cascade-deletes the user's `PointLedger` rows); email lowercase normalization + `lower(email)` unique index; leaderboard UTC + exclusive window bounds — archived. |
| TASK-081 | ⏳ Open — ntfy/Gotify notifications (`docs/archive/backend-report-2026-07-15.md` L10) |

---

## TASK-060: Flutter — Wire Up Chore Editing (Currently Unreachable)

**Domain**: Flutter  
**Priority**: High  
**Depends on**: none  
**Source**: `docs/archive/frontend-report-2026-07-15.md` F-8

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
**Source**: `docs/archive/frontend-report-2026-07-15.md` F-10

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
**Source**: `docs/archive/frontend-report-2026-07-15.md` F-12, F-13

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
## TASK-065: Flutter — Dead Code Removal and Constant Deduplication

**Domain**: Flutter  
**Priority**: Medium  
**Depends on**: none  
**Source**: `docs/archive/frontend-report-2026-07-15.md` F-15, F-16

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
**Source**: `docs/archive/frontend-report-2026-07-15.md` F-19

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
**Source**: `docs/archive/frontend-report-2026-07-15.md` F-17, F-21, F-22, F-23, F-25, F-26, F-27, F-28

Small independent fixes, safe to do in one PR:
1. **Chore description is write-only** (F-17): show it — e.g. tap a chore card to expand or open a detail bottom sheet displaying description, category, assignee, due date, recurrence.
2. **`AuthState.copyWith` token trap** (F-21, `auth_state.dart:60-65`): `token ?? this.token` makes clearing impossible; use the sentinel pattern already used in `ChoreFilter.copyWith`.
3. **Two sources of current-user ID** (F-22): standardize on `currentUserProvider` (`GET /users/me`); remove the client-side JWT decode in `leaderboard_provider.dart:19-45` and the usage in `chore_list_screen.dart:179`.
4. **Empty displayName crash** (F-23): guard `displayName[0]` at `household_management_screen.dart:869,1022` like the other avatar widgets do.
5. **Cold-start login flash** (F-25): add a splash/loading route while auth status is `unknown` (`app_router.dart:86-88`).
6. **Bundle the Outfit font** (F-26): add font assets and `GoogleFonts.config.allowRuntimeFetching = false` so LAN-only installs render correctly on first run.
7. **Pull-to-refresh on management screen** (F-27): wrap the `SingleChildScrollView` at `household_management_screen.dart:216` in a `RefreshIndicator` invalidating the members provider.
8. **Dependency bumps** (F-28): raise `flutter_lints`, `go_router`, `intl`, `share_plus` to current majors; fix any resulting deprecations. Also clear the ~17 info-level analyzer findings reported by Flutter stable ≥3.44 (Radio `groupValue`/`onChanged` → `RadioGroup`, `DropdownButtonFormField.value` → `initialValue`, `prefer_const_constructors` in `create_chore_screen.dart` and `household_management_screen.dart`) — CI currently runs `flutter analyze --no-fatal-infos`, so these are reported but not blocking; once cleared, consider dropping the flag.
9. **`test/widget_test.dart` uses real `FlutterSecureStorage`** (F-20): `_initialize()` throws `MissingPluginException` in the test environment (`auth_state.dart:79-86` has no try/catch). Override the storage/auth provider in the test, and add a try/catch around storage reads in `_initialize` so a broken keystore degrades to logged-out instead of crashing.

**Acceptance criteria**:
- [ ] Each numbered item verified individually; `flutter analyze` and `flutter test` green.
- [ ] Chore description is visible somewhere in the UI.

---
## TASK-081: Backend — Chore Reminder Notifications via ntfy/Gotify Webhook

**Domain**: Backend  
**Priority**: Low (next feature milestone)  
**Depends on**: TASK-073  
**Source**: `docs/archive/backend-report-2026-07-15.md` L10

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
