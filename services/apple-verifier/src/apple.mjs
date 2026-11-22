/**
 * Pipo Apple Purchase Verification Foundation — review only.
 *
 * NEVER interpret an unverified JWS body (atob / JSON.parse) as a purchase.
 * Apple's official SignedDataVerifier validates the certificate chain, JWS
 * signature, bundle and environment. This module is NODE.js ONLY: as of
 * 2026-11 Supabase Edge Runtime has a reported X509Certificate compatibility
 * failure (supabase/edge-runtime#761).
 */
import { createHash, X509Certificate } from "node:crypto";
import { Buffer } from "node:buffer";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APPLE_TRANSACTION_ID = /^[0-9]{1,80}$/;
const PRODUCT_ID = /^[A-Za-z0-9._-]{5,160}$/;
const ENVIRONMENTS = new Set(["Sandbox", "Production"]);
const ACTIONS = new Set(["purchased", "refunded", "revoked"]);
const NOTIFICATION_ACTIONS = {
  ONE_TIME_CHARGE: "purchased",
  REFUND: "refunded",
  REVOKE: "revoked",
};

export class VerificationRejected extends Error {
  constructor(message = "Signed purchase evidence was rejected", status = 422) {
    super(message);
    this.status = status;
    this.name = "VerificationRejected";
  }
}

export function normalUuid(candidate) {
  if (typeof candidate !== "string" || !UUID.test(candidate)) {
    throw new VerificationRejected("Missing verified app-account binding");
  }
  return candidate.toLowerCase();
}

export function sha256Hex(value) {
  return createHash("sha256").update(value).digest("hex");
}

function requireNonEmptyJws(jws) {
  if (typeof jws !== "string" || jws.length > 32000
      || jws.length < 20 || jws.split(".").length !== 3
      || !/^[A-Za-z0-9_.-]+$/.test(jws)) {
    throw new VerificationRejected("Invalid signed Apple evidence format", 400);
  }
  return jws;
}

export function validateVerifiedTransaction(tx, config, environment) {
  if (!ENVIRONMENTS.has(environment)
      || !tx || typeof tx !== "object"
      || tx.environment !== environment
      || tx.bundleId !== config.bundleId
      || typeof tx.transactionId !== "string"
      || !APPLE_TRANSACTION_ID.test(tx.transactionId)
      || typeof tx.originalTransactionId !== "string"
      || !APPLE_TRANSACTION_ID.test(tx.originalTransactionId)
      || typeof tx.productId !== "string"
      || !PRODUCT_ID.test(tx.productId)
      || !config.products?.[environment]?.includes(tx.productId)
      || !Number.isSafeInteger(tx.signedDate)
      || tx.signedDate < 1262304000000
      || tx.signedDate > Date.now() + 5 * 60 * 1000) {
    throw new VerificationRejected("Verified Apple payload does not match Pipo");
  }
  const account = normalUuid(tx.appAccountToken);
  return {
    environment,
    transactionId: tx.transactionId,
    originalTransactionId: tx.originalTransactionId,
    productId: tx.productId,
    bundleId: config.bundleId,
    appAccountToken: account,
    signedAt: new Date(tx.signedDate).toISOString(),
    refunded: typeof tx.revocationDate === "number" && tx.revocationDate > 0,
  };
}

function checkSameTransaction(initial, current) {
  for (const key of [
    "environment", "transactionId", "originalTransactionId",
    "productId", "bundleId", "appAccountToken",
  ]) {
    if (initial[key] !== current[key]) {
      throw new VerificationRejected("Apple status refresh changed the purchase identity");
    }
  }
}

export async function verifyDeviceTransaction({
  signedTransactionInfo, environment, authenticatedOwner, apple, config,
}) {
  requireNonEmptyJws(signedTransactionInfo);
  const owner = normalUuid(authenticatedOwner);
  if (!ENVIRONMENTS.has(environment)
      || (environment === "Sandbox" && !config.allowSandbox)) {
    throw new VerificationRejected("App Store environment not permitted");
  }
  // Verify device JWS signature BEFORE making a transaction-ID API request.
  const initial = validateVerifiedTransaction(
    await apple.verifyTransaction(signedTransactionInfo, environment),
    config, environment,
  );
  if (initial.appAccountToken !== owner) {
    throw new VerificationRejected("Apple purchase belongs to another Pipo account", 409);
  }

  // A once-valid device JWS may have been refunded. Fetch Apple's CURRENT
  // signed transaction, verify THAT JWS too, and check owner/transaction/SKU.
  const refreshed = await apple.getLatestTransaction(initial.transactionId, environment);
  if (!refreshed || typeof refreshed.signedTransactionInfo !== "string") {
    throw new VerificationRejected("Apple status refresh unavailable", 503);
  }
  requireNonEmptyJws(refreshed.signedTransactionInfo);
  const current = validateVerifiedTransaction(
    await apple.verifyTransaction(refreshed.signedTransactionInfo, environment),
    config, environment,
  );
  checkSameTransaction(initial, current);
  return toTrustedEvent(current,
    "device." + sha256Hex(refreshed.signedTransactionInfo),
    current.refunded ? "refunded" : "purchased",
    sha256Hex(refreshed.signedTransactionInfo));
}

export async function verifyAppleNotification({
  signedPayload, environment, apple, config,
}) {
  requireNonEmptyJws(signedPayload);
  if (!ENVIRONMENTS.has(environment)
      || (environment === "Sandbox" && !config.allowSandbox)) {
    throw new VerificationRejected("App Store environment not permitted");
  }
  // Verify OUTER Apple JWS using Apple's root X.509 chain.
  const decoded = await apple.verifyNotification(signedPayload, environment);
  if (!decoded || typeof decoded !== "object") {
    throw new VerificationRejected("Invalid Apple notification");
  }
  const { notificationType, notificationUUID, data } = decoded;
  if (data?.environment && data.environment !== environment) {
    throw new VerificationRejected("Notification environment mismatch");
  }
  if (data?.bundleId && data.bundleId !== config.bundleId) {
    throw new VerificationRejected("Notification bundle mismatch");
  }
  if (environment === "Production"
      && data?.appAppleId !== config.appAppleId) {
    throw new VerificationRejected("Notification appAppleId mismatch");
  }
  const action = NOTIFICATION_ACTIONS[notificationType];
  if (!action) {
    // Test, consumption request, other subscription events: acknowledged
    // only AFTER verified outer JWS, and never credited/revoked accidentally.
    return { handled: false, notificationType };
  }
  if (typeof notificationUUID !== "string"
      || notificationUUID.length < 8 || notificationUUID.length > 100
      || !/^[A-Za-z0-9-]+$/.test(notificationUUID)
      || typeof data?.signedTransactionInfo !== "string") {
    throw new VerificationRejected("Relevant Apple event missing signed transaction");
  }
  const jws = requireNonEmptyJws(data.signedTransactionInfo);
  // A valid outer notification does not mean the INNER JWS can be trusted.
  const transaction = validateVerifiedTransaction(
    await apple.verifyTransaction(jws, environment), config, environment);
  if (action === "purchased" && transaction.refunded) {
    throw new VerificationRejected("Cannot grant a revoked Apple transaction");
  }
  return {
    handled: true,
    event: toTrustedEvent(transaction,
      "notification." + notificationUUID, action, sha256Hex(jws)),
  };
}

function toTrustedEvent(tx, eventId, action, hash) {
  if (!ACTIONS.has(action)) throw new VerificationRejected("Invalid verified action");
  return Object.freeze({
    p_environment: tx.environment,
    p_event_id: eventId,
    p_transaction_id: tx.transactionId,
    p_original_transaction_id: tx.originalTransactionId,
    p_product_id: tx.productId,
    p_bundle_id: tx.bundleId,
    // Strictly from the Apple-signed appAccountToken, never request JSON.
    p_user_id: tx.appAccountToken,
    p_app_account_token: tx.appAccountToken,
    p_action: action,
    p_proof_sha256: hash,
    p_apple_signed_at: tx.signedAt,
  });
}

function parseRootCertificates(value) {
  if (typeof value !== "string" || value.length > 70000) {
    throw new Error("Apple roots configuration missing");
  }
  let roots;
  try { roots = JSON.parse(value); } catch { throw new Error("Invalid Apple roots JSON"); }
  if (!Array.isArray(roots) || roots.length < 1 || roots.length > 8) {
    throw new Error("Missing trusted Apple PKI root certificates");
  }
  return roots.map((entry) => {
    if (typeof entry !== "string" || !/^[A-Za-z0-9+/=\s]{300,20000}$/.test(entry)) {
      throw new Error("Invalid Apple root certificate input");
    }
    const der = Buffer.from(entry.replace(/\s/g, ""), "base64");
    const root = new X509Certificate(der);
    if (!root.ca || root.subject !== root.issuer
        || !root.verify(root.publicKey)
        || !/Apple Root CA/i.test(root.subject)) {
      throw new Error("Configured root is not an Apple self-signed root CA");
    }
    return der;
  });
}

/**
 * Actual signature-verifying adapter. Never use these methods on Supabase
 * Edge until an exact-hosted-runtime X509Certificate integration test passes.
 * Accepts trusted deployment secrets, NOT request-controlled inputs.
 */
export async function createOfficialAppleAdapter(environment, configuration) {
  if (!ENVIRONMENTS.has(environment)) throw new Error("Invalid Apple environment");
  if (environment === "Sandbox" && !configuration.allowSandbox) {
    throw new Error("Sandbox not enabled");
  }
  if (environment === "Production" && !Number.isSafeInteger(configuration.appAppleId)) {
    throw new Error("Production appAppleId required");
  }
  // Node native X.509 methods are necessary for Apple's official verifier.
  if (typeof X509Certificate.prototype.verify !== "function"
      || typeof X509Certificate.prototype.checkIssued !== "function") {
    throw new Error("Node native X509Certificate API unavailable; fail closed");
  }
  const rootCertificates = parseRootCertificates(configuration.appleRootCertificatesJSON);
  const appleModule = await import("@apple/app-store-server-library");
  const api = appleModule.default ?? appleModule;
  const appEnv = environment === "Sandbox" ? api.Environment.SANDBOX
    : api.Environment.PRODUCTION;
  const verifier = new api.SignedDataVerifier(
    rootCertificates, true, appEnv, configuration.bundleId,
    environment === "Production" ? configuration.appAppleId : undefined,
  );
  const key = configuration.appleServerApi;
  const client = key?.issuerId && key?.keyId && key?.privateKey
    ? new api.AppStoreServerAPIClient(
      key.privateKey, key.keyId, key.issuerId, configuration.bundleId, appEnv)
    : null;
  return {
    async verifyTransaction(jws, requestedEnvironment) {
      if (requestedEnvironment !== environment) throw new VerificationRejected();
      return verifier.verifyAndDecodeTransaction(jws);
    },
    async verifyNotification(jws, requestedEnvironment) {
      if (requestedEnvironment !== environment) throw new VerificationRejected();
      return verifier.verifyAndDecodeNotification(jws);
    },
    async getLatestTransaction(transactionId, requestedEnvironment) {
      if (requestedEnvironment !== environment || !client) {
        throw new VerificationRejected("Trusted Apple API status lookup unavailable", 503);
      }
      return client.getTransactionInfo(transactionId);
    },
  };
}
