-- Pipo Pay Schema Backend Foundation V1 · #28 / #87 · REVIEW ONLY
-- DO NOT apply to connected / production Supabase. NO Apple verification
-- exists in this SQL. Only an independently audited, server-held Apple JWS
-- verifier may call the service_role-only ingestion function.
-- SKU catalog deliberately EMPTY: no product ID is approved for billing.
-- Intended for local disposable Postgres 17 with current public.user_profiles
-- schema (whose paid counters remain unmodified and read-only to clients).
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.user_profiles') IS NULL
     OR to_regclass('auth.users') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_class
       WHERE oid = 'public.user_profiles'::regclass AND relrowsecurity
     ) THEN
    RAISE EXCEPTION 'Pipo auth/users or RLS-protected profile schema missing';
  END IF;
  IF has_table_privilege('authenticated', 'public.user_profiles', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.user_profiles', 'INSERT') THEN
    RAISE EXCEPTION 'Existing legacy paid counters must remain server-owned';
  END IF;
  IF to_regclass('public.pipo_entitlements_v2') IS NOT NULL
     OR to_regclass('pipo_billing_private.apple_transactions') IS NOT NULL THEN
    RAISE EXCEPTION 'Pay V2 schema already exists: require reviewed upgrade migration';
  END IF;
END
$preflight$;

CREATE SCHEMA IF NOT EXISTS pipo_billing_private;
REVOKE ALL ON SCHEMA pipo_billing_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA pipo_billing_private TO service_role;

-- Product IDs are release-specific and NEVER enabled by this proposal.
-- One distinct logical category per environment/product ID; no generic
-- device-supplied +1 / is_group / tier field is used to award credits.
CREATE TABLE pipo_billing_private.apple_catalog (
  environment text NOT NULL CHECK (environment IN ('Sandbox','Production')),
  product_id text NOT NULL CHECK (
    length(product_id) BETWEEN 5 AND 160
    AND product_id ~ '^[A-Za-z0-9._-]+$'
  ),
  bundle_id text NOT NULL CHECK (length(bundle_id) BETWEEN 6 AND 160),
  benefit text NOT NULL CHECK (
    benefit IN ('personal_slot','group_slot','personal_lifetime_pro')
  ),
  enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(environment, product_id)
);

-- Apple transaction identity is unique across all Pipo accounts.
-- A refund/revocation received BEFORE purchase creates a terminal tombstone:
-- later delayed "purchased" cannot silently mint a benefit.
CREATE TABLE pipo_billing_private.apple_transactions (
  environment text NOT NULL CHECK (environment IN ('Sandbox','Production')),
  transaction_id text NOT NULL CHECK (
    length(transaction_id) BETWEEN 1 AND 80 AND transaction_id ~ '^[0-9]+$'
  ),
  original_transaction_id text NOT NULL CHECK (
    length(original_transaction_id) BETWEEN 1 AND 80
    AND original_transaction_id ~ '^[0-9]+$'
  ),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_account_token uuid NOT NULL,
  product_id text NOT NULL,
  benefit text NOT NULL CHECK (
    benefit IN ('personal_slot','group_slot','personal_lifetime_pro')
  ),
  state text NOT NULL CHECK (
    state IN ('purchased','refunded','revoked')
  ),
  proof_sha256 text NOT NULL CHECK (
    length(proof_sha256) = 64 AND proof_sha256 ~ '^[a-f0-9]{64}$'
  ),
  apple_signed_at timestamptz NOT NULL,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(environment, transaction_id),
  FOREIGN KEY(environment, product_id)
    REFERENCES pipo_billing_private.apple_catalog(environment, product_id),
  CHECK (app_account_token = user_id)
);
CREATE INDEX apple_transactions_owner_idx
  ON pipo_billing_private.apple_transactions(user_id, environment, state);

-- Every Apple notification / proof delivery has a unique stable EVENT ID.
-- Duplicate event IDs with mismatched transaction/owner/body fail closed.
CREATE TABLE pipo_billing_private.apple_events (
  environment text NOT NULL CHECK(environment IN ('Sandbox','Production')),
  event_id text NOT NULL CHECK (length(event_id) BETWEEN 1 AND 160),
  transaction_id text NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id text NOT NULL,
  action text NOT NULL CHECK(action IN ('purchased','refunded','revoked')),
  proof_sha256 text NOT NULL CHECK (
    proof_sha256 ~ '^[a-f0-9]{64}$'
  ),
  received_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(environment, event_id),
  FOREIGN KEY(environment, transaction_id)
    REFERENCES pipo_billing_private.apple_transactions(environment, transaction_id)
    ON DELETE CASCADE
);
CREATE INDEX apple_events_owner_idx ON
  pipo_billing_private.apple_events(user_id, environment, received_at DESC);

-- Read-only client snapshot. Never rely on local purchases/goal counters
-- for authorization. Lifetime Pro applies only to PERSONAL capacity.
CREATE TABLE public.pipo_entitlements_v2 (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  permanent_personal_slots integer NOT NULL DEFAULT 0
    CHECK (permanent_personal_slots >= 0),
  permanent_group_slots integer NOT NULL DEFAULT 0
    CHECK (permanent_group_slots >= 0),
  personal_lifetime_pro boolean NOT NULL DEFAULT false,
  revision bigint NOT NULL DEFAULT 0 CHECK (revision >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.pipo_entitlements_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipo_billing_private.apple_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipo_billing_private.apple_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipo_billing_private.apple_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.pipo_entitlements_v2 FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.pipo_entitlements_v2 TO authenticated;
GRANT ALL ON TABLE public.pipo_entitlements_v2 TO service_role;
REVOKE ALL ON TABLE pipo_billing_private.apple_catalog,
  pipo_billing_private.apple_transactions,
  pipo_billing_private.apple_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE pipo_billing_private.apple_catalog,
  pipo_billing_private.apple_transactions,
  pipo_billing_private.apple_events TO service_role;

CREATE POLICY pipo_entitlements_v2_select_owner
  ON public.pipo_entitlements_v2
  FOR SELECT TO authenticated
  USING (user_id = (select auth.uid()));

-- Returning a single zero-entitlement row for a first-time authenticated user
-- avoids assuming that a profile has been created. No client-owned user arg.
CREATE FUNCTION public.pipo_read_entitlements_v2()
RETURNS TABLE (
  user_id uuid,
  free_personal_slots integer,
  free_group_creator_slots integer,
  permanent_personal_slots integer,
  permanent_group_slots integer,
  personal_lifetime_pro boolean,
  revision bigint
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $read$
  SELECT (select auth.uid()), 2::integer, 1::integer,
    coalesce(s.permanent_personal_slots, 0),
    coalesce(s.permanent_group_slots, 0),
    coalesce(s.personal_lifetime_pro, false),
    coalesce(s.revision, 0::bigint)
  FROM (SELECT 1) AS anchor
  LEFT JOIN public.pipo_entitlements_v2 s
    ON s.user_id = (select auth.uid())
  WHERE (select auth.uid()) IS NOT NULL
$read$;
REVOKE ALL ON FUNCTION public.pipo_read_entitlements_v2()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pipo_read_entitlements_v2()
  TO authenticated, service_role;

-- TRUST BOUNDARY: caller MUST have independently verified Apple's signed
-- JWS / notification with trusted Apple chain, environment, appAppleId,
-- bundleId, appAccountToken, transaction status and Server API freshness.
-- This private database function DOES NOT verify cryptographic signatures.
-- Never expose it via a user-controlled Edge endpoint or install a catalog
-- entry before that external verifier and refund notification pipeline exist.
CREATE FUNCTION pipo_billing_private.apply_verified_apple_event_v1(
  p_environment text,
  p_event_id text,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_bundle_id text,
  p_user_id uuid,
  p_app_account_token uuid,
  p_action text,
  p_proof_sha256 text,
  p_apple_signed_at timestamptz
)
RETURNS TABLE(
  owner_id uuid,
  personal_slots integer,
  group_slots integer,
  lifetime_pro boolean,
  entitlement_revision bigint
)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $apply$
DECLARE
  v_catalog pipo_billing_private.apple_catalog%ROWTYPE;
  v_tx pipo_billing_private.apple_transactions%ROWTYPE;
  v_event pipo_billing_private.apple_events%ROWTYPE;
  v_entitlements public.pipo_entitlements_v2%ROWTYPE;
  v_changed boolean := false;
BEGIN
  IF p_environment IS NULL OR p_environment NOT IN ('Sandbox','Production')
     OR p_action IS NULL OR p_action NOT IN ('purchased','refunded','revoked')
     OR p_user_id IS NULL OR p_app_account_token IS DISTINCT FROM p_user_id
     OR p_event_id IS NULL OR length(p_event_id) NOT BETWEEN 1 AND 160
     OR p_transaction_id IS NULL OR p_transaction_id !~ '^[0-9]{1,80}$'
     OR p_original_transaction_id IS NULL
     OR p_original_transaction_id !~ '^[0-9]{1,80}$'
     OR p_product_id IS NULL OR p_bundle_id IS NULL
     OR p_proof_sha256 IS NULL OR p_proof_sha256 !~ '^[a-f0-9]{64}$'
     OR p_apple_signed_at IS NULL
     OR p_apple_signed_at > now() + interval '5 minutes'
  THEN
    RAISE EXCEPTION 'Invalid Apple verified-event envelope'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_catalog
    FROM pipo_billing_private.apple_catalog
    WHERE environment=p_environment AND product_id=p_product_id
      AND bundle_id=p_bundle_id AND enabled=true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Apple product/environment/bundle not in enabled server catalog'
      USING ERRCODE = '22023';
  END IF;

  -- Serialize per owner across distinct simultaneous purchases, including
  -- first-time entitlements row creation. The ledger is recomputed from
  -- canonical Apple transaction statuses, not from client-supplied totals.
  INSERT INTO public.pipo_entitlements_v2(user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO STRICT v_entitlements
    FROM public.pipo_entitlements_v2 WHERE user_id=p_user_id FOR UPDATE;

  -- Same event ID with changed transaction/account/proof is a hard error.
  SELECT * INTO v_event FROM pipo_billing_private.apple_events
    WHERE environment=p_environment AND event_id=p_event_id;
  IF FOUND THEN
    IF v_event.transaction_id IS DISTINCT FROM p_transaction_id
       OR v_event.user_id IS DISTINCT FROM p_user_id
       OR v_event.product_id IS DISTINCT FROM p_product_id
       OR v_event.action IS DISTINCT FROM p_action
       OR v_event.proof_sha256 IS DISTINCT FROM p_proof_sha256 THEN
      RAISE EXCEPTION 'Apple event ID conflict' USING ERRCODE = '23505';
    END IF;
    RETURN QUERY SELECT p_user_id, v_entitlements.permanent_personal_slots,
      v_entitlements.permanent_group_slots,
      v_entitlements.personal_lifetime_pro, v_entitlements.revision;
    RETURN;
  END IF;

  SELECT * INTO v_tx FROM pipo_billing_private.apple_transactions
    WHERE environment=p_environment AND transaction_id=p_transaction_id
    FOR UPDATE;

  IF FOUND THEN
    IF v_tx.user_id IS DISTINCT FROM p_user_id
       OR v_tx.app_account_token IS DISTINCT FROM p_app_account_token
       OR v_tx.product_id IS DISTINCT FROM p_product_id
       OR v_tx.original_transaction_id IS DISTINCT FROM p_original_transaction_id
       OR v_tx.benefit IS DISTINCT FROM v_catalog.benefit THEN
      RAISE EXCEPTION 'Apple transaction bound to another account or SKU'
        USING ERRCODE = '23505';
    END IF;

    -- Revocation/refund is terminal for this transaction. An out-of-order
    -- old "purchased" event cannot re-grant or restore a refunded purchase.
    IF v_tx.state = 'purchased' AND p_action IN ('refunded','revoked') THEN
      UPDATE pipo_billing_private.apple_transactions SET
        state = p_action, last_seen_at = now()
        WHERE environment=p_environment AND transaction_id=p_transaction_id;
      v_changed := true;
    ELSIF v_tx.state = 'refunded' AND p_action = 'revoked' THEN
      UPDATE pipo_billing_private.apple_transactions SET
        state = 'revoked', last_seen_at = now()
        WHERE environment=p_environment AND transaction_id=p_transaction_id;
    END IF;
  ELSE
    INSERT INTO pipo_billing_private.apple_transactions (
      environment, transaction_id, original_transaction_id,
      user_id, app_account_token, product_id, benefit, state,
      proof_sha256, apple_signed_at
    ) VALUES (
      p_environment, p_transaction_id, p_original_transaction_id,
      p_user_id, p_app_account_token, p_product_id, v_catalog.benefit,
      p_action, p_proof_sha256, p_apple_signed_at
    );
    v_changed := p_action = 'purchased';
  END IF;

  INSERT INTO pipo_billing_private.apple_events(
    environment, event_id, transaction_id, user_id, product_id,
    action, proof_sha256
  ) VALUES (
    p_environment, p_event_id, p_transaction_id, p_user_id,
    p_product_id, p_action, p_proof_sha256
  );

  IF v_changed THEN
    UPDATE public.pipo_entitlements_v2 AS e SET
      permanent_personal_slots = (
        SELECT count(*)::integer
        FROM pipo_billing_private.apple_transactions t
        WHERE t.user_id=p_user_id AND t.state='purchased'
          AND t.benefit='personal_slot'
      ),
      permanent_group_slots = (
        SELECT count(*)::integer
        FROM pipo_billing_private.apple_transactions t
        WHERE t.user_id=p_user_id AND t.state='purchased'
          AND t.benefit='group_slot'
      ),
      personal_lifetime_pro = EXISTS (
        SELECT 1 FROM pipo_billing_private.apple_transactions t
        WHERE t.user_id=p_user_id AND t.state='purchased'
          AND t.benefit='personal_lifetime_pro'
      ),
      revision = e.revision + 1,
      updated_at = now()
    WHERE e.user_id=p_user_id
    RETURNING * INTO STRICT v_entitlements;
  END IF;

  RETURN QUERY SELECT p_user_id, v_entitlements.permanent_personal_slots,
    v_entitlements.permanent_group_slots,
    v_entitlements.personal_lifetime_pro, v_entitlements.revision;
END
$apply$;

REVOKE ALL ON FUNCTION pipo_billing_private.apply_verified_apple_event_v1(
  text,text,text,text,text,text,uuid,uuid,text,text,timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION pipo_billing_private.apply_verified_apple_event_v1(
  text,text,text,text,text,text,uuid,uuid,text,text,timestamptz
) TO service_role;

DO $postflight$
BEGIN
  IF has_schema_privilege('authenticated','pipo_billing_private','USAGE')
     OR has_schema_privilege('anon','pipo_billing_private','USAGE')
     OR has_table_privilege('authenticated','public.pipo_entitlements_v2','UPDATE')
     OR has_table_privilege('authenticated','public.pipo_entitlements_v2','INSERT')
     OR has_table_privilege('authenticated','public.pipo_entitlements_v2','DELETE')
     OR has_function_privilege(
       'authenticated',
       'pipo_billing_private.apply_verified_apple_event_v1(text,text,text,text,text,text,uuid,uuid,text,text,timestamptz)',
       'EXECUTE'
     )
  THEN RAISE EXCEPTION 'Pay V2 grant boundary broken'; END IF;
  IF (SELECT count(*) FROM pipo_billing_private.apple_catalog) <> 0 THEN
    RAISE EXCEPTION 'Live Apple catalog must start empty'; END IF;
END
$postflight$;

COMMIT;
-- NO Apple JWS verification, webhook, StoreKit product activation, billing
-- reconciliation, App Store Connect setup, iOS paywall or production migration.
