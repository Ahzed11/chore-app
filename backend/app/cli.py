"""Operator management CLI for the ChoreApp backend (TASK-077).

Email-based password reset is not available for self-hosted deployments
(no SMTP is assumed), so this is the documented "forgot password" recovery
path: an operator with shell access to the host runs this command directly.

Usage:
    python -m app.cli reset-password <email>

The command prompts (without echoing) for a new password, confirms it,
updates the account's password hash directly, and revokes all of that
account's outstanding refresh tokens — mirroring the in-app
``POST /users/me/password`` flow, since an operator-initiated reset is
often a response to a compromised or forgotten-credential account.
"""
import argparse
import asyncio
import getpass
import sys
from collections.abc import Callable
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy import update as sql_update

from app.core.constants import PASSWORD_MAX_LENGTH, PASSWORD_MIN_LENGTH
from app.core.security import hash_password
from app.db.session import AsyncSessionLocal
from app.models.refresh_token import RefreshToken
from app.models.user import User

PasswordReader = Callable[[str], str]


async def _reset_password(email: str, password_reader: PasswordReader = getpass.getpass) -> int:
    """Reset the password for the account with ``email``.

    Returns a process-style exit code: 0 on success, 1 on any failure
    (unknown email, mismatched confirmation, or a password outside the
    registration strength constraints). ``password_reader`` is injectable
    so tests can supply canned input instead of reading a real TTY.
    """
    normalized_email = email.strip().lower()

    async with AsyncSessionLocal() as session:
        result = await session.execute(select(User).where(User.email == normalized_email))
        user = result.scalar_one_or_none()
        if user is None:
            print(f"No account found with email {normalized_email!r}.", file=sys.stderr)
            return 1

        new_password = password_reader(f"New password for {normalized_email}: ")
        confirm_password = password_reader("Confirm new password: ")

        if new_password != confirm_password:
            print("Passwords do not match. Aborting.", file=sys.stderr)
            return 1

        if not (PASSWORD_MIN_LENGTH <= len(new_password) <= PASSWORD_MAX_LENGTH):
            print(
                f"Password must be between {PASSWORD_MIN_LENGTH} and "
                f"{PASSWORD_MAX_LENGTH} characters long.",
                file=sys.stderr,
            )
            return 1

        user.password_hash = hash_password(new_password)

        # Revoke all outstanding refresh tokens, same as the in-app change flow.
        await session.execute(
            sql_update(RefreshToken)
            .where(
                RefreshToken.user_id == user.id,
                RefreshToken.revoked_at == None,  # noqa: E711
            )
            .values(revoked_at=datetime.now(timezone.utc))
        )

        await session.commit()

    print(f"Password updated for {normalized_email}.")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m app.cli",
        description="ChoreApp backend operator utilities.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    reset_parser = subparsers.add_parser(
        "reset-password",
        help="Reset a user's password directly in the database (self-host recovery path).",
    )
    reset_parser.add_argument("email", help="Email address of the account to reset")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command == "reset-password":
        return asyncio.run(_reset_password(args.email))

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
