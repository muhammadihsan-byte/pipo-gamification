#!/usr/bin/env python3
"""Disposable signed Supabase Auth A/B + PostgREST CAS acceptance, localhost only.

Must run *after* local_authenticated_global_v1_qa.py in same Supabase CLI
stack: that script installs initial schema + immutable currency + #42 guard.
This script then applies #29 and #81 to LOCAL loopback Postgres ONLY.
All public table and RPC assertions use real signed user JWTs, not admin keys.
"""
from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from decimal import Decimal
import json
import subprocess
from threading import Barrier
import time
import urllib.parse
import uuid

from local_authenticated_global_v1_qa import (
    LocalQAError, api, local_stack_config, loopback_only, make_user, require,
)

def run_sql(db: str, statement_or_path: str, *, file: bool = False) -> None:
    loopback_only(db, "DB_URL")
    cmd = ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", db]
    cmd.extend(["-f", statement_or_path] if file else ["-c", statement_or_path])
    result = subprocess.run(cmd, text=True, capture_output=True, timeout=45)
    require(result.returncode == 0,
            "Disposable local migration/SQL failed: " + result.stderr[-900:])

def rpc(base: str, anon: str, token: str, goal: str,
        request: str, expected: int, target: int, date: str):
    return api(
        base, anon, "/rest/v1/rpc/pipo_apply_plan_revision_v1",
        method="POST", bearer=token,
        body={
            "p_request_id": request, "p_goal_id": goal,
            "p_expected_revision": expected,
            "p_target_amount": target, "p_target_date": date,
            "p_rhythm": "weekly", "p_preferred_saving_day": 2,
            "p_planned_contribution_override": 25,
        },
    )

def read_goal(base: str, anon: str, token: str, goal: str):
    route = "/rest/v1/saving_goals?" + urllib.parse.urlencode({
        "select": "id,user_id,currency_code,target_amount,plan_revision",
        "id": "eq." + goal,
    })
    status, rows = api(base, anon, route, bearer=token)
    require(status == 200 and isinstance(rows, list), "Signed goal SELECT failed")
    return rows

def main() -> None:
    cfg = local_stack_config()  # Refuses any non-loopback API/DB before I/O.
    base, db, anon, service = (
        cfg[k] for k in ("API_URL", "DB_URL", "ANON_KEY", "SERVICE_ROLE_KEY")
    )
    loopback_only(base, "API_URL")
    loopback_only(db, "DB_URL")
    # This project runs strictly in a disposable Supabase CLI stack.
    for path in (
        "supabase/proposals/issue_29_immutable_contribution_acl_REVIEW_ONLY.sql",
        "supabase/proposals/issue_80_plan_revision_cas_REVIEW_ONLY.sql",
    ):
        run_sql(db, path, file=True)
    run_sql(db, "NOTIFY pgrst, 'reload schema'")
    time.sleep(1.0)

    alice, a_jwt = make_user(
        base, service, anon, "charlie+casqa@local.test"
    )
    bob, b_jwt = make_user(
        base, service, anon, "dana+casqa@local.test"
    )
    goal = str(uuid.uuid4())
    deadline = "2030-01-01T00:00:00+00:00"
    status, created = api(
        base, anon, "/rest/v1/saving_goals", method="POST",
        bearer=a_jwt, prefer="return=representation",
        body={
            "id": goal, "title": "Disposable CAS goal",
            "category": "trip", "target_amount": 300,
            "currency_code": "IDR", "target_date": deadline,
            "rhythm": "weekly", "preferred_saving_day": 2,
            "planned_contribution_override": 25,
        },
    )
    require(status == 201 and isinstance(created, list) and len(created) == 1,
            f"Signed Alice INSERT failed: HTTP {status} {str(created)[:200]}")
    require(created[0].get("user_id") == alice,
            "Server-derived owner differs from signed Alice")
    require(created[0].get("plan_revision") == 0,
            "New goal did not start at revision zero")
    require(read_goal(base, anon, b_jwt, goal) == [],
            "Signed Bob can SELECT Alice's goal")

    good = str(uuid.uuid4())
    code, result = rpc(base, anon, a_jwt, goal, good, 0, 400, deadline)
    require(code == 200 and isinstance(result, dict)
            and result.get("status") == "applied"
            and result.get("accepted_revision") == 1,
            f"Alice CAS failed: {code} {str(result)[:280]}")
    code, replay = rpc(base, anon, a_jwt, goal, good, 0, 400, deadline)
    require(code == 200 and replay == result, "Exact JWT replay not idempotent")

    code, stale = rpc(base, anon, a_jwt, goal, str(uuid.uuid4()),
                      0, 600, deadline)
    require(code == 200 and isinstance(stale, dict)
            and stale.get("status") == "conflict"
            and stale.get("current_revision") == 1,
            "Stale signed Alice edit overwrote goal")

    code, forbidden = rpc(base, anon, b_jwt, goal, str(uuid.uuid4()),
                          1, 500, deadline)
    require(code in (401, 403, 404) and isinstance(forbidden, dict)
            and forbidden.get("code") == "42501",
            "Signed Bob CAS unexpectedly accessed Alice's goal")

    code, denied = api(
        base, anon,
        "/rest/v1/saving_goals?" + urllib.parse.urlencode({"id": "eq." + goal}),
        method="PATCH", bearer=a_jwt, body={"target_amount": 999},
    )
    require(code >= 400 and isinstance(denied, dict)
            and denied.get("code") == "42501",
            "Direct goal UPDATE still bypasses CAS")

    # History writing must still work after the privileged contribution
    # trigger replacement. Historical rows become immutable via #29 ACL.
    event = str(uuid.uuid4())
    code, result_event = api(
        base, anon, "/rest/v1/saving_transactions",
        method="POST", bearer=a_jwt, prefer="return=representation",
        body={
            "id": event, "goal_id": goal, "amount": 50,
            "xp_earned": 300, "date": datetime.now(timezone.utc).isoformat(),
        },
    )
    require(code == 201 and isinstance(result_event, list)
            and result_event[0].get("xp_earned") == 300,
            f"Contribution INSERT broke after CAS ACL: {code} {str(result_event)[:200]}")
    code, denied = api(
        base, anon, "/rest/v1/saving_transactions?"
        + urllib.parse.urlencode({"id": "eq." + event}),
        method="PATCH", bearer=a_jwt, body={"xp_earned": 9000},
    )
    require(code >= 400 and isinstance(denied, dict)
            and denied.get("code") == "42501",
            "Historical XP remained mutable")

    # Two independent real signed HTTP request connections; winner must
    # be unique. Explicit DB lock-overlap proof is a separate PG17 job.
    barrier = Barrier(2, timeout=10)
    requests = [(str(uuid.uuid4()), 450), (str(uuid.uuid4()), 470)]
    def concurrent_call(item):
        token, amount = item
        barrier.wait()
        return rpc(base, anon, a_jwt, goal, token, 1, amount, deadline)
    with ThreadPoolExecutor(max_workers=2) as executor:
        outcomes = list(executor.map(concurrent_call, requests))
    applied = [p for c, p in outcomes if c == 200 and isinstance(p, dict)
               and p.get("status") == "applied"]
    conflicted = [p for c, p in outcomes if c == 200 and isinstance(p, dict)
                  and p.get("status") == "conflict"]
    require(len(applied) == 1 and len(conflicted) == 1,
            f"Parallel signed RPCs not serialized: {str(outcomes)[:500]}")
    require(applied[0].get("accepted_revision") == 2 and
            conflicted[0].get("current_revision") == 2,
            "Parallel signed CAS returned inconsistent revision")
    rows = read_goal(base, anon, a_jwt, goal)
    require(len(rows) == 1 and rows[0].get("plan_revision") == 2,
            "Parallel CAS did not end at exactly one new revision")
    require(Decimal(str(rows[0]["target_amount"])) in
            {Decimal("450"), Decimal("470")},
            "Parallel winner amount was not preserved")
    require(read_goal(base, anon, b_jwt, goal) == [], "Bob can see Alice's goal")
    print("PASS: signed local Auth A/B REST + RLS, CAS replay, stale rejection, "
          "direct-update denial, immutable contribution XP and parallel CAS")

if __name__ == "__main__":
    main()
