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
(`.github/workflows/flutter.yml`) builds a release APK and publishes it as a
GitHub Release, which the self-hosted F-Droid repository
([chore-app-fdroid](https://github.com/Ahzed11/chore-app-fdroid)) indexes
automatically.

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
(`JWT_EXPIRY_MINUTES`, `REFRESH_TOKEN_TTL_DAYS`, `INVITE_TOKEN_TTL_HOURS`,
`SCHEDULER_RUN_HOUR`, `INSTANCE_GENERATION_DAYS_AHEAD`,
`CORS_ALLOWED_ORIGINS`, etc.). Nothing needs to be set by editing the
compose YAML.

## Getting the app onto your phone

The Flutter workflow builds a signed release APK on every push to `main` and
publishes it as a GitHub Release. The release is picked up automatically by
the project's self-hosted F-Droid repository, so updates arrive through your
F-Droid client — no manual APK downloads.

### Recommended: install via the F-Droid repository

1. Install the [F-Droid client](https://f-droid.org/) on your Android device.
2. Add the ChoreApp repository (Settings → Repositories → `+`), either by
   scanning the QR code in the
   [chore-app-fdroid repo](https://github.com/Ahzed11/chore-app-fdroid) or by
   entering the URL directly:

   ```
   https://raw.githubusercontent.com/Ahzed11/chore-app-fdroid/main/fdroid/repo?fingerprint=2F197F32A3F10720DCEB884640306EA6309E688839BF4AE8E97F056CA2D83F7F
   ```

3. Install **ChoreApp** from the repository. From then on, every release
   (each merge to `main` with a bumped `version` in `flutter_app/pubspec.yaml`)
   appears as an update in F-Droid automatically.

### Alternative: grab the APK from a GitHub Release

1. Go to the repo's **Releases** page → the latest `v*` release → download the
   attached `app-release.apk`.
2. Install it on an Android device (you'll need to allow installs from
   unknown sources, since it isn't distributed through the Play Store).

On first launch the app asks for your server's URL (e.g.
`https://chores.example.com`) and tests the connection before continuing;
you can change it later from the settings icon on the login and dashboard
screens. No custom build is needed — the CI-built APK works against any
server.

For development builds, the compile-time default
(`flutter_app/lib/core/config/app_config.dart`) can still be overridden:

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

## Chore reminder notifications

The nightly scheduler job can push a summary notification per household —
chores due today and chores that just became overdue, with assignee names —
via [ntfy](https://ntfy.sh) or [Gotify](https://gotify.net), two self-hostable
push services. This is entirely optional: it's off by default and stays off
until you set `NOTIFY_URL`.

**Option 1: the public ntfy.sh instance (fastest to try).** Pick a hard-to-guess
topic name and set in `.env`:

```bash
NOTIFY_URL=https://ntfy.sh/choreapp-<something-random>
```

Then subscribe from the phone: install the [ntfy Android
app](https://play.google.com/store/apps/details?id=io.heckel.ntfy), add the
same topic. No `NOTIFY_TOKEN` is needed for a public, unauthenticated topic
— anyone who knows the topic name can read it, so keep it random or self-host
instead for anything sensitive.

**Option 2: self-hosted ntfy alongside the stack.** Add an `ntfy` service to
`docker-compose.prod.yml` (or your own compose override):

```yaml
  ntfy:
    image: binwiederhier/ntfy
    restart: unless-stopped
    command: serve
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - ntfy_data:/var/cache/ntfy
```

then point the backend at it and put it behind the same reverse proxy as the
API (see [HTTPS / reverse proxy](#https--reverse-proxy)) so the phone app can
reach it from outside your LAN:

```bash
NOTIFY_URL=https://ntfy.example.com/choreapp
```

**Option 3: Gotify.** Run a Gotify server, create an application in its
admin UI to get an app token, then set:

```bash
NOTIFY_URL=https://gotify.example.com
NOTIFY_TOKEN=<the application token>
NOTIFY_KIND=gotify
```

(`NOTIFY_KIND` defaults to `ntfy`; the backend builds a different request
shape for each — a plain-text POST with a `Title` header for ntfy, a JSON
POST to `/message?token=...` for Gotify.) `NOTIFY_TOKEN` is also honored for
ntfy, as a Bearer `Authorization` header, for topics with access control
enabled.

All households currently share the single configured topic/server (a
notification's title names the household so multiple households sharing a
topic stay distinguishable) — see `.env.example` for the full list of
`NOTIFY_*` variables. Delivery failures are logged and never fail the nightly
job — a broken or unreachable notify endpoint never blocks chore instance
generation.

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
- `docs/tasks.md` — the project's task backlog (including known
  limitations referenced above, e.g. TASK-057 for in-app server URL
  configuration); completed task bodies live in `docs/archive/tasks-completed.md`.
- `docs/archive/backend-report-2026-07-15.md` / `docs/archive/frontend-report-2026-07-15.md`
  — the architecture and code-quality reports that produced the current task backlog.
