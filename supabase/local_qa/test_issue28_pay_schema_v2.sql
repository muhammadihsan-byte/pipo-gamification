-- #28 / #87 · disposable PostgreSQL ONLY, no production Auth/user/billing.
-- Synthetic Apple proof hashes are NOT signature verification evidence.
-- Run after local_qa/bootstrap.sql + issue28_pay_schema_v2_REVIEW_ONLY.sql.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(id) VALUES
 ('a1000000-0000-4000-8000-000000000001'),
 ('b2000000-0000-4000-8000-000000000002');

-- No production products are seeded by the foundation. Disposable test
-- alone enables three synthetic SKU mappings, and one disabled product.
INSERT INTO pipo_billing_private.apple_catalog
 (environment,product_id,bundle_id,benefit,enabled)
VALUES
 ('Sandbox','qa.pipo.personal.slot','com.pipo.app','personal_slot',true),
 ('Sandbox','qa.pipo.group.slot','com.pipo.app','group_slot',true),
 ('Sandbox','qa.pipo.personal.lifetime','com.pipo.app','personal_lifetime_pro',true),
 ('Production','qa.pipo.personal.slot','com.pipo.app','personal_slot',false);

DO $initial_acl$
BEGIN
 IF has_table_privilege('authenticated','public.pipo_entitlements_v2','INSERT')
    OR has_table_privilege('authenticated','public.pipo_entitlements_v2','UPDATE')
    OR has_table_privilege('authenticated','public.pipo_entitlements_v2','DELETE')
    OR has_table_privilege('anon','public.pipo_entitlements_v2','SELECT')
    OR has_schema_privilege('authenticated','pipo_billing_private','USAGE')
    OR has_function_privilege('authenticated',
      'pipo_billing_private.apply_verified_apple_event_v1(text,text,text,text,text,text,uuid,uuid,text,text,timestamptz)',
      'EXECUTE')
    OR has_table_privilege('authenticated','public.user_profiles','UPDATE')
 THEN RAISE EXCEPTION 'FAIL: untrusted client can mutate entitlements'; END IF;
END
$initial_acl$;

-- Simulated server call via service_role; SQL itself never validates JWS.
SET LOCAL ROLE service_role;
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.a1','1001','1001','qa.pipo.personal.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'purchased',repeat('a',64),now());

DO $initial_grant$
DECLARE e public.pipo_entitlements_v2%ROWTYPE;
BEGIN
 SELECT * INTO e FROM public.pipo_entitlements_v2
   WHERE user_id='a1000000-0000-4000-8000-000000000001';
 IF e.permanent_personal_slots <> 1 OR e.permanent_group_slots <> 0
    OR e.personal_lifetime_pro OR e.revision <> 1
 THEN RAISE EXCEPTION 'FAIL: first personal slot not granted'; END IF;
END
$initial_grant$;

-- Exact same event and different notification for same transaction:
-- both are idempotent (no double credit), even after relaunch/retries.
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.a1','1001','1001','qa.pipo.personal.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'purchased',repeat('a',64),now());
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.a1-second','1001','1001','qa.pipo.personal.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'purchased',repeat('b',64),now());

SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.group','2001','2001','qa.pipo.group.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'purchased',repeat('c',64),now());
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.lifetime','3001','3001','qa.pipo.personal.lifetime','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'purchased',repeat('d',64),now());
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.b1','4001','4001','qa.pipo.personal.slot','com.pipo.app',
 'b2000000-0000-4000-8000-000000000002',
 'b2000000-0000-4000-8000-000000000002',
 'purchased',repeat('e',64),now());

DO $verify_balances$
DECLARE a public.pipo_entitlements_v2%ROWTYPE;
        b public.pipo_entitlements_v2%ROWTYPE;
BEGIN
 SELECT * INTO a FROM public.pipo_entitlements_v2
   WHERE user_id='a1000000-0000-4000-8000-000000000001';
 SELECT * INTO b FROM public.pipo_entitlements_v2
   WHERE user_id='b2000000-0000-4000-8000-000000000002';
 IF a.permanent_personal_slots<>1 OR a.permanent_group_slots<>1
    OR NOT a.personal_lifetime_pro OR a.revision<>3
    OR b.permanent_personal_slots<>1 OR b.permanent_group_slots<>0
    OR b.personal_lifetime_pro OR b.revision<>1
 THEN RAISE EXCEPTION 'FAIL: wrong product category or double grant'; END IF;
END
$verify_balances$;

DO $reject_forged$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN
  PERFORM * FROM pipo_billing_private.apply_verified_apple_event_v1(
   'Sandbox','qa.event.a1','1001','1001','qa.pipo.personal.slot','com.pipo.app',
   'a1000000-0000-4000-8000-000000000001',
   'a1000000-0000-4000-8000-000000000001',
   'purchased',repeat('f',64),now());
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: mutated duplicate event accepted'; END IF;

 denied:=false;
 BEGIN
  PERFORM * FROM pipo_billing_private.apply_verified_apple_event_v1(
   'Sandbox','qa.event.cross-owner','1001','1001','qa.pipo.personal.slot','com.pipo.app',
   'b2000000-0000-4000-8000-000000000002',
   'b2000000-0000-4000-8000-000000000002',
   'purchased',repeat('f',64),now());
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: cross-account Apple replay accepted'; END IF;

 denied:=false;
 BEGIN
  PERFORM * FROM pipo_billing_private.apply_verified_apple_event_v1(
   'Sandbox','qa.event.bad-token','5001','5001','qa.pipo.group.slot','com.pipo.app',
   'a1000000-0000-4000-8000-000000000001',
   'b2000000-0000-4000-8000-000000000002',
   'purchased',repeat('f',64),now());
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: mismatched appAccountToken accepted'; END IF;

 denied:=false;
 BEGIN
  PERFORM * FROM pipo_billing_private.apply_verified_apple_event_v1(
   'Production','qa.event.prod','6001','6001','qa.pipo.personal.slot','com.pipo.app',
   'a1000000-0000-4000-8000-000000000001',
   'a1000000-0000-4000-8000-000000000001',
   'purchased',repeat('f',64),now());
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: disabled production SKU accepted'; END IF;

 denied:=false;
 BEGIN
  PERFORM * FROM pipo_billing_private.apply_verified_apple_event_v1(
   'Sandbox','qa.event.bundle','7001','7001','qa.pipo.personal.slot','com.someone.else',
   'a1000000-0000-4000-8000-000000000001',
   'a1000000-0000-4000-8000-000000000001',
   'purchased',repeat('f',64),now());
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: wrong bundle accepted'; END IF;
END
$reject_forged$;

-- Refund before purchase produces a terminal transaction tombstone.
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.refund-first','9001','9001','qa.pipo.personal.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'refunded',repeat('1',64),now());
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.purchase-late','9001','9001','qa.pipo.personal.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'purchased',repeat('2',64),now());

SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.refund-personal','1001','1001','qa.pipo.personal.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'refunded',repeat('3',64),now());
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.purchase-again','1001','1001','qa.pipo.personal.slot','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'purchased',repeat('4',64),now());
SELECT * FROM pipo_billing_private.apply_verified_apple_event_v1(
 'Sandbox','qa.event.revoke-pro','3001','3001','qa.pipo.personal.lifetime','com.pipo.app',
 'a1000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001',
 'revoked',repeat('5',64),now());

DO $refund_assert$
DECLARE a public.pipo_entitlements_v2%ROWTYPE;
BEGIN
 SELECT * INTO a FROM public.pipo_entitlements_v2
   WHERE user_id='a1000000-0000-4000-8000-000000000001';
 IF a.permanent_personal_slots <> 0 OR a.permanent_group_slots <> 1
    OR a.personal_lifetime_pro OR a.revision <> 5
 THEN RAISE EXCEPTION 'FAIL: tombstone/revocation/double-credit safety failed'; END IF;
 IF (SELECT state FROM pipo_billing_private.apple_transactions
    WHERE environment='Sandbox' AND transaction_id='9001') <> 'refunded'
 THEN RAISE EXCEPTION 'FAIL: refund-before-purchase was overwritten'; END IF;
END
$refund_assert$;
RESET ROLE;

-- Sign-in A/B read: auth.uid comes from session, not an arbitrary ID arg.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',true);
DO $account_a$
DECLARE own_count integer; snap record; denied boolean:=false;
BEGIN
 SELECT count(*) INTO own_count FROM public.pipo_entitlements_v2;
 IF own_count <> 1 THEN RAISE EXCEPTION 'FAIL: A can read B snapshot'; END IF;
 SELECT * INTO snap FROM public.pipo_read_entitlements_v2();
 IF snap.user_id <> 'a1000000-0000-4000-8000-000000000001'::uuid
    OR snap.free_personal_slots <> 2 OR snap.free_group_creator_slots <> 1
    OR snap.permanent_personal_slots <> 0 OR snap.permanent_group_slots <> 1
    OR snap.personal_lifetime_pro OR snap.revision <> 5
 THEN RAISE EXCEPTION 'FAIL: invalid A authenticated DTO'; END IF;
 BEGIN
  UPDATE public.pipo_entitlements_v2 SET permanent_personal_slots=999;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: client can forge credits'; END IF;
 denied:=false;
 BEGIN
  PERFORM * FROM pipo_billing_private.apply_verified_apple_event_v1(
   'Sandbox','qa.unauth-event','1234','1234','qa.pipo.personal.slot','com.pipo.app',
   'a1000000-0000-4000-8000-000000000001',
   'a1000000-0000-4000-8000-000000000001',
   'purchased',repeat('9',64),now());
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: client can grant via private SQL function'; END IF;
END
$account_a$;

SELECT set_config('request.jwt.claim.sub',
 'b2000000-0000-4000-8000-000000000002',true);
DO $account_b$
DECLARE snap record; own_count integer;
BEGIN
 SELECT count(*) INTO own_count FROM public.pipo_entitlements_v2;
 SELECT * INTO snap FROM public.pipo_read_entitlements_v2();
 IF own_count <> 1 OR snap.user_id <> 'b2000000-0000-4000-8000-000000000002'::uuid
    OR snap.permanent_personal_slots <> 1 OR snap.permanent_group_slots <> 0
    OR snap.personal_lifetime_pro OR snap.revision <> 1
 THEN RAISE EXCEPTION 'FAIL: B sees A entitlement or gets false Pro'; END IF;
END
$account_b$;
RESET ROLE;

-- Whole-account deletion continues to clear Pipo account-owned ledger and
-- snapshot. Apple original-transaction anti-reclaim policy on deletion is a
-- separate product/privacy decision and is NOT solved by this prototype.
DELETE FROM auth.users WHERE id='a1000000-0000-4000-8000-000000000001';
DO $erase$
BEGIN
 IF EXISTS(SELECT 1 FROM public.pipo_entitlements_v2
           WHERE user_id='a1000000-0000-4000-8000-000000000001')
    OR EXISTS(SELECT 1 FROM pipo_billing_private.apple_transactions
           WHERE user_id='a1000000-0000-4000-8000-000000000001')
    OR EXISTS(SELECT 1 FROM pipo_billing_private.apple_events
           WHERE user_id='a1000000-0000-4000-8000-000000000001')
 THEN RAISE EXCEPTION 'FAIL: account deletion did not cascade to paid state'; END IF;
END
$erase$;

ROLLBACK;
\echo 'PASS: pay V2 local test — owner A/B, exact-once grants, sku mapping, terminal refunds, no client grants, erasure'
