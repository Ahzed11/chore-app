# ChoreApp

Self-hosted household chore coordinator: a FastAPI + PostgreSQL backend and an Android
Flutter client. Members join a household via invite link/QR, chores are auto-assigned
round-robin (or manually), completing a chore awards fixed points, and a per-household
leaderboard ranks members by points (all-time / this-week / this-month).

## Repo map

- `backend/app/` — `api/` (route modules), `core/` (config, security, constants),
  `db/` (session, base), `models/` (SQLAlchemy ORM), `schemas/` (Pydantic),
  `services/` (assignment, redistribution, account deletion), `tasks/` (scheduler).
  Plus `alembic/` (migrations) and `tests/` at `backend/` top level.
- `flutter_app/lib/` — `core/` (api client, auth, config), `features/` (auth, chores,
  household, leaderboard — each with screens/providers), `shared/` (widgets, theme),
  `router/`. Tests under `flutter_app/test/`.
- `docs/` — `requirements.md` (FR/BR/NFR IDs, data model, resolved decisions),
  `tasks.md` (status ledger + open task bodies), `archive/` (completed task bodies in
  `tasks-completed.md`, and dated point-in-time review reports).
- `README.md` — self-hosting/deployment guide (production quick start, HTTPS/reverse
  proxy, backup/restore); this file is about developing the app, not deploying it.

## Backend: run tests locally

Requires a local PostgreSQL reachable at the URL below (`docker-compose.yml` has a
ready-made `db` service, or point at your own).

```
cd backend && uv sync --extra test
export DATABASE_URL=postgresql+asyncpg://choreapp:choreapp_test@localhost:5432/choreapp_test
export TEST_DATABASE_URL=$DATABASE_URL JWT_SECRET=local_dev_secret_at_least_32_chars_long
export JWT_ALGORITHM=HS256 APP_BASE_URL=http://localhost:8000
uv run pytest tests/ -v
uv run ruff check .
```

CI (`.github/workflows/ci.yml`) runs this identical sequence on every branch push.

## Flutter: run checks locally

```
cd flutter_app
flutter pub get
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
```

CI (`.github/workflows/flutter.yml`) runs the same analyze/test (plus a release APK
build) on every branch push.

## Running the stack

- `docker-compose.yml` — local **dev** config (`--reload`, `DEBUG=true`, source bind
  mount). Wrapped by `make up` / `make dev` / `make migrate` / `make test`.
- `docker-compose.prod.yml` — **production**: published GHCR image, migrations run
  automatically on startup, no reload/mount/debug, plus a `backup` sidecar. Wrapped by
  `make prod-up` / `make prod-down` / `make backup` / `make restore`. See `README.md`
  for the full self-hosting walkthrough.

## Conventions

- Work is tracked in `docs/tasks.md` as a status ledger + full bodies for open tasks
  (completed task bodies live in `docs/archive/tasks-completed.md`). Implement against
  a task's acceptance criteria and update the ledger row when done.
- Never commit `.env` (gitignored; `.env.example` at repo root documents every variable).
- CI runs on pushes to all branches, not just `main`/`master`.
