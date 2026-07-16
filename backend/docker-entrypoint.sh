#!/bin/sh
# Production entrypoint: run pending Alembic migrations, then start uvicorn.
#
# Running migrations on container startup is safe here because self-hosted
# deployments run a single API instance (see docker-compose.prod.yml) — there
# is no risk of two instances racing to apply the same migration.
#
# This script is the image's default CMD. It is NOT used in local
# development: docker-compose.yml overrides `command:` with a plain
# `uv run uvicorn ... --reload`, which bypasses this script entirely and
# leaves migrations to `make migrate` / `make dev`.
set -eu

echo "docker-entrypoint: running database migrations (alembic upgrade head)..."
alembic upgrade head

echo "docker-entrypoint: starting uvicorn..."
exec uvicorn main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --proxy-headers \
    --forwarded-allow-ips "${FORWARDED_ALLOW_IPS:-127.0.0.1}"
