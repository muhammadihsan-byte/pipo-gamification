-- #29 audited emergency rollback ONLY. DO NOT execute without approval.
-- Reverts *this exact* ACL proposal to the previously observed permissions.
-- A rollback re-opens the documented client-side journal mutation risk.
BEGIN;
DROP TRIGGER IF EXISTS pipo_guard_goal_identity_update ON public.saving_goals;
DROP FUNCTION IF EXISTS public.pipo_guard_goal_identity();
GRANT UPDATE, DELETE ON TABLE public.saving_transactions TO authenticated;
GRANT DELETE ON TABLE public.saving_goals TO authenticated;
CREATE POLICY pipo_transactions_update_own ON public.saving_transactions
  FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY pipo_transactions_delete_own ON public.saving_transactions
  FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY pipo_goals_delete_own ON public.saving_goals
  FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);
COMMIT;
