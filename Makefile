FLUTTER := $(HOME)/.local/share/flutter/bin/flutter

.PHONY: up down migrate test logs shell dev

up:
	podman compose up -d

down:
	podman compose down

migrate:
	podman compose exec api uv run alembic upgrade head

downgrade:
	podman compose exec api uv run alembic downgrade -1

test:
	podman compose exec api uv run pytest tests/ -v

logs:
	podman compose logs -f api

shell:
	podman compose exec api bash

db-shell:
	podman compose exec db psql -U choreapp choreapp

dev:
	podman compose up -d
	@echo "Waiting for API to be healthy..."
	@until podman compose exec api curl -sf http://localhost:8000/health > /dev/null 2>&1; do sleep 1; done
	podman compose exec api uv run alembic upgrade head
	cd flutter_app && $(FLUTTER) run --dart-define=API_BASE_URL=http://10.0.2.2:8000
