# Frontend Report — ChoreApp Flutter

**Date:** 2026-07-15 (supersedes the 2026-07-02 report)
**Branch:** `claude/brave-ritchie-1owy48`
**Stack:** Flutter 3.x, Dart 3.12+, Riverpod 2.5, go_router 14, Dio 5.4, flutter_secure_storage 9

> Static review — the Flutter SDK was not available in the review environment, so `flutter analyze` / `flutter test` were not executed locally. CI (`.github/workflows/flutter.yml`) runs both on push.

---

## Executive Summary

Most of the previous report's findings were fixed (TASK-045 through TASK-051 landed). The architecture remains solid: feature-slice layout, consistent Riverpod patterns, go_router with auth redirects, and 147 widget tests across 10 files.

However, this review found **three critical issues** in the current code:

1. **The release APK cannot make network calls at all** — the main `AndroidManifest.xml` lacks the `INTERNET` permission (only debug/profile manifests have it), and there is no cleartext-traffic config for plain-HTTP self-hosted servers. The CI-built release APK is dead on arrival.
2. **Logout never revokes tokens server-side** — the dashboard's logout handler clears local storage *before* calling `AuthNotifier.logout()`, so the `POST /auth/logout` call is silently skipped.
3. **The refresh interceptor can loop indefinitely** on repeated 401s and mishandles concurrent 401s and transient network failures.

Beyond bugs, the single biggest product gap for a self-hosted app: **the server URL is a compile-time constant**. Users installing the CI APK cannot point the app at their own server without building a custom APK.

| Category | Score |
|---|---|
| Code Quality | 8 / 10 |
| Architecture | 8 / 10 |
| State Management | 7 / 10 |
| Release Readiness | 3 / 10 |
| API Contract Alignment | 7.5 / 10 |
| Test Coverage | 6.5 / 10 |

---

## 1. Verification of Previous Fixes (TASK-045..053)

| Task | Status | Notes |
|---|---|---|
| TASK-045 paginated chores | **Landed** | `chores_provider.dart:89` reads the `items` envelope. UI still only fetches page 1 — see F-6. |
| TASK-046 refresh token flow | **Landed, buggy** | Interceptor exists (`api_client.dart:37–63`), tokens persisted on login. Three defects — F-1, F-4, F-5. |
| TASK-047 server-side logout | **Landed, defeated by caller bug** | `AuthNotifier.logout()` is correct, but its only caller clears the token first — F-2. |
| TASK-048 stale widget tests | **Landed** | `chore_list_screen_test.dart` rewritten against the current tree (17 tests). |
| TASK-049 ApiEndpoints constants | **Partial** | Constants added, but `authLogout()`/`authRefresh()` are never used — `auth_state.dart:104,132` still hardcode paths. `choreAssignee`/`revokeInvite` unused because TASK-052/053 were never built. |
| TASK-050 Dio timeouts | **Mostly landed** | Main client and logout Dio have timeouts; the **refresh Dio at `auth_state.dart:130` has none**. |
| TASK-051 pointsAwarded | **Landed for the banner only** | `my_chores_screen.dart:115` uses `pointsAwarded ?? pointValue`, but completion snackbars, the confirm sheet, and the completed-card pill still show client-derived `pointValue`. |
| TASK-052 reassignment UI | **NOT implemented** | Zero call sites for `ApiEndpoints.choreAssignee`; admin menu has only "Delete series". |
| TASK-053 invite management UI | **NOT implemented** | `InviteApi` only exposes `generateInvite`. Both invite UIs generate a **new** token on every open, so unrevokable tokens accumulate server-side. |

---

## 2. Findings

### Critical

**F-1. [Bug] Refresh interceptor can retry-loop indefinitely on repeated 401s** — `lib/core/api/api_client.dart:41–60`
`isRefreshing` is reset to `false` *before* `dio.fetch(opts)` retries the original request. If the retry 401s again (revoked user, backend rejecting the new token for a non-expiry reason), the interceptor refreshes again — and since the backend rotates refresh tokens, each refresh succeeds, producing an infinite 401 → refresh → retry loop. There is no per-request "already retried" marker. The interceptor also fires for 401s from `/auth/login` and `/auth/register`, so a wrong password triggers a pointless refresh attempt.
*Fix:* set `error.requestOptions.extra['retried'] = true` before `dio.fetch` and skip the refresh branch when that flag (or an `/auth/` path) is present.

**F-2. [Bug] Logout never revokes the token server-side** — `lib/features/household/screens/household_dashboard_screen.dart:78–81`
```dart
Future<void> _logout(WidgetRef ref) async {
  await AuthStorage.clearToken();               // clears token first
  await ref.read(authNotifierProvider.notifier).logout();  // reads null token → skips POST /auth/logout
}
```
Silently defeats TASK-047. *Fix:* delete the `AuthStorage.clearToken()` line; `logout()` already clears both tokens.

**F-3. [Bug] Release APK has no INTERNET permission** — `android/app/src/main/AndroidManifest.xml`
Only `src/debug` and `src/profile` manifests declare `android.permission.INTERNET`. The release APK CI builds cannot make any network call. Additionally, the default base URL is `http://` with no `usesCleartextTraffic`/network-security-config, so even with the permission Android 9+ blocks plaintext HTTP to a self-hosted LAN server.
*Fix:* add the permission to the main manifest plus a network security config (or HTTPS guidance).

### High

**F-4. [Bug] Concurrent 401s: only one request is retried, the rest surface errors** — `api_client.dart:41`
Screens fire 3+ requests in parallel. On token expiry the first 401 starts the refresh; every other in-flight 401 hits `!isRefreshing == false` and passes straight through as an error, so the user sees random error widgets even though refresh succeeded.
*Fix:* queue subsequent 401s on a shared `Completer<bool>` and retry them all when the refresh resolves.

**F-5. [Bug] Transient network failure during refresh logs the user out** — `lib/core/auth/auth_state.dart:141–144`
`refresh()`'s `catch (_)` treats *any* failure — timeout, DNS, server reboot — as auth failure and wipes both tokens. On a self-hosted server users will be randomly logged out. The refresh Dio also has no timeouts (line 130).
*Fix:* only clear tokens on 401/403 from the refresh endpoint; on network errors return `false` without clearing; add timeouts.

**F-6. [Bug] Chore list silently truncated to the first 50 chores** — `lib/features/chores/providers/chores_provider.dart:84–93`
The fetch sends no `limit`/`offset` and ignores `total`; the backend default limit is 50. Older items vanish, and the client-side weekly-points computation (`my_chores_screen.dart:111–115`) becomes quietly wrong.
*Fix:* loop pages until `items.length == total` or add infinite scroll; longer term, take weekly points from the leaderboard response.

**F-7. [Missing feature] No runtime server-URL configuration for a self-hosted backend** — `lib/core/config/app_config.dart:4–7`
`API_BASE_URL` is a compile-time `String.fromEnvironment` defaulting to the Android-emulator localhost. Users installing the CI APK cannot point the app at their own server. The single biggest gap for a self-hosted product.
*Fix:* first-run/settings "Server URL" screen persisted in storage, validated via `GET /health` (constant already exists, unused); make `dioProvider` watch it.

**F-8. [Bug/dead code] Chore editing is unreachable** — `lib/features/chores/models/chore_form_init_data.dart`
`CreateChoreScreen` fully supports edit mode, but `ChoreFormInitData` is never constructed anywhere — no navigation passes it and the admin long-press menu has no "Edit" item. Also, once wired: the due-date validator (`create_chore_screen.dart:455–464`) rejects past dates even in edit mode.
*Fix:* add "Edit series" to the admin menu; relax past-date validation in edit mode.

**F-9. [Missing feature] TASK-052 (reassignment UI) and TASK-053 (invite list/revoke UI) still open** — backend endpoints and `ApiEndpoints` constants are ready; only UI + notifier methods are missing.

**F-10. [Missing feature] Invite links don't deep-link into the app** — `AndroidManifest.xml`, `lib/router/app_router.dart`
Scanning the invite QR opens a browser at the API server, not the app; joining requires manual copy-paste.
*Fix:* intent-filter for the invite URL pattern (or custom scheme), a GoRouter `/invites/:token` route calling `joinByToken`, and stash-token-then-redirect handling for the logged-out case.

**F-11. [Bug] Leaderboard/rank state is stale after completing chores** — `chores_provider.dart:101–147`
`completeChore` never invalidates `leaderboardProvider`/`weeklyLeaderboardProvider`, so the rank pill and Leaderboard tab show pre-completion data. Same class of issue: `removeMember`/`changeRole` don't invalidate chores (assignee names go stale); `leaveHousehold`/`joinByToken` don't invalidate members/chores families.
*Fix:* invalidate the related providers after each successful mutation.

### Medium

**F-12. [Improvement] Raw exception strings shown to users** — `shared/widgets/error_widget.dart:38` plus ~10 call sites. `error.toString()` on a `DioException` dumps the request URL and boilerplate. Map DioException → friendly message in one shared helper; `_extractMessage` (`auth_provider.dart:112`) is a start but auth-only, and it renders FastAPI 422 validation lists as raw JSON.

**F-13. [Bug] Household rename has no error handling** — `household_management_screen.dart:230–238`. No try/catch; on failure the edit UI stays open with no feedback. The screen also lacks an admin guard, unlike `CreateChoreScreen`.

**F-14. [Improvement] Release build config is template state** — `android/app/build.gradle.kts`. Release signs with the debug keystore (TODO comment), `applicationId` is the template placeholder, app label is `chore_app`, and `pubspec.yaml` version is static `1.0.0+1` with no CI bump.

**F-15. [Improvement] Dead code (~750 lines)** —
- `invite_screen.dart` (355 lines) + route `AppRoutes.invite`: never navigated to; the management screen's inline accordion replaced it.
- `member_tile.dart` (245) and `leaderboard_entry_tile.dart` (143): never imported.
- `ChoreFilter`/`ChoreFilterNotifier` (`chores_provider.dart:11–54, 202–232`): still dead (carried over from the previous report); screens filter client-side.
- `riverpod_annotation` + `riverpod_generator` + `build_runner` in `pubspec.yaml`: no codegen is used anywhere.

**F-16. [Improvement] Duplicated constants and flows** — category labels duplicated with *diverging* text (`chore_model.dart:18–27` vs `create_chore_screen.dart:18–27`); effort points duplicated; `_confirmComplete` duplicated verbatim in two screens; avatar palette duplicated in 4 files; "find my household / isAdmin" lookup duplicated in 5 widgets (extract `householdByIdProvider(id)` / `isAdminProvider(id)`).

**F-17. [UX gap] Chore `description` is write-only** — collected by the form, parsed by the model, never displayed anywhere. Add a tap-to-expand or detail sheet.

**F-18. [UX gap] No i18n and no dark theme** — all strings hardcoded English; only a light theme exists and screens hardcode ~30 hex colors per file. Acceptable MVP debt — if a dark theme is ever wanted, first migrate screen-local colors into the theme.

**F-19. [Improvement] Accessibility** — most tap targets are bare `GestureDetector`s with no semantics; the 30px status-circle complete target (`chore_card.dart:85–90`) is below the 48dp minimum; overdue/complete state is conveyed by color alone in several places. Replace with `IconButton`/`InkWell` + `Semantics`, enlarge hit areas.

**F-20. [Test gaps]** — zero tests for the riskiest code: refresh interceptor, `AuthNotifier`, provider mutation+invalidation logic (F-1/F-2/F-4/F-5 would have been caught by a Dio mock-adapter test). `test/widget_test.dart` pumps the real app with real `FlutterSecureStorage`, which throws `MissingPluginException` in the test env (`auth_state.dart:79–86` has no try/catch).

### Low

**F-21.** `AuthState.copyWith` can't clear the token (`token ?? this.token` trap) — `auth_state.dart:60–65`.
**F-22.** Two sources of truth for current user ID persist: JWT decode (`leaderboard_provider.dart:19–45`) vs `GET /users/me`. Standardize on `currentUserProvider`.
**F-23.** Empty `displayName` crashes avatars — `household_management_screen.dart:869,1022` index `[0]` without a guard.
**F-24.** Timezone edges: `ChoreModel.isOverdue` and the Monday `weekStart` use device-local midnight vs the server's UTC scheduler; weekly points can mis-bucket near boundaries. Prefer server-computed points.
**F-25.** Cold-start login flash: router shows `/login` while auth status is `unknown`, then jumps. Add a splash route.
**F-26.** `google_fonts` fetches Outfit at runtime — fails silently on LAN-only setups. Bundle the font and disable runtime fetching.
**F-27.** Pull-to-refresh missing on the household management screen.
**F-28.** Dependency majors behind: `flutter_lints ^4` (6.x current), `go_router ^14` (16.x), `intl ^0.19`, `share_plus ^10`. Not urgent; schedule a bump and drop unused codegen deps.

---

## 3. Suggested Order of Work

1. F-3 (INTERNET permission + cleartext config) and F-2 (logout ordering) — two tiny fixes with outsized impact.
2. F-1/F-4/F-5 — harden the refresh interceptor, with Dio mock-adapter tests (F-20).
3. F-7 — runtime server URL screen (the self-hosted headline feature).
4. F-6 + F-11 — pagination and post-mutation invalidation.
5. F-8/F-9/F-10 — chore edit entry point, TASK-052/053, invite deep links.
6. Medium/low cleanup batch: F-12..F-19, dead-code deletion, release signing.

Corresponding tasks: see `docs/tasks.md` TASK-054 onward.
