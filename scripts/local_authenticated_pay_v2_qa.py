#!/usr/bin/env python3
"""Pay V2 signed JWT + PostgREST A/B test against local Supabase LOOPBACK ONLY.

A real local GoTrue user obtains a JWT; service-role exercises ONLY synthetic
purchase hashes, not real Apple JWS verification or live billing. No remote
URLs, service key, credentials, or real App Store secrets are used.
"""
from __future__ import annotations

from datetime import datetime, timezone
import subprocess
import uuid

from local_authenticated_global_v1_qa import (
    local_stack_config, loopback_only, bootstrap_local_schema,
    api, make_user, require,
)

OWNER_A = "alice+payv2qa@local.test"
OWNER_B = "bob+payv2qa@local.test"

def run_sql(db_url: str, sql: str) -> None:
    loopback_only(db_url, "DB_URL")
    subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", db_url, "-c", sql],
        check=True, timeout=25, stdout=subprocess.DEVNULL
    )

def install(db_url: str) -> None:
    bootstrap_local_schema(db_url)
    subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", db_url,
         "-f", "supabase/proposals/issue28_pay_schema_v2_REVIEW_ONLY.sql"],
        check=True, timeout=40, stdout=subprocess.DEVNULL
    )
    run_sql(db_url, """
    INSERT INTO pipo_billing_private.apple_catalog
      (environment,product_id,bundle_id,benefit,enabled)
    VALUES ('Sandbox','qa.pipo.personal.slot','com.pipo.app','personal_slot',true);
    NOTIFY pgrst, 'reload schema';
    """)

def rpc_body(
    owner: str, transaction: str, event: str,
    action: str = "purchased", proof: str = "a" * 64
) -> dict[str, object]:
    return dict(
        p_environment="Sandbox",
        p_event_id=event,
        p_transaction_id=transaction,
        p_original_transaction_id=transaction,
        p_product_id="qa.pipo.personal.slot",
        p_bundle_id="com.pipo.app",
        p_user_id=owner,
        p_app_account_token=owner,
        p_action=action,
        p_proof_sha256=proof,
        p_apple_signed_at=datetime.now(timezone.utc).isoformat(),
    )

def snapshot(base: str, anon: str, token: str, user_id: str) -> dict:
    status, obj = api(
        base, anon, "/rest/v1/rpc/pipo_read_entitlements_v2",
        bearer=token, method="POST", body={}
    )
    require(status == 200 and isinstance(obj, list) and len(obj) == 1,
            "Authenticated owner entitlement read RPC failed")
    row = obj[0]
    require(row["user_id"] == user_id and row["free_personal_slots"] == 2
            and row["free_group_creator_slots"] == 1,
            "Wrong authenticated user or free capacity")
    return row

def main() -> None:
    env = local_stack_config()  # STRICT loopback check on every DB/API URL
    base, anon, service, db = (
        env[k] for k in ("API_URL", "ANON_KEY", "SERVICE_ROLE_KEY", "DB_URL")
    )
    install(db)
    alice, a_token = make_user(base, service, anon, OWNER_A)
    bob, b_token = make_user(base, service, anon, OWNER_B)
    require(alice != bob, "Synthetic accounts must not be the same")
    require(snapshot(base, anon, a_token, alice)["revision"] == 0,
            "New owner should start with zero paid credits")
    require(snapshot(base, anon, b_token, bob)["revision"] == 0,
            "Second owner should start with zero paid credits")

    # User cannot directly INSERT, UPDATE or request the privileged grant.
    restricted = "/rest/v1/pipo_entitlements_v2"
    status, _ = api(
        base, anon, restricted, method="POST", bearer=a_token,
        body={"user_id":alice,"permanent_personal_slots":500}
    )
    require(status in (401, 403),
            f"Client could INSERT paid entitlement; HTTP {status}")
    status, _ = api(
        base, anon, restricted+"?user_id=eq."+alice,
        method="PATCH", bearer=a_token,
        body={"permanent_group_slots":900}
    )
    require(status in (401, 403),
            f"Client could UPDATE paid entitlement; HTTP {status}")

    tx = "100100100"
    body = rpc_body(alice, tx, "qa.event."+uuid.uuid4().hex)
    grant_route = "/rest/v1/rpc/pipo_internal_ingest_verified_apple_event_v1"
    status, _ = api(
        base, anon, grant_route, method="POST", bearer=a_token, body=body
    )
    require(status in (401, 403),
            f"Client could call private grant wrapper; HTTP {status}")

    # Test-only stand-in for an independently verified Apple backend. Using
    # service role does NOT imply this fake hash represents a real purchase.
    status, awarded = api(
        base, service, grant_route, method="POST", body=body
    )
    require(status == 200 and isinstance(awarded, list)
            and len(awarded) == 1 and awarded[0]["personal_slots"] == 1,
            f"Local service-only synthetic grant failed; HTTP {status}")
    a = snapshot(base, anon, a_token, alice)
    b = snapshot(base, anon, b_token, bob)
    require(a["permanent_personal_slots"] == 1 and a["revision"] == 1,
            "A did not receive first server-owned synthetic credit")
    require(b["permanent_personal_slots"] == 0 and b["revision"] == 0,
            "B received A's credit")

    # RLS must prevent B selecting even with Alice UUID in the query.
    status, foreign_rows = api(
        base, anon,
        restricted+"?select=user_id,permanent_personal_slots&user_id=eq."+alice,
        method="GET", bearer=b_token
    )
    require(status == 200 and foreign_rows == [],
            f"RLS leaked A's paid snapshot to B, HTTP {status}")

    status, _ = api(base, service, grant_route, method="POST", body=body)
    require(status == 200, "Exact event replay not acknowledged")
    require(snapshot(base, anon, a_token, alice)["revision"] == 1,
            "Exact event replay minted a second credit")

    # Cross-account re-claim of the same Apple transaction must be blocked.
    stolen = rpc_body(bob, tx, "qa.cross."+uuid.uuid4().hex)
    status, _ = api(base, service, grant_route, method="POST", body=stolen)
    require(status >= 400, "Apple transaction was reassigned to B")
    require(snapshot(base, anon, b_token, bob)["permanent_personal_slots"] == 0,
            "Cross-account transaction replay minted B credit")

    refund = rpc_body(
        alice, tx, "qa.refund."+uuid.uuid4().hex,
        action="refunded", proof="f"*64
    )
    status, _ = api(base, service, grant_route, method="POST", body=refund)
    require(status == 200, "Authorized synthetic refund failed")
    a = snapshot(base, anon, a_token, alice)
    require(a["permanent_personal_slots"] == 0 and a["revision"] == 2,
            "Refund did not revoke A's synthetic credit")
    late = rpc_body(alice, tx, "qa.late."+uuid.uuid4().hex)
    status, _ = api(base, service, grant_route, method="POST", body=late)
    require(status == 200, "Delayed old purchase event not recorded")
    require(snapshot(base, anon, a_token, alice)["revision"] == 2,
            "Late purchase replay revived a refunded credit")

    print("PASS local Auth/JWT/PostgREST Pay V2: A/B owner RLS, privileged grant denial,"
          " server-only synthetic grant, replay, refund and late event fail-close")

if __name__ == "__main__":
    main()
