# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**114 tasks complete, 0 pending.** Completed task bodies
live in `docs/archive/tasks-completed.md`; the ledger below is the authoritative
history. TASK-105 (signing-key drift runbook) is retained inline below as an
operational reference rather than trimmed to the archive. New work: append
tasks here as TASK-115+ following the same format (self-contained body,
acceptance criteria, ledger row).

---

## Status Ledger (updated 2026-08-18)

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
| TASK-110 | ✅ Done 2026-08-18 — autonomous E2E testing harness, both layers: Layer-1 headless layout/overflow smoke sweep (`test/features/_layout_smoke_test.dart`, every major screen at phone + narrow/large-text sizes, sanity-verified to fail on a deliberate overflow); Layer-2 `integration_test/app_flows_test.dart` on the Linux desktop running the REAL app against a live backend (register → household → chore → copy-from-existing → dismiss → complete → leaderboard → logout), headless via dbus+gnome-keyring+xvfb; `docs/testing.md` documents commands + how to add screens/flows. The harness caught and drove three fixes: TASK-112 (category dropdown overflow), TASK-113/114 (backend pool hygiene + the register→login commit race) — archived. |
| TASK-112 | ✅ Done 2026-08-18 — category dropdown RenderFlex overflow on narrow screens / large text (create form): `isExpanded: true` + Flexible ellipsizing item text; narrow/large-text variant added to the Layer-1 sweep (fails without the fix) — archived. |
| TASK-113 | ✅ Done 2026-08-18 — backend connection-pool hygiene after the "register 201 → login 401" incident: `pool_recycle=1800`, dedicated pytest DB `choreapp_test_db` (tests drop/recreate the schema per session), docs record the "never pytest a live DB" rule. ⚠️ TASK-113's original "stale pool" diagnosis was superseded by TASK-114 — the real cause was the FastAPI yield-teardown commit racing the client's auto-login — archived. |
| TASK-114 | ✅ Done 2026-08-18 — register→login race fixed: FastAPI runs `yield`-dependency teardown (get_db's commit) AFTER the response is sent, so a client acting immediately on a write response can race the commit. Explicit `await db.commit()` before returning in auth register, create household, create chore (the endpoints whose 201s trigger immediate client follow-ups); convention documented in session.py + docs/testing.md. Verified: 15/15 rapid register→login cycles green, suite 253 @ 97.4%, E2E journey green — archived. |
| TASK-109 | ✅ Done 2026-08-18 — "Copy from existing task" sheet hardened to the canonical DraggableScrollableSheet pattern (initial 0.5 / min 0.2 / max 0.85, non-shrinkWrap ListView, header as first list item, bottom safe-area inset, unfocus before open). Harness found no repro of the reported breakage, so the planned hardening was applied + an adversarial review (REQUEST CHANGES) drove a second round: all task-required tests added (15-template tap-last-row-copy, throwing-provider friendlyErrorMessage snackbar, half-height-panel + landscape/large-text sweep variants). Suite 246 green at merge; E2E green — archived. |
| TASK-111 | ✅ Done 2026-08-18 — chore lists sort newest-first: backend `list_chores` ORDER BY `(created_at DESC, id DESC)` (id keeps offset pagination deterministic on ties); `created_at` added to `ChoreInstanceResponse`; Flutter `ChoreModel.createdAt` + optimistic paths; My Chores pending sorts createdAt DESC with id tiebreaker (overdue pinned, Done unchanged); All Chores preserves server order. Deterministic backdate-based backend tests (+ rowcount guard); All Chores/My Chores ordering widget tests (distinct createdAt fixtures); E2E asserts newest chore on top. Adversarial review APPROVE — actionable findings applied. Suite 254 @ 97.4% + Flutter 248 green; pubspec 1.0.6+10006; fdroid index rebuilt after merge — archived. |

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
