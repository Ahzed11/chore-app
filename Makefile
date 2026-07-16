FLUTTER := $(HOME)/.local/share/flutter/bin/flutter

# Override to use Docker instead of Podman, e.g.:
#   COMPOSE="docker compose" make up
COMPOSE ?= podman compose
PROD_COMPOSE := $(COMPOSE) -f docker-compose.prod.yml

.PHONY: up down migrate downgrade test logs shell db-shell dev \
	prod-up prod-down prod-logs prod-shell prod-db-shell prod-migrate \
	backup restore

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

migrate:
	$(COMPOSE) exec api uv run alembic upgrade head

downgrade:
	$(COMPOSE) exec api uv run alembic downgrade -1

test:
	$(COMPOSE) exec api uv run pytest tests/ -v

logs:
	$(COMPOSE) logs -f api

shell:
	$(COMPOSE) exec api bash

db-shell:
	$(COMPOSE) exec db psql -U choreapp choreapp

dev:
	$(COMPOSE) up -d
	@echo "Waiting for API to be healthy..."
	@until $(COMPOSE) exec api curl -sf http://localhost:8000/health > /dev/null 2>&1; do sleep 1; done
	$(COMPOSE) exec api uv run alembic upgrade head
	cd flutter_app && $(FLUTTER) run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# ---- Production (docker-compose.prod.yml) --------------------------------
# See README.md for full self-hosting instructions.

prod-up:
	$(PROD_COMPOSE) up -d

prod-down:
	$(PROD_COMPOSE) down

prod-logs:
	$(PROD_COMPOSE) logs -f api

prod-shell:
	$(PROD_COMPOSE) exec api bash

prod-db-shell:
	$(PROD_COMPOSE) exec db psql -U choreapp choreapp

# Migrations normally run automatically on api startup (docker-entrypoint.sh);
# this is only needed to apply a new migration without restarting the api.
prod-migrate:
	$(PROD_COMPOSE) exec api alembic upgrade head

# ---- Backup / restore ------------------------------------------------------
# The `backup` service in docker-compose.prod.yml already takes automatic
# nightly dumps into ./backups with 7 daily / 4 weekly retention. These
# targets are for on-demand backups and for restoring.

backup:
	@mkdir -p backups
	$(PROD_COMPOSE) exec -T db pg_dump -U choreapp -Fc choreapp > backups/choreapp_$$(date +%Y%m%d_%H%M%S).dump
	@echo "Backup written to backups/"

# Usage: make restore FILE=backups/choreapp_20260101_030000.dump
# Stops the api, drops+recreates the schema from the dump, then restarts
# the api. See README.md "Backup and restore" for the full walkthrough.
restore:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore FILE=backups/choreapp_YYYYMMDD_HHMMSS.dump"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "File not found: $(FILE)"; \
		exit 1; \
	fi
	$(PROD_COMPOSE) stop api
	$(PROD_COMPOSE) exec -T db pg_restore -U choreapp -d choreapp --clean --if-exists < $(FILE)
	$(PROD_COMPOSE) start api
	@echo "Restore complete."
