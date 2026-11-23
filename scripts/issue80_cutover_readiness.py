#!/usr/bin/env python3
"""Issue #80 non-deploying, fail-closed CAS production cutover decision gate.

Never reads DB credentials, contacts Supabase, executes SQL, modifies branches,
enables client flags or grants approval. Submitted evidence is a review input,
not independently verified by this script. Independent human review remains
mandatory even when this advisory gate reports no missing conditions.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


MUST_PASS = (
    "signed_legacy_client_pre_post_cutover_qa",
    "signed_insert_only_bridge_qa",
    "signed_cas_v2_budget_client_qa",
    "cross_device_offline_reinstall_recovery_qa",
    "account_switch_and_deletion_journal_cleanup_qa",
    "disposable_real_auth_a_b_qa",
    "backup_restore_drill",
    "rollback_forward_fix_drill",
    "approved_user_upgrade_messaging",
)
# Conservative policy proposal, NOT an observed client-adoption statistic.
MIN_OBSERVATION_DAYS = 14
MAX_TELEMETRY_AGE = timedelta(hours=48)


def _date(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        item = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if item.tzinfo is None:
        return None
    return item.astimezone(timezone.utc)


def evaluate(evidence: Any, *, now: datetime | None = None) -> list[str]:
    """Return review blockers. Missing/false/untrusted evidence is NOT PASS.

    If all fields are populated, the result is only READY_FOR_HUMAN_REVIEW,
    not an instruction or permission to migrate the production database.
    """
    if now is None:
        now = datetime.now(timezone.utc)
    if now.tzinfo is None:
        raise ValueError("Clock must be timezone-aware")
    now = now.astimezone(timezone.utc)
    if not isinstance(evidence, dict):
        return ["Evidence must be a JSON object"]

    blocked: list[str] = []
    if evidence.get("decision_scope") != "review_only_no_execution":
        blocked.append("decision_scope must explicitly forbid production execution")
    if evidence.get("repository_sha") is None or not isinstance(
        evidence.get("repository_sha"), str
    ) or len(evidence["repository_sha"]) != 40 or any(
        ch not in "0123456789abcdef" for ch in evidence["repository_sha"]
    ):
        blocked.append("Exact reviewed source commit SHA is required")

    checks = evidence.get("checks")
    if not isinstance(checks, dict):
        checks = {}
    for key in MUST_PASS:
        item = checks.get(key)
        if not isinstance(item, dict) or item.get("status") != "passed" or not (
            isinstance(item.get("evidence_url"), str)
            and item["evidence_url"].startswith("https://")
            and len(item["evidence_url"]) > 12
        ):
            blocked.append("Missing independently reviewable PASS evidence: " + key)

    distribution = evidence.get("distribution")
    if not isinstance(distribution, dict):
        distribution = {}
    mode = distribution.get("mode")
    if mode == "signed_clients_exist":
        adoption = evidence.get("adoption")
        if not isinstance(adoption, dict):
            adoption = {}
        counts = ("observed_active_client_count",
                  "legacy_upsert_client_count", "unknown_version_client_count")
        for key in counts:
            value = adoption.get(key)
            if type(value) is not int or value < 0:
                blocked.append("Measured nonnegative integer required: " + key)
        total = adoption.get("observed_active_client_count")
        legacy = adoption.get("legacy_upsert_client_count")
        unknown = adoption.get("unknown_version_client_count")
        if type(total) is int and type(legacy) is int and type(unknown) is int:
            if total == 0:
                blocked.append("Zero observed clients cannot prove legacy adoption")
            if legacy != 0 or unknown != 0:
                blocked.append("Legacy/unknown-version clients remain active")
            if legacy + unknown > total:
                blocked.append("Inconsistent adoption cohort counts")
        period = adoption.get("observation_window_days")
        if type(period) is not int or period < MIN_OBSERVATION_DAYS:
            blocked.append("At least 14 days of signed-version cohort data required")
        seen_at = _date(adoption.get("last_observed_at_utc"))
        if seen_at is None or not (timedelta() <= now - seen_at <= MAX_TELEMETRY_AGE):
            blocked.append("Signed-version cohort observation missing, future or stale")
        source = adoption.get("evidence_url")
        if not isinstance(source, str) or not source.startswith("https://"):
            blocked.append("Independent source for signed-version cohort required")
    elif mode == "no_signed_distribution_ever":
        # Alternative for a genuinely unreleased app. A zero-row DB is NOT
        # release-history evidence, and manually setting this field is not proof.
        if distribution.get("app_store_and_testflight_inventory_verified") is not True:
            blocked.append("Unreleased claim needs official distribution inventory proof")
        if distribution.get("prior_adhoc_enterprise_and_local_signed_builds_reviewed") is not True:
            blocked.append("Review prior signed ad-hoc/enterprise/device installations")
        if not isinstance(distribution.get("evidence_url"), str) or not (
            distribution["evidence_url"].startswith("https://")
        ):
            blocked.append("Official no-signed-distribution evidence required")
    else:
        blocked.append("Distribution provenance is unknown or invalid")

    if evidence.get("owner_approval_for_production_cutover") is not True:
        blocked.append("Separate explicit production migration approval absent")
    if evidence.get("pre_cutover_operational_freeze_accepted") is not True:
        blocked.append("Pre-cutover operational freeze not approved")
    if evidence.get("no_unsafe_update_regrant_rollback") is not True:
        blocked.append("Unsafe UPDATE regrant must be explicitly forbidden")
    return blocked


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--evidence", type=Path,
        default=Path("docs/issue80_cutover_evidence_REVIEW_TEMPLATE.json"),
    )
    args = parser.parse_args()
    try:
        evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print("BLOCKED: missing or malformed review evidence: " + str(error))
        return 2
    blockers = evaluate(evidence)
    if blockers:
        print("BLOCKED: CAS PRODUCTION CUTOVER IS NOT AUTHORIZED")
        for reason in blockers:
            print("- " + reason)
        return 2
    print("READY FOR INDEPENDENT HUMAN REVIEW ONLY")
    print("This is NOT approval to merge, deploy SQL, enable Save or touch production.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
