# Backend Report — ChoreApp API

**Date:** 2026-07-01  
**Branch:** master (`a79405f`)  
**Stack:** FastAPI 0.138+, SQLAlchemy 2.0 async, PostgreSQL (asyncpg), APScheduler 3.x, Pydantic v2, Python 3.12

---

## Executive Summary

The backend is a well-structured FastAPI application with a clean three-layer architecture, correct async patterns, solid transaction management, and a meaningful test suite. The core business logic (chore lifecycle, leaderboard, household management, invite system) is largely correct and bug-free.

However, the application is **not ready for production** in its current state. Two critical security issues must be fixed first: credentials are committed to git, and unauthenticated users can read any household's chores. Beyond those, there are significant gaps in the operational layer (rate limiting, token revocation, observability, deployment hardening) and several schema validation gaps that produce HTTP 500s instead of clean 422s.

| Category | Score |
|---|---|
| Code Quality | 7 / 10 |
| Architecture | 7 / 10 |
| Error Handling | 6.5 / 10 |
| Type Safety | 6 / 10 |
| Test Coverage | 6.5 / 10 |
| Maintainability | 7 / 10 |
| **Overall Code Quality** | **7.0 / 10** |
| **Security Rating** | **4.5 / 10** |
| **Implementation Completeness** | **~72%** |

---

## 1. Implementation Completeness

### Feature Completion by Domain

| Domain | Completion | Notes |
|---|---|---|
| Authentication | 70% | Register + login solid; no token refresh, no revocation, no password reset |
| User profile | 60% | GET + PATCH display_name; no password change, no account deletion |
| Households CRUD | 80% | Create/list/get/rename; no delete |
| Members management | 90% | List, remove, role-change, leave — all with admin guards |
| Invites | 70% | Generate + accept; no list-active or revoke |
| Chores CRUD | 80% | Full definition lifecycle, instance completion, filtering; no reassign, no skip, no pagination |
| Leaderboard | 90% | Three scopes, dense ranking, zero-point members included |
| Background scheduler | 80% | Daily generate + flag-overdue, idempotent; not safe under multiple workers |
| Testing | 85% | Wide coverage; fixture code heavily duplicated |
| Security hardening | 50% | JWT works; no rate limiting, no security headers, no CORS, no revocation |
| Deployment readiness | 50% | Dockerfile exists; no health check, runs as root, no migration step on startup |
| Observability | 10% | stdlib `logging` only; no structured logs, no metrics, no tracing |

### Implemented Endpoints (26 total)

| Method | Path | Status | Notes |
|---|---|---|---|
| POST | `/auth/register` | Complete | Email uniqueness check, 409 on collision |
| POST | `/auth/login` | Complete | Enumeration-hardened 401 |
| GET | `/users/me` | Complete | |
| PATCH | `/users/me` | Complete | `display_name` only |
| POST | `/households` | Complete | Creator becomes admin |
| GET | `/households` | Complete | Includes role + member count via subquery |
| GET | `/households/{id}` | Complete | Member count |
| PATCH | `/households/{id}` | Complete | Rename, admin only |
| GET | `/households/{id}/members` | Complete | |
| DELETE | `/households/{id}/members/{uid}` | Complete | Redistribution on remove |
| PATCH | `/households/{id}/members/{uid}/role` | Complete | Sole-admin guard |
| POST | `/households/{id}/leave` | Complete | Sole-admin guard |
| POST | `/households/{id}/invites` | Complete | |
| POST | `/invites/{token}/accept` | Complete | Idempotency check |
| POST | `/households/{id}/chores` | Complete | Creates definition + first instance, round-robin or manual |
| GET | `/households/{id}/chores` | **Partial** | No pagination; **authorization bug** (see §2) |
| GET | `/households/{id}/chores/{iid}` | **Partial** | **Authorization bug** (see §2) |
| POST | `/households/{id}/chores/{iid}/complete` | Complete | Row locking, PointLedger, assignee-only guard |
| PATCH | `/households/{id}/chores/{did}` | Complete | Partial update via `exclude_unset` |
| DELETE | `/households/{id}/chores/{did}` | Complete | Soft-delete, cancels pending instances |
| GET | `/households/{id}/leaderboard` | Complete | `all_time`, `this_week`, `this_month` |
| GET | `/health` | Stub | Returns `{"status": "ok"}` without DB probe |

### What Is Missing

**High-priority (blocking production):**
- No rate limiting on any endpoint — auth endpoints are open to brute-force
- Authorization bypass on chore read endpoints (any authenticated user can read any household)
- No token refresh or revocation endpoint
- No pagination on `GET /chores` — unbounded SELECT on a table that grows indefinitely
- Recurrence rule key mismatch: schema uses `interval_unit`/`interval_n`, some tests and integration paths send `unit`/`interval`

**Medium-priority (feature gaps):**
- No chore reassignment endpoint (`PATCH /chores/{iid}/reassign`)
- No invite management (`GET /invites`, `DELETE /invites/{token}`)
- No household deletion
- No password change or reset flow
- No push notifications for assignments, due dates, or overdue chores
- Shallow health check — cannot distinguish app alive vs. DB alive

**Low-priority (polish):**
- No API versioning (`/api/v1/`)
- No CORS middleware
- No security headers
- No structured logging or request IDs
- No Prometheus/OpenTelemetry metrics
- `rotation_pointer` exposed in all household responses — internal implementation detail

---

## 2. Security Audit

**Overall Security Rating: 4.5 / 10** — Not suitable for production without addressing Critical and High findings.

| Severity | Count |
|---|---|
| Critical | 2 |
| High | 4 |
| Medium | 8 |
| Low | 9 |

### Critical

**SEC-001 — Credentials committed to version control**  
`backend/.env` is not excluded by `.gitignore` and is committed to the repository. It contains a live `DATABASE_URL` and `JWT_SECRET`. `docker-compose.yml` also hardcodes credentials.

*Impact:* Full database access + ability to forge arbitrary JWT tokens for any user.

*Fix:*
1. Add `.env` to `backend/.gitignore` immediately.
2. Rotate the PostgreSQL password and `JWT_SECRET` now.
3. Purge the file from git history (BFG Repo-Cleaner or `git filter-branch`).
4. In `docker-compose.yml`, use `env_file: .env` rather than inline values.
5. Add `git-secrets` or `trufflehog` to CI to prevent future leakage.

---

**SEC-002 — Weak, predictable JWT signing secret**  
Both `.env` (`test-secret-for-local-dev-change-in-production`) and `docker-compose.yml` (`dev_secret_change_in_production`) use human-readable, low-entropy secrets. A captured JWT can be cracked offline.

*Fix:* Generate a cryptographically random secret (`python -c "import secrets; print(secrets.token_hex(32))"`) and validate minimum length at startup in `config.py`.

---

### High

**SEC-003 — IDOR: Chore read endpoints missing household membership check**  
`app/api/chores.py:164` and `app/api/chores.py:203` use `Depends(get_current_user)` instead of `Depends(require_household_member)`. Any authenticated user who knows a household UUID can enumerate all chore instances and assignees.

*Fix:*
```python
# chores.py — list_chores and get_chore_instance
_membership: HouseholdMembership = Depends(require_household_member)  # replace get_current_user
```

---

**SEC-004 — No rate limiting on auth endpoints**  
`POST /auth/login` and `POST /auth/register` accept unlimited requests. Enables credential stuffing and account enumeration at scale.

*Fix:* Add `slowapi` middleware, limit `/auth/login` to ~5 req/min per IP, add account lockout after N consecutive failures.

---

**SEC-005 — Container runs as root**  
`backend/Dockerfile` has no `USER` directive. RCE in any dependency grants root inside the container.

*Fix:* Add `RUN addgroup --system app && adduser --system --ingroup app app` + `USER app` before the `CMD`.

---

**SEC-006 — No JWT revocation or logout mechanism**  
7-day tokens have no revocation path. A stolen token is valid until expiry; there is no logout endpoint.

*Fix:* Add a `jti` claim to every JWT, maintain a token blocklist (Redis), and add `POST /auth/logout`.

---

### Medium (summary)

| ID | Description | File |
|---|---|---|
| SEC-007 | Enum fields (`category`, `effort_level`, `chore_type`) are plain `str` — invalid values cause HTTP 500 instead of 422 | `app/schemas/chore.py:17–19` |
| SEC-008 | Manual chore assignee not validated as household member — any user ID accepted | `app/api/chores.py:102–105` |
| SEC-009 | OpenAPI docs (`/docs`, `/redoc`, `/openapi.json`) exposed with no access control in production | `main.py` |
| SEC-010 | PostgreSQL port `5432` bound to all host interfaces in `docker-compose.yml` | `docker-compose.yml:9` |
| SEC-011 | `display_name` lacks `max_length=100` — strings over 100 chars cause HTTP 500 | `app/api/users.py:15` |
| SEC-012 | No security headers (`X-Content-Type-Options`, `X-Frame-Options`, `Strict-Transport-Security`) | `main.py` |
| SEC-013 | Unlimited active invite tokens per household — no revocation or cap | `app/api/invites.py:29–54` |
| SEC-014 | Password policy: no `max_length` (bcrypt silently truncates at 72 bytes, enabling same-prefix collision) and no complexity requirements | `app/schemas/auth.py:8–11` |

### Low (summary)

| ID | Description |
|---|---|
| SEC-015 | Email enumeration via `POST /auth/register` returning 409 with "Email already registered" |
| SEC-016 | Scheduler uses `date.today()` (local timezone) while APScheduler runs in UTC — wrong date near midnight |
| SEC-017 | `rotation_pointer` exposed in household response schemas — leaks internal algorithm state |
| SEC-018 | `passlib` unmaintained since 2022; `bcrypt<4.0.0` pin blocks security patches |
| SEC-019 | No security audit logging (failed logins, role changes, member removal) |
| SEC-020 | `--reload` flag active in `docker-compose.yml` production command |
| SEC-021 | `RecurrenceRule.interval_n` has no upper bound (`ge=1` only) |
| SEC-022 | Host volume mount exposes entire `backend/` directory including `.venv` and secrets |
| SEC-023 | No CORS configuration — `allow_origins=["*"]` risk if added later without thought |

### Positive Security Findings

These controls are implemented correctly and should be maintained:
- All DB operations use SQLAlchemy ORM with parameterized queries — **no SQL injection risk**
- Login returns identical error for unknown email and wrong password — **enumeration hardened**
- Write endpoints on chores, members, and households correctly gate on `require_admin` or `require_household_member`
- Sole-admin guard prevents household lockout on member removal and leave
- Invite tokens use `secrets.token_urlsafe(16)` — 128 bits of entropy
- Single-use invite tokens protected with `used_at` flag set atomically
- `SELECT FOR UPDATE` in `complete_chore_instance` prevents double-completion race
- UUID primary keys throughout — ID enumeration infeasible
- bcrypt password hashing with salt — no plaintext storage
- JWT `exp` claim set and verified; algorithm pinned to prevent algorithm-switching attacks

---

## 3. Code Quality

### Architecture

The codebase demonstrates clear architectural intent: route handlers → service layer → ORM. The `AssignmentStrategy` Protocol with `RoundRobinStrategy` is well-designed. The `deps.py` dependency stack (`get_current_user` → `require_household_member` → `require_admin`) is composable and reusable.

**Issues:**

- `complete_chore_instance` (`chores.py:241–323`) contains ~80 lines of business logic (status transitions, point calculation, ledger creation) that belongs in a `ChoreService` — not in the route handler.
- `create_chore` (`chores.py:71–148`) manually orchestrates definition creation, instance creation, and display-name resolution inline.
- `redistribution.py:113` instantiates `AssignmentService(RoundRobinStrategy())` directly, bypassing the injection pattern used elsewhere.
- Complex aggregation queries (leaderboard, household list) live inline in route handlers — no query/repository layer.

### Type Safety Gaps

All five of these accept arbitrary strings but should use `Literal` types:

```python
# app/schemas/chore.py — current (broken)
category: str         # should be Literal["kitchen", "bathroom", ...]
effort_level: str     # should be Literal["easy", "medium", "hard"]
chore_type: str       # should be Literal["one_off", "recurring"]
interval_unit: str    # should be Literal["days", "weeks", "months"]

# app/schemas/chore.py — ChoreDefinitionResponse
recurrence_rule: Optional[dict]  # should be Optional[RecurrenceRule]
```

Invalid values pass Pydantic validation, hit the PostgreSQL enum constraint, and return HTTP 500.

### Dead Code and Inconsistencies

- `chores.py:233`: `_COMPLETABLE_STATUSES` is defined but never referenced — the guard at line 278 uses `_TERMINAL_STATUSES`.
- `test_chores.py:205`: `_recurring_payload` is defined but never called.
- `security.py:4`: docstring says "Stubs — full implementation comes in a later task" — the module is fully implemented.
- `Optional[str]` and `str | None` used inconsistently in the same file (`chores.py`); Python 3.12 project should use `X | None` uniformly.

### Error Handling

- `GET /households/{id}/chores` `status_filter` and `category` query parameters accept arbitrary strings with no validation — an invalid value silently returns an empty list instead of a 422.
- Leaderboard `window_end` uses `time(23, 59, 59)` — timestamps between `23:59:59.000001` and `23:59:59.999999` on the period boundary are excluded.
- `accept_invite` uses `scalar_one()` on the household lookup — if the household was hard-deleted after token creation, a 500 is returned instead of a 410.

### Test Suite

The test suite has good breadth (16 files covering all routers, services, scheduler, and integration flows) and correctly uses real PostgreSQL — not mocks.

**Critical issue — confirmed key mismatch:** `test_integration.py:318` sends `{"unit": "weeks", "interval": 1}` but `RecurrenceRule` requires `interval_unit` and `interval_n`. In Pydantic v2 with default `extra="ignore"`, these unknown keys are dropped and the required fields are missing, causing a 422. The test asserts 201. The comment block at `test_integration.py:18–26` acknowledges "a key mismatch" but misattributes it to the scheduler's storage format.

**DRY violations:** `_get_test_database_url()` is duplicated in 9 test files. The `async_client` fixture is duplicated in ~8 test files. A single `conftest.py` fixture would eliminate ~300 lines of duplication and prevent fixture drift.

**Missing test cases:**
- Reading chores as a non-member (the authorization bypass is untested)
- Passing invalid `category`, `effort_level`, or `chore_type` values
- PATCH on a chore definition from a different household
- `flag_overdue_instances` on the exact `due_date == today` boundary

### Performance (N+1 patterns)

- `redistribution.py:104–117`: One `SELECT FOR UPDATE` per chore instance inside a loop — ten pending chores = ten lock acquisitions on the same `households` row.
- `scheduler.py:118–123`: One `SELECT due_date WHERE definition_id = ?` per definition inside the scheduler loop — 100 definitions = 100 round-trips. Should be a single aggregated query.

### Dependencies

| Package | Issue |
|---|---|
| `passlib` | Last release 2022, effectively unmaintained |
| `bcrypt<4.0.0` | Version cap blocks security fixes from bcrypt 4.x |
| `python-jose` | Known CVEs, last release 2022; replace with `PyJWT` |
| `pytest`, `httpx`, `pytest-cov` | In `[project]` dependencies — installed in production containers |

---

## 4. Prioritized Action Plan

### Immediate (security/correctness — do before any deployment)

1. **Purge `.env` from git, rotate credentials** — `backend/.gitignore`, `docker-compose.yml`
2. **Generate a strong `JWT_SECRET`** — `python -c "import secrets; print(secrets.token_hex(32))"`
3. **Fix IDOR on chore read endpoints** — replace `Depends(get_current_user)` with `Depends(require_household_member)` at `app/api/chores.py:164` and `app/api/chores.py:203`
4. **Fix recurrence rule key mismatch** — align `test_integration.py:318` to send `interval_unit`/`interval_n`, or add Pydantic field aliases to `RecurrenceRule`

### Short-term (1–2 weeks)

5. Add rate limiting via `slowapi` on `/auth/login` and `/auth/register`
6. Add non-root `USER` to `backend/Dockerfile`
7. Replace `str` with `Literal` types for `category`, `effort_level`, `chore_type`, `interval_unit` in `app/schemas/chore.py`
8. Add `max_length=72` to password field in `app/schemas/auth.py`
9. Add database probe to `/health` endpoint
10. Disable `/docs` and `/openapi.json` in production (`DEBUG` flag in `Settings`)
11. Remove PostgreSQL `ports: "5432:5432"` from `docker-compose.yml`
12. Consolidate `_get_test_database_url()` and `async_client` fixture into `tests/conftest.py`
13. Move test dependencies (`pytest`, `httpx`, `pytest-cov`) to `[project.optional-dependencies.test]`

### Medium-term (1 month)

14. Implement `POST /auth/logout` with JWT blocklist (add `jti` claim + Redis blocklist)
15. Implement `POST /auth/refresh` with short-lived access token + long-lived refresh token
16. Add chore reassignment endpoint (`PATCH /households/{id}/chores/{iid}` with `assignee_id`)
17. Add pagination to `GET /households/{id}/chores` (`limit`/`offset` or cursor-based)
18. Add invite management endpoints (`GET /invites`, `DELETE /invites/{token}`)
19. Add security headers middleware (`X-Content-Type-Options`, `X-Frame-Options`, `HSTS`)
20. Replace `passlib` + `python-jose` with `bcrypt>=4.0.0` and `PyJWT`
21. Fix scheduler timezone: replace `date.today()` with `datetime.now(timezone.utc).date()` in `app/tasks/scheduler.py:37`
22. Remove `rotation_pointer` from all response schemas
23. Add PostgreSQL advisory lock in `run_daily_job` to handle multi-worker deployments
24. Fix N+1 in `redistribution.py` and `scheduler.py`
25. Add `max_length` constraints to `UpdateProfileRequest.display_name` and `HouseholdCreate.name`

### Long-term (v2 features)

26. Push notifications for chore assignments and overdue reminders (device token model + FCM/APNS)
27. Structured logging with `structlog` — include `request_id`, `user_id`, `household_id` per request
28. Prometheus metrics via `prometheus-fastapi-instrumentator`
29. API versioning (`/api/v1/` prefix)
30. Password reset flow (forgot-password email + time-limited reset token)
31. Household deletion with cascading cleanup
32. Extract `ChoreService` from route handlers to isolate business logic

---

## 5. Recommended Dockerfile (Production)

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN pip install uv
COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-dev --no-editable

FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN addgroup --system app && adduser --system --ingroup app app
COPY --from=builder /app/.venv /app/.venv
COPY . .
USER app

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

CMD ["/app/.venv/bin/uvicorn", "main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]
```

---

## 6. Key File Reference

| File | Primary Issues |
|---|---|
| `backend/.env` | Committed credentials (SEC-001) |
| `backend/.gitignore` | Missing `.env` exclusion (SEC-001) |
| `docker-compose.yml` | Hardcoded secrets, exposed DB port, `--reload` flag (SEC-001, SEC-010, SEC-020) |
| `app/api/chores.py:164,203` | IDOR — missing `require_household_member` (SEC-003) |
| `app/api/chores.py:102–105` | Assignee not validated as household member (SEC-008) |
| `app/schemas/chore.py:9–19` | Unvalidated enum strings (SEC-007, type safety) |
| `app/schemas/auth.py:8–11` | Weak password policy (SEC-014) |
| `app/api/users.py:15` | Missing `max_length` on display_name (SEC-011) |
| `app/api/health.py` | Shallow health check — no DB probe |
| `app/core/security.py` | No JWT revocation (SEC-006) |
| `app/tasks/scheduler.py:37` | Wrong timezone `date.today()` (SEC-016), N+1 query |
| `app/schemas/household.py:19–21` | `rotation_pointer` exposed (SEC-017) |
| `Dockerfile` | Runs as root, no HEALTHCHECK (SEC-005) |
| `pyproject.toml` | Test deps in wrong group; unmaintained deps |
| `tests/conftest.py` | Fixture consolidation target (DRY violations across 9 test files) |
| `tests/test_integration.py:318` | Confirmed broken recurrence rule key mismatch |
