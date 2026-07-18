# ChoreApp Backend

FastAPI + SQLAlchemy (async) + PostgreSQL backend for ChoreApp.

## Development

```bash
uv sync --extra test
cp .env.example .env   # then fill in real values
uv run alembic upgrade head
uv run uvicorn main:app --reload
```

Run the test suite (requires `TEST_DATABASE_URL` pointing at a scratch
PostgreSQL database):

```bash
uv run pytest tests/ -q
```

## Forgot password (self-host recovery path)

ChoreApp is designed for self-hosting and does not assume an SMTP server, so
there is no email-based password reset. Instead:

- **Users who know their current password** can change it in-app via
  `POST /users/me/password` with body
  `{"current_password": "...", "new_password": "..."}`. All refresh tokens
  are revoked on change, so other logged-in sessions must sign in again.
- **Users who forgot their password** ask the server operator to reset it.
  On the host (same environment/`.env` as the API so `DATABASE_URL` is set),
  the operator runs:

  ```bash
  python -m app.cli reset-password <email>
  ```

  The command prompts for the new password (input hidden), confirms it,
  updates the account's password hash directly, and revokes all of the
  account's refresh tokens. If the backend runs in Docker:

  ```bash
  docker compose exec api python -m app.cli reset-password <email>
  ```

## Account and household deletion

- `DELETE /households/{id}?confirm=<household name>` — admin only; the
  `confirm` query parameter must exactly match the household's name. Hard
  deletes the household and all related data (memberships, invites, chores,
  point ledger) via database cascades.
- `DELETE /users/me` with body `{"current_password": "..."}` — deletes the
  account. Households where the user is the sole member are deleted;
  memberships elsewhere are deactivated and the user's pending/overdue chores
  are redistributed to the remaining members. If the user is the sole admin
  of a household that still has other active members, the request fails with
  409 — promote another admin first.
