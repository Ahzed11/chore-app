# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**89 tasks complete, 3 pending.** Completed task bodies live in
`docs/archive/tasks-completed.md`; the ledger below is the authoritative
history. New work: append tasks here as TASK-090+ following the same format
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
| TASK-090 | ⏳ Pending — GroceryListScreen theming: remove AppBar, use inline header matching ChoreListScreen pattern |
| TASK-091 | ⏳ Pending — GroceryListScreen: remove the back-arrow button (bottom nav already handles navigation) |
| TASK-092 | ⏳ Pending — GroceriesNotifier: fix addItem/updateItem/deleteItem to update state directly from API responses so the list refreshes immediately |

---

## TASK-090 — GroceryListScreen theming: match other screens' style

**Domain**: Flutter frontend — groceries feature
**Depends on**: None
**Branch**: `fix/grocery-list-polish`

The current `GroceryListScreen` uses a `Scaffold.appBar` with `AppBar(backgroundColor: Colors.white, ...)` and an inline title styled with the `_teal` color. The other screens in the app (e.g. `ChoreListScreen`) embed their header as the first child of the `Scaffold.body > SafeArea > Column`, with no `appBar` parameter at all. The title uses the `_darkText` color and the header area follows a consistent layout.

**Acceptance criteria**:
1. `GroceryListScreen` no longer passes an `appBar` to `Scaffold` — the header is rendered inline in the `body` column, matching `ChoreListScreen`'s structure.
2. The household name text uses the `_darkText` color (`Color(0xFF0F2E2C)`) with `fontSize: 30`, `fontWeight: FontWeight.w700`, and `letterSpacing: -0.5` — exactly matching `_ChoreListHeader`.
3. The `_teal` constant is removed from `grocery_list_screen.dart` if unused after the refactor (it's still used by the add button and checkbox, so keep it — but the `_darkText` constant must be added).
4. The bottom `_GroceryBottomNav` widget is unchanged and still rendered via `Scaffold.bottomNavigationBar`.
5. The widget tests in `grocery_list_screen_test.dart` pass without modification.
6. `flutter analyze` returns zero errors.

**Why AppBar is wrong here**: The other screens (chores, my-chores, leaderboard) all use inline headers. AppBar with just a title and leading button is an odd-one-out that makes the grocery screen feel like a different app.

---

## TASK-091 — GroceryListScreen: remove back-arrow button

**Domain**: Flutter frontend — groceries feature
**Depends on**: TASK-090 (same file, same header area)
**Branch**: `fix/grocery-list-polish`

The current screen has `leading: IconButton(icon: Icons.arrow_back_rounded, ...)` in the AppBar that navigates to `/households`. This button is redundant: the bottom `_GroceryBottomNav` already provides navigation to "All Chores" (tab 0), which is the primary view, and the user can reach `/households` via the Android back button or by switching tabs.

**Acceptance criteria**:
1. There is no back-arrow button anywhere on the `GroceryListScreen`.
2. The bottom navigation bar still functions correctly (tab switching between All Chores, My Chores, Leaderboard, Groceries).
3. The widget tests in `grocery_list_screen_test.dart` pass (they don't test the back button, but verify nothing breaks).
4. `flutter analyze` returns zero errors.

**Note**: When TASK-090 converts the header from `AppBar` to an inline widget, the back button is automatically removed because the `leading` property disappears. If any back-button icon or text remains visible, remove it.

---

## TASK-092 — GroceriesNotifier: fix list not refreshing after add/update/delete

**Domain**: Flutter frontend — groceries provider
**Depends on**: None (can be done independently, but best after TASK-090/TASK-091)
**Branch**: `fix/grocery-list-polish`

**Root cause**: The `addItem`, `updateItem`, and `deleteItem` methods in `GroceriesNotifier` call the API then use `ref.invalidateSelf() + await future` to trigger a re-fetch. The backend **does** return the created/updated item in its response:

- `POST /groceries` → returns `GroceryItemResponse` (201)
- `PATCH /groceries/{id}` → returns `GroceryItemResponse` (200)
- `DELETE /groceries/{id}` → returns 204 (no body)

But the current provider code ignores these responses. The `togglePurchased` method works correctly because it directly mutates `state` — this is the pattern to follow.

**Acceptance criteria**:
1. **`addItem`**: Parses the `GroceryItemResponse` from the POST response and appends it to `state` via `state = state.whenData((items) => [...items, GroceryItemModel.fromJson(response.data!)]);` — no `ref.invalidateSelf()` or `await future` needed.
2. **`updateItem`**: Parses the response from the PATCH and replaces the matching item in `state` via `state.whenData(...)` — exactly like `togglePurchased` does after receiving the server response (lines 98-101).
3. **`deleteItem`**: Removes the matching item from `state` via `state = state.whenData((items) => items.where((i) => i.id != itemId).toList());` — no `ref.invalidateSelf()` or `await future`.
4. After adding an item, the grocery list on screen shows the new item immediately without requiring an app restart or manual refresh.
5. After updating an item (via the edit sheet), the list reflects the changes immediately.
6. After deleting an item, it disappears from the list immediately.
7. All existing widget tests pass.
8. `flutter analyze` returns zero errors.

**Implementation notes**:

`addItem` should become:
```dart
Future<void> addItem(String name, {String? quantity, String? notes}) async {
  final householdId = arg;
  final dio = ref.read(dioProvider);
  final response = await dio.post<Map<String, dynamic>>(
    ApiEndpoints.householdGroceries(householdId),
    data: {
      'name': name,
      if (quantity != null && quantity.isNotEmpty) 'quantity': quantity,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    },
  );
  final newItem = GroceryItemModel.fromJson(response.data!);
  state = state.whenData((items) => [newItem, ...items]);
}
```

`updateItem` should become:
```dart
Future<void> updateItem(String itemId, Map<String, dynamic> body) async {
  final householdId = arg;
  final dio = ref.read(dioProvider);
  final response = await dio.patch<Map<String, dynamic>>(
    ApiEndpoints.groceryItem(householdId, itemId),
    data: body,
  );
  final updated = GroceryItemModel.fromJson(response.data!);
  state = state.whenData((items) => [
    for (final i in items) if (i.id == itemId) updated else i,
  ]);
}
```

`deleteItem` should become:
```dart
Future<void> deleteItem(String itemId) async {
  final householdId = arg;
  final dio = ref.read(dioProvider);
  await dio.delete<void>(
    ApiEndpoints.groceryItem(householdId, itemId),
  );
  state = state.whenData((items) => items.where((i) => i.id != itemId).toList());
}
```

**Note**: The `dio.delete<void>` call returns `void` (204), so `response.data` is not available — that's fine, we just filter the item out of the list.

---

