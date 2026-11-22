import test from "node:test";
import assert from "node:assert/strict";
import { X509Certificate } from "node:crypto";
import {
  VerificationRejected, createOfficialAppleAdapter, validateVerifiedTransaction,
  verifyDeviceTransaction, verifyAppleNotification, sha256Hex,
} from "../src/apple.mjs";
import {
  createAppleVerificationHandler, configFromEnvironment,
} from "../src/handler.mjs";

const A = "a1111111-1111-4111-8111-111111111111";
const B = "b2222222-2222-4222-8222-222222222222";
const JWS = "e30.eyJpc3MiOiJBcHBsZS1URVNULU9OTFkifQ.c2lnbmF0dXJl";
const FRESH_JWS = "e30.eyJpc3MiOiJBcHBsZS1SRUZSRVNIRUQifQ.c2lnbmF0dXJl";
const BUNDLE = "com.pipo.app";
const SKU = "qa.pipo.personal.slot";

function config(extra = {}) {
  return {
    supabaseUrl: "https://testing.supabase.co/",
    anonKey: "anon-test-only",
    serviceRoleKey: "service-role-test-only",
    bundleId: BUNDLE,
    appAppleId: 1234567890,
    allowSandbox: true,
    products: {
      Sandbox: [SKU],
      Production: [SKU],
    },
    ledgerWritesEnabled: true,
    ...extra,
  };
}
function transaction(owner=A, extra={}) {
  return {
    environment: "Sandbox",
    bundleId: BUNDLE, productId: SKU,
    transactionId: "1000111222333", originalTransactionId: "1000111222333",
    appAccountToken: owner, signedDate: Date.now(),
    ...extra,
  };
}
function fakeApple(options={}) {
  return {
    async verifyTransaction(_jws, _env) {
      if (options.rejectInner) throw Object.assign(new Error("bad signature"), { name: "VerificationException" });
      return transaction(options.owner ?? A, options.transactionExtra);
    },
    async verifyNotification(_jws, _env) {
      if (options.rejectOuter) throw Object.assign(new Error("bad signature"), { name: "VerificationException" });
      return {
        notificationType: options.notificationType || "ONE_TIME_CHARGE",
        notificationUUID: "5c064a0d-0de0-46a2-91b8-5711c64abd18",
        data: {
          environment: "Sandbox", bundleId: BUNDLE,
          signedTransactionInfo: JWS, ...options.notificationData,
        },
      };
    },
    async getLatestTransaction() {
      if (options.refreshUnavailable) throw new Error("Store API unavailable");
      return { signedTransactionInfo: FRESH_JWS };
    },
  };
}
function req(path, json, token, headers = {}) {
  return new Request("https://pipo.example" + path, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: "Bearer " + token } : {}),
      ...headers,
    },
    body: JSON.stringify(json),
  });
}
function envFetch(records) {
  return async (url, options) => {
    records.push({ url, options });
    if (url.endsWith("/auth/v1/user")) {
      const user = options.headers.authorization === "Bearer token-A"
        ? A : options.headers.authorization === "Bearer token-B" ? B : null;
      return new Response(JSON.stringify(user ? {id:user} : {error:"invalid"}), {
        status: user ? 200 : 401, headers: {"content-type":"application/json"}
      });
    }
    if (url.endsWith("/rest/v1/rpc/pipo_internal_ingest_verified_apple_event_v1")) {
      const event = JSON.parse(options.body);
      return new Response(JSON.stringify([{
        owner_id: event.p_user_id, personal_slots: 1,
        group_slots: 0, lifetime_pro: false, entitlement_revision: 1,
      }]), { status: 200, headers: {"content-type":"application/json"} });
    }
    throw new Error("Unexpected remote endpoint");
  };
}
function handler(options={}) {
  const calls = [];
  const app = createAppleVerificationHandler({
    config: config(options.config),
    appleFactory: async () => fakeApple(options.apple),
    fetchImpl: envFetch(calls),
  });
  return { app, calls };
}

test("official verifier requires native X509 APIs and rejects missing trusted Apple roots", async () => {
  assert.equal(typeof X509Certificate.prototype.verify, "function");
  assert.equal(typeof X509Certificate.prototype.checkIssued, "function");
  await assert.rejects(
    createOfficialAppleAdapter("Sandbox", config({
      appleRootCertificatesJSON: "[]",
    })),
    /trusted Apple PKI root certificates/);
});

test("unknown route and HTTP method fail without any Apple verification", async () => {
  const { app, calls } = handler();
  const r = await app(req("/does-not-exist", {signedPayload:JWS}));
  assert.equal(r.status,404);
  const get = await app(new Request("https://pipo.example/v1/verify-transaction"));
  assert.equal(get.status,405);
  assert.equal(calls.length,0);
});

test("buyer purchase needs a VERIFIED auth session, not caller-provided user_id", async () => {
  const { app, calls } = handler();
  let r = await app(req("/v1/verify-transaction", {
    environment:"Sandbox",signedTransactionInfo:JWS,user_id:A,
  }));
  assert.equal(r.status,401);
  r = await app(req("/v1/verify-transaction", {
    environment:"Sandbox",signedTransactionInfo:JWS,user_id:A,
  },"unknown-token"));
  assert.equal(r.status,401);
  assert.equal(calls.filter(x => x.url.includes("/rest/v1/")).length,0);
});

test("cross-account Apple appAccountToken mismatch blocks purchase", async () => {
  const { app, calls } = handler({apple:{owner:B}});
  const r = await app(req("/v1/verify-transaction", {
    environment:"Sandbox",signedTransactionInfo:JWS,user_id:A,
  },"token-A"));
  assert.equal(r.status,409);
  assert.equal(calls.filter(x=>x.url.includes("/rest/v1/")).length,0);
});

test("malformed Apple JWS and official signature exception both fail closed", async () => {
  const { app, calls }=handler();
  let r=await app(req("/v1/verify-transaction",{
    environment:"Sandbox",signedTransactionInfo:"e30.ew.bad"
  },"token-A"));
  assert.equal(r.status,400);
  const broken=handler({apple:{rejectInner:true}});
  r=await broken.app(req("/v1/verify-transaction",{
    environment:"Sandbox",signedTransactionInfo:JWS,
  },"token-A"));
  assert.equal(r.status,422);
  assert.equal(calls.filter(x=>x.url.includes("/rest/v1/")).length,0);
  assert.equal(broken.calls.filter(x=>x.url.includes("/rest/v1/")).length,0);
});

test("device receipt must refresh its current status via Apple's API", async () => {
  const { app, calls }=handler({apple:{refreshUnavailable:true}});
  const r=await app(req("/v1/verify-transaction",{
    environment:"Sandbox",signedTransactionInfo:JWS
  },"token-A"));
  assert.equal(r.status,503);
  assert.equal(calls.filter(x=>x.url.includes("/rest/v1/")).length,0);
});

test("verified Apple payload metadata and allowed product/environment enforced", () => {
  const valid=validateVerifiedTransaction(transaction(),config(),"Sandbox");
  assert.equal(valid.appAccountToken,A);
  for (const mutation of [
    {bundleId:"com.another.app"},
    {environment:"Production"},
    {transactionId:"some-fake-id"},
    {productId:"unsupported.slot"},
    {appAccountToken:B.slice(0,6)},
    {signedDate:Date.now()+3600000},
    {signedDate:null},
  ]) {
    assert.throws(()=>
      validateVerifiedTransaction(transaction(A,mutation),config(),"Sandbox"),
      VerificationRejected);
  }
});

test("purchase success passes only server-refreshed verified JWS metadata to privileged RPC",async()=>{
  const {app,calls}=handler();
  const r=await app(req("/v1/verify-transaction", {
    environment:"Sandbox",signedTransactionInfo:JWS,user_id:B,
  },"token-A"));
  assert.equal(r.status,200);
  const rpc=calls.find(x=>x.url.endsWith("pipo_internal_ingest_verified_apple_event_v1"));
  assert.ok(rpc);
  assert.equal(rpc.options.headers.authorization,"Bearer service-role-test-only");
  const event=JSON.parse(rpc.options.body);
  assert.equal(event.p_user_id,A);
  assert.equal(event.p_app_account_token,A);
  assert.equal(event.p_action,"purchased");
  assert.equal(event.p_proof_sha256,sha256Hex(FRESH_JWS));
  assert.match(event.p_event_id,/^device\.[a-f0-9]{64}$/);
  assert.equal(event.p_product_id,SKU);
});

test("purchase readback with refunded Apple status must never mint a slot", async()=>{
  const {app,calls}=handler({apple:{transactionExtra:{revocationDate:Date.now()}}});
  const r=await app(req("/v1/verify-transaction",{
    environment:"Sandbox",signedTransactionInfo:JWS
  },"token-A"));
  assert.equal(r.status,200);
  const rpc=calls.find(x=>x.url.includes("/rest/v1/rpc/"));
  assert.equal(JSON.parse(rpc.options.body).p_action,"refunded");
});

test("disabled ledger accepts no purchasable credit even after signed verification",async()=>{
  const {app,calls}=handler({config:{ledgerWritesEnabled:false}});
  const r=await app(req("/v1/verify-transaction",{
    environment:"Sandbox",signedTransactionInfo:JWS
  },"token-A"));
  assert.equal(r.status,503);
  assert.equal(calls.filter(x=>x.url.includes("/rest/v1/")).length,0);
});

test("Apple notification must verify both outer and inner signed JWS", async()=>{
  const failOuter=handler({apple:{rejectOuter:true}});
  let r=await failOuter.app(req("/v1/notifications/sandbox",{
    signedPayload:JWS,
  }));
  assert.equal(r.status,422);
  assert.equal(failOuter.calls.length,0);
  const failInner=handler({apple:{rejectInner:true}});
  r=await failInner.app(req("/v1/notifications/sandbox",{
    signedPayload:JWS,
  }));
  assert.equal(r.status,422);
  assert.equal(failInner.calls.length,0);
});

test("verified Apple refund notification needs no user JWT but stays bound to signed account",async()=>{
  const {app,calls}=handler({apple:{notificationType:"REFUND"}});
  const r=await app(req("/v1/notifications/sandbox",{signedPayload:JWS}));
  assert.equal(r.status,200);
  assert.equal(calls.filter(x=>x.url.includes("/auth/v1/user")).length,0);
  const rpc=calls.find(x=>x.url.includes("/rest/v1/rpc/"));
  const event=JSON.parse(rpc.options.body);
  assert.equal(event.p_user_id,A);
  assert.equal(event.p_action,"refunded");
  assert.match(event.p_event_id,/^notification\.[0-9a-f-]{36}$/);
});

test("unknown but authenticated Apple notification is never interpreted as a purchase",async()=>{
  const {app,calls}=handler({apple:{notificationType:"TEST"}});
  const r=await app(req("/v1/notifications/sandbox",{signedPayload:JWS}));
  assert.equal(r.status,200);
  assert.deepEqual(await r.json(),{received:true,applied:false});
  assert.equal(calls.length,0);
});

test("Apple notification mismatched bundle and environment are refused",async()=>{
  for(const bad of [{bundleId:"com.other.app"},{environment:"Production"}]){
    const {app,calls}=handler({apple:{notificationData:bad}});
    const r=await app(req("/v1/notifications/sandbox",{signedPayload:JWS}));
    assert.equal(r.status,422);
    assert.equal(calls.length,0);
  }
});

test("signed purchase from Sandbox is denied when that environment is disabled",async()=>{
  const {app,calls}=handler({config:{allowSandbox:false}});
  const r=await app(req("/v1/verify-transaction",{
    environment:"Sandbox",signedTransactionInfo:JWS
  },"token-A"));
  assert.equal(r.status,422);
  assert.equal(calls.filter(x=>x.url.includes("/rest/v1/")).length,0);
});

test("missing service-role secret denies ledger delivery even when write flag enabled",async()=>{
  const {app,calls}=handler({config:{serviceRoleKey:null}});
  const r=await app(req("/v1/verify-transaction",{
    environment:"Sandbox",signedTransactionInfo:JWS,
  },"token-A"));
  assert.equal(r.status,503);
  assert.equal(calls.filter(x=>x.url.includes("/rest/v1/")).length,0);
});

test("notification refusal is retryable when ledger is disabled, preventing lost refunds",async()=>{
  const {app,calls}=handler({config:{ledgerWritesEnabled:false},apple:{notificationType:"REFUND"}});
  const r=await app(req("/v1/notifications/sandbox",{signedPayload:JWS}));
  assert.equal(r.status,503);
  assert.equal(calls.length,0);
});

test("environment parser defaults to zero SKUs, grants off and sandbox off",()=>{
  const cfg=configFromEnvironment({SUPABASE_URL:"https://demo.supabase.co",SUPABASE_ANON_KEY:"anon"});
  assert.deepEqual(cfg.products,{Sandbox:[],Production:[]});
  assert.equal(cfg.ledgerWritesEnabled,false);
  assert.equal(cfg.allowSandbox,false);
  assert.throws(()=>configFromEnvironment({PIPO_APPLE_APPROVED_SKUS_JSON:'{"Sandbox":"x"}'}));
});
