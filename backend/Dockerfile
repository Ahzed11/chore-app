# ---- builder stage ----
FROM python:3.12-slim AS builder

WORKDIR /app

RUN pip install uv

COPY pyproject.toml uv.lock* ./
# Install only production deps (no test group)
RUN uv sync --frozen --no-dev

# ---- runtime stage ----
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# Create non-root user
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --no-create-home appuser

# Copy venv from builder
COPY --from=builder /app/.venv /app/.venv

# Copy source
COPY . .

# Ensure the migration+startup entrypoint is executable regardless of the
# host filesystem's permission bits at build time.
RUN chmod +x docker-entrypoint.sh

# Own the workdir
RUN chown -R appuser:appgroup /app

USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Default (production) command: run pending migrations, then start uvicorn.
# See docker-entrypoint.sh. Local dev (docker-compose.yml) overrides this
# with a plain `uv run uvicorn ... --reload` command that bypasses it.
CMD ["./docker-entrypoint.sh"]
