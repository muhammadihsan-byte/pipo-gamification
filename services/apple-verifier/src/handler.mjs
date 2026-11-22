/**
 * Review-only HTTP application for trusted Node verification service.
 * No deployment manifest, no StoreKit checkout, and NO ledger write by
 * default. Production use requires separate owner approval and Apple QA.
 */
import { VerificationRejected, createOfficialAppleAdapter,
  verifyDeviceTransaction, verifyAppleNotification } from "./apple.mjs";

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

function result(status, fields) {
  return new Response(JSON.stringify(fields), { status, headers: JSON_HEADERS });
}

function safeJsonParse(value) {
  try { return JSON.parse(value); } catch {
    throw new VerificationRejected("Invalid JSON", 400);
  }
}

async function readJsonLimited(req) {
  if (req.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase()
      !== "application/json") {
    throw new VerificationRejected("Expected JSON request", 415);
  }
  if (!req.body) throw new VerificationRejected("Missing body", 400);
  const reader = req.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > 65536) throw new VerificationRejected("Request too large", 413);
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(total);
  let index = 0;
  for (const chunk of chunks) { bytes.set(chunk, index); index += chunk.byteLength; }
  const parsed = safeJsonParse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new VerificationRejected("Expected JSON object", 400);
  }
  return parsed;
}

function publicOrigin(origin, allowLoopbackForTests = false) {
  let u;
  try { u = new URL(origin); } catch { throw new Error("Invalid Supabase origin"); }
  const local = allowLoopbackForTests && u.protocol === "http:"
    && ["localhost", "127.0.0.1", "[::1]"].includes(u.hostname);
  if (!(u.protocol === "https:" || local)
      || u.username || u.password || u.search || u.hash
      || u.pathname !== "/") {
    throw new Error("Only trusted Supabase origin allowed");
  }
  return u.origin;
}

function parseProductsJSON(value) {
  if (!value) return { Sandbox: [], Production: [] };
  let parsed;
  try { parsed = JSON.parse(value); } catch { throw new Error("Invalid SKU allowlist"); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)
      || Object.keys(parsed).some((k) => !["Sandbox","Production"].includes(k))) {
    throw new Error("SKU allowlist must be environment-scoped");
  }
  for (const env of ["Sandbox", "Production"]) {
    const entries = parsed[env] ?? [];
    if (!Array.isArray(entries) || entries.length > 12
        || entries.some((p) => typeof p !== "string"
          || !/^[A-Za-z0-9._-]{5,160}$/.test(p))
        || new Set(entries).size !== entries.length) {
      throw new Error("Invalid Apple SKU allowlist");
    }
  }
  return { Sandbox: parsed.Sandbox ?? [], Production: parsed.Production ?? [] };
}

export function configFromEnvironment(env = process.env) {
  return {
    supabaseUrl: env.SUPABASE_URL,
    anonKey: env.SUPABASE_ANON_KEY,
    serviceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY,
    bundleId: env.PIPO_APP_BUNDLE_ID || "com.pipo.app",
    appAppleId: Number(env.PIPO_APP_APPLE_ID),
    products: parseProductsJSON(env.PIPO_APPLE_APPROVED_SKUS_JSON),
    allowSandbox: env.PIPO_ALLOW_APPLE_SANDBOX === "true",
    appleRootCertificatesJSON: env.PIPO_APPLE_ROOTS_DER_JSON,
    appleServerApi: {
      issuerId: env.PIPO_APPLE_API_ISSUER_ID,
      keyId: env.PIPO_APPLE_API_KEY_ID,
      privateKey: env.PIPO_APPLE_API_PRIVATE_KEY_P8?.replace(/\\n/g, "\n"),
    },
    // Explicit independent production/security approval required.
    ledgerWritesEnabled: env.PIPO_APPLE_LEDGER_WRITES_ENABLED === "true",
  };
}

function requiredKeys(config, { needLedger = false } = {}) {
  if (!config.supabaseUrl || !config.anonKey || (needLedger && !config.serviceRoleKey)) {
    throw new VerificationRejected("Billing backend is not configured", 503);
  }
}

async function resolvedUser(request, config, fetchImpl) {
  requiredKeys(config);
  const match = /^Bearer ([^\s]+)$/i.exec(request.headers.get("authorization") ?? "");
  if (!match) throw new VerificationRejected("Authenticated session required", 401);
  const origin = publicOrigin(config.supabaseUrl, config.localTestOnly === true);
  const res = await fetchImpl(origin + "/auth/v1/user", {
    method: "GET",
    headers: { apikey: config.anonKey, authorization: "Bearer " + match[1] },
    redirect: "error",
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new VerificationRejected("Session no longer valid", 401);
  const user = await res.json();
  if (typeof user?.id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(user.id)) {
    throw new VerificationRejected("Account identity not verified", 401);
  }
  return user.id.toLowerCase();
}

async function persistTrustedEvent(event, config, fetchImpl) {
  requiredKeys(config, { needLedger: true });
  if (!config.ledgerWritesEnabled) {
    throw new VerificationRejected("Billing ledger is disabled", 503);
  }
  const origin = publicOrigin(config.supabaseUrl, config.localTestOnly === true);
  const res = await fetchImpl(
    origin + "/rest/v1/rpc/pipo_internal_ingest_verified_apple_event_v1", {
    method: "POST",
    headers: {
      apikey: config.serviceRoleKey,
      authorization: "Bearer " + config.serviceRoleKey,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(event),
    redirect: "error",
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) {
    // In a refund flow, fail/retry rather than claim it was processed.
    throw new VerificationRejected("Server billing ledger did not confirm delivery", 503);
  }
  const rows = await res.json();
  if (!Array.isArray(rows) || rows.length !== 1
      || rows[0]?.owner_id !== event.p_user_id
      || !Number.isSafeInteger(rows[0]?.entitlement_revision)) {
    // PostgREST serializes bigint as JSON number up to 2^53; if it becomes a
    // JSON string, adapt this only after explicit integration contract QA.
    throw new VerificationRejected("Server billing acknowledgement invalid", 503);
  }
  return { recorded: true };
}

export function createAppleVerificationHandler({
  config,
  appleFactory = createOfficialAppleAdapter,
  fetchImpl = fetch,
} = {}) {
  if (!config) throw new Error("Explicit server configuration required");
  return async function handle(req) {
    if (req.method !== "POST") return result(405, { error: "method_not_allowed" });
    const path = new URL(req.url).pathname;
    const devicePath = path === "/v1/verify-transaction";
    const m = /^\/v1\/notifications\/(sandbox|production)$/.exec(path);
    if (!devicePath && !m) return result(404, { error: "not_found" });
    try {
      const payload = await readJsonLimited(req);
      let event;
      if (devicePath) {
        const account = await resolvedUser(req, config, fetchImpl);
        const env = payload.environment;
        if (!["Sandbox","Production"].includes(env)) {
          throw new VerificationRejected("Invalid App Store environment", 400);
        }
        const apple = await appleFactory(env, config);
        event = await verifyDeviceTransaction({
          signedTransactionInfo: payload.signedTransactionInfo,
          environment: env,
          authenticatedOwner: account,
          apple, config,
        });
      } else {
        const env = m[1] === "sandbox" ? "Sandbox" : "Production";
        const apple = await appleFactory(env, config);
        const notification = await verifyAppleNotification({
          signedPayload: payload.signedPayload, environment: env, apple, config,
        });
        if (!notification.handled) {
          return result(200, { received: true, applied: false });
        }
        event = notification.event;
      }
      await persistTrustedEvent(event, config, fetchImpl);
      return result(200, { verified: true, recorded: true });
    } catch (error) {
      if (error instanceof VerificationRejected) {
        return result(error.status, { error: "apple_verification_rejected" });
      }
      // Apple official library throws VerificationException for bad signatures.
      // Do not fallback to JSON decoding / unchecked claim extraction.
      if (error?.name === "VerificationException") {
        return result(422, { error: "apple_signature_invalid" });
      }
      // Unknown runtime/cert/transport errors are retryable but fail CLOSED.
      // Never print signed purchase payloads, secrets or stack traces.
      return result(503, { error: "apple_verification_unavailable" });
    }
  };
}
