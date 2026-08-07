# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**98 tasks complete, 2 pending (TASK-099, TASK-100).** Completed task bodies
live in `docs/archive/tasks-completed.md`; the ledger below is the authoritative
history. New work: append tasks here as TASK-099+ following the same format
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

---

## TASK-099: CI — pin the release APK signing certificate (fail closed on any drift)

**Domain**: CI / release pipeline (chore-app)
**Depends on**: TASK-093..096 (release publishing), TASK-063 (keystore signing)
**Branch**: `fix/pin-apk-signing-cert`

**Background — the v1.0.0 incident**: the v1.0.0 release APK was built while the
`ANDROID_KEYSTORE_*` secrets were unset, so CI silently fell back to the Flutter
**debug keystore**. Android refuses to install an "update" whose signing key
differs from the installed app's, so that debug-signed release can never be
updated by any user — F-Droid simply never offers it. Nothing in the pipeline
detected this. The fix must make this failure mode *impossible*, not merely
unlikely.

**Acceptance criteria**:
1. A new `Verify APK signing certificate` step runs after `Build release APK`
   (before artifact upload) whenever the keystore secrets are configured
   (`env.HAS_ANDROID_KEYSTORE == 'true'`). It locates `apksigner` in the
   Android build-tools, extracts `Signer #1 certificate SHA-256 digest` from
   the built APK, and compares it (case-insensitive, whitespace-trimmed)
   against the `ANDROID_APK_CERT_SHA256` repository secret.
2. If `ANDROID_APK_CERT_SHA256` is unset while a keystore is configured, the
   step **fails** with instructions for obtaining and setting the fingerprint
   (no unverifiable release may ever be produced).
3. On mismatch, the step **fails** printing expected vs actual digest plus an
   explanation that installed users cannot update across signing keys and that
   the keystore must never change silently.
4. Releases are fail-closed: `Create GitHub Release` additionally requires
   `env.HAS_ANDROID_KEYSTORE == 'true'`, and a dedicated
   `Ensure release signing is configured` step **fails the workflow on main**
   when the keystore is not configured — a debug-signed release can never be
   published again. (Branch builds without secrets still work for forks.)
5. The workflow header comment is updated: releases now *require* the keystore;
   the debug fallback only applies to non-release builds.
6. The step logic is validated locally before merge: with a stub `apksigner`
   printing a known digest, the script passes on match and exits 1 on mismatch
   and on empty `ANDROID_APK_CERT_SHA256`.
7. After merge, the main CI run is green and the verify step reports the pinned
   digest `6113f55dd8dce6c27ddca5ec033aea123819820bd13833f20f4c45ae14cb7606`
   (the current real keystore, taken from the v1.0.1 APK itself).

---

## TASK-100: F-Droid repo — signature-consistency guard + purge the debug-signed v1.0.0

**Domain**: CI / release pipeline (chore-app-fdroid repo)
**Depends on**: TASK-099 (same incident), TASK-093..096
**Branch**: `fix/signature-consistency` (in Ahzed11/chore-app-fdroid)

**Background**: the F-Droid repo index currently contains two versions of
`dev.ahzed11.choreapp` signed with *different* keys (1.0.0 = debug key, 1.0.1 =
real key). The index-building pipeline (`update.sh` via metascoop) did not
reject the drift. Two things are needed: (a) purge the stale debug-signed
1.0.0 so the index only offers real-key versions, and (b) a guard that fails
the index rebuild if a new version's signer ever differs from the newest
version already in the index — a second line of defense behind TASK-099.

**Acceptance criteria**:
1. `update.sh` in the fdroid repo runs a consistency check after metascoop
   succeeds and **before** `git add/commit/push`: for every package in
   `fdroid/repo/index-v1.json`, every version's `signer` must equal the signer
   of the highest-versionCode version of that package. Any drift → exit
   nonzero with the offending package(s) and signers listed; the bad index is
   never pushed.
2. The debug-signed `chore-app_v1.0.0.apk` is deleted from `fdroid/repo/` and
   the index is regenerated (with the repo keystore) so `index-v1.json` lists
   only `1.0.1` / versionCode `10001` for `dev.ahzed11.choreapp`.
3. The check is validated locally: it fails against a crafted index containing
   the old two-signer state, and passes against the regenerated index.
4. A dispatched workflow run on the fdroid repo succeeds end-to-end, and the
   live `index-v1.json` shows exactly one signer for the package.
5. The drift-detection message is actionable: it names the package, both
   signers, and says the keystore must not change silently (see TASK-099).

---