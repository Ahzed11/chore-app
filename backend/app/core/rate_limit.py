"""Shared slowapi Limiter instance (TASK-031).

Defined in its own module — rather than directly in ``main.py`` — so that
``app/api/auth.py`` can decorate its routes with the same ``Limiter`` without
creating a circular import (``main.py`` imports the auth router).
"""
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings

# get_remote_address keys on `request.client.host`, i.e. the ASGI scope's
# client address. When uvicorn runs with --proxy-headers (see
# backend/docker-entrypoint.sh / README "HTTPS / reverse proxy") and the
# proxy's address is in --forwarded-allow-ips, uvicorn's own
# ProxyHeadersMiddleware rewrites that scope client from X-Forwarded-For
# *before* the ASGI app ever sees the request. So this stays correct behind a
# trusted reverse proxy without this app parsing forwarded headers itself.
#
# `enabled` and the per-route limit strings (see app/api/auth.py) are read
# dynamically off `settings` at request time rather than baked in here, which
# lets the test suite flip rate limiting on/off and swap in tight limits at
# runtime (see backend/tests/conftest.py and tests/test_rate_limit.py).
limiter = Limiter(
    key_func=get_remote_address,
    enabled=settings.RATE_LIMIT_ENABLED,
    headers_enabled=True,  # required for slowapi to emit the Retry-After header
)
