# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**105 tasks complete, 2 pending (TASK-106 … TASK-107).** Completed task bodies
live in `docs/archive/tasks-completed.md`; the ledger below is the authoritative
history. TASK-105 (signing-key drift runbook) is retained inline below as an
operational reference rather than trimmed to the archive. New work: append
tasks here as TASK-108+ following the same format (self-contained body,
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

## TASK-106: Backend — chore-template endpoints (list suggestions + hide)

**Domain**: Backend — chores API / data model
**Depends on**: none (TASK-107's UI depends on this)
**Branch**: `feat/chore-templates` (shared with TASK-107)

**What & why**: When creating a chore, an admin wants to start from a previous
task and copy its title, description, category and **score**. In this app
"score" IS the effort level — easy = 10, medium = 25, hard = 50 points
(`EFFORT_POINTS` in `app/core/constants.py`; `effortLevels` in
`flutter_app/lib/core/constants/chore_constants.dart`) — so copying
`effort_level` copies the score. Suggestions are the household's active
`ChoreDefinition`s. "Remove from suggestions" must NOT delete the chore or hide
it from the chore list — it only hides the definition from the create-form
template list, so a boolean flag on the definition is the right shape.

**How to implement** (backend):

1. `backend/app/models/chore_definition.py` — add a column next to `is_active`:
   ```python
   hidden_from_suggestions: Mapped[bool] = mapped_column(
       Boolean, nullable=False, default=False, server_default=sa.text("false")
   )
   ```
   (`Boolean` is already imported; add `import sqlalchemy as sa` or import
   `text` from sqlalchemy.) No new model → `app/models/__init__.py` unchanged.

2. New Alembic migration (mirror `d4e5f6a7b8c9_add_dismissed_chore_status.py`
   for style; `down_revision` = current head):
   ```python
   op.add_column(
       "chore_definitions",
       sa.Column("hidden_from_suggestions", sa.Boolean(),
                 nullable=False, server_default=sa.text("false")),
   )
   ```
   Downgrade drops the column.

3. `backend/app/schemas/chore.py` — add a response schema:
   ```python
   class ChoreTemplateResponse(BaseModel):
       model_config = ConfigDict(from_attributes=True)
       id: uuid.UUID
       title: str
       description: Optional[str]
       category: str
       effort_level: str
   ```

4. `backend/app/api/chores.py` — two endpoints. **IMPORTANT:** declare
   `GET /templates` ABOVE the existing `GET /{instance_id}` route — FastAPI
   matches routes in declaration order and `/{instance_id}` expects a UUID, so
   a literal `/templates` declared after it would 422. Both endpoints are
   admin-gated (create is admin-only, so only admins consume templates):
   ```python
   @router.get("/templates", response_model=list[ChoreTemplateResponse])
   async def list_chore_templates(
       household_id: uuid.UUID,
       db: AsyncSession = Depends(get_db),
       _membership: HouseholdMembership = Depends(require_admin),
   ) -> list[ChoreTemplateResponse]:
       """Active chore definitions usable as create-form templates, newest first."""
       result = await db.execute(
           select(ChoreDefinition)
           .where(
               ChoreDefinition.household_id == household_id,
               ChoreDefinition.is_active.is_(True),
               ChoreDefinition.hidden_from_suggestions.is_(False),
           )
           .order_by(ChoreDefinition.created_at.desc())
       )
       return [ChoreTemplateResponse.model_validate(d) for d in result.scalars()]
   ```
   (`created_at` exists via `TimestampMixin` on `ChoreDefinition`.)
   ```python
   @router.post("/{definition_id}/hide", status_code=status.HTTP_204_NO_CONTENT)
   async def hide_chore_template(
       household_id: uuid.UUID,
       definition_id: uuid.UUID,
       db: AsyncSession = Depends(get_db),
       _membership: HouseholdMembership = Depends(require_admin),
   ) -> None:
       """Stop showing a definition as a create-form template (admin only)."""
       definition = (
           await db.execute(
               select(ChoreDefinition).where(
                   ChoreDefinition.id == definition_id,
                   ChoreDefinition.household_id == household_id,
                   ChoreDefinition.is_active.is_(True),
               )
           )
       ).scalar_one_or_none()
       if definition is None:
           raise HTTPException(
               status_code=status.HTTP_404_NOT_FOUND,
               detail="Chore definition not found",
           )
       definition.hidden_from_suggestions = True
   ```
   (`status`, `select`, `HTTPException` are already imported; the router prefix
   is `/households/{household_id}/chores`.)

5. Tests — new `backend/tests/test_templates.py` (mirror `test_completion.py`'s
   self-contained `async_client` + seed helpers):
   - admin GET `/templates` → 200, active definitions ordered newest-first,
     each carrying title/description/category/effort_level.
   - a hidden definition is excluded from templates but STILL returns its
     instances in `GET /chores` — proves hiding ≠ deleting.
   - admin POST `/{definition_id}/hide` → 204; a follow-up GET excludes it.
   - hide a non-existent definition → 404.
   - non-admin GET `/templates` → 403 and POST `hide` → 403.

**Acceptance criteria**: `alembic upgrade head` applies cleanly;
`uv run pytest tests/ -v` and `uv run ruff check .` pass with no coverage
regression (both endpoints are exercised by the new tests).

---

## TASK-107: Flutter — template picker on the create screen + hide a suggestion

**Domain**: Flutter frontend — chores create UI
**Depends on**: TASK-106 (endpoints must exist)
**Branch**: `feat/chore-templates`

**What & why**: Surface "start from a previous task" on the create screen.
Tapping a suggestion copies ONLY title / description / category / effort_level
("score") into the form — the due date, chore type, recurrence and assignee are
left for the admin to set fresh. A remove affordance hides that suggestion via
the backend `hide` endpoint.

**How to implement** (frontend):

1. `lib/core/api/api_endpoints.dart` — add:
   ```dart
   static String choreTemplates(String hId) => '/households/$hId/chores/templates';
   static String choreHideTemplate(String hId, String defId) =>
       '/households/$hId/chores/$defId/hide';
   ```

2. New model `lib/features/chores/models/chore_template.dart`:
   ```dart
   class ChoreTemplate {
     const ChoreTemplate({required this.id, required this.title,
       this.description, required this.category, required this.effortLevel});
     final String id; final String title; final String? description;
     final String category; final String effortLevel;
     factory ChoreTemplate.fromJson(Map<String, dynamic> j) => ChoreTemplate(
       id: j['id'] as String,
       title: j['title'] as String,
       description: j['description'] as String?,
       category: j['category'] as String,
       effortLevel: j['effort_level'] as String,
     );
   }
   ```

3. New provider `lib/features/chores/providers/chore_templates_provider.dart`:
   `AsyncNotifierProvider.family<List<ChoreTemplate>, String>` keyed on
   householdId that GETs `choreTemplates(hId)`. Add
   `Future<void> hideTemplate(String definitionId)` — POST `choreHideTemplate`,
   then update `state` DIRECTLY by filtering the id out (the TASK-092 pattern:
   `state = state.whenData((list) => list.where((t) => t.id != id).toList())`).
   Do NOT `invalidateSelf()` after a mutation; keep `invalidateSelf` only in
   `refresh()`. On failure, rethrow so the screen can show
   `friendlyErrorMessage`.

4. `lib/features/chores/screens/create_chore_screen.dart` — in CREATE mode only
   (NOT edit mode), render a "Start from a previous task" section at the TOP of
   the form (above the title field). `ref.watch(choreTemplatesProvider(widget.householdId))`:
   - loading → nothing (or a small spinner); error → nothing (suggestions are
     optional and must never block create);
   - data → a horizontal list of tappable suggestion chips/cards showing
     `title`, category label + icon, and the effort label + points
     (e.g. "Medium · 25 pts", from `chore_constants.dart` `effortLevels` and
     `categoryIcons`/`categoryLabels`).
   - Tap a suggestion → `setState` and copy into the form: `_titleController.text`,
     `_descriptionController.text = description ?? ''`, `_category`,
     `_effortLevel`. Leave `_choreType`, `_firstDueDate`, the recurrence fields,
     and `_assigneeId` untouched.
   - Each suggestion has a remove affordance (small X icon button, or
     long-press) that calls `hideTemplate(id)`. Keys: `Key('template_<id>')`
     for the suggestion and `Key('remove_template_<id>')` for its remove
     affordance.

5. Widget tests — extend `test/features/chores/create_chore_screen_test.dart`
   (override `choreTemplatesProvider` with a fake notifier; see the
   fake-notifier pattern in `my_chores_screen_test.dart`): tapping a suggestion
   prefills title/description/category/effort (assert via the field keys /
   controller text); the remove affordance calls hide and drops the suggestion;
   the section is absent in edit mode.

**Acceptance criteria**: `flutter analyze --no-pub --no-fatal-infos` clean;
`flutter test --no-pub` green including the new tests; selecting a template
copies exactly title/description/category/effort_level and nothing else;
removing a suggestion hides it from the list without affecting the chore list.
