"""Issue #80: static proposal gates ONLY. Never connects to Supabase."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/proposals/issue_80_plan_revision_cas_REVIEW_ONLY.sql"
QA = ROOT / "supabase/local_qa/test_issue80_plan_revision_STAGING_ONLY.sql"
DOC = ROOT / "docs/ISSUE_80_PLAN_CAS_STAGING_REVIEW.md"


class PlanRevisionCASProposalSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SQL.read_text()
        cls.qa = QA.read_text()
        cls.doc = DOC.read_text()

    def test_review_only_and_atomic_cutover(self):
        self.assertIn("REVIEW ONLY", self.sql)
        self.assertIn("NOT APPLIED", self.sql)
        self.assertRegex(self.sql, r"(?m)^BEGIN;$")
        self.assertRegex(self.sql, r"(?m)^COMMIT;$")
        self.assertIn("pipo_goals_update_own", self.sql)
        self.assertRegex(
            self.sql,
            r"REVOKE UPDATE ON TABLE public\.saving_goals FROM PUBLIC, anon, authenticated;",
        )
        self.assertRegex(
            self.sql,
            r"DROP POLICY pipo_goals_update_own ON public\.saving_goals;",
        )
        self.assertIn("has_table_privilege('authenticated','public.saving_goals','DELETE')", self.sql)
        self.assertIn("#29", self.sql)

    def test_server_owned_revision_and_restricted_receipts(self):
        self.assertRegex(self.sql, r"ADD COLUMN plan_revision bigint NOT NULL DEFAULT 0")
        self.assertIn("NEW.plan_revision := 0;", self.sql)
        self.assertIn("BEFORE INSERT ON public.saving_goals", self.sql)
        self.assertIn("PRIMARY KEY (owner_id, request_id)", self.sql)
        self.assertIn("ALTER TABLE private.pipo_plan_revision_receipts ENABLE ROW LEVEL SECURITY", self.sql)
        self.assertIn("REVOKE ALL ON TABLE private.pipo_plan_revision_receipts", self.sql)
        self.assertIn("REFERENCES public.saving_goals(id, user_id) ON DELETE CASCADE", self.sql)

    def test_rpc_auth_ownership_anti_bypass(self):
        self.assertRegex(self.sql, r"CREATE FUNCTION public\.pipo_apply_plan_revision_v1\(")
        self.assertIn("SECURITY DEFINER SET search_path = ''", self.sql)
        self.assertIn("v_owner := auth.uid();", self.sql)
        self.assertRegex(self.sql, r"WHERE id=p_goal_id AND user_id=v_owner FOR UPDATE;")
        self.assertIn("REVOKE ALL ON FUNCTION public.pipo_apply_plan_revision_v1(", self.sql)
        self.assertIn("FROM PUBLIC, anon, authenticated;", self.sql)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.pipo_apply_plan_revision_v1(", self.sql)
        self.assertIn("TO authenticated;", self.sql)
        self.assertIn("DROP POLICY pipo_goals_update_own", self.sql)
        self.assertIn("has_function_privilege('anon'", self.sql)

    def test_cas_and_idempotent_receipt(self):
        self.assertIn("v_goal.plan_revision <> p_expected_revision", self.sql)
        self.assertIn("'status','conflict'", self.sql)
        self.assertIn("'current_revision',v_goal.plan_revision", self.sql)
        self.assertIn("plan_revision=plan_revision + 1", self.sql)
        self.assertIn("request_payload=v_request", self.sql)
        self.assertIn("v_receipt.result_snapshot", self.sql)
        self.assertIn("'Request UUID reused with different plan payload'", self.sql)
        self.assertIn("ERRCODE='23505'", self.sql)
        self.assertIn("extract(epoch from p_target_date)", self.sql)
        self.assertRegex(
            self.sql, r"INSERT INTO private\.pipo_plan_revision_receipts"
        )

    def test_allowlisted_future_fields_currency_precision(self):
        self.assertIn("target_amount=p_target_amount", self.sql)
        self.assertIn("target_date=p_target_date", self.sql)
        self.assertIn("rhythm=p_rhythm", self.sql)
        self.assertIn("preferred_saving_day=p_preferred_saving_day", self.sql)
        self.assertIn("planned_contribution_override=p_planned_contribution_override", self.sql)
        self.assertIn("p_target_amount <> trunc(p_target_amount, 2)", self.sql)
        self.assertIn("v_zero_fraction", self.sql)
        self.assertIn("p_target_amount <> trunc(p_target_amount, 0)", self.sql)
        # Currency must not be in the RPC parameter list or updated in SQL.
        rpc = self.sql.split("CREATE FUNCTION public.pipo_apply_plan_revision_v1(", 1)[1]
        signature = rpc.split(") RETURNS jsonb", 1)[0]
        self.assertNotIn("p_currency", signature)
        update = self.sql.split("UPDATE public.saving_goals", 1)[1].split(
            "RETURNING * INTO v_goal", 1
        )[0]
        for forbidden in ("currency_code=", "user_id=", "xp_earned=", "created_at="):
            self.assertNotIn(forbidden, update)

    def test_staging_qa_never_runs_automatically(self):
        self.assertIn("STAGING_ONLY", str(QA))
        self.assertIn("pipo.allow_synthetic_auth_qa", self.qa)
        self.assertRegex(self.qa, r"(?m)^BEGIN;$")
        self.assertRegex(self.qa, r"(?m)^ROLLBACK;$")
        self.assertIn("SET LOCAL ROLE authenticated;", self.qa)
        self.assertIn("request.jwt.claim.sub", self.qa)
        self.assertIn("same request UUID", self.doc)
        self.assertIn("TWO committed sessions", self.doc)
        for contract in ("client spoofed initial revision", "stale revision",
                         "UUID reused with changed payload",
                         "fractional IDR", "direct goal UPDATE",
                         "account B could mutate A goal"):
            self.assertIn(contract, self.qa)

    def test_explicit_rollout_compatibility_hold(self):
        self.assertIn("saving_goals UPSERT", self.doc)
        self.assertIn("INSERT-only", self.doc)
        self.assertIn("Budget breakdown", self.doc)
        self.assertIn("Mac runner", self.doc)
        self.assertIn("Hold all merges", self.doc)


if __name__ == "__main__":
    unittest.main()
