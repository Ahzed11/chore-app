# Backend Report — ChoreApp API

**Date:** 2026-07-15 (supersedes the 2026-07-01 report)
**Branch:** `claude/brave-ritchie-1owy48`
**Stack:** FastAPI 0.138+, SQLAlchemy 2.0 async, PostgreSQL (asyncpg), APScheduler 3.x, Pydantic v2, PyJWT, bcrypt 5.x, Python 3.12

> This review ran the full test suite against a local PostgreSQL 16 (137 tests), applied migrations to a fresh database (clean, zero autogenerate drift), and verified several findings live against a running server.

---

## Executive Summary

Nearly all of the 2026-07-01 report's findings were fixed (TASK-028..044), and the fixes are genuine: IDOR closed, JWT revocation + refresh implemented, enums validated, Dockerfile hardened, scheduler UTC + advisory-locked, invite management and reassignment endpoints added.

However, this review found one **showstopper regression**: **`POST /auth/login` returns HTTP 500 on every call.** TASK-042 removed the `expires_delta` parameter from `create_access_token`, but `app/api/auth.py:78-81` still passes it. 68 of 137 tests fail on this single error. The branch merged without CI ever running — CI only triggers on `main`/`master` — which is the systemic issue behind it.

Beyond that: rate limiting (TASK-031) was never implemented, access tokens still live 7 days (defeating the refresh/revocation system), pagination has no ORDER BY, and the self-hosting operational layer (production compose file, startup migrations, backups, README) doesn't exist yet.

| Category | Score |
|---|---|
| Code Quality | 7.5 / 10 |
| Architecture | 7.5 / 10 |
| Security | 6.5 / 10 (was 4.5) |
| Test Suite | 6 / 10 (broken gate, slow, 68 failing due to C1) |
| Self-Hosting Readiness | 4 / 10 |

---

## 1. Verification of Previous Findings (TASK-028..044)

| Old finding | Status | Evidence |
|---|---|---|
| SEC-001 committed `.env` | **Fixed** | Untracked, gitignored, dockerignored; `git log --all -- backend/.env` empty |
| SEC-002 weak JWT secret | **Partial** | Compose requires `${JWT_SECRET:?}`; but `config.py:11` accepts any string — no min-length/placeholder validation |
| SEC-003 IDOR on chore reads | **Fixed** | `chores.py:185,240` use `require_household_member`; non-member 403 tested |
| SEC-004 rate limiting (TASK-031) | **NOT DONE** | No limiter anywhere in `backend/` — the only TASK-028..044 item never implemented |
| SEC-005 root container | **Fixed** | Multi-stage Dockerfile, `USER appuser`, `HEALTHCHECK` |
| SEC-006 revocation/logout | **Fixed** | `jti` claim, `revoked_tokens` checked in `deps.py:42-52`, `POST /auth/logout`. Caveats: double logout → 409, no cleanup job (M1, M2) |
| Token refresh (TASK-038) | **Fixed** | Hashed stored tokens + rotation — but see C1 for the login regression that rode in alongside |
| SEC-007 enum validation | **Fixed for bodies only** | `schemas/chore.py:9-21` uses `Literal`s; query params `status_filter`/`category` still plain `str` → verified live HTTP 500 (H5) |
| Pagination (TASK-039) | **Fixed, with a bug** | No ORDER BY on the paged query (H3) |
| N+1 (TASK-041) | **Mostly fixed** | Scheduler pre-fetch + bulk redistribution; remaining per-instance `auto_assign` loop in `scheduler.py:140-142` (M11) |
| SEC-016 scheduler UTC | **Fixed in scheduler only** | `leaderboard.py:32-34` still uses local `date.today()` (M9) |
| Advisory lock (TASK-044) | **Fixed** | `pg_try_advisory_xact_lock` in `scheduler.py:196-201` |
| Health check | **Fixed** | `SELECT 1`, 503 on failure |
| Headers/CORS (TASK-037) | **Fixed** | `main.py:50-92`; docs disabled when `DEBUG=false`; length constraints in place |
| Invite management (TASK-040) | **Fixed** | List + revoke endpoints, single-active-invite cap |
| Reassignment endpoint | **Fixed** | `chores.py:372-449` with member validation (no terminal-status guard — L3) |
| Fixtures (TASK-036) | **Fixed, gate broken** | Single conftest; but `--cov-fail-under=75` fails at 68% actual coverage (H4) |
| `rotation_pointer` exposure | **Fixed** | Absent from response schemas |
| Deps (TASK-042) | **Fixed — introduced C1** | bcrypt 5.x + PyJWT; login call site not updated |
| SEC-020/022 `--reload` + bind mount in compose | **NOT fixed** | `docker-compose.yml:26,37` — still a dev config, and it's the only compose file (M4) |
| Leaderboard 23:59:59 window gap | **NOT fixed** | `leaderboard.py:54,62` (M9) |

---

## 2. Findings

### Critical

**C1. [Bug/Regression] `POST /auth/login` is completely broken — every login returns HTTP 500**
`app/api/auth.py:78-81` calls `create_access_token(subject=..., expires_delta=expires_delta)`, but TASK-042 (commit `b231179`) removed the `expires_delta` parameter from `app/core/security.py:34`. `TypeError` on every login; **68 of 137 tests fail** on this one error. `tests/test_auth_middleware.py:101` also calls the removed kwarg. With a one-line patch applied locally, the suite goes to 136 passed / 1 failed (the 1 is H6).
*Fix:* restore `expires_delta: timedelta | None = None` on `create_access_token`, or drop the kwarg at both call sites. Root cause is H4 (no CI on working branches).

### High

**H1. [Security] No rate limiting on `/auth/login` and `/auth/register`** — TASK-031 never implemented. Unlimited credential stuffing; combined with register's 409 email enumeration, the biggest remaining auth gap. Self-hosted instances are commonly internet-exposed for family phones. *Fix:* `slowapi` with in-memory storage (fine for a single-process self-host), ~5/min login, ~3/min register per client IP.

**H2. [Security] 7-day access tokens defeat the revocation/refresh system** — `config.py:13` `JWT_EXPIRY_DAYS: int = 7` while rotated 30-day refresh tokens exist and the Flutter app implements the refresh flow. A stolen access token stays valid for 7 days. *Fix:* switch to `JWT_EXPIRY_MINUTES` (15–60 min).

**H3. [Bug] `GET /chores` pagination has no ORDER BY** — `chores.py:210-217`: `LIMIT/OFFSET` without ordering means pages can repeat/skip rows. *Fix:* `.order_by(ChoreInstance.due_date, ChoreInstance.id)`.

**H4. [Operational] CI never runs on working branches; the coverage gate fails anyway** — `.github/workflows/ci.yml` triggers only on push/PR to `main`/`master`; all work happens on `claude/*` branches merged locally — which is exactly how C1 shipped. With C1 patched, coverage is **68.1% vs the 75% `--cov-fail-under`**, so the next master push fails regardless. *Fix:* trigger on `push: branches: ['**']`; raise coverage (`redistribution.py` is at 25%) or lower the gate to reality.

**H5. [Bug] Invalid `status_filter`/`category` query values return HTTP 500** — verified live (`GET /chores?status_filter=bogus` → 500). `chores.py:179-180` accept arbitrary strings compared against native PG enums. *Fix:* type the query params with the existing `Literal` aliases so FastAPI returns 422.

**H6. [Bug/Test] Stale integration test breaks once login is fixed** — `tests/test_integration.py:283-285` still treats `GET /chores` as a bare list; since TASK-039 it's `{items, total, limit, offset}`. *Fix:* `instances = chores_resp.json()["items"]`.

### Medium

**M1. [Bug] Second logout with the same token returns 409** — `auth.py:184-193` inserts the `jti` unconditionally; duplicate PK → `IntegrityError`, swallowed by the blanket handler at `main.py:95-98`. Should be idempotent. The blanket IntegrityError→409 handler also masks real bugs.

**M2. [Operational] `revoked_tokens` and `refresh_tokens` grow forever** — both model docstrings promise a cleanup job that doesn't exist; every login inserts a refresh-token row with no per-user cap. *Fix:* purge expired rows in `run_daily_job`.

**M3. [Bug/Operational] Scheduler silently skips a day if the app isn't running at 00:00 UTC** — `scheduler.py:220-243`: no `misfire_grace_time`, nothing runs at startup. A home server rebooted overnight generates nothing until the next midnight. *Fix:* run `run_daily_job()` once in lifespan startup (idempotent + advisory-locked) and/or set `misfire_grace_time`.

**M4. [Operational] `docker-compose.yml` is a dev config presented as the only deployment path** — `--reload`, `DEBUG: "true"`, bind mount `./backend:/app` (hides the hardened image), no `env_file:` (so `REFRESH_TOKEN_TTL_DAYS`, `CORS_ALLOWED_ORIGINS`, `SCHEDULER_RUN_HOUR` can't be set without editing YAML), no migrations on startup. Old SEC-020/SEC-022 effectively unfixed. *Fix:* production compose file/profile — no mount, no reload, `DEBUG=false`, `env_file`, entrypoint running `alembic upgrade head` before uvicorn; use the GHCR image CI already builds.

**M5. [Operational] No backup story** — the Postgres volume is the household's entire data; nothing dumps it. *Fix:* `pg_dump` sidecar or `make backup`/cron target + restore documentation.

**M6. [Missing feature] No password change or reset** — a forgotten password is unrecoverable without psql. For self-host without SMTP: authenticated `POST /users/me/password` (verify old password, revoke all refresh tokens), plus a small CLI script for admin resets.

**M7. [Missing feature] No account deletion, no household deletion** — FK cascades are already defined; implementation is mostly authorization + sole-admin/last-member semantics.

**M8. [Bug] Emails are case-sensitive** — `auth.py:32,58`: `Alex@…` and `alex@…` are distinct accounts. *Fix:* lowercase-normalize on register/login + data migration (or `citext`/functional unique index).

**M9. [Bug] Leaderboard time-window issues** — `leaderboard.py:32-34` uses local `date.today()` (wrong boundaries on non-UTC hosts, inconsistent with the UTC scheduler); `:54,62` cap windows at `23:59:59`, excluding the final second. *Fix:* UTC dates + exclusive `< next_period_start` upper bound.

**M10. [Improvement] Refresh-token replay not treated as theft; inconsistent response shape** — replaying a rotated token → 401 only; standard hardening revokes all the user's refresh tokens on reuse. The endpoint also returns a bare dict while login returns `TokenResponse` — declare `response_model=TokenResponse`.

**M11. [Improvement] Scheduler backfills unbounded past instances** — `scheduler.py:130-134` generates every due date from `first_due_date`; after downtime a daily chore floods the household with instantly-overdue instances, each advancing the rotation pointer. Also the per-instance `auto_assign` loop (`:140-142`) remains an N+1. *Fix:* start at `max(first_due_date, today - grace)`; reuse the bulk single-lock assignment pattern.

**M12. [Improvement] No JWT_SECRET strength validation** — `config.py:11`. Add a `field_validator` requiring ≥32 chars and rejecting the `.env.example` placeholder.

### Low

**L1. [Bug] Rotation-pointer adjustment on member removal is wrong for pointers ≥ member count** — `redistribution.py:121-130` compares `removed_index` against the raw unbounded pointer (`assignment.py:55` stores `pointer+1` unmodded), so the decrement fires almost always. *Fix:* compare against `original_pointer % member_count`, or store the pointer modulo N.

**L2. [Bug] Invite-accept race** — `invites.py:84-117` doesn't lock the invite row; two users can redeem one single-use token concurrently. Add `with_for_update()`.

**L3. [Bug] Reassignment allows terminal instances** — `chores.py:376-449` reassigns `complete`/`cancelled` instances; add a status guard.

**L4. [Debt] Dead code / no lint** — `_COMPLETABLE_STATUSES` unused (`chores.py:269`); dead `hasattr(value, "model_dump")` branch (`chores.py:487-489`); unused imports in several files. No ruff/mypy config, no lint step in CI.

**L5. [Debt] Test suite speed** — `conftest.py:78-80` drops/recreates the entire schema per `async_client` test (~2m50s for 137 tests). Session-scoped schema + per-test transaction rollback would cut this dramatically.

**L6. [Debt] Config/docs mismatches** — `.env.example:52` documents the test DB on port 5433 and references a nonexistent `docker-compose.test.yml`, while CI/Makefile use 5432.

**L7. [Accepted] Register email enumeration (409)** — acceptable for an MVP once rate limiting (H1) exists.

**L8. [Architecture] Business logic in route handlers** — `complete_chore_instance` (~90 lines) and `create_chore` (~95 lines) orchestrate inline. Extract a `ChoreService` before adding notifications/skip features.

**L9. [Missing minor endpoints]** — no `GET` for a single chore definition or definition list; no "skip chore" action.

**L10. [Roadmap] Notifications** — nothing notifies assignees of due/overdue chores. For self-host, ntfy.sh/Gotify/webhook push from `run_daily_job` fits better than FCM/APNS.

### Repo-level (not backend code, found during this review)

**R1. No root README / self-hosting guide** — only `flutter_app/README.md` exists. There is no documentation of how to deploy the stack, configure the app, or restore a backup. For a self-hosted-only project this is a top gap.
**R2. Makefile hardcodes `podman compose` and a personal Flutter path** — fine for the owner's machine, worth a `COMPOSE ?=` variable.

---

## 3. Suggested Order of Work

1. **C1 + H6** — fix login and the stale test (trivial diffs, unblocks everything).
2. **H4** — CI on all branches + coverage gate reality check.
3. **H3, H5, M1** — small `chores.py`/logout correctness fixes.
4. **H1, H2, M12** — rate limiting, short access tokens, secret validation.
5. **M3, M2, M11** — scheduler resilience and token-table hygiene.
6. **M4, M5, R1** — production compose + startup migrations, backups, README.
7. **M6, M7, M8, M9, M10** — password change, deletions, email normalization, leaderboard windows.
8. Low items opportunistically; **L10** notifications as the next feature milestone.

Corresponding tasks: see `docs/tasks.md` TASK-068 onward (rate limiting remains tracked as TASK-031).
