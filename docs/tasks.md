# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**92 tasks complete, 0 pending.** Completed task bodies live in
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
|| TASK-090, TASK-091, TASK-092 | ✅ Done 2026-08-06 — grocery list polish: AppBar replaced with inline header matching other tabs (_darkText title); back-arrow button removed (regression test added); GroceriesNotifier add/update/delete now update state directly from API responses so the list refreshes immediately — archived. |
|| TASK-093, TASK-094, TASK-095, TASK-096 | 🔲 Pending — F-Droid auto-publishing pipeline (see bodies below) |

---

### TASK-093: Publish signed APK as GitHub Release from CI

**Domain**: CI/CD — GitHub Actions  
**Depends on**: TASK-063 (release signing already configured in CI)  
**Acceptance criteria**:
- Pushing to `main` with a version bump in `pubspec.yaml` creates a GitHub Release
- The release contains the signed release APK as an asset
- The release tag matches the version from `pubspec.yaml` (e.g., `v1.1.0`)
- Non-main pushes and PRs do NOT create releases (only build artifacts)
- Release body includes the commit message or a changelog summary

**Why this matters**: F-Droid repos (self-hosted or third-party) consume APKs from GitHub Releases. Without releases, there is nothing for an F-Droid repo to index. The existing CI already builds a signed release APK (`flutter build apk --release --build-number=$GITHUB_RUN_NUMBER`) and uploads it as a 30-day artifact — but artifacts are not publicly accessible URLs, so F-Droid tooling cannot reach them. Publishing as a proper GitHub Release makes the APK permanently available at a stable URL.

**Implementation notes**:

1. **Gate on main branch pushes only**. The `flutter.yml` workflow currently runs on all branches. Add a separate job or conditional step that only fires on `push` to `main` (not PRs, not feature branches). Use:
   ```yaml
   if: github.event_name == 'push' && github.ref == 'refs/heads/main'
   ```

2. **Extract version from pubspec.yaml**. Use a simple grep/sed (no extra dependencies):
   ```bash
   APP_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
   # Result: "1.0.0+1" → tag "v1.0.0" (versionName before the +)
   TAG="v$(echo "$APP_VERSION" | cut -d+ -f1)"
   echo "TAG=$TAG" >> $GITHUB_ENV
   ```

3. **Use `softprops/action-gh-release@v2`** to create the release. This is the de-facto standard GitHub Action for releases. Key parameters:
   ```yaml
   - name: Create GitHub Release
     uses: softprops/action-gh-release@v2
     with:
       files: flutter_app/build/app/outputs/flutter-apk/app-release.apk
       tag_name: ${{ env.TAG }}
       name: ${{ env.TAG }}
       draft: false
       prerelease: false
       fail_on_unmatched_files: true
     env:
       GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```

4. **Handle duplicate tags**. If a release for `v1.0.0` already exists, `softprops/action-gh-release` will fail. Two strategies:
   - **(Recommended) Check if tag exists first**, skip release if it does. This means version must be bumped in `pubspec.yaml` before merging for a new release:
     ```bash
     if git rev-parse "$TAG" >/dev/null 2>&1; then
       echo "Tag $TAG already exists, skipping release"
       echo "SKIP_RELEASE=true" >> $GITHUB_ENV
     fi
     ```
     Then gate the release step on `SKIP_RELEASE != 'true'`.
   - **Alternative**: Delete and recreate the tag/release (risky — breaks F-Droid index history).
   
   The recommended approach enforces the discipline of bumping the version before merging.

5. **APK naming**. The artifact is currently named `chore-app-${{ github.sha }}` in the upload-artifact step. For the release, the APK filename on disk is `app-release.apk`. Consider renaming it to include the version for clarity:
   ```bash
   APK_PATH="flutter_app/build/app/outputs/flutter-apk/app-release.apk"
   RELEASE_APK="chore-app-${TAG}.apk"
   cp "$APK_PATH" "$RELEASE_APK"
   ```
   Then upload `$RELEASE_APK` instead.

6. **Workflow file location**: Modify `.github/workflows/flutter.yml`. The release step goes after the existing "Upload APK" artifact step (or replace it — the release is now the permanent artifact).

**Files to modify**:
- `.github/workflows/flutter.yml` — add version extraction + release creation step

**Verification**: After merging to main with a version bump, check the repo's Releases page on GitHub. The APK should be downloadable. Confirm the tag matches `pubspec.yaml` versionName.

---

### TASK-094: Create and initialize the chore-app-fdroid repository

**Domain**: GitHub repo management + F-Droid infrastructure  
**Depends on**: TASK-093 (GitHub Releases must exist before the fdroid repo has anything to index)  
**Acceptance criteria**:
- A new public GitHub repo `Ahzed11/chore-app-fdroid` exists, created from the `xarantolus/fdroid` template
- The repo has been initialized with `fdroid init`, producing `fdroid/config.yml` and `fdroid/keystore.p12`
- `apps.yaml` references the `Ahzed11/chore-app` repo and the app is configured with name, description, and category
- The repo's GitHub Actions workflow runs successfully on schedule (no APK to index yet, but it shouldn't crash)
- Repository secrets (`CONFIG_YML`, `KEYSTORE_P12`, `GH_ACCESS_TOKEN`) are configured

**Why this approach — xarantolus/fdroid template**: After evaluating three options for F-Droid distribution:

| Option | Pros | Cons |
|---|---|---|
| **Self-hosted via xarantolus/fdroid** | Full control, instant updates, no review queue, free (GitHub-hosted) | Slightly more setup, two repos to maintain |
| **IzzyOnDroid** | One-click submission, large user base | Third-party review queue, inclusion criteria may reject small/household apps, updates depend on their scraper schedule |
| **Official F-Droid (fdroiddata)** | Most trusted, largest audience | Requires reproducible builds, multi-week review, strict inclusion policy (may reject apps not in an "app store" quality tier) |

For a self-hosted household chore app, the xarantolus/fdroid template is the clear winner: zero gatekeeping, instant updates, full control.

**How the template works**:
1. The fdroid repo has a scheduled GitHub Action (every 6 hours) that:
   - Reads `apps.yaml` to find which GitHub repos to watch
   - Fetches the latest GitHub Release from each app repo
   - Downloads the APK asset from the release
   - Runs `fdroid update` to rebuild the repository index (`index.xml`, `index.jar`, etc.)
   - Commits and pushes the updated index back to the fdroid repo
2. The repo's contents are served via **raw.githubusercontent.com** URLs — NOT GitHub Pages.
   This is a completely different mechanism from `ahzed11.github.io`. GitHub serves raw
   file content for every public repo automatically at `raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`
   with no configuration needed. There is zero conflict with your existing GitHub Pages blog
   at `ahzed11.github.io` — they use different domains and different serving infrastructure.
3. Users add `https://raw.githubusercontent.com/Ahzed11/chore-app-fdroid/main/fdroid/repo` to their F-Droid client
4. The F-Droid client checks this URL for updates and downloads new APKs automatically

**Implementation steps**:

1. **Fork/clone the template from `xarantolus/fdroid`**:
   ```bash
   gh repo fork xarantolus/fdroid --clone --remote-name fdroid-template
   cd fdroid-template
   # Clean out the template's own apps
   rm -rf fdroid/repo/* fdroid/archive/* fdroid/icons/*
   # Optionally delete .git and re-init for a clean history
   rm -rf .git && git init
   git remote add origin https://github.com/Ahzed11/chore-app-fdroid.git
   ```
   Then push to the new repo: `Ahzed11/chore-app-fdroid`.

   **Alternative (no local setup)**: Use GitHub's "Use this template" button on `xarantolus/fdroid`, then clone the new repo and clean out the fdroid directory.

2. **Install fdroidserver locally and initialize**:
   ```bash
   sudo add-apt-repository ppa:fdroid/fdroidserver
   sudo apt-get update
   sudo apt-get install fdroidserver
   cd fdroid && fdroid init
   ```
   This creates `fdroid/config.yml` and `fdroid/keystore.p12`. The keystore signs the repository index — it is NOT the same as the APK signing key. Users will see this key's fingerprint when adding the repo.

3. **Edit `fdroid/config.yml`**: Set the repo URL to point at the raw GitHub content:
   ```yaml
   repo_url: https://raw.githubusercontent.com/Ahzed11/chore-app-fdroid/main/fdroid/repo
   repo_name: ChoreApp F-Droid Repository
   repo_description: Auto-updating F-Droid repository for the ChoreApp household chore coordinator app.
   archive_older: 0
   ```

4. **Base64-encode and store as GitHub secrets** on the `chore-app-fdroid` repo:
   ```bash
   cd fdroid
   base64 -w0 config.yml > /tmp/config_b64.txt
   base64 -w0 keystore.p12 > /tmp/keystore_b64.txt
   ```
   - Secret `CONFIG_YML` ← contents of `/tmp/config_b64.txt`
   - Secret `KEYSTORE_P12` ← contents of `/tmp/keystore_b64.txt`

5. **Create a GitHub PAT** for `GH_ACCESS_TOKEN`:
   - Go to https://github.com/settings/tokens/new
   - Note/description: "chore-app-fdroid repo access"
   - No scopes needed (public repo read is free)
   - Expiration: No expiration (or longest available)
   - Store the token as secret `GH_ACCESS_TOKEN` on the `chore-app-fdroid` repo

6. **Edit `apps.yaml`** in the fdroid repo to point at ChoreApp:
   ```yaml
   chore-app:
     git: https://github.com/Ahzed11/chore-app
     name: "ChoreApp"
     description: |
       Self-hosted household chore coordinator. Members join via invite link/QR,
       chores are auto-assigned round-robin, completing chores awards points,
       and a leaderboard ranks members by points (all-time / this-week / this-month).
       
       Also includes a shared grocery list.
     categories:
       - Organization
   ```

7. **Commit and push**: The GitHub Action in the fdroid repo will now pick up future releases automatically. It will fail gracefully on the first run (no release exists yet).

**Files created/modified**:
- New repo `Ahzed11/chore-app-fdroid` created
- `fdroid/config.yml` — repository configuration
- `fdroid/keystore.p12` — repo signing key (gitignored, stored as secret)
- `apps.yaml` — app definitions listing ChoreApp

**Verification**: After TASK-093 publishes the first release, go to the `chore-app-fdroid` repo's Actions tab and confirm the scheduled workflow runs successfully and the `fdroid/repo/` directory now contains `index.xml`, `index.jar`, and the APK.

---

### TASK-095: Version management for F-Droid compatibility

**Domain**: Build configuration  
**Depends on**: TASK-093 (release pipeline must exist first)  
**Acceptance criteria**:
- `versionCode` (the integer after `+` in pubspec.yaml `version`) strictly increases with every release
- CI build-number (`$GITHUB_RUN_NUMBER`) no longer used as the sole versionCode — it is replaced by a deterministic scheme based on the pubspec version
- The `pubspec.yaml` version line is the single source of truth for both `versionName` and `versionCode`
- A merge to main without bumping the `+N` part of the version does NOT create a duplicate tag/release (handled by TASK-093's tag-exists guard)

**Why this matters**: F-Droid (and Android itself) uses `versionCode` — a strictly increasing integer — to determine whether one APK is an upgrade over another. The current CI uses `--build-number=$GITHUB_RUN_NUMBER`, which works but has two problems for F-Droid:

1. **CI provider dependency**: If you ever migrate from GitHub Actions, the run-number counter resets. A future build with a lower number won't install over the previous one.
2. **No correlation with `pubspec.yaml`**: F-Droid's tooling reads `versionCode` from the APK manifest. If pubspec says `1.0.0+1` but CI run number is `472`, the APK's versionCode is 472 — confusing and untethered from the source of truth.

**Implementation**:

1. **Adopt a deterministic versionCode scheme**. Recommended: embed the versionName components into versionCode. For a `MAJOR.MINOR.PATCH` semver, use:
   ```
   versionCode = MAJOR * 10000 + MINOR * 100 + PATCH
   ```
   Examples:
   - `1.0.0` → versionCode `10000`
   - `1.2.3` → versionCode `10203`
   - `2.0.0` → versionCode `20000`
   
   This is standard in the Flutter/F-Droid community and is self-documenting.

2. **Read versionCode from pubspec.yaml in CI** instead of using `$GITHUB_RUN_NUMBER`:
   ```bash
   VERSION_CODE=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ' | cut -d+ -f2)
   echo "VERSION_CODE=$VERSION_CODE" >> $GITHUB_ENV
   ```
   Then use `--build-number=$VERSION_CODE` in the `flutter build apk` command.

3. **Enforce the convention**: Add a comment in `pubspec.yaml` documenting the versionCode scheme:
   ```yaml
   # version: MAJOR.MINOR.PATCH+CODE  where CODE = MAJOR*10000 + MINOR*100 + PATCH
   version: 1.0.0+10000
   ```
   (Bump from the current `1.0.0+1` to `1.0.0+10000` as part of this task.)

4. **Guard against duplicate tags** (already covered in TASK-093 step 4): CI should check if the tag already exists before creating a release. If a developer forgets to bump the `+CODE` and merges, the CI will skip release creation rather than erroring.

**Files to modify**:
- `flutter_app/pubspec.yaml` — update version line and add explanatory comment
- `.github/workflows/flutter.yml` — extract versionCode from pubspec instead of `$GITHUB_RUN_NUMBER`

**Verification**: After bumping pubspec.yaml to `1.0.0+10000` and merging, the resulting APK's `versionCode` in its AndroidManifest should be `10000`. Check with:
```bash
aapt dump badging app-release.apk | grep versionCode
```

---

### TASK-096: End-to-end verification and documentation

**Domain**: Documentation  
**Depends on**: TASK-093, TASK-094, TASK-095  
**Acceptance criteria**:
- README.md contains a new "Android Updates via F-Droid" section with the repo URL and QR code
- The F-Droid repo fingerprint is documented (so users can verify they're adding the correct repo)
- A test round-trip is performed: merge version bump → release created → fdroid repo indexes it → F-Droid client sees the update
- Any issues found during verification are documented or fixed

**Implementation**:

1. **Get the repository fingerprint** from the fdroid repo's first successful Actions run. The output will contain lines like:
   ```
   INFO: Creating signed index with this key (SHA256):
   INFO: AA BB CC DD EE FF 00 11 22 33 44 55 66 77 88 99 ...
   ```
   Remove spaces to get the hex fingerprint. The full repo URL with fingerprint is:
   ```
   https://raw.githubusercontent.com/Ahzed11/chore-app-fdroid/main/fdroid/repo?fingerprint=AABBCCDDEEFF00112233445566778899...
   ```

2. **Generate a QR code** for the repo URL (without fingerprint, as it makes the QR denser). Use any online QR generator or:
   ```bash
   sudo apt-get install qrencode
   qrencode -o fdroid-repo-qr.png "https://raw.githubusercontent.com/Ahzed11/chore-app-fdroid/main/fdroid/repo"
   ```
   Store the QR image in the fdroid repo (it may already have a `.github/qrcode.png` placeholder — replace it).

3. **Update `README.md`** — add a section after the existing setup instructions:
   ```markdown
   ## Android Updates via F-Droid

   ChoreApp is distributed through a self-hosted F-Droid repository. Once added,
   the F-Droid client will automatically notify you of updates — no manual
   reinstallation needed.

   ### Add the repository

   1. Install [F-Droid](https://f-droid.org/) on your Android device
   2. Open F-Droid → Settings → Repositories → +
   3. Scan this QR code or enter the URL manually:

   ![F-Droid repo QR](https://raw.githubusercontent.com/Ahzed11/chore-app-fdroid/main/.github/qrcode.png)

   **Repository URL:**
   ```
   https://raw.githubusercontent.com/Ahzed11/chore-app-fdroid/main/fdroid/repo
   ```

   **Fingerprint:** `AABBCCDDEEFF00112233445566778899...`
   (Verify this fingerprint when adding the repo to ensure authenticity.)

   ### How updates work

   Every merge to `main` that bumps the version in `pubspec.yaml` triggers a signed
   APK build and GitHub Release. Within 6 hours, the F-Droid repository picks up
   the new release and your device will show an available update.
   ```

4. **End-to-end test** (manual, done once):
   - Bump version in `pubspec.yaml` (e.g., `1.0.0+10000` → `1.1.0+10100`)
   - Merge to main
   - Confirm: GitHub Release created with APK asset
   - Wait for or manually trigger the fdroid repo's scheduled workflow
   - Confirm: `fdroid/repo/index.xml` on the fdroid repo contains the new APK entry
   - On an Android device with F-Droid installed: add the repo URL, install ChoreApp, then check for updates after the next release

**Files to modify**:
- `README.md` — add F-Droid section
- `.github/qrcode.png` in the fdroid repo — replace with ChoreApp's QR code

**Verification**: The README section should be clear enough that a non-technical household member can follow it to set up auto-updates.

---

### Context: investigation summary (for future reference)

This feature was researched on 2026-08-06. Key findings:

- **F-Droid official nightly** (`fdroid nightly`): GitLab-first, cumbersome on GitHub (requires separate `-nightly` repo + SSH deploy keys + debug keystore secrets). Overkill for a single-app household repo.
- **IzzyOnDroid**: Watches GitHub Releases. Submission requires filing an issue at their GitLab tracker. Free, but third-party dependent and subject to inclusion review. Good fallback option.
- **Self-hosted via xarantolus/fdroid** (CHOSEN): Template repo that auto-indexes APKs from GitHub Releases. Zero ongoing maintenance — just bump version + merge. Users get a standard F-Droid repo URL. This is the approach implemented above.

The existing CI infrastructure (Flutter build + release signing via `ANDROID_KEYSTORE_*` secrets, TASK-063) is already compatible — no changes needed to the signing pipeline.

**Alternative considered but rejected**: `fdroid nightly` with the `wardvl/f-droid-nightly-action` GitHub Action. This requires managing a DEBUG_KEYSTORE secret and SSH deploy keys, and produces a nightly channel (every push) rather than stable releases. The xarantolus approach gives stable, versioned releases which is a better fit for a household app where every update should be deliberate.

---
