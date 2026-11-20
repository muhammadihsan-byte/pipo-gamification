#!/usr/bin/env python3
"""Non-destructive, live Pipo Supabase security smoke test.

Only PUBLIC iOS build configuration is read. Never supplies a real user token,
creates an account, or deletes user data. A passing run is NOT authenticated
two-account proof and NOT a substitute for signed iPhone testing.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

EXPECTED_HOST = "jdboaaiiwkblxvejnhol.supabase.co"
FAKE_ID = "00000000-0000-4000-8000-000000000000"
PRIVATE_TABLES = ("saving_goals", "saving_transactions", "user_profiles")


def load_public_configuration(project: Path) -> tuple[str, str]:
    text = project.read_text(encoding="utf-8")
    url_match = re.search(r'SUPABASE_URL\s*=\s*"([^"]+)"', text)
    key_match = re.search(r'SUPABASE_ANON_KEY\s*=\s*"([^"]+)"', text)
    if not url_match or not key_match:
        raise ValueError("Missing public Supabase Xcode build configuration")
    url, key = url_match.group(1).rstrip("/"), key_match.group(1)
    components = urlsplit(url)
    if components.scheme != "https" or components.netloc != EXPECTED_HOST:
        raise ValueError("Unexpected Supabase host; refusing to send requests")
    if not key.startswith("sb_publishable_"):
        raise ValueError("Client key must be publishable (not secret/service role)")
    return url, key


def fetch_status(url: str, *, key: str, method: str = "GET",
                 token: str | None = None, data: bytes | None = None) -> int:
    headers = {"apikey": key, "accept": "application/json"}
    if data is not None:
        headers["content-type"] = "application/json"
    if token is not None:
        headers["authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def probe(base: str, key: str) -> list[dict[str, object]]:
    tests: list[dict[str, object]] = []

    def record(name: str, actual: int, allowed: set[int]) -> None:
        tests.append({
            "check": name, "http_status": actual,
            "passed": actual in allowed,
            "expected_statuses": sorted(allowed),
        })

    gateway = f"{base}/functions/v1/delete-account"
    body = json.dumps({"expected_user_id": FAKE_ID}).encode("utf-8")
    record("Deletion without bearer JWT is denied",
           fetch_status(gateway, key=key, method="POST", data=body), {401, 403})
    record("Deletion with forged JWT is denied",
           fetch_status(gateway, key=key, method="POST",
                        token="invalid.jwt.signature", data=body), {401, 403})

    # No authenticated access token, no mutation: all Pipo public tables
    # should be inaccessible to the anonymous PostgREST role.
    for table in PRIVATE_TABLES:
        endpoint = f"{base}/rest/v1/{table}?select=*&limit=1"
        record(f"Anonymous {table} read is denied",
               fetch_status(endpoint, key=key), {401, 403})

    # Public GoTrue settings is a health check; it does NOT expose redirect
    # allow-list details and must not be interpreted as proof of email delivery.
    record("Supabase Auth public settings endpoint is reachable",
           fetch_status(f"{base}/auth/v1/settings", key=key), {200})
    return tests


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path,
                        default=Path("Pipo.xcodeproj/project.pbxproj"))
    parser.add_argument("--output", type=Path,
                        default=Path("validation/live-auth-smoke.json"))
    args = parser.parse_args()
    try:
        base, key = load_public_configuration(args.project)
        results = probe(base, key)
    except (ValueError, OSError, urllib.error.URLError, TimeoutError) as exc:
        # Do not dump request headers or public key into CI logs.
        print(f"Live smoke incomplete: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    passed = all(item["passed"] for item in results)
    evidence = {
        "project_ref": "jdboaaiiwkblxvejnhol",
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "anonymous-only, nondestructive",
        "all_passed": passed,
        "checks": results,
        "NOT_VERIFIED": [
            "Supabase Auth redirect URL allowlist",
            "Password reset email and recovery deep link on signed device",
            "Authenticated two-user RLS isolation",
            "Authenticated hard deletion/cascade with disposable user",
            "Apple developer signing, TestFlight and App Store submission",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    for item in results:
        label = "PASS" if item["passed"] else "FAIL"
        print(f"{label} {item['check']} (HTTP {item['http_status']})")
    print("Scope: anonymous/forged credentials only; no account deletion executed")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
