#!/usr/bin/env python3
"""Read-only, credentialed two-account RLS QA against Pipo Supabase.

Run ONLY with explicitly approved disposable accounts you control. Passwords
and JWTs must come from environment secrets, NEVER code or build artifacts.
This never creates, mutates or deletes a user, goal, or transaction.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from uuid import UUID

from smoke_supabase_live import load_public_configuration

TABLES = ("saving_goals", "saving_transactions")
MARKER = "+pipoqa"


class QAError(RuntimeError):
    pass


def approved_email(value: str) -> bool:
    """Refuse unmarked personal/customer accounts even if credentials exist."""
    address = value.strip().lower()
    return (bool(re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", address))
            and MARKER in address.split("@", 1)[0])


def validate_accounts(a_email: str, b_email: str) -> None:
    if not approved_email(a_email) or not approved_email(b_email):
        raise QAError("Both account addresses must have a +pipoqa disposable marker")
    if a_email.strip().casefold() == b_email.strip().casefold():
        raise QAError("Two different disposable accounts are required")


def request_json(url: str, key: str, *,
                 token: str | None = None,
                 method: str = "GET",
                 body: dict[str, object] | None = None) -> object:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {
        "apikey": key,
        "accept": "application/json",
    }
    if data is not None:
        headers["content-type"] = "application/json"
    if token:
        headers["authorization"] = "Bearer " + token
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=18) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        # Do not echo response body: it may contain account-identifying data.
        raise QAError(f"Supabase endpoint returned HTTP {exc.code}") from None


def sign_in(base: str, key: str, email: str, password: str) -> tuple[str, str]:
    payload = request_json(
        base + "/auth/v1/token?grant_type=password", key, method="POST",
        body={"email": email, "password": password},
    )
    if not isinstance(payload, dict):
        raise QAError("Unexpected sign-in response")
    token = payload.get("access_token")
    user = payload.get("user")
    if not isinstance(token, str) or not isinstance(user, dict):
        raise QAError("No authenticated session: verify disposable account and email")
    user_id = user.get("id")
    if not isinstance(user_id, str):
        raise QAError("Unexpected account identifier")
    try:
        UUID(user_id)
    except ValueError:
        raise QAError("Invalid UUID in Auth session") from None

    user_info = request_json(base + "/auth/v1/user", key, token=token)
    if not isinstance(user_info, dict) or user_info.get("id") != user_id:
        raise QAError("Session lookup did not match the signed-in user")
    actual_email = str(user_info.get("email", "")).casefold()
    if actual_email != email.casefold():
        raise QAError("Signed-in email does not match the approved disposable alias")
    return user_id, token


def owned_rows(base: str, key: str, token: str,
               table: str, owner: str) -> list[object]:
    if table not in TABLES:
        raise QAError("Table not allowlisted")
    url = base + "/rest/v1/" + table + "?" + urllib.parse.urlencode({
        "select": "id,user_id",
        "user_id": "eq." + owner,
        "limit": "100",
    })
    rows = request_json(url, key, token=token)
    if not isinstance(rows, list):
        raise QAError("Expected a list of scoped rows")
    return rows


def cross_account_assertions(a_rows: list[object], b_rows: list[object],
                             a_seen_from_b: list[object],
                             b_seen_from_a: list[object], table: str) -> None:
    if not a_rows or not b_rows:
        raise QAError(
            f"Seed a personal {table} row for EACH test account on a signed iPhone "
            "before running this check; no empty-table false positive allowed"
        )
    if a_seen_from_b or b_seen_from_a:
        raise QAError(f"Potential cross-account read exposure on {table}")


def main() -> int:
    try:
        if os.getenv("PIPO_QA_DISPOSABLE_APPROVED") != "I_CONFIRM_BOTH_ARE_DISPOSABLE":
            raise QAError("Explicit disposable-user approval flag is required")
        email_a = os.environ["PIPO_QA_A_EMAIL"]
        email_b = os.environ["PIPO_QA_B_EMAIL"]
        validate_accounts(email_a, email_b)
        password_a = os.environ["PIPO_QA_A_PASSWORD"]
        password_b = os.environ["PIPO_QA_B_PASSWORD"]
        if not password_a or not password_b:
            raise QAError("Both passwords are required from Actions secrets")
        base, key = load_public_configuration(Path("Pipo.xcodeproj/project.pbxproj"))
        id_a, token_a = sign_in(base, key, email_a, password_a)
        id_b, token_b = sign_in(base, key, email_b, password_b)
        if id_a == id_b:
            raise QAError("Expected different Auth identities")

        for table in TABLES:
            own_a = owned_rows(base, key, token_a, table, id_a)
            own_b = owned_rows(base, key, token_b, table, id_b)
            cross_a = owned_rows(base, key, token_a, table, id_b)
            cross_b = owned_rows(base, key, token_b, table, id_a)
            cross_account_assertions(own_a, own_b, cross_b, cross_a, table)
            print(f"PASS two-account RLS SELECT separation: {table}")
        print("PASS both disposable Auth sessions and self-owned seeded records")
        print("SCOPE: READ-ONLY. Password reset, account deletion and signed device still require E2E QA.")
        return 0
    except (QAError, KeyError, OSError, urllib.error.URLError) as exc:
        # Credentials/JWT/email are deliberately never printed.
        label = "Missing required Actions secret" if isinstance(exc, KeyError) else str(exc)
        print(f"RLS QA incomplete or failed: {label}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
