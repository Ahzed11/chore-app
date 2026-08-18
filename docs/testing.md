# ChoreApp Testing Guide

How to run every layer of the test stack, and how to add coverage. Written so
any agent can reproduce the commands headlessly without guidance (TASK-110).

## Layer 0 — unit & widget tests (fast, always run)

```bash
# Backend (needs the postgres container; see .hermes.md for env)
cd backend
uv sync --extra test
export DATABASE_URL=postgresql+asyncpg://choreapp:choreapp_test@localhost:5432/choreapp_test
export TEST_DATABASE_URL=$DATABASE_URL
export JWT_SECRET=local_dev_secret_at_least_32_chars_long
export JWT_ALGORITHM=HS256 APP_BASE_URL=http://localhost:8000
uv run pytest tests/ -v
uv run ruff check .

# Flutter
export PATH="$PATH:/home/hermes/flutter/bin"
cd flutter_app
flutter pub get
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
```

CI runs both suites on every branch push.

## Layer 1 — layout/overflow smoke sweep (headless, no extra deps)

`flutter_app/test/features/_layout_smoke_test.dart` pumps every major screen
with empty / one / many data variants at phone (390x844) and narrow/large-text
(320x568 @ textScale 1.3) sizes and asserts `tester.takeException()` is null
after each settle.

**Any `RenderFlex overflow` / `unbounded height` caught here is a REAL bug** —
fix it, don't suppress it. This sweep exists because a bottom-sheet layout bug
(TASK-109) shipped past widget tests that used a single data point.

Run just the sweep (fast):

```bash
cd flutter_app
flutter test --no-pub test/features/_layout_smoke_test.dart
```

Covered screens: household dashboard, chore list (every filter tab),
create-chore form (incl. opening the copy-from-existing-task sheet with 15
templates, and the category dropdown at narrow/large-text sizes — TASK-112),
my chores (todo + done tabs), leaderboard, groceries.

**Sanity check** (prove the sweep can catch bugs): temporarily add a widget
that overflows (e.g. a `Row` of two 500px-wide boxes) to the sweep and confirm
it fails, then remove it. Verified once when the harness was built (TASK-110).

### How to add a screen to the sweep

Copy an existing group in `_layout_smoke_test.dart`. Override the providers
the screen watches with data notifiers (see the per-screen tests in
`test/features/` for the exact provider sets — `ref.watch` in the screen file
is the authoritative list). Iterate the data variants you care about
(empty/one/many/statuses). Use `_phoneView`/`_narrowView` + textScale for
size-sensitive screens. Each variant ends with
`expect(tester.takeException(), isNull)` after `pumpAndSettle()`.

## Layer 2 — true E2E on the Linux desktop device

Runs the REAL app against a LIVE backend (podman postgres + uvicorn), driven
by `integration_test` — this is what catches runtime bugs that unit/widget
tests miss (broken flows, real network round-trips, keyboard/sheet behaviour).

### 0. Linux desktop prerequisites (one-time)

```bash
sudo dnf install -y cmake ninja-build clang gtk3-devel pkg-config \
  libsecret-devel xorg-x11-server-Xvfb xorg-x11-xauth gnome-keyring
```

`libsecret-devel` is required by the flutter_secure_storage Linux plugin
(CMake `pkg_check_modules` fails without it). The repo's `linux/CMakeLists.txt`
carries a Clang-only `-Wno-deprecated-literal-operator` so the plugin's bundled
json.hpp builds on Clang 16+ — do not remove it.

### 1. Start the backend

```bash
podman start choreapp-db            # postgres 16 on 5432 (create if missing:
podman run -d --name choreapp-db \
  -e POSTGRES_USER=choreapp -e POSTGRES_PASSWORD=choreapp_test \
  -e POSTGRES_DB=choreapp_test -p 5432:5432 \
  docker.io/library/postgres:16-alpine)

cd backend
export PATH="$PATH:/home/hermes/.hermes/bin"   # uv location
export DATABASE_URL=postgresql+asyncpg://choreapp:choreapp_test@localhost:5432/choreapp_test
export JWT_SECRET=local_dev_secret_at_least_32_chars_long
export JWT_ALGORITHM=HS256 APP_BASE_URL=http://localhost:8000
uv run alembic upgrade head
uv run uvicorn main:app --host 0.0.0.0 --port 8000 &
curl -s http://localhost:8000/health   # expect {"status":"ok"}
```

Two hard rules for the backend server (TASK-113, learned the hard way):

1. **Start the server fresh for every E2E run.** A long-lived uvicorn can
   develop stale pooled-connection state when client connections are
   interrupted mid-request (aborted E2E runs are prime culprits) — symptoms:
   register succeeds (201) but the immediately-following login returns 401
   "Invalid credentials", and the user CAN log in minutes later. Restarting
   uvicorn clears it. `pool_recycle=1800` (in `app/db/session.py`) bounds the
   blast radius.
2. **Never run pytest against the same database a live server uses.** The
   suite drops and recreates the schema per session on `TEST_DATABASE_URL` —
   pointing that at the dev DB corrupts the server's pool. Use the dedicated
   `choreapp_test_db` (created in step 1) for pytest.

### 2. Run the E2E flow

The app uses `flutter_secure_storage`, which on Linux needs an unlocked
gnome-keyring — so the headless recipe wraps the test in a private dbus
session + xvfb + a keyring unlocked with an empty password:

```bash
cd flutter_app
dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
  export PATH="$PATH:/home/hermes/flutter/bin"
  printf "\n" | gnome-keyring-daemon --unlock --components=secrets
  flutter test integration_test/app_flows_test.dart -d linux \
    --dart-define=API_BASE_URL=http://localhost:8000
'
```

On a machine with a live desktop + keyring you can drop the
`dbus-run-session -- xvfb-run ...` wrapper and run the `flutter test` line
directly.

The test resets persisted state (server URL + tokens) first, so it always
starts at first-run setup. It registers a fresh user (timestamped email),
creates a household, creates a chore, copies it via "Copy from existing task"
(asserting the 4 prefilled fields), dismisses the first chore, completes the
second, checks the leaderboard shows the 25 pts, and logs out.

### How to add an E2E flow

- Add a `testWidgets(...)` block to `integration_test/app_flows_test.dart`.
- Drive the REAL UI by widget keys (see the `Key('...')` strings in the
  screens; `search_files` for `Key` in `lib/` to find them).
- **Always follow a network-triggering action with `waitFor(tester, finder)`
  instead of `pumpAndSettle`** — real I/O doesn't schedule frames, so
  `pumpAndSettle` can return mid-request. `waitFor` (defined in the test
  file) polls with a timeout and then settles.
- Keep each run idempotent: unique emails/names per run, and clear persisted
  storage at the start if the flow depends on first-run state.

## When to use which layer

| Question | Layer |
|---|---|
| Does the code compile / analyzer clean / unit logic correct? | 0 |
| Does a screen blow up its layout with lots of data or small screens? | 1 |
| Does the real app work end-to-end against a real server? | 2 |
| Is a UI bug fixed for real (reproduce → fix → re-run)? | 1 + 2 |
