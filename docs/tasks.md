# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**108 tasks complete, 3 pending (TASK-109 … TASK-111).** Completed task bodies
live in `docs/archive/tasks-completed.md`; the ledger below is the authoritative
history. TASK-105 (signing-key drift runbook) is retained inline below as an
operational reference rather than trimmed to the archive. New work: append
tasks here as TASK-111+ following the same format (self-contained body,
acceptance criteria, ledger row).

---

## Status Ledger (updated 2026-08-14)

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
| TASK-090, TASK-091, TASK-092 | ✅ Done 2026-08-06 — grocery list polish: AppBar replaced with inline header matching other tabs (_darkText title); back-arrow button removed (regression test added); GroceriesNotifier add/update/delete now update state directly from API responses so the list refreshes immediately — archived. |
| TASK-093, TASK-094, TASK-095, TASK-096 | ✅ Done 2026-08-07 — F-Droid auto-publishing pipeline: signed release APK published as a GitHub Release on main pushes (tag derived from pubspec versionName, duplicate-tag guard); chore-app-fdroid repo created from the xarantolus/fdroid template with apps.yaml + keystore/config stored as repo secrets; deterministic versionCode (MAJOR*10000+MINOR*100+PATCH) in pubspec + CI; README F-Droid install docs with repo URL + fingerprint — archived. |
| TASK-097 | ✅ Done 2026-08-07 — shared `AppBottomNavBar` widget replaces the four per-screen bottom-nav copies (single source of truth for icons/labels/order/navigation, `Key('bottom_nav_bar')` preserved); Leaderboard destination uses the trophy icon (`emoji_events_rounded`) on every tab; All Chores standardized on `checklist_rounded`; current-tab tap is a no-op — archived. |
| TASK-098 | ✅ Done 2026-08-07 — grocery screen header title is now the static "Groceries" instead of the household name; dead `householdsNotifierProvider` watch + import removed; regression test added (header shows "Groceries", household name absent); 217/217 tests pass, analyzer clean — archived. |
| TASK-099 | ✅ Done 2026-08-07 — release signing pinned: `Verify APK signing certificate` CI step fails on any signer drift or missing `ANDROID_APK_CERT_SHA256` (robust digest extraction, works with old & new apksigner output formats); releases fail-closed without a keystore (dedicated error step on main, release gated on keystore presence) — debug-signed releases are now impossible; permanent keystore generated (backup `~/.hermes/keystores/choreapp-release.jks`) and all 5 signing secrets set; v1.0.2 published as the first permanent-key release and its APK cert verified end-to-end — archived. |
| TASK-100 | ✅ Done 2026-08-07 — fdroid repo hardened: `check_signatures.py` guard in `update.sh` aborts (exit 3, no push) if any version's signer differs from the newest; it caught the push-triggered CI run resurrecting v1.0.0/v1.0.1 (metascoop indexes ALL GitHub releases — the broken releases were the poison source); those releases + tags deleted; index purged to only real-key 1.0.2; dispatched workflow green, live index shows exactly one signer — archived. |
| TASK-101 … TASK-104 | ✅ Done 2026-08-14 — `dismissed` chore status (DB enum + migration + schema Literal + terminal guards, scheduler/redistribution audit clean); `POST .../dismiss` (zero points, no PointLedger row, assignee-or-admin) + admin completes-for-assignee (points credited to assignee, unassigned-member edge closes without points); Flutter `dismissChore` provider (optimistic, no leaderboard invalidation); UI: long-press dismiss for assignees + admin "Mark done for {assignee}"/"Dismiss (no points)" menu, "No points" pill, dismissed in Done filters/counts, weekly banner counts dismissed as 0, admin snackbar credits the assignee; 8 backend integration + 11 Flutter tests; suite 248 backend @ 97.3%, 229 Flutter; v1.0.3+10003 — archived. |
| TASK-105 | ✅ Done 2026-08-14 — signing-drift runbook + fail-closed guard (body retained inline below): diagnosed the "signature changed, can't update" report — v1.0.2/v1.0.3 verified identical permanent cert `f0096466…9be600af` at the byte level (GitHub Release APKs + fdroid-repo copies), so the residual cause is a stale debug-signed install needing one-time reinstall, not a new drift; hardened `chore-app-fdroid/check_signatures.py` to re-extract the real v2 signing cert from every APK and check it + each index `signer` field against a committed pin (`signing_cert.sha256`) instead of trusting metadata / comparing only to the newest version — any key rotation now aborts the rebuild (exit 3, no push), even with a single version. |
| TASK-106 | ✅ Done 2026-08-14 — backend chore-template endpoints: `GET /households/{id}/chores/templates` (active definitions, newest first, hidden ones excluded) + `POST /chores/{definition_id}/hide` (admin-only, sets new `hidden_from_suggestions` column via Alembic migration); `ChoreTemplateResponse` schema; hiding ≠ deleting (instances stay in the chore list); 5 integration tests; suite 253 @ 97.4% — archived. |
| TASK-107 | ✅ Done 2026-08-14 — Flutter template picker: `ChoreTemplate` model, `choreTemplatesProvider` (hide updates state directly), "Start from a previous task" horizontal suggestions on the create screen (create mode only) — tap copies exactly title/description/category/effort_level, X removes the suggestion via the hide endpoint; 4 widget tests; suite 233, analyzer clean — archived. |
| TASK-108 | ✅ Done 2026-08-15 — Flutter "Copy from existing task": explicit `OutlinedButton.icon` on the create form (create mode only) opens a `showModalBottomSheet<ChoreTemplate>` listing the household's existing tasks (reuses TASK-106 `/templates` + `choreTemplatesProvider`, awaiting `.future` so the first tap isn't a stale read); selecting a row copies exactly title/description/category/effort_level and leaves due date/chore type/recurrence/assignee untouched; empty list → snackbar, no sheet; replaced the TASK-107 auto-suggestion strip (widgets removed, tests rewritten); 3 widget tests; suite 232, analyzer clean — archived. |

---

## TASK-105: Signing-key drift — diagnose, fix, and prevent the "F-Droid won't update" failure

**Domain**: Release pipeline (Ahzed11/chore-app + Ahzed11/chore-app-fdroid)
**Depends on**: TASK-099 (build-time cert pin), TASK-100 (fdroid consistency guard)
**Branch**: `fix/pin-signer-cert` (in Ahzed11/chore-app-fdroid)

**What & why**: The user reported (2026-08-14) that the latest F-Droid version's
signature was "once again different" — Android refused the update, forcing a
reinstall. Byte-level investigation proved the *current* releases are NOT
drifted: v1.0.2 and v1.0.3 (both the GitHub Release APKs and the F-Droid repo
copies) carry the identical permanent signing certificate
`f00964666c8f09e3c70b435f506340761c7922b27d8a54ce5b21863c9be600af`, and the
index is consistent. The residual cause of the user's failure is a DEBUG-signed
install still on the device from before the permanent keystore existed
(v1.0.0/v1.0.1) — that can only be migrated by uninstall/reinstall. The real
gap was that the fdroid-side guard only compared index `signer` metadata against
the *newest* version, so a keystore rotation (or a wrong `signer` written by the
tooling) with a single version in the index would ship silently. This task
documents how to diagnose and fix a genuine drift, and hardens the guard to
fail closed.

**How to diagnose** (do this FIRST — never assume a drift):

1. Extract the signing cert from every published APK and compare to the pin
   `f00964666c8f09e3c70b435f506340761c7922b27d8a54ce5b21863c9be600af`:

   ```
   python3 ~/.hermes/scripts/apk_cert_compare.py
   ```

   (downloads each GitHub Release APK + fdroid-repo APK and prints the SHA-256
   of the v2 signing certificate). If every APK matches the pin → the keys are
   fine; the user's install is a stale debug-signed build → uninstall/reinstall,
   no repo change needed.
2. Also inspect the live index:

   ```
   python3 ~/.hermes/scripts/fdroid_check_index.py   # versions + signers
   python3 ~/.hermes/scripts/fdroid_dump.py            # raw signer/sig/hash + file list
   ```

   A healthy repo shows exactly one distinct `signer` across all versions,
   equal to the pin, and every APK `hash` matches the served file.

**How to fix a REAL drift** (an APK cert != the pin):

1. Restore the permanent keystore secrets in Ahzed11/chore-app from the backup
   at `~/.hermes/keystores/choreapp-release.jks` (cert `f0096466…9be600af`).
   NEVER generate a new keystore — that is a second key and bricks every
   existing install. Use `~/.hermes/scripts/set_github_secret.py` to reset
   `ANDROID_KEYSTORE_BASE64`/`ANDROID_KEYSTORE_PASSWORD`/`ANDROID_KEY_ALIAS`/
   `ANDROID_KEY_PASSWORD` and set `ANDROID_APK_CERT_SHA256` back to the pin.
2. Delete every GitHub Release AND git tag that was signed with the wrong key
   (metascoop indexes ALL GitHub releases). `gh` is not installed — use the
   GitHub API (releases/tags endpoints) or the repo UI.
3. Purge the bad APK from `chore-app-fdroid/fdroid/repo/` and the stale index.
4. Rebuild: push a version bump (or re-tag) so CI republishes a correctly-signed
   APK → dispatch `fdroid.yml` in Ahzed11/chore-app-fdroid
   (`python3 ~/.hermes/scripts/fdroid_dispatch.py`) → verify with
   `fdroid_check_index.py` that every version has exactly one signer == the pin.
5. Tell affected users: one-time uninstall + reinstall (Android never upgrades
   across signing keys; no other recovery exists once the old key is gone).

**Prevention (implemented)**: `chore-app-fdroid/check_signatures.py` now
(a) re-extracts the actual APK Signature Scheme v2 certificate from every
`*.apk` in `fdroid/repo/`, (b) compares it against the committed pin
`signing_cert.sha256`, and (c) cross-checks every index `signer` field against
the same pin — instead of trusting metascoop's metadata or comparing only to
the newest version. `update.sh` runs it before commit/push and `exit 3` (no
push) on any mismatch. The pin is the single source of truth and MUST equal
`ANDROID_APK_CERT_SHA256` in chore-app's CI secrets — update BOTH together
only for a deliberate uninstall/reinstall migration. On the app side,
`flutter.yml` already verifies the built APK's cert against the pin and fails
closed without a keystore (TASK-099).

**Acceptance criteria**:
- `python3 check_signatures.py fdroid/repo` exits 0 on the live repo (2 APKs +
  index, all `f0096466…9be600af`).
- The guard exits 1 (no push) on each of: a tampered index `signer`, a wrong
  `signing_cert.sha256` value, and a malformed pin — each with an actionable
  message naming the offending APK/version and the expected cert.

---

---

---

## TASK-109: Fix the broken "Copy from existing task" control on the create form

**Domain**: Flutter frontend — chores create UI
**Depends on**: TASK-108 (the control this fixes)
**Branch**: `fix/copy-from-existing-task`

**What & why**: The "Copy from existing task" control added in TASK-108 is
reported broken/unusable in the real app. Reproduce, fix, and prove it with
tests that exercise the paths the current tests miss.

**Current code** (in `flutter_app/lib/features/chores/screens/create_chore_screen.dart`):
- `_pickTemplateToCopy()` — awaits `choreTemplatesProvider(hId).future`, then
  shows a snackbar on empty/error, else opens the sheet and copies the 4 fields.
- `_CopyTaskSheet` — `SafeArea > Padding > Column(mainAxisSize: min) > [
  header, subtitle, Flexible(child: ListView.separated(shrinkWrap: true, …)) ]`.

**Investigate, in this order** (don't assume — reproduce first):

1. **Bottom-sheet layout is the prime suspect.** `Flexible` inside a
   `Column(mainAxisSize: MainAxisSize.min)` with a `shrinkWrap: true` ListView
   is fragile: on real devices and/or with several tasks it can throw
   `RenderFlex children have non-zero flex but incoming height constraints are
   unbounded`, or overflow past the screen. The existing widget test only
   pumped **one** task, so it never exercised this. A red error screen (or the
   sheet silently not opening) is exactly "broken and unusable".
2. **`_pickTemplateToCopy` future handling** — confirm the provider future
   resolves (not hangs) and that the error path shows `friendlyErrorMessage`
   rather than an unhandled exception.
3. Confirm `/templates` returns data for the household (TASK-106 tests cover
   the backend; a 403/422 here would surface as the error snackbar).

**Fix (canonical, robust pattern):**

- Replace the sheet body with a `DraggableScrollableSheet` and a plain
  (non-`shrinkWrap`) `ListView` driven by its controller — the standard
  bottom-sheet-list pattern, no `Flexible`-in-`min`-Column, no `shrinkWrap`:
  ```dart
  final chosen = await showModalBottomSheet<ChoreTemplate>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // fixed header ("Copy from existing task" + subtitle), padded
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: templates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _CopyTaskRow(template: templates[i]),
            ),
          ),
        ],
      ),
    ),
  );
  ```
  Keep `_CopyTaskRow` (ListTile with `Key('copy_task_<id>')`, category icon,
  title, `cat · effort · pts` subtitle, `onTap: () => Navigator.pop(context, template)`).
- Keep the empty-list snackbar and the `friendlyErrorMessage` snackbar in
  `_pickTemplateToCopy()` unchanged (they are correct).

**Tests — REQUIRED (these catch the bug):**

- Open the sheet with **~15 tasks**: assert `tester.takeException()` is null
  after `pumpAndSettle`, scroll to the last row, tap it, and assert the fields
  copied (title/description/category/effort_level).
- 1 task (existing test, keep), empty → snackbar no sheet (keep), error →
  `friendlyErrorMessage` snackbar (add: fake notifier whose `build` throws).
- Button present in create mode / absent in edit mode (keep).

**Acceptance criteria**: `flutter analyze --no-pub --no-fatal-infos` clean;
`flutter test --no-pub` green including the 15-task overflow/scroll test; the
sheet opens and scrolls on a real device without any layout exception (verify
via TASK-110's harness once available).

---

## TASK-110: Autonomous end-to-end app testing harness (find + fix issues)

**Domain**: QA / test infrastructure (Flutter + backend)
**Depends on**: none (independent of TASK-109; its harness is what catches the TASK-109 class of bug)
**Branch**: `feat/e2e-testing-harness`

**What & why**: We need a repeatable, headless way for an agent to run the REAL
app (not just unit/widget tests) and surface runtime/UI bugs — layout
exceptions, overflow, broken flows — then fix them. The copy-control bug slipped
through because the widget test used a single data point. Build two layers, in
cost order.

**Layer 1 — layout/overflow sweep (widget tests, no new system deps):**
A smoke harness that pumps each screen/flow with empty / one / many data
variants and asserts `expect(tester.takeException(), isNull)` after
`pumpAndSettle()`. This is the cheapest detector for the class of bug we just
hit. Add `flutter_app/test/features/_layout_smoke_test.dart` (or extend the
existing per-screen tests) that iterates: households list, chore list
(empty/one/many, each status), create-chore form (incl. opening the
copy-from-existing-task sheet with many tasks), my-chores screen, leaderboard,
groceries list. Each variant asserts no uncaught exception. Document that any
`RenderFlex overflow`/`unbounded height` caught here is a real bug to fix.

**Layer 2 — `integration_test` on the Linux desktop device (true E2E):**
Only the `android/` platform folder exists and the Linux desktop toolchain is
missing, so add it:
1. `sudo dnf install -y cmake ninja-build clang gtk3-devel pkg-config`
   (`flutter doctor` confirms; sudo password is in the user's memory notes).
2. From `flutter_app/`: `flutter create --platforms=linux .` (adds `linux/`).
3. Add dev dependency: `integration_test: {sdk: flutter}` to `pubspec.yaml`.
4. Start the backend: podman container `choreapp-db` (postgres, 5432), then
   `cd backend && uv run uvicorn main:app --host 0.0.0.0 --port 8000` with the
   usual `DATABASE_URL`/`JWT_SECRET` env (see the repo's test README / TASK-001
   notes). Run the app's migrations (`uv run alembic upgrade head`).
5. Write `integration_test/app_flows_test.dart` using
   `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`, covering the full
   journey: register → create household → create a chore → **copy from existing
   task** (select a previous task, assert the 4 fields prefilled) → dismiss →
   complete → leaderboard points → logout. Use `--dart-define` to point the app
   at the local server:
   ```
   flutter test integration_test/app_flows_test.dart -d linux \
     --dart-define=API_BASE_URL=http://localhost:8000
   ```
   (`AppConfig.baseUrl` reads `API_BASE_URL`; default is the Android-emulator
   `10.0.2.2:8000`.) On a headless box wrap with `xvfb-run -a …`.
6. (Optional alternative, lower priority) Flutter web + browser automation:
   `flutter create --platforms=web .`, then
   `flutter run -d web-server --web-port 8080 --web-renderer html
   --dart-define=API_BASE_URL=http://localhost:8000` and drive it with the
   browser / computer_use tools. Note CanvasKit (default) renders to a canvas
   with no DOM, so use `--web-renderer html` for DOM-driven automation.

**Agent workflow**: run the Layer-1 sweep → record failures → fix → re-run →
run the Layer-2 E2E flow → record any failures → fix → re-run. Log every found
issue and its fix as a ledger entry (TASK-1xx), archiving bodies as usual. The
first concrete target: reproduce and confirm the TASK-109 copy-control fix
through BOTH layers.

**Acceptance criteria**: Layer-1 sweep runs headlessly and fails on a
deliberately-introduced overflow (sanity check that it can catch bugs); Layer-2
E2E flow passes end-to-end against a live local backend; both are documented in
a `docs/testing.md` (commands + how to add a flow) so any future agent can run
them without guidance.

---

## TASK-111: Sort chore lists newest-first — new tasks on top, oldest at the bottom

**Domain**: Backend API + Flutter frontend — chore list ordering
**Depends on**: none (supersedes the ordering introduced by TASK-070; TASK-071's
`test_list_chores_pagination_is_stable` must be updated, see Tests below)
**Branch**: `feat/newest-tasks-first`

**What & why**: User report (2026-08-18): tasks appear in the wrong order —
oldest on top, newest at the bottom. Desired: the newest-created task at the top
of every list and the oldest at the bottom, with ONE exception — in My Chores
the overdue chores stay pinned on top (urgency beats age). "Newest" means
creation time (`created_at` of the chore instance), the same convention the
templates endpoint already uses (TASK-106: `ChoreDefinition.created_at.desc()`).
User decision recorded: "Both lists, but My Chores keeps overdue tasks pinned on
top, everything else newest-first."

**Current behaviour**:
- `backend/app/api/chores.py` — `list_chores` orders by
  `ChoreInstance.due_date, ChoreInstance.id` (ascending): the soonest-due task
  sits on top; a newly created task with a later due date lands at the bottom.
  All four All-Chores filter tabs (All/Pending/Overdue/Done) inherit this order
  because the frontend preserves server order.
- `ChoreInstanceResponse` (`backend/app/schemas/chore.py`) does not expose
  `created_at`, and `ChoreModel` (Flutter) has no `createdAt` — the client
  cannot sort by creation today.
- `flutter_app/lib/features/chores/screens/my_chores_screen.dart` re-sorts
  locally: overdue by `dueDate` ASC, pending by `dueDate` ASC (so newest tasks
  sink to the bottom), done by `completedAt` DESC (already newest-first — keep).

**Changes**:

1. Backend — `backend/app/api/chores.py` `list_chores` (~line 218): change the
   ORDER BY to `ChoreInstance.created_at.desc(), ChoreInstance.id.desc()`.
   `id` DESC keeps offset pagination deterministic when `created_at` ties
   (UUIDs are unique) — never order by `created_at` alone. Do NOT "fix" this
   back to due-date order: the user explicitly wants creation order. Consequence
   to accept: future instances of recurring chores (generated by the scheduler)
   sort to the top of All Chores — that is the requested behaviour.
2. Backend — schema: add `created_at: datetime` to `ChoreInstanceResponse`
   (`backend/app/schemas/chore.py`) and populate it in
   `_instance_response_from_row` (`created_at=instance.created_at`). The field
   then also flows into the create/complete/dismiss responses — harmless,
   `from_attributes` covers it.
3. Flutter — `flutter_app/lib/features/chores/models/chore_model.dart`: add
   `required DateTime createdAt`; parse `json['created_at']` in `fromJson`
   (server always sends it once step 2 lands) and emit it in `toJson`.
4. Flutter — `flutter_app/lib/features/chores/providers/chores_provider.dart`:
   the two optimistic `ChoreModel(...)` constructions in `completeChore` and
   `dismissChore` must pass `createdAt: c.createdAt`. Any other construction
   sites the analyzer flags likewise.
5. Flutter — `my_chores_screen.dart`:
   - overdue: keep `dueDate` ASC (pinned block, most-overdue first).
   - pending: sort by `createdAt` DESC (newest first) instead of `dueDate` ASC.
   - done: unchanged (`completedAt` DESC — most recently completed first is
     already "newest on top").
   - `chore_list_screen.dart` needs NO change — the server order flows through
     `_applyFilter` unchanged.
6. Tests:
   - Backend: `test_list_chores_pagination_is_stable`
     (`backend/tests/test_chores.py` ~line 707) asserts due dates are ascending
     and WILL FAIL — rewrite it for the new order. Pitfall: Postgres
     `func.now()` is transaction time, so consecutive creates can tie on
     `created_at`; the `id DESC` tiebreaker is random UUIDs → flaky. Make it
     deterministic by backdating `created_at` directly in the DB via
     `_get_session_factory()` (e.g. `UPDATE chore_instances SET created_at =
     now() - make_interval(days => n)` per chore), then assert: pages disjoint,
     cover all rows, `created_at` non-increasing across the concatenated pages,
     and `created_at` present in every item. Add a focused newest-first test:
     3 chores created in sequence → titles come back reversed (newest first)
     with descending `created_at`.
   - Flutter: update fixtures that build `ChoreModel` (fromJson maps need
     `created_at`); add widget tests for (a) All Chores list shows newest-created
     first and (b) My Chores todo shows overdue on top, then pending
     newest-first. `flutter analyze --no-pub --no-fatal-infos` must stay clean
     (it flags missed construction sites).
7. Release (standing rule): bump `flutter_app/pubspec.yaml` version patch →
   next `1.0.6+10006` (verify current version at merge time; a duplicate tag
   makes CI skip the release). After merge to main, dispatch the fdroid index
   rebuild: `python3 ~/.hermes/scripts/fdroid_dispatch.py`.

**Acceptance criteria**:
- `GET /households/{id}/chores` returns items newest-created first, each item
  carries `created_at`; pagination pages stay disjoint and cover all rows.
- All Chores tab (every filter) shows the newest task at the top.
- My Chores todo: overdue pinned on top, then pending newest-first; Done tab
  unchanged.
- Backend suite + Flutter suite green; analyzer clean with zero infos; new
  ordering tests added (not just existing ones updated).
- pubspec bumped to 1.0.6+10006 and the fdroid index rebuilt after merge.
