#!/usr/bin/env python3
"""#80 genuine two-connection, committed CAS race on DISPOSABLE localhost PG17.

Unlike the single-transaction SQL fixture, this uses separate PostgreSQL
backend sessions. A wins and HOLDS a row lock inside an uncommitted transaction
while B waits on that lock, then B must observe a stale-revision conflict.
Session auth claims are synthetic here; separate local signed JWT/REST QA
lives in local_authenticated_issue80_cas_qa.py.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
import uuid

DB = "pipo_global_v1_local_qa"
OWNER = "88888888-1111-4111-8111-888888888881"
OTHER = "88888888-1111-4111-8111-888888888882"
GOAL = "88888888-2222-4222-8222-888888888881"
WIN = "88888888-3333-4333-8333-888888888881"
LOSE = "88888888-3333-4333-8333-888888888882"
DATE = "2030-01-01T00:00:00+00:00"

def require(ok: bool, description: str) -> None:
    if not ok:
        raise RuntimeError(description)

def guard() -> None:
    require(os.getenv("PGHOST") in {"127.0.0.1", "localhost", "::1"},
            "Refusing non-loopback PostgreSQL")
    require(os.getenv("PGDATABASE") == DB, "Refusing non-disposable database")
    require(os.getenv("PGUSER") == "postgres", "Refusing unrecognized QA superuser")
    require(os.getenv("PGPASSWORD") == "disposable-test-only",
            "Refusing unexpected PostgreSQL credentials")
    require("pipo.allow_synthetic_auth_qa=staging-only" in os.getenv("PGOPTIONS", ""),
            "Missing explicit disposable QA PGOPTIONS")
    require(os.getenv("PGPORT", "5432").isdigit(), "Invalid test port")
    response = subprocess.run(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c",
         "SELECT current_database(),current_user,"
         "to_regclass('private.pipo_plan_revision_receipts') IS NOT NULL,"
         "current_setting('server_version_num')::integer >= 170000"],
        text=True, capture_output=True, timeout=10, check=True,
    )
    fields = response.stdout.strip().split("|")
    # Docker's internal server interface is a bridge IP; require the
    # CLIENT to connect via PGHOST=loopback and verify DB, QA role,
    # pinned disposable credential, receipt schema and PG17 instead.
    require(fields == [DB, "postgres", "t", "t"],
            "Unsafe or incomplete local PG test setup")

def admin(sql: str) -> str:
    x = subprocess.run(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", sql],
        text=True, capture_output=True, timeout=15,
    )
    require(x.returncode == 0, "Disposable QA SQL failed: " + x.stderr[-1200:])
    return x.stdout.strip()

def transaction(claim: str, sql: str) -> str:
    return (
        "BEGIN;\n"
        "SET LOCAL ROLE authenticated;\n"
        f"SELECT set_config('request.jwt.claim.sub','{claim}',true);\n"
        + sql + "\nCOMMIT;\n"
    )

def rpc(request: str, target: int) -> str:
    return (
        "SELECT public.pipo_apply_plan_revision_v1("
        f"'{request}'::uuid,'{GOAL}'::uuid,0,{target}::numeric,"
        f"'{DATE}'::timestamptz,'weekly',2::smallint,25::numeric);"
    )

def spawn(sql: str, app_name: str) -> subprocess.Popen[str]:
    env = os.environ.copy()
    env["PGAPPNAME"] = app_name
    proc = subprocess.Popen(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env=env, bufsize=1,
    )
    assert proc.stdin is not None
    proc.stdin.write(sql)
    proc.stdin.flush()
    proc.stdin.close()
    return proc

def collect(proc: subprocess.Popen[str]) -> str:
    require(proc.wait(timeout=22) == 0, "Concurrent PG session failed: "
            + (proc.stderr.read() if proc.stderr else ""))
    return proc.stdout.read() if proc.stdout else ""

def state(s: str) -> dict:
    return next((json.loads(line) for line in s.splitlines()
                 if line.strip().startswith('{"')), {})

def main() -> None:
    guard()
    # Every object is synthetic and occurs inside dedicated temporary PG17.
    admin(f"INSERT INTO auth.users(id) VALUES ('{OWNER}'),('{OTHER}')")
    try:
        initial = transaction(
            OWNER,
            "INSERT INTO public.saving_goals(id,title,category,target_amount,"
            "target_date,currency_code) VALUES "
            f"('{GOAL}','Race-only saving goal','trip',300,"
            f"'{DATE}'::timestamptz,'IDR');"
        )
        x = spawn(initial, "pipo_issue80_race_setup")
        collect(x)

        # The first call locks goal and intentionally holds it for 6s before
        # COMMIT. This proves the second actual DB session waits on the lock.
        a_sql = transaction(
            OWNER, rpc(WIN, 400) +
            "\nSELECT 'WINNER_APPLIED';\nSELECT pg_sleep(6);\n"
        )
        a = spawn(a_sql, "pipo_issue80_race_winner")
        try:
            assert a.stdout is not None
            lines: list[str] = []
            for _ in range(8):
                line = a.stdout.readline()
                require(bool(line), "Winner did not reach the critical section")
                lines.append(line)
                if "WINNER_APPLIED" in line:
                    break
            require(any("WINNER_APPLIED" in s for s in lines),
                    "Winner did not acquire lock before loser started")
            require(state("".join(lines)).get("status") == "applied",
                    "First CAS did not apply before the commit hold")

            b = spawn(transaction(OWNER, rpc(LOSE, 600)),
                      "pipo_issue80_race_loser")
            try:
                locked = False
                for _ in range(30):
                    out = admin(
                        "SELECT COALESCE(bool_or(wait_event_type='Lock'),false)"
                        " FROM pg_stat_activity WHERE application_name="
                        "'pipo_issue80_race_loser' AND state='active'"
                    )
                    if out == "t":
                        locked = True
                        break
                    require(a.poll() is None, "Winner committed before loser blocked")
                    time.sleep(0.10)
                require(locked, "Independent loser was not observed waiting on row lock")
                loser_output = collect(b)
                require(state(loser_output).get("status") == "conflict",
                        "Second independent CAS did not reject stale revision")
                require(state(loser_output).get("current_revision") == 1,
                        "Loser did not observe winner's committed revision")
            finally:
                if b.poll() is None:
                    b.kill()
                    b.wait(timeout=5)
            rest = collect(a)
            require(a.returncode == 0, "Winner failed to COMMIT")
            require(state("".join(lines)).get("accepted_revision") == 1,
                    "Winner accepted wrong revision")
            require(rest is not None, "Winner output unexpectedly absent")

            # Exact UUID replay keeps prior receipt and never increments.
            replay = spawn(transaction(OWNER, rpc(WIN, 400)),
                           "pipo_issue80_race_replay")
            receipt = state(collect(replay))
            require(receipt.get("status") == "applied"
                    and receipt.get("accepted_revision") == 1,
                    "Idempotent replay did not return original receipt")

            actual = admin(
                "SELECT plan_revision,target_amount,"
                "(SELECT count(*) FROM private.pipo_plan_revision_receipts "
                f" WHERE goal_id='{GOAL}') FROM public.saving_goals "
                f"WHERE id='{GOAL}'"
            )
            require(actual == "1|400|1",
                    f"Race mutated goal/receipts incorrectly: {actual}")
            print("PASS: two committed PG sessions; true row-lock wait, one CAS "
                  "winner, one revision conflict, exact UUID replay, one receipt")
        finally:
            if a.poll() is None:
                a.kill()
                a.wait(timeout=5)
    finally:
        admin(f"DELETE FROM auth.users WHERE id IN ('{OWNER}','{OTHER}')")
        require(admin(f"SELECT count(*) FROM public.saving_goals WHERE id='{GOAL}'")=="0",
                "Auth erasure left orphan goal")

if __name__ == "__main__":
    main()
