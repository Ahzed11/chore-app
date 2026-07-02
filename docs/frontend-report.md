# Frontend Report — ChoreApp Flutter

**Date:** 2026-07-02  
**Branch:** master (`a79405f`)  
**Stack:** Flutter 3.x, Dart 3.12+, Riverpod 2.5, go_router 14, Dio 5.4, flutter_secure_storage 9

---

## Executive Summary

The Flutter frontend is a well-built, polished app with clean architecture: a clear feature-slice structure, consistent Riverpod state management, good widget decomposition, and solid widget test coverage. The UI is production-quality — custom designs, smooth animations, and thoughtful empty/error/loading states throughout.

However, there is one **blocking regression** introduced by the backend TASK-039 change: the chores provider expects a bare JSON array but the backend now returns a paginated envelope `{items, total, limit, offset}`. This will crash the app immediately on the chores screen. Beyond that, the refresh-token flow is absent (400+ line auth interceptor logs the user out on any 401 instead of refreshing), logout never calls the server, and several widget tests reference keys and text that do not match the actual widget tree.

| Category | Score |
|---|---|
| Code Quality | 8 / 10 |
| Architecture | 8 / 10 |
| State Management | 8 / 10 |
| Test Coverage | 6.5 / 10 |
| API Contract Alignment | 5 / 10 |
| Maintainability | 8 / 10 |
| **Overall Code Quality** | **7.5 / 10** |
| **Implementation Completeness** | **~78%** |

---

## 1. Implementation Completeness

### Feature Completion by Screen

| Screen / Feature | Completion | Notes |
|---|---|---|
| Login | 95% | Form validation, error display, auto-navigate on success |
| Register | 95% | 4 fields, confirm-password check, auto-login after register |
| Household dashboard | 90% | List + create + join by token (URL extraction); no multi-household switcher |
| Household management | 90% | Members list, role-change, remove, leave guard, QR invite, inline accordion |
| All Chores list | 85% | Filter tabs, admin delete, tap-to-complete with confirmation sheet; pagination not handled |
| My Chores | 90% | To-do / done tabs, weekly points banner, rank badge, overdue ordering |
| Create / Edit Chore | 90% | Full form, edit-mode banner, assignee dropdown, recurrence section |
| Leaderboard | 95% | Podium for top 3, rest list, three scopes, invite nudge |
| Auth token management | 40% | Access token stored; refresh token ignored; logout doesn't call server |

### What Is Missing

**Critical (app will crash or break immediately):**
- `chores_provider.dart` casts the `GET /chores` response to `List<dynamic>` — the backend now returns `{"items": [...], "total": N, "limit": 50, "offset": 0}`. The cast will throw a `TypeError` at runtime.

**High-priority (feature gaps visible to users):**
- Refresh token flow: login response includes `refresh_token` but it is discarded; when the access token expires (7 days), users are silently logged out
- Logout does not call `POST /auth/logout` — revoked tokens remain valid on the server until natural expiry
- No chore reassignment UI — backend `PATCH /{instance_id}/assignee` endpoint exists but no Flutter screen or action reaches it
- No invite management UI — backend now has `GET /invites` and `DELETE /invites/{id}` but Flutter does not use them

**Medium-priority (correctness / polish):**
- `deleteChore` in `chores_provider.dart:182` uses a hardcoded URL string; should use `ApiEndpoints`
- `weeklyPoints` in My Chores uses `chore.pointValue` (derived from effort level) instead of `chore.pointsAwarded` (authoritative server value) — diverges if points are ever overridden
- `ChoreFilterNotifier` is defined and partially wired but never used for server-side filtering; API calls always fetch all chores
- No Dio timeout — requests to an unreachable server will hang indefinitely
- `currentUserIdProvider` decodes the JWT payload client-side to extract `sub`; `currentUserProvider` already has the user ID from `GET /users/me` — two sources of truth for user ID

**Low-priority (test quality):**
- `chore_list_screen_test.dart` references 7+ keys/text strings that don't exist in the current widget tree (see §3)
- No tests for the 401 → clearOnUnauthorized path or refresh-token flow

---

## 2. Architecture & Code Quality

### Strengths

**Feature-slice structure** is well-enforced. Each feature directory owns its models, providers, screens, and widgets. Cross-feature dependencies go through named providers, never direct screen imports.

**Consistent Riverpod patterns** throughout. `FamilyAsyncNotifier` for household-scoped chores, `FutureProvider.family` for leaderboard, `Notifier` for local UI state (filter, scope). The optimistic update in `completeChore` (snapshot → optimistic → server confirm → revert on error) is implemented correctly.

**go_router with `refreshListenable`** — The `_AuthStateListenable` bridge in `app_router.dart` correctly converts Riverpod state to a `Listenable` that GoRouter can watch. Auth redirects are declarative and reliable.

**Widget test infrastructure** — Every screen has a dedicated test file with fake notifier subclasses, `ProviderScope` overrides, and distinct loading/error/data states. The pattern is solid, just the assertions are stale.

**Error and empty states** — All async widgets have distinct loading, error, and empty renderings with retry buttons. `AppErrorWidget` and `LoadingWidget` are shared components used consistently.

### Weaknesses

**Auth interceptor logs out on any 401** (`api_client.dart`):
```dart
// Current behaviour — line ~37
onError: (e, handler) async {
  if (e.response?.statusCode == 401) {
    await ref.read(authNotifierProvider.notifier).clearOnUnauthorized();
  }
  handler.next(e);
},
```
This should attempt a token refresh first, then fall back to logout only on refresh failure.

**Two user-ID sources** — `currentUserIdProvider` (JWT decode) vs. `currentUserProvider` (API call). The JWT-decoded ID is used in `chore_list_screen.dart:179` for "is this my chore" logic. If the JWT `sub` claim ever diverges from the user's DB ID these will disagree.

**`ChoreFilterNotifier` is dead code** — It tracks `status`, `category`, and `assigneeId` filter state, but `_fetchChores` in `ChoresNotifier` only passes filters if explicitly called. The filter notifier is never read in any screen; filtering is applied purely client-side after a full list fetch.

**`deleteChore` bypasses `ApiEndpoints`** (`chores_provider.dart:182`):
```dart
await dio.delete<void>('/households/$householdId/chores/$definitionId');
```
All other calls go through `ApiEndpoints` static methods. This one hardcodes the path, making URL refactoring harder.

---

## 3. Test Quality

### Coverage

| Test file | Tests | Passes today? |
|---|---|---|
| `login_screen_test.dart` | ~8 | Likely — standard Material widget keys used |
| `register_screen_test.dart` | ~6 | Likely |
| `household_dashboard_test.dart` | ~6 | Likely |
| `household_management_test.dart` | ~10 | Likely |
| `chore_list_screen_test.dart` | 15 | **No** — stale assertions |
| `my_chores_screen_test.dart` | ~8 | Unknown |
| `create_chore_screen_test.dart` | ~8 | Likely |
| `leaderboard_screen_test.dart` | ~6 | Likely |

### Stale Assertions in `chore_list_screen_test.dart`

The test file was written against a prior design of the chore list screen that used `FilterChip` widgets and different widget keys. The current screen uses plain `GestureDetector` tabs.

| Line | Assertion | Actual widget |
|---|---|---|
| 225 | `find.byKey(Key('overdue_warning_icon'))` | `_StatusCircle` uses `Icon(Icons.priority_high)` with no key |
| 253 | `find.byKey(Key('status_chip_All'))` | No `FilterChip` — screen uses custom `GestureDetector` tabs |
| 256 | `find.byKey(Key('status_chip_Pending'))` | Same — no FilterChip |
| 269 | `tester.widget<FilterChip>(...)` | No FilterChip in widget tree |
| 295 | `find.byKey(Key('my_chores_chip'))` | No chip — My Chores is bottom nav item |
| 395 | `find.text('No chores found')` | Actual empty state shows `'All clear!'` |
| 424 | `find.text('Something went wrong')` | `AppErrorWidget` message text may differ |

---

## 4. API Contract Alignment

### Backend endpoints not yet called by Flutter

| Endpoint | Status in Flutter |
|---|---|
| `POST /auth/logout` | Not called — logout only clears local storage |
| `POST /auth/refresh` | Not called — no refresh token flow |
| `GET /households/{id}/invites` | Not called |
| `DELETE /households/{id}/invites/{id}` | Not called |
| `PATCH /households/{id}/chores/{iid}/assignee` | Not called |

### Endpoint contracts that are broken

| Issue | File | Detail |
|---|---|---|
| Paginated chores response | `chores_provider.dart:84` | Casts to `List<dynamic>`; backend returns `{items, total, limit, offset}` |

### Missing `ApiEndpoints` constants

`api_endpoints.dart` is missing:
- `authLogout` → `POST /auth/logout`
- `authRefresh` → `POST /auth/refresh`
- `householdInvites(id)` → `GET /households/{id}/invites`
- `revokeInvite(householdId, inviteId)` → `DELETE /households/{id}/invites/{inviteId}`
- `choreAssignee(householdId, instanceId)` → `PATCH /households/{id}/chores/{iid}/assignee`

---

## 5. Security Observations

All security concerns are **low severity** for a self-hosted personal app:

- **Access token stored in `flutter_secure_storage`** — correct; Keystore-backed on Android
- **JWT decoded client-side for user ID** (`leaderboard_provider.dart:19`) — acceptable for UI highlighting; not used for authorization decisions
- **Refresh token discarded on login** — no security risk currently (only access tokens used), but means no ability to call the refresh endpoint when added
- **Logout doesn't revoke server-side** — access tokens remain valid until expiry (7 days). For a household app this is acceptable

---

## 6. Actionable Tasks

See `docs/tasks.md` tasks TASK-045 through TASK-053.
