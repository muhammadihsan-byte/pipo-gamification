#!/usr/bin/env python3
"""Real Supabase Auth + PostgREST Global V1 QA against LOOPBACK ONLY.

Starts with an ephemeral local Supabase CLI stack and two synthetic Auth users.
It refuses all remote/non-loopback URLs. Never use service-role credentials to
perform goal/transaction assertions; these run with each user's signed-in JWT.
No production credentials, customer records, billing or cloud project involved.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal
import json
import secrets
import shlex
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


class LocalQAError(RuntimeError):
    pass


def loopback_only(url: str, name: str) -> None:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in {"http", "postgres", "postgresql"}:
        raise LocalQAError(f"{name}: unsupported local URL scheme")
    if parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise LocalQAError(f"{name}: refusing non-local service host")
    if parsed.username and name == "API_URL":
        raise LocalQAError("API_URL: credentials in URL are not expected")


def local_stack_config() -> dict[str, str]:
    completed = subprocess.run(
        ["supabase", "status", "-o", "env"], text=True, capture_output=True,
        check=True, timeout=30,
    )
    values: dict[str, str] = {}
    for line in completed.stdout.splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[7:].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key not in {"API_URL", "DB_URL", "ANON_KEY", "SERVICE_ROLE_KEY"}:
            continue
        parts = shlex.split(value)
        values[key] = parts[0] if parts else ""
    for key in ("API_URL", "DB_URL", "ANON_KEY", "SERVICE_ROLE_KEY"):
        if not values.get(key):
            raise LocalQAError(f"Missing local Supabase CLI output: {key}")
    loopback_only(values["API_URL"], "API_URL")
    loopback_only(values["DB_URL"], "DB_URL")
    return values


def bootstrap_local_schema(db_url: str) -> None:
    loopback_only(db_url, "DB_URL")
    for filename in (
        "supabase/local_qa/20261120052238_verified_schema_snapshot.sql",
        "supabase/proposals/global_v1_goal_currency_immutable_REVIEW_ONLY.sql",
    ):
        subprocess.run(
            ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", db_url, "-f", filename],
            check=True, timeout=40, stdout=subprocess.DEVNULL,
        )
    subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", db_url,
         "-c", "NOTIFY pgrst, 'reload schema'"],
        check=True, timeout=15, stdout=subprocess.DEVNULL,
    )


def api(
    base: str, key: str, route: str, *, method: str = "GET",
    bearer: str | None = None, body: object | None = None,
    prefer: str | None = None,
) -> tuple[int, object | None]:
    loopback_only(base, "API_URL")
    headers = {
        "apikey": key, "authorization": "Bearer " + (bearer or key),
        "accept": "application/json",
    }
    data = None
    if body is not None:
        data = json.dumps(body, separators=(",", ":")).encode("utf-8")
        headers["content-type"] = "application/json"
    if prefer is not None:
        headers["prefer"] = prefer
    req = urllib.request.Request(
        base.rstrip("/") + route, data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            raw = response.read()
            return response.status, (
                json.loads(raw, parse_float=Decimal) if raw else None
            )
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            payload = json.loads(raw)
        except (ValueError, TypeError):
            payload = None
        return exc.code, payload


def require(condition: bool, description: str) -> None:
    if not condition:
        raise LocalQAError(description)


def expect_error(
    response: tuple[int, object | None], code: str, description: str
) -> None:
    status, payload = response
    require(
        status >= 400 and isinstance(payload, dict) and payload.get("code") == code,
        description + f" (unexpected HTTP {status} or database error code)",
    )


def make_user(base: str, service: str, anon: str, email: str) -> tuple[str, str]:
    password = secrets.token_urlsafe(24)
    status, account = api(
        base, service, "/auth/v1/admin/users", method="POST",
        body={"email": email, "password": password, "email_confirm": True},
    )
    require(status in (200, 201) and isinstance(account, dict) and account.get("id"),
            "Could not create disposable LOCAL Auth user")
    status, session = api(
        base, anon, "/auth/v1/token?grant_type=password", method="POST",
        body={"email": email, "password": password},
    )
    require(status == 200 and isinstance(session, dict), "Local Auth sign-in failed")
    user = session.get("user") or {}
    token = session.get("access_token")
    require(
        isinstance(user, dict) and user.get("id") == account.get("id")
        and isinstance(token, str) and bool(token),
        "Authenticated session did not match local disposable user",
    )
    return str(account["id"]), token


def query_owned(base: str, anon: str, token: str, table: str, owner: str):
    require(table in {"saving_goals", "saving_transactions"}, "Non-allowlisted table")
    route = "/rest/v1/" + table + "?" + urllib.parse.urlencode({
        "select": "id,user_id", "user_id": "eq." + owner
    })
    code, rows = api(base, anon, route, bearer=token)
    require(code == 200 and isinstance(rows, list), "RLS select failed")
    return rows


def main() -> None:
    values = local_stack_config()  # validates both remote targets first
    base, anon, service = (values[k] for k in ("API_URL", "ANON_KEY", "SERVICE_ROLE_KEY"))
    bootstrap_local_schema(values["DB_URL"])
    alice, a_token = make_user(
        base, service, anon, "alice+pipoqa@local.test"
    )
    bob, b_token = make_user(
        base, service, anon, "bob+pipoqa@local.test"
    )
    require(alice != bob, "Local Auth returned the same identity twice")
    deadline = (datetime.now(timezone.utc) + timedelta(days=90)).isoformat()
    a_goal = "a1111111-1111-4111-8111-111111111111"
    b_goal = "b2222222-2222-4222-8222-222222222222"
    a_txn = "a3333333-3333-4333-8333-333333333333"
    b_txn = "b4444444-4444-4444-8444-444444444444"

    a_insert = api(
        base, anon, "/rest/v1/saving_goals?select=id,user_id,currency_code,target_amount",
        method="POST", bearer=a_token, prefer="return=representation",
        body={
            "id": a_goal, "title": "QA Laptop USD", "category": "gadget",
            "target_amount": "1500.50", "target_date": deadline,
            "currency_code": "USD",
        },
    )
    require(a_insert[0] == 201 and isinstance(a_insert[1], list)
            and len(a_insert[1]) == 1 and a_insert[1][0]["user_id"] == alice
            and Decimal(str(a_insert[1][0]["target_amount"])) == Decimal("1500.50"),
            "Authenticated Alice USD 1500.50 INSERT failed")
    a_saving = api(
        base, anon, "/rest/v1/saving_transactions?select=id,goal_id,user_id,amount",
        method="POST", bearer=a_token, prefer="return=representation",
        body={"id": a_txn, "goal_id": a_goal, "amount": "0.01", "xp_earned": 5},
    )
    require(
        a_saving[0] == 201 and isinstance(a_saving[1], list)
        and len(a_saving[1]) == 1
        and a_saving[1][0]["user_id"] == alice
        and Decimal(str(a_saving[1][0]["amount"])) == Decimal("0.01"),
        "Authenticated Alice one-cent saving INSERT failed",
    )
    expect_error(
        api(base, anon, "/rest/v1/saving_goals?id=eq." + a_goal, method="PATCH",
            bearer=a_token, prefer="return=representation",
            body={"currency_code": "JPY"}),
        "23514", "Immutable USD currency trigger did not reject relabel",
    )
    a_retry = api(
        base, anon, "/rest/v1/saving_goals?on_conflict=id",
        method="POST", bearer=a_token,
        prefer="resolution=merge-duplicates,return=representation",
        body={
            "id": a_goal, "title": "QA Laptop USD", "category": "gadget",
            "target_amount": "1550.50", "target_date": deadline,
            "currency_code": "USD",
        },
    )
    require(
        a_retry[0] in (200, 201) and isinstance(a_retry[1], list)
        and len(a_retry[1]) == 1
        and Decimal(str(a_retry[1][0]["target_amount"])) == Decimal("1550.50"),
        "Same-currency replay with updated USD target was not permitted",
    )
    print("PASS local signed JWT: Alice USD 1500.50 + saving 0.01, currency lock, safe upsert")

    b_insert = api(
        base, anon, "/rest/v1/saving_goals?select=id,user_id,currency_code,target_amount",
        method="POST", bearer=b_token, prefer="return=representation",
        body={
            "id": b_goal, "title": "QA Trip JPY", "category": "trip",
            "target_amount": "500000", "target_date": deadline,
            "currency_code": "JPY",
        },
    )
    require(
        b_insert[0] == 201 and isinstance(b_insert[1], list)
        and len(b_insert[1]) == 1 and b_insert[1][0]["user_id"] == bob,
        "Authenticated Bob JPY goal creation failed",
    )
    b_saving = api(
        base, anon, "/rest/v1/saving_transactions?select=id,user_id",
        method="POST", bearer=b_token, prefer="return=representation",
        body={"id": b_txn, "goal_id": b_goal, "amount": "10.00", "xp_earned": 2},
    )
    require(
        b_saving[0] == 201 and isinstance(b_saving[1], list)
        and b_saving[1][0]["user_id"] == bob,
        "Authenticated Bob JPY contribution failed",
    )
    require(query_owned(base, anon, a_token, "saving_goals", alice),
            "Alice cannot see her own goal")
    require(query_owned(base, anon, b_token, "saving_goals", bob),
            "Bob cannot see his own goal")
    require(query_owned(base, anon, a_token, "saving_transactions", alice),
            "Alice cannot see her own saving")
    require(query_owned(base, anon, b_token, "saving_transactions", bob),
            "Bob cannot see his own saving")
    for table in ("saving_goals", "saving_transactions"):
        require(not query_owned(base, anon, b_token, table, alice),
                "RLS leaked Alice " + table + " to Bob")
        require(not query_owned(base, anon, a_token, table, bob),
                "RLS leaked Bob " + table + " to Alice")

    code, payload = api(
        base, anon, "/rest/v1/saving_goals?id=eq." + a_goal,
        method="PATCH", bearer=b_token,
        prefer="return=representation", body={"target_amount": "1"},
    )
    require(code in (200, 204) and payload in ([], None),
            "Bob updated Alice's USD goal")
    code, payload = api(
        base, anon, "/rest/v1/saving_transactions?id=eq." + a_txn,
        method="DELETE", bearer=b_token, prefer="return=representation",
    )
    require(code in (200, 204) and payload in ([], None),
            "Bob deleted Alice's saving")
    expect_error(
        api(
            base, anon, "/rest/v1/saving_goals", method="POST", bearer=b_token,
            body={"id": "b5555555-5555-4555-8555-555555555555",
                  "user_id": alice, "title": "Forged", "target_amount": "100",
                  "target_date": deadline, "currency_code": "EUR"},
        ), "42501", "Bob could forge a new goal for Alice",
    )
    expect_error(
        api(
            base, anon, "/rest/v1/saving_transactions", method="POST", bearer=b_token,
            body={"id": "b6666666-6666-4666-8666-666666666666",
                  "goal_id": a_goal, "amount": "4.50"},
        ), "23503", "Bob could attach a transaction to Alice's goal",
    )
    expect_error(
        api(base, anon, "/rest/v1/saving_goals?id=eq." + b_goal, method="PATCH",
            bearer=b_token, body={"currency_code": "IDR"}),
        "23514", "Immutable JPY currency trigger did not reject relabel",
    )
    a_read = api(
        base, anon, "/rest/v1/saving_transactions?select=id,amount&id=eq." + a_txn,
        bearer=a_token,
    )
    require(
        a_read[0] == 200 and isinstance(a_read[1], list)
        and len(a_read[1]) == 1
        and Decimal(str(a_read[1][0]["amount"])) == Decimal("0.01"),
        "Alice one-cent saving was altered after Bob's requests",
    )
    # Offline and ambiguous-response replay: use the same immutable local UUID
    # across all attempts. The disconnected attempt MUST hit only a local closed
    # socket; no credentials or customer rows ever leave this ephemeral stack.
    pending_id = "a7777777-7777-4777-8777-777777777777"
    route = "/rest/v1/saving_transactions?on_conflict=id&select=id,user_id,goal_id,amount,xp_earned"
    pending_body = {
        "id": pending_id, "goal_id": a_goal, "amount": "0.02",
        "xp_earned": 7,
    }
    try:
        api("http://127.0.0.1:1", anon, route,
            method="POST", bearer=a_token, body=pending_body,
            prefer="resolution=merge-duplicates,return=representation")
    except urllib.error.URLError:
        pass  # Expected: no listener, analogous to an offline upload failure.
    else:
        raise LocalQAError("Closed-loopback offline attempt unexpectedly succeeded")
    read_pending = "/rest/v1/saving_transactions?select=id,amount,xp_earned&id=eq." + pending_id
    before = api(base, anon, read_pending, bearer=a_token)
    require(before == (200, []),
            "Disconnected attempt must not invent a cloud backup")

    first_replay = api(
        base, anon, route, method="POST", bearer=a_token, body=pending_body,
        prefer="resolution=merge-duplicates,return=representation",
    )
    require(first_replay[0] in (200, 201)
            and isinstance(first_replay[1], list)
            and len(first_replay[1]) == 1
            and first_replay[1][0]["id"] == pending_id,
            "Foreground reconnect did not send exact pending UUID once")
    # The client loses the first HTTP response after the server commits:
    # replay the SAME request as after an uncertain timeout, never mint a new ID.
    second_replay = api(
        base, anon, route, method="POST", bearer=a_token, body=pending_body,
        prefer="resolution=merge-duplicates,return=representation",
    )
    require(second_replay[0] in (200, 201)
            and isinstance(second_replay[1], list)
            and len(second_replay[1]) == 1,
            "Ambiguous-response replay of the same UUID was not idempotent")
    after = api(base, anon, read_pending, bearer=a_token)
    require(after[0] == 200 and isinstance(after[1], list)
            and len(after[1]) == 1
            and after[1][0]["id"] == pending_id
            and Decimal(str(after[1][0]["amount"])) == Decimal("0.02")
            and after[1][0]["xp_earned"] == 7,
            "Two online retries duplicated or changed the saved contribution/XP")
    require(api(base, anon, read_pending, bearer=b_token) == (200, []),
            "Pending/replayed Alice saving leaked to Bob")
    print("PASS local Auth REST offline failure -> retry -> ambiguous response retry: "
          "one saving UUID, exact cents and XP, no owner leak")

    print("PASS local signed JWT: Bob JPY, bidirectional RLS, write isolation, composite FK")
    print("PASS GLOBAL EXPERIENCE V1 LOCAL AUTH+POSTGREST E2E - ZERO PRODUCTION ACCESS")


if __name__ == "__main__":
    try:
        main()
    except (LocalQAError, subprocess.SubprocessError, urllib.error.URLError,
            ValueError, KeyError, TypeError) as exc:
        print("FAIL LOCAL AUTH QA: " + str(exc), file=sys.stderr)
        sys.exit(1)
