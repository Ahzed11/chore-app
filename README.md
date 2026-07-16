# ChoreApp

A self-hosted household chore tracker: recurring/rotating chore definitions,
automatic daily instance generation, assignment, completion tracking, and
household invites — no third-party account or cloud service required.

## Architecture

- **Backend**: FastAPI + PostgreSQL (`backend/`), async SQLAlchemy, Alembic
  migrations, JWT auth with refresh tokens, an APScheduler-driven nightly job
  that generates chore instances and flags overdue ones.
- **Frontend**: a Flutter app (`flutter_app/`) targeting Android, talking to
  the backend over HTTP(S).
- **Deployment model**: single-tenant, one household (or a few) per
  deployment, run on hardware you control (a home server, a small VPS, etc.).
  There is no multi-tenant SaaS mode.

CI (`.github/workflows/ci.yml`) publishes a backend image to
`ghcr.io/ahzed11/chore-app-api` on every push to `main`, and
(`.github/workflows/flutter.yml`) builds and uploads a release APK as a
workflow artifact.

## Production quick start

Requires Docker or Podman with the Compose plugin.

```bash
git clone https://github.com/Ahzed11/chore-app.git
cd chore-app
cp .env.example .env
```

Edit `.env`:

- Generate `JWT_SECRET`: `python -c "import secrets; print(secrets.token_hex(32))"`
- Set `POSTGRES_PASSWORD` to something other than the default.
- Set `APP_BASE_URL` to the URL you'll actually reach the API at (used to
  build absolute links such as invite URLs).

Then start the stack:

```bash
make prod-up
# or directly: docker compose -f docker-compose.prod.yml up -d
```

This runs `docker-compose.prod.yml`, which:

- pulls the published `api` image (`CHORE_APP_IMAGE`, default
  `ghcr.io/ahzed11/chore-app-api:latest` — pin a specific tag, e.g. a commit
  SHA, for reproducible deploys instead of tracking `:latest`),
- runs pending Alembic migrations automatically on startup
  (`backend/docker-entrypoint.sh`) before uvicorn starts,
- disables `/docs`, `/redoc`, and `/openapi.json` (`DEBUG=false`),
- does not bind-mount source and does not use `--reload`,
- does not publish the database port to the host,
- runs a `backup` service that takes nightly `pg_dump` snapshots into
  `./backups` (see [Backup and restore](#backup-and-restore)).

Check it's up:

```bash
curl http://localhost:8000/health
```

To stop: `make prod-down`.

All settings the backend reads (`backend/app/core/config.py`) are listed
with defaults in `.env.example` — see it for the full list
(`JWT_EXPIRY_DAYS`, `REFRESH_TOKEN_TTL_DAYS`, `INVITE_TOKEN_TTL_HOURS`,
`SCHEDULER_RUN_HOUR`, `INSTANCE_GENERATION_DAYS_AHEAD`,
`CORS_ALLOWED_ORIGINS`, etc.). Nothing needs to be set by editing the
compose YAML.

## Getting the app onto your phone

The Flutter workflow builds a release APK on every push and uploads it as a
build artifact (not a GitHub Release):

1. Go to the repo's **Actions** tab → the latest successful **Flutter**
   workflow run on `main` → download the `chore-app-<sha>` artifact and
   unzip it to get `app-release.apk`.
2. Install it on an Android device (you'll need to allow installs from
   unknown sources, since it isn't distributed through the Play Store).

**Current limitation**: the app's API base URL
(`flutter_app/lib/core/config/app_config.dart`) is a compile-time value
(`API_BASE_URL`, defaulting to `http://10.0.2.2:8000`, the Android emulator's
loopback address). CI builds the APK without overriding it, so the
CI-built APK will **not** work against your server as-is — it will try to
reach the emulator loopback address. Until in-app runtime server
configuration ships (see `docs/tasks.md` TASK-057), point the app at your
server by building it yourself with the flag set to your server's URL:

```bash
cd flutter_app
flutter build apk --release --dart-define=API_BASE_URL=https://chores.example.com
```

The same flag is what `make dev` uses to point a locally-run app at
`http://10.0.2.2:8000` for the Android emulator.

## HTTPS / reverse proxy

`docker-compose.prod.yml` publishes the API over plain HTTP on `API_PORT`
(default `8000`). For anything reachable outside your LAN, put a reverse
proxy with a real TLS certificate in front of it — don't expose port 8000
directly to the internet.

The backend image already runs uvicorn with `--proxy-headers`, so it will
honor `X-Forwarded-For`/`X-Forwarded-Proto` from a trusted proxy, but only
from IPs listed in `FORWARDED_ALLOW_IPS` (see `.env.example`; default
`127.0.0.1`, correct when the proxy runs on the same host and connects via
the published `API_PORT`). If you instead run the proxy as another
container on the same compose network, set `FORWARDED_ALLOW_IPS` to that
container's service name or the network's CIDR.

### Example: Caddy (automatic HTTPS)

```
# Caddyfile
chores.example.com {
    reverse_proxy localhost:8000
}
```

Caddy obtains and renews a Let's Encrypt certificate automatically as long
as the domain's DNS points at this host and ports 80/443 are reachable.

### Example: nginx

```nginx
server {
    listen 443 ssl;
    server_name chores.example.com;

    ssl_certificate     /etc/letsencrypt/live/chores.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chores.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Whichever proxy you use, also set `APP_BASE_URL` in `.env` to the public
`https://` URL so links the backend generates (e.g. invites) are correct.

## Backup and restore

`docker-compose.prod.yml` includes a `backup` service
(`prodrigestivill/postgres-backup-local`) that takes automatic `pg_dump`
snapshots into `./backups` on the host:

- schedule: daily (`BACKUP_SCHEDULE`, default `@daily`)
- retention: 7 daily / 4 weekly (`BACKUP_KEEP_DAYS` / `BACKUP_KEEP_WEEKS`,
  see `.env.example`)

For an on-demand backup instead of waiting for the schedule:

```bash
make backup
# writes backups/choreapp_<timestamp>.dump (pg_dump -Fc, custom format)
```

### Restoring

```bash
make restore FILE=backups/choreapp_20260101_030000.dump
```

This stops the `api` service, restores the dump into the running `db`
service with `pg_restore --clean --if-exists` (drops and recreates existing
objects before restoring), then restarts `api`. Equivalent manual steps:

```bash
podman compose -f docker-compose.prod.yml stop api
cat backups/choreapp_20260101_030000.dump | \
  podman compose -f docker-compose.prod.yml exec -T db \
  pg_restore -U choreapp -d choreapp --clean --if-exists
podman compose -f docker-compose.prod.yml start api
```

Restoring onto a completely fresh volume (e.g. after disk loss): start only
`db` (`docker compose -f docker-compose.prod.yml up -d db`), wait for it to
report healthy, run the `pg_restore` command above, then start `api`.

## Development setup

Requires Podman (or Docker — see below) with the Compose plugin, and the
Flutter SDK for running the app.

```bash
cp .env.example .env      # fill in JWT_SECRET at minimum
make dev
```

`make dev` starts `docker-compose.yml` (source-mounted, `--reload`,
`DEBUG=true`), waits for `/health`, runs migrations, then launches the
Flutter app against `http://10.0.2.2:8000` (Android emulator).

Other useful targets (see `Makefile`):

- `make up` / `make down` — start/stop the dev stack without launching Flutter.
- `make migrate` / `make downgrade` — run Alembic migrations.
- `make test` — run the backend test suite (`pytest`) inside the container.
- `make logs`, `make shell`, `make db-shell` — inspect the running dev stack.

By default the Makefile shells out to `podman compose`. To use Docker
instead:

```bash
COMPOSE="docker compose" make up
```

### Running tests directly

Backend tests need a real PostgreSQL instance and `TEST_DATABASE_URL` set
(see `backend/.env.example`); CI (`.github/workflows/ci.yml`) runs them
against a `postgres:16` service container on port 5432. Locally:

```bash
cd backend
uv sync --extra test
TEST_DATABASE_URL=postgresql+asyncpg://choreapp:choreapp_dev@localhost:5432/choreapp_test \
  uv run pytest tests/ -v
```

Frontend tests and analysis:

```bash
cd flutter_app
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
```

## More documentation

- `docs/requirements.md` — product requirements.
- `docs/backend-report.md` / `docs/frontend-report.md` — architecture and
  code-quality reports.
- `docs/tasks.md` — the project's task backlog (including known
  limitations referenced above, e.g. TASK-057 for in-app server URL
  configuration).
