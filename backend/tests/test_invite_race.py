"""Concurrency test for single-use invite acceptance (TASK-080 L2).

The invite-token select uses SELECT ... FOR UPDATE, so concurrent accepts of
the same token serialize: exactly one succeeds, the rest get 410.
"""
import asyncio

from httpx import AsyncClient


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _register_and_login(client: AsyncClient, email: str) -> str:
    await client.post(
        "/auth/register",
        json={"email": email, "password": "securepassword", "display_name": email.split("@")[0]},
    )
    resp = await client.post(
        "/auth/login",
        json={"email": email, "password": "securepassword"},
    )
    return resp.json()["access_token"]


async def test_concurrent_accept_of_single_use_invite(async_client: AsyncClient) -> None:
    """Several users racing on one invite token: exactly one membership is created."""
    admin_token = await _register_and_login(async_client, "admin@race.example")
    resp = await async_client.post(
        "/households", json={"name": "Race House"}, headers=_auth(admin_token)
    )
    assert resp.status_code == 201, resp.text
    household_id = resp.json()["id"]

    invite_resp = await async_client.post(
        f"/households/{household_id}/invites", headers=_auth(admin_token)
    )
    assert invite_resp.status_code == 200, invite_resp.text
    invite_token = invite_resp.json()["token"]

    contender_tokens = [
        await _register_and_login(async_client, f"user{i}@race.example") for i in range(4)
    ]

    responses = await asyncio.gather(
        *(
            async_client.post(f"/invites/{invite_token}/accept", headers=_auth(tok))
            for tok in contender_tokens
        )
    )
    statuses = sorted(r.status_code for r in responses)
    assert statuses == [200, 410, 410, 410], statuses

    # The roster contains exactly the admin plus the single winner.
    members_resp = await async_client.get(
        f"/households/{household_id}/members", headers=_auth(admin_token)
    )
    assert members_resp.status_code == 200
    assert len(members_resp.json()) == 2
