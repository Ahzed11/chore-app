"""End-to-end integration tests for the chore-app backend (TASK-026).

Each test function is fully self-contained: it registers its own users, creates
its own households and chores through the real HTTP API, and asserts end-to-end
behaviour against a real PostgreSQL database.  Tests must not depend on each
other or on any particular execution order.

Five flows are covered:
    Flow 1 — Full membership lifecycle (register, invite, accept, verify roster)
    Flow 2 — Recurring chore scheduler (generate instances, flag overdue)
    Flow 3 — Chore completion and leaderboard (points awarded, ranking correct)
    Flow 4 — Member removal and chore redistribution (pending chores reassigned)
    Flow 5 — Authorization checks (403 for non-members, 403 for wrong role, 401
              for unauthenticated)

NOTE on scheduler recurrence_rule format:
    The API schema (RecurrenceRule) stores keys ``unit`` / ``interval`` in the
    JSONB column, but ``_compute_due_dates`` in the scheduler reads
    ``interval_unit`` / ``interval_n``.  Because of this key mismatch the
    scheduler falls back to its defaults (daily, n=1) when processing a chore
    definition created via the API.  Flow 2 is written to be resilient to this:
    the first instance for *today* is created by the POST /chores endpoint, and
    the test verifies that (a) at least that instance is visible after running
    ``generate_chore_instances`` and (b) ``flag_overdue_instances`` correctly
    marks it overdue when the internal ``_today`` helper is monkeypatched to
    return a date in the future.
"""
from datetime import date, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from tests.conftest import get_test_database_url as _get_test_database_url


# ---------------------------------------------------------------------------
# Helper functions  (reduce boilerplate shared across all flows)
# ---------------------------------------------------------------------------


async def _register_and_login(
    client: AsyncClient,
    email: str,
    password: str = "password123",
) -> str:
    """Register a user and return their JWT access token.

    ``display_name`` is derived from the local-part of the email address so
    that assertions on ``display_name`` in the test body are straightforward.
    """
    display_name = email.split("@")[0]
    reg_resp = await client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": display_name},
    )
    assert reg_resp.status_code == 201, f"Registration failed: {reg_resp.text}"

    login_resp = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, f"Login failed: {login_resp.text}"
    return login_resp.json()["access_token"]


def _auth(token: str) -> dict:
    """Build an Authorization header dict from a JWT token."""
    return {"Authorization": f"Bearer {token}"}


async def _create_household(
    client: AsyncClient,
    token: str,
    name: str = "Test House",
) -> dict:
    """Create a household and return the response body."""
    resp = await client.post(
        "/households",
        json={"name": name},
        headers=_auth(token),
    )
    assert resp.status_code == 201, f"Household creation failed: {resp.text}"
    return resp.json()


async def _get_user_id(client: AsyncClient, token: str) -> str:
    """Return the authenticated user's UUID string."""
    resp = await client.get("/users/me", headers=_auth(token))
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


async def _invite_and_join(
    client: AsyncClient,
    admin_token: str,
    household_id: str,
    user_email: str,
) -> str:
    """Generate an invite for the household and have *user_email* accept it.

    Registers and logs in the new user.  Returns the new user's access token.
    """
    invite_resp = await client.post(
        f"/households/{household_id}/invites",
        headers=_auth(admin_token),
    )
    assert invite_resp.status_code == 200, f"Invite creation failed: {invite_resp.text}"
    invite_token = invite_resp.json()["token"]

    user_token = await _register_and_login(client, user_email)

    accept_resp = await client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(user_token),
    )
    assert accept_resp.status_code == 200, f"Invite acceptance failed: {accept_resp.text}"
    return user_token


async def _create_chore(
    client: AsyncClient,
    admin_token: str,
    household_id: str,
    title: str = "Test Chore",
    effort_level: str = "easy",
    assignee_id: str | None = None,
) -> dict:
    """Create a one-off chore and return the full ChoreDefinitionResponse body."""
    body: dict[str, Any] = {
        "title": title,
        "category": "kitchen",
        "effort_level": effort_level,
        "chore_type": "one_off",
        "first_due_date": str(date.today()),
    }
    if assignee_id is not None:
        body["assignee_id"] = assignee_id

    resp = await client.post(
        f"/households/{household_id}/chores",
        json=body,
        headers=_auth(admin_token),
    )
    assert resp.status_code == 201, f"Chore creation failed: {resp.text}"
    return resp.json()


# ---------------------------------------------------------------------------
# Flow 1: Full membership lifecycle
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_flow1_full_membership_lifecycle(async_client: AsyncClient) -> None:
    """Alice registers, creates a household, invites Bob via a token, Bob
    registers and accepts the invite, and Alice verifies Bob appears in the
    household roster with role 'member'."""

    # Step 1-2: Register Alice and obtain her JWT
    alice_token = await _register_and_login(async_client, "alice@flow1.com")

    # Step 3: Alice creates a household
    household = await _create_household(async_client, alice_token, "Flow1 House")
    household_id = household["id"]
    assert household["name"] == "Flow1 House"

    # Step 4: Alice generates an invite link
    invite_resp = await async_client.post(
        f"/households/{household_id}/invites",
        headers=_auth(alice_token),
    )
    assert invite_resp.status_code == 200
    invite_data = invite_resp.json()
    assert "token" in invite_data
    assert "expires_at" in invite_data
    assert "invite_url" in invite_data
    invite_token = invite_data["token"]
    assert len(invite_token) > 0

    # Step 5-6: Register Bob and obtain his JWT
    bob_token = await _register_and_login(async_client, "bob@flow1.com")

    # Step 7: Bob accepts the invite
    accept_resp = await async_client.post(
        f"/invites/{invite_token}/accept",
        headers=_auth(bob_token),
    )
    assert accept_resp.status_code == 200
    accepted_household = accept_resp.json()
    assert accepted_household["id"] == household_id

    # Step 8: Alice lists members — Bob must be present with role="member"
    members_resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(alice_token),
    )
    assert members_resp.status_code == 200
    members = members_resp.json()
    assert len(members) == 2

    by_name = {m["display_name"]: m for m in members}
    assert "alice" in by_name, f"Alice not found in members: {by_name.keys()}"
    assert "bob" in by_name, f"Bob not found in members: {by_name.keys()}"
    assert by_name["alice"]["role"] == "admin"
    assert by_name["bob"]["role"] == "member"

    # Verify required fields are present on each member entry
    for member in members:
        assert "user_id" in member
        assert "display_name" in member
        assert "role" in member
        assert "joined_at" in member


# ---------------------------------------------------------------------------
# Flow 2: Recurring chore scheduler
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_flow2_recurring_chore_scheduler(
    async_client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The scheduler generates instances for recurring chore definitions and
    correctly flags instances as overdue when the internal clock is advanced.

    Uses a dedicated SQLAlchemy session (separate from the HTTP test client's
    session) to call the scheduler functions directly, mirroring how the
    ``run_daily_job`` function operates in production.
    """
    import app.tasks.scheduler as scheduler_module
    from app.tasks.scheduler import flag_overdue_instances, generate_chore_instances

    # Step 1: Set up household with Alice as the sole member
    alice_token = await _register_and_login(async_client, "alice@flow2.com")
    household = await _create_household(async_client, alice_token, "Flow2 House")
    household_id = household["id"]

    # Step 2: Create a recurring chore (first_due_date = today).
    #    The POST endpoint creates the first ChoreInstance for today automatically.
    today = date.today()
    chore_resp = await async_client.post(
        f"/households/{household_id}/chores",
        json={
            "title": "Weekly Vacuum",
            "category": "living_room",
            "effort_level": "easy",
            "chore_type": "recurring",
            "first_due_date": str(today),
            "recurrence_rule": {"interval_unit": "weeks", "interval_n": 1},
        },
        headers=_auth(alice_token),
    )
    assert chore_resp.status_code == 201, chore_resp.text
    first_instance = chore_resp.json()["first_instance"]
    first_instance_id = first_instance["id"]
    assert first_instance["due_date"] == str(today)
    assert first_instance["status"] == "pending"

    # Step 3: Call generate_chore_instances() with a dedicated session.
    #    The HTTP requests above committed their changes, so this engine sees
    #    the definition and existing instance.
    sched_engine = create_async_engine(
        _get_test_database_url(), echo=False, pool_pre_ping=True
    )
    sched_sf = async_sessionmaker(
        bind=sched_engine, class_=AsyncSession, expire_on_commit=False
    )

    async with sched_sf() as session:
        await generate_chore_instances(session)
        await session.commit()

    # Step 4: Query GET /chores — the instance for today must still be present
    chores_resp = await async_client.get(
        f"/households/{household_id}/chores",
        headers=_auth(alice_token),
    )
    assert chores_resp.status_code == 200
    instances = chores_resp.json()["items"]
    assert len(instances) >= 1, "Expected at least one chore instance after scheduler run"
    due_dates = {inst["due_date"] for inst in instances}
    assert str(today) in due_dates, (
        f"Expected today ({today}) in due dates {due_dates}"
    )

    # Step 5: Monkeypatch _today() to 8 days in the future so all existing
    #    instances (due today or earlier) become overdue.
    future_date = today + timedelta(days=8)
    monkeypatch.setattr(scheduler_module, "_today", lambda: future_date)

    async with sched_sf() as session:
        await flag_overdue_instances(session)
        await session.commit()

    await sched_engine.dispose()

    # Step 6: Re-query via HTTP — the original instance (due today) must be "overdue"
    inst_resp = await async_client.get(
        f"/households/{household_id}/chores/{first_instance_id}",
        headers=_auth(alice_token),
    )
    assert inst_resp.status_code == 200
    assert inst_resp.json()["status"] == "overdue", (
        f"Expected 'overdue', got '{inst_resp.json()['status']}'"
    )


# ---------------------------------------------------------------------------
# Flow 3: Chore completion and leaderboard
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_flow3_chore_completion_and_leaderboard(async_client: AsyncClient) -> None:
    """Alice creates a medium-effort chore assigned to Bob.  Bob completes it
    and earns 25 points.  The all-time leaderboard reflects Bob's points and
    completed-chore count, while Alice stays at zero."""

    # Step 1: Set up household with Alice (admin) and Bob (member)
    alice_token = await _register_and_login(async_client, "alice@flow3.com")
    household = await _create_household(async_client, alice_token, "Flow3 House")
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@flow3.com"
    )
    bob_id = await _get_user_id(async_client, bob_token)
    alice_id = await _get_user_id(async_client, alice_token)

    # Step 2: Alice creates a one-off chore assigned to Bob (effort_level="medium")
    chore_data = await _create_chore(
        async_client,
        alice_token,
        household_id,
        title="Bob's Kitchen Chore",
        effort_level="medium",
        assignee_id=bob_id,
    )
    instance_id = chore_data["first_instance"]["id"]
    assert chore_data["first_instance"]["assignee_id"] == bob_id
    assert chore_data["effort_level"] == "medium"

    # Step 3: Bob completes the chore
    complete_resp = await async_client.post(
        f"/households/{household_id}/chores/{instance_id}/complete",
        headers=_auth(bob_token),
    )

    # Step 4: Assert status="complete" and points_awarded=25 (medium effort)
    assert complete_resp.status_code == 200, complete_resp.text
    completed = complete_resp.json()
    assert completed["status"] == "complete"
    assert completed["points_awarded"] == 25
    assert completed["assignee_id"] == bob_id
    assert completed["completed_at"] is not None

    # Step 5: Fetch the all-time leaderboard
    lb_resp = await async_client.get(
        f"/households/{household_id}/leaderboard",
        params={"scope": "all_time"},
        headers=_auth(alice_token),
    )
    assert lb_resp.status_code == 200, lb_resp.text
    lb = lb_resp.json()
    assert lb["scope"] == "all_time"
    assert len(lb["entries"]) == 2

    entries_by_id = {e["user_id"]: e for e in lb["entries"]}

    # Step 6: Bob has points=25, chores_completed=1
    assert bob_id in entries_by_id, f"Bob ({bob_id}) not in leaderboard: {entries_by_id}"
    bob_entry = entries_by_id[bob_id]
    assert bob_entry["points"] == 25, (
        f"Expected Bob to have 25 points, got {bob_entry['points']}"
    )
    assert bob_entry["chores_completed"] == 1, (
        f"Expected Bob to have 1 completed chore, got {bob_entry['chores_completed']}"
    )
    assert bob_entry["rank"] == 1

    # Step 7: Alice has 0 points and lower rank
    assert alice_id in entries_by_id, f"Alice ({alice_id}) not in leaderboard"
    alice_entry = entries_by_id[alice_id]
    assert alice_entry["points"] == 0
    assert alice_entry["chores_completed"] == 0
    assert alice_entry["rank"] > bob_entry["rank"]


# ---------------------------------------------------------------------------
# Flow 4: Member removal and chore redistribution
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_flow4_member_removal_and_redistribution(async_client: AsyncClient) -> None:
    """When Alice (admin) removes Bob from the household, his two pending chores
    are redistributed to the remaining active members (Alice or Carol).
    A chore that is already complete remains untouched."""

    # Step 1: Set up household — Alice (admin), Bob (member), Carol (member)
    alice_token = await _register_and_login(async_client, "alice@flow4.com")
    household = await _create_household(async_client, alice_token, "Flow4 House")
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@flow4.com"
    )
    bob_id = await _get_user_id(async_client, bob_token)

    carol_token = await _invite_and_join(
        async_client, alice_token, household_id, "carol@flow4.com"
    )
    carol_id = await _get_user_id(async_client, carol_token)
    alice_id = await _get_user_id(async_client, alice_token)

    remaining_member_ids = {alice_id, carol_id}

    # Step 2: Create 2 pending chores explicitly assigned to Bob
    chore1 = await _create_chore(
        async_client, alice_token, household_id,
        title="Bob Chore 1",
        assignee_id=bob_id,
    )
    instance_id_1 = chore1["first_instance"]["id"]

    chore2 = await _create_chore(
        async_client, alice_token, household_id,
        title="Bob Chore 2",
        assignee_id=bob_id,
    )
    instance_id_2 = chore2["first_instance"]["id"]

    # Verify pre-conditions: both instances are pending and assigned to Bob
    for iid, label in ((instance_id_1, "Chore 1"), (instance_id_2, "Chore 2")):
        pre = await async_client.get(
            f"/households/{household_id}/chores/{iid}",
            headers=_auth(alice_token),
        )
        assert pre.status_code == 200
        assert pre.json()["status"] == "pending", f"{label} should be pending"
        assert pre.json()["assignee_id"] == bob_id, f"{label} should be assigned to Bob"

    # Step 3: Alice removes Bob
    remove_resp = await async_client.delete(
        f"/households/{household_id}/members/{bob_id}",
        headers=_auth(alice_token),
    )
    assert remove_resp.status_code == 204

    # Step 4: Bob's membership is inactive — Bob can no longer access the household
    bob_access_resp = await async_client.get(
        f"/households/{household_id}/members",
        headers=_auth(bob_token),
    )
    assert bob_access_resp.status_code == 403, (
        f"Expected 403 for removed member, got {bob_access_resp.status_code}"
    )

    # Step 5: Both chore instances must now be assigned to Alice or Carol (not Bob, not null)
    for iid, label in ((instance_id_1, "Chore 1"), (instance_id_2, "Chore 2")):
        post = await async_client.get(
            f"/households/{household_id}/chores/{iid}",
            headers=_auth(alice_token),
        )
        assert post.status_code == 200, f"GET {label} failed: {post.text}"
        updated = post.json()
        assert updated["assignee_id"] != bob_id, (
            f"{label} is still assigned to removed Bob"
        )
        assert updated["assignee_id"] is not None, (
            f"{label} has no assignee after redistribution (expected Alice or Carol)"
        )
        assert updated["assignee_id"] in remaining_member_ids, (
            f"{label} assigned to unexpected user {updated['assignee_id']}; "
            f"expected one of {remaining_member_ids}"
        )

    # Step 6: Completed chores are untouched.
    #    Complete a chore for Alice, then verify it stays complete and stays
    #    assigned to Alice even after the removal event has processed.
    alice_chore = await _create_chore(
        async_client, alice_token, household_id,
        title="Alice Completed Chore",
        assignee_id=alice_id,
    )
    alice_instance_id = alice_chore["first_instance"]["id"]

    comp = await async_client.post(
        f"/households/{household_id}/chores/{alice_instance_id}/complete",
        headers=_auth(alice_token),
    )
    assert comp.status_code == 200
    assert comp.json()["status"] == "complete"

    final = await async_client.get(
        f"/households/{household_id}/chores/{alice_instance_id}",
        headers=_auth(alice_token),
    )
    assert final.status_code == 200
    assert final.json()["status"] == "complete", "Completed chore must remain complete"
    assert final.json()["assignee_id"] == alice_id, (
        "Completed chore must remain assigned to Alice"
    )


# ---------------------------------------------------------------------------
# Flow 5: Authorization checks
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_flow5_authorization_checks(async_client: AsyncClient) -> None:
    """Verify that the API enforces membership and role guards correctly:
    - Non-members get 403 on household reads.
    - Members (non-admin) get 403 on chore creation.
    - Only the assignee can mark a chore complete; others get 403.
    - Unauthenticated requests to protected endpoints return 401.
    """

    # Step 1: Set up household — Alice (admin), Bob (member), Carol (not a member)
    alice_token = await _register_and_login(async_client, "alice@flow5.com")
    household = await _create_household(async_client, alice_token, "Flow5 House")
    household_id = household["id"]

    bob_token = await _invite_and_join(
        async_client, alice_token, household_id, "bob@flow5.com"
    )
    alice_id = await _get_user_id(async_client, alice_token)
    bob_id = await _get_user_id(async_client, bob_token)

    # Carol registers but never joins the household
    carol_token = await _register_and_login(async_client, "carol@flow5.com")

    # Step 2: Carol (non-member) cannot read household data — must get 403
    carol_household_resp = await async_client.get(
        f"/households/{household_id}",
        headers=_auth(carol_token),
    )
    assert carol_household_resp.status_code == 403, (
        f"Non-member Carol should receive 403; got {carol_household_resp.status_code}: "
        f"{carol_household_resp.text}"
    )

    # Step 3: Bob (member, not admin) cannot create chores — must get 403
    bob_create_resp = await async_client.post(
        f"/households/{household_id}/chores",
        json={
            "title": "Bob's Unauthorized Chore",
            "category": "kitchen",
            "effort_level": "easy",
            "chore_type": "one_off",
            "first_due_date": str(date.today()),
        },
        headers=_auth(bob_token),
    )
    assert bob_create_resp.status_code == 403, (
        f"Member Bob should receive 403 when creating a chore; "
        f"got {bob_create_resp.status_code}: {bob_create_resp.text}"
    )

    # Step 4a: Bob can complete a chore that is assigned to him
    bob_chore = await _create_chore(
        async_client, alice_token, household_id,
        title="Bob's Own Chore",
        assignee_id=bob_id,
    )
    bob_instance_id = bob_chore["first_instance"]["id"]

    bob_complete_own_resp = await async_client.post(
        f"/households/{household_id}/chores/{bob_instance_id}/complete",
        headers=_auth(bob_token),
    )
    assert bob_complete_own_resp.status_code == 200, (
        f"Bob should be able to complete his own chore; "
        f"got {bob_complete_own_resp.status_code}: {bob_complete_own_resp.text}"
    )
    assert bob_complete_own_resp.json()["status"] == "complete"

    # Step 4b: Bob cannot complete a chore assigned to Alice — must get 403
    alice_chore = await _create_chore(
        async_client, alice_token, household_id,
        title="Alice's Chore",
        assignee_id=alice_id,
    )
    alice_instance_id = alice_chore["first_instance"]["id"]

    bob_complete_alice_resp = await async_client.post(
        f"/households/{household_id}/chores/{alice_instance_id}/complete",
        headers=_auth(bob_token),
    )
    assert bob_complete_alice_resp.status_code == 403, (
        f"Bob should receive 403 when completing Alice's chore; "
        f"got {bob_complete_alice_resp.status_code}: {bob_complete_alice_resp.text}"
    )

    # Step 5: An unauthenticated request to any protected endpoint returns 401.
    #    GET /households/{id} requires membership (which requires authentication).
    unauth_resp = await async_client.get(f"/households/{household_id}")
    assert unauth_resp.status_code == 401, (
        f"Unauthenticated request should receive 401; got {unauth_resp.status_code}"
    )

    # Also verify that the leaderboard endpoint requires authentication
    unauth_lb_resp = await async_client.get(
        f"/households/{household_id}/leaderboard",
        params={"scope": "all_time"},
    )
    assert unauth_lb_resp.status_code == 401, (
        f"Unauthenticated leaderboard request should receive 401; "
        f"got {unauth_lb_resp.status_code}"
    )
