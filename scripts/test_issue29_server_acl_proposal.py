"""Static review gates only: this is NOT a staging SQL or two-account test."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
ACL = ROOT / "supabase/proposals/issue_29_immutable_contribution_acl_REVIEW_ONLY.sql"
QA = ROOT / "supabase/local_qa/test_issue29_ledger_acl.sql"
ROLLBACK = ROOT / "supabase/proposals/issue_29_immutable_contribution_acl_ROLLBACK_ONLY.sql"


class ServerLedgerProposalSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.acl = ACL.read_text()
        cls.qa = QA.read_text()
        cls.rollback = ROLLBACK.read_text()

    def test_proposal_is_transactional_explicitly_review_only(self):
        self.assertIn("REVIEW ONLY", self.acl)
        self.assertIn("NOT APPLIED", self.acl)
        self.assertRegex(self.acl, r"(?m)^BEGIN;")
        self.assertRegex(self.acl, r"(?m)^COMMIT;")
        self.assertIn("RAISE EXCEPTION", self.acl)
        self.assertIn("RLS must be enabled", self.acl)

    def test_authenticated_cannot_rewrite_events_or_cascade_delete_goals(self):
        self.assertRegex(self.acl, r"REVOKE UPDATE, DELETE ON TABLE public\.saving_transactions\s+FROM PUBLIC, anon, authenticated")
        self.assertRegex(self.acl, r"REVOKE DELETE ON TABLE public\.saving_goals FROM PUBLIC, anon, authenticated")
        for policy in (
            "pipo_transactions_update_own", "pipo_transactions_delete_own",
            "pipo_goals_delete_own"
        ):
            self.assertIn("DROP POLICY " + policy, self.acl)
        self.assertIn("ON CONFLICT DO NOTHING", self.acl)
        self.assertIn("has_table_privilege('authenticated'", self.acl)

    def test_auth_privacy_cascade_preserved_no_definer_or_fk_rewrite(self):
        self.assertIn("saving_goals_user_id_fkey", self.acl)
        self.assertIn("saving_transactions_user_id_fkey", self.acl)
        self.assertIn("saving_transaction_owned_goal", self.acl)
        self.assertNotRegex(self.acl, r"(?i)\bALTER\s+TABLE\s+.*\bDROP\s+CONSTRAINT\b")
        self.assertNotRegex(self.acl, r"(?i)\bSECURITY\s+DEFINER\b")
        self.assertIn("SECURITY INVOKER", self.acl)
        self.assertIn("OLD.user_id IS DISTINCT FROM NEW.user_id", self.acl)

    def test_qa_uses_rollback_and_two_synthetic_auth_accounts(self):
        self.assertRegex(self.qa, r"(?m)^BEGIN;")
        self.assertRegex(self.qa, r"(?m)^ROLLBACK;")
        self.assertIn("SET LOCAL ROLE authenticated", self.qa)
        self.assertIn("11111111-2222-4333-8444-555555555551", self.qa)
        self.assertIn("11111111-2222-4333-8444-555555555552", self.qa)
        for case in ("UPDATE permitted", "DELETE permitted",
                     "CASCADE DELETE permitted", "B sees A journal",
                     "Auth erasure did not cascade"):
            self.assertIn(case, self.qa)
        self.assertIn("ON CONFLICT(id) DO NOTHING", self.qa)

    def test_separate_rollback_requires_security_review(self):
        self.assertIn("DO NOT execute without approval", self.rollback)
        self.assertIn("GRANT UPDATE, DELETE", self.rollback)
        self.assertIn("CREATE POLICY pipo_transactions_update_own", self.rollback)
        self.assertNotIn("issue_29_immutable_contribution_acl_ROLLBACK_ONLY.sql", self.acl)


if __name__ == "__main__":
    unittest.main()
