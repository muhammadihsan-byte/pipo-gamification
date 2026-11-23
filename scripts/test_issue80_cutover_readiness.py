"""Offline cutover policy and signed legacy migration contract regressions.

Never contacts live Supabase, deploys SQL, enables feature flags, or consumes
paid iOS runner minutes. The signed HTTP/PG integration is a separate QA job.
"""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json
import unittest

from scripts.issue80_cutover_readiness import (
    MIN_OBSERVATION_DAYS,
    MUST_PASS,
    evaluate,
)

ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 11, 23, 5, 0, tzinfo=timezone.utc)
SAFE_SHA = "a" * 40


def complete_review_input(mode: str = "signed_clients_exist") -> dict:
    return {
        "decision_scope": "review_only_no_execution",
        "repository_sha": SAFE_SHA,
        "checks": {
            key: {"status": "passed", "evidence_url": "https://qa.example.test/" + key}
            for key in MUST_PASS
        },
        "distribution": {
            "mode": mode,
            "app_store_and_testflight_inventory_verified": True,
            "prior_adhoc_enterprise_and_local_signed_builds_reviewed": True,
            "evidence_url": "https://qa.example.test/distribution",
        },
        "adoption": {
            "observation_window_days": MIN_OBSERVATION_DAYS,
            "observed_active_client_count": 100,
            "legacy_upsert_client_count": 0,
            "unknown_version_client_count": 0,
            "last_observed_at_utc": "2026-11-23T04:00:00Z",
            "evidence_url": "https://qa.example.test/telemetry",
        },
        "owner_approval_for_production_cutover": True,
        "pre_cutover_operational_freeze_accepted": True,
        "no_unsafe_update_regrant_rollback": True,
    }


class CutoverReadinessTests(unittest.TestCase):
    def test_committed_review_manifest_fail_closed(self):
        path = ROOT / "docs/issue80_cutover_evidence_REVIEW_TEMPLATE.json"
        missing = evaluate(json.loads(path.read_text()), now=NOW)
        self.assertGreaterEqual(len(missing), 12)
        self.assertTrue(any("Separate explicit production" in x for x in missing))
        self.assertTrue(any("Distribution provenance" in x for x in missing))

    def test_complete_synthetic_inputs_only_show_advisory_ready(self):
        self.assertEqual(evaluate(complete_review_input(), now=NOW), [])
        self.assertEqual(
            evaluate(complete_review_input("no_signed_distribution_ever"), now=NOW),
            [],
        )

    def test_zero_rows_or_no_observed_users_not_adoption(self):
        doc = complete_review_input()
        doc["adoption"]["observed_active_client_count"] = 0
        self.assertTrue(any("Zero observed clients" in x
                            for x in evaluate(doc, now=NOW)))
        # An asserted no-release case with no distribution inventory is NOT proof.
        doc = complete_review_input("no_signed_distribution_ever")
        doc["distribution"]["app_store_and_testflight_inventory_verified"] = False
        doc["distribution"]["evidence_url"] = None
        self.assertTrue(any("inventory" in x for x in evaluate(doc, now=NOW)))

    def test_legacy_unknown_clients_and_telemetry_freshness(self):
        for field in ("legacy_upsert_client_count", "unknown_version_client_count"):
            doc = complete_review_input()
            doc["adoption"][field] = 1
            self.assertTrue(any("remain active" in x
                                for x in evaluate(doc, now=NOW)))
        for at in ("2026-11-19T04:00:00Z", "2026-11-24T04:00:00Z", "naive date"):
            doc = complete_review_input()
            doc["adoption"]["last_observed_at_utc"] = at
            self.assertTrue(any("stale" in x or "future" in x
                                for x in evaluate(doc, now=NOW)))
        doc = complete_review_input()
        doc["adoption"]["observation_window_days"] = 13
        self.assertTrue(any("14 days" in x for x in evaluate(doc, now=NOW)))

    def test_missing_real_signed_qa_and_owner_permission_block(self):
        doc = complete_review_input()
        for key in MUST_PASS:
            broken = deepcopy(doc)
            broken["checks"][key]["evidence_url"] = None
            self.assertTrue(any(key in x for x in evaluate(broken, now=NOW)))
        for key in ("owner_approval_for_production_cutover",
                    "pre_cutover_operational_freeze_accepted",
                    "no_unsafe_update_regrant_rollback"):
            broken = deepcopy(doc)
            broken[key] = False
            self.assertNotEqual(evaluate(broken, now=NOW), [])

    def test_signed_local_harness_proves_three_cutover_phases(self):
        source = (ROOT / "scripts/local_authenticated_issue80_cas_qa.py").read_text()
        markers = (
            "PHASE 0: real signed old-version write contract",
            "PHASE 1: immutable ledger ACL #29",
            "PHASE 2: #81 CAS migration",
        )
        for marker in markers:
            self.assertIn(marker, source)
        self.assertLess(source.index(markers[0]), source.index(markers[1]))
        self.assertLess(source.index(markers[1]), source.index(markers[2]))
        self.assertIn('prefer="resolution=merge-duplicates,return=representation"', source)
        self.assertIn('and denied_old.get("code") == "42501"', source)
        self.assertIn('updated_legacy.get("accepted_revision") == 1', source)
        self.assertIn("loopback_only(base, \"API_URL\")", source)
        self.assertIn("loopback_only(db, \"DB_URL\")", source)

    def test_migration_and_client_compile_release_flags_stay_off(self):
        project = (ROOT / "Pipo.xcodeproj/project.pbxproj").read_text()
        service = (ROOT / "Pipo/Core/Network/SupabaseService.swift").read_text()
        for unsafe_flag in ("PIPO_ISSUE80_STAGING", "PIPO_ISSUE80_BRIDGE"):
            self.assertNotIn(unsafe_flag, project)
        self.assertIn("#if PIPO_ISSUE80_BRIDGE", service)
        self.assertIn('upsert(payloads, onConflict: "id")', service)
        cas = (ROOT / "supabase/proposals/issue_80_plan_revision_cas_REVIEW_ONLY.sql").read_text()
        self.assertIn("REVOKE UPDATE ON TABLE public.saving_goals", cas)
        self.assertIn("DROP POLICY pipo_goals_update_own", cas)
        self.assertIn("COMMIT;", cas)
        for path in (ROOT / "supabase/migrations").glob("*.sql"):
            source = path.read_text().lower()
            self.assertNotIn("pipo_apply_plan_revision_v1(", source,
                             f"Accidental live CAS migration: {path}")
            self.assertNotIn("pipo_apply_plan_budget_v2(", source,
                             f"Accidental live Budget CAS migration: {path}")


if __name__ == "__main__":
    unittest.main()
