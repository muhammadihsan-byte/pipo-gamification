"""#28 Pay Schema V2: fast safety contract checks, not a substitute for PG QA.

Never executes on connected Supabase. Native checkout stays disabled.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "supabase/proposals/issue28_pay_schema_v2_REVIEW_ONLY.sql"
QA = ROOT / "supabase/local_qa/test_issue28_pay_schema_v2.sql"
IAP = ROOT / "Pipo/Core/Paywall/StoreKitManager.swift"
CATALOG = ROOT / "StoreKit.storekit"

class PaySchemaFoundationReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = SCHEMA.read_text()
        cls.qa = QA.read_text()
        cls.app = IAP.read_text()

    def test_proposal_is_review_only_unseeded_and_transactional(self):
        self.assertIn("REVIEW ONLY", self.s)
        self.assertIn("DO NOT apply", self.s)
        self.assertRegex(self.s, r"(?m)^BEGIN;")
        self.assertRegex(self.s, r"(?m)^COMMIT;")
        self.assertRegex(self.s, r"RAISE EXCEPTION 'Pay V2 grant boundary broken'")
        self.assertIn("Live Apple catalog must start empty", self.s)
        self.assertIn("enabled boolean NOT NULL DEFAULT false", self.s)
        self.assertNotIn("qa.pipo.personal.slot", self.s)
        self.assertIn("pipo_billing_private.apple_catalog", self.s)

    def test_no_direct_client_write_or_private_apple_ledger_access(self):
        self.assertIn("REVOKE ALL ON SCHEMA pipo_billing_private FROM PUBLIC, anon, authenticated", self.s)
        self.assertIn("GRANT USAGE ON SCHEMA pipo_billing_private TO service_role", self.s)
        self.assertIn("ALTER TABLE public.pipo_entitlements_v2 ENABLE ROW LEVEL SECURITY", self.s)
        self.assertIn("CREATE POLICY pipo_entitlements_v2_select_owner", self.s)
        self.assertIn("USING (user_id = (select auth.uid()))", self.s)
        self.assertIn("GRANT SELECT ON TABLE public.pipo_entitlements_v2 TO authenticated", self.s)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.pipo_read_entitlements_v2()", self.s)
        self.assertIn("GRANT EXECUTE ON FUNCTION pipo_billing_private.apply_verified_apple_event_v1(", self.s)
        self.assertIn("TO service_role", self.s)
        self.assertIn("public.pipo_internal_ingest_verified_apple_event_v1", self.s)
        self.assertIn("REVOKE ALL ON FUNCTION public.pipo_internal_ingest_verified_apple_event_v1(", self.s)
        self.assertIn("AND (enabled=true OR p_action IN ('refunded','revoked'))", self.s)
        self.assertNotRegex(self.s, r"(?i)GRANT\s+(?:INSERT|UPDATE|ALL).*?pipo_entitlements_v2\s+TO\s+authenticated")
        self.assertIn("SECURITY INVOKER SET search_path = ''", self.s)
        self.assertNotIn("SECURITY DEFINER", self.s)

    def test_event_idempotency_refund_terminal_and_personal_pro_only(self):
        for phrase in (
            "PRIMARY KEY(environment, transaction_id)",
            "PRIMARY KEY(environment, event_id)",
            "app_account_token = user_id",
            "p_app_account_token IS DISTINCT FROM p_user_id",
            "Apple event ID conflict",
            "Apple transaction bound to another account or SKU",
            "p_action IN ('refunded','revoked')",
            "revocation/refund is terminal",
            "personal_lifetime_pro",
            "benefit='personal_slot'",
            "benefit='group_slot'",
            "revision = e.revision + 1",
          ):
             self.assertIn(phrase.lower(), self.s.lower())
        self.assertIn("personal_lifetime_pro boolean NOT NULL DEFAULT false", self.s)
        self.assertIn("2::integer, 1::integer", self.s)

    def test_no_false_apple_verification_or_checkout_activation(self):
        self.assertIn("DOES NOT verify cryptographic signatures", self.s)
        self.assertIn("caller MUST have independently verified", self.s)
        self.assertIn("static let purchasesEnabled = false", self.app)
        self.assertIn('"productID" : "com.pipo.goalslot"', CATALOG.read_text())
        self.assertNotIn("Apple secret", self.s)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", self.s)

    def test_disposable_local_qa_is_roll_back_only(self):
        self.assertRegex(self.qa, r"(?m)^BEGIN;")
        self.assertRegex(self.qa, r"(?m)^ROLLBACK;")
        self.assertIn("SET LOCAL ROLE authenticated", self.qa)
        self.assertIn("SET LOCAL ROLE service_role", self.qa)
        for token in (
            "cross-account Apple replay accepted",
            "mismatched appAccountToken accepted",
            "disabled production SKU accepted",
            "refund-before-purchase was overwritten",
            "B sees A entitlement",
            "client can forge credits",
            "client can grant via private SQL function",
            "account deletion did not cascade",
            "retired SKU refund did not revoke credit",
            "retired SKU minted new purchase",
            "client can call service-only public RPC",
        ):
            self.assertIn(token, self.qa)

if __name__ == "__main__":
    unittest.main()
