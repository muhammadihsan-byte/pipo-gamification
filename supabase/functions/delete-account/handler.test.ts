import { handleDeleteAccount } from "./handler.ts";

const OWNER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const VICTIM = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const environment = {
  supabaseUrl: "https://example.supabase.co",
  anonKey: "public-key",
  serviceRoleKey: "server-only-secret",
};
function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}
function req(token?: string, body?: string): Request {
  return new Request("https://example.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body,
  });
}

Deno.test("unauthenticated deletion cannot reach privileged API", async () => {
  let invoked = false;
  const response = await handleDeleteAccount(
    req(), environment,
    async () => { invoked = true; throw new Error("must not be invoked"); },
  );
  check(response.status === 401, "must reject missing credentials");
  check(!invoked, "must not call Auth or admin endpoints");
});

Deno.test("verified Auth user is the only permitted deletion subject", async () => {
  const calls: Array<{ url: string; method: string; headers: Headers }> = [];
  const response = await handleDeleteAccount(
    req("valid-jwt", JSON.stringify({ user_id: VICTIM })),
    environment,
    async (input, init) => {
      const url = String(input);
      const headers = new Headers(init?.headers);
      calls.push({ url, method: init?.method ?? "GET", headers });
      if (calls.length === 1) {
        return Response.json({ id: OWNER });
      }
      return new Response(null, { status: 204 });
    },
  );
  const json = await response.json();
  check(response.status === 200 && json.deleted === true, "confirmed");
  check(calls.length === 2, "lookup followed by exactly one deletion");
  check(calls[0].url.endsWith("/auth/v1/user"), "identity lookup");
  check(calls[0].headers.get("authorization") === "Bearer valid-jwt", "caller JWT used for lookup");
  check(calls[1].url.endsWith(`/auth/v1/admin/users/${OWNER}`), "only verified owner is deleted");
  check(!calls[1].url.includes(VICTIM), "injected victim ignored");
  check(calls[1].headers.get("authorization") === "Bearer server-only-secret", "server key used only in admin call");
});

Deno.test("invalid credentials cannot delete any account", async () => {
  let calls = 0;
  const response = await handleDeleteAccount(
    req("expired-jwt"), environment,
    async () => {
      calls++;
      return new Response("Invalid token", { status: 401 });
    },
  );
  check(response.status === 401, "invalid session rejected");
  check(calls === 1, "no admin call");
});

Deno.test("upstream deletion failure never returns success", async () => {
  let calls = 0;
  const response = await handleDeleteAccount(
    req("valid-jwt"), environment,
    async () => {
      calls++;
      return calls === 1
        ? Response.json({ id: OWNER })
        : new Response("Do not expose upstream details", { status: 409 });
    },
  );
  const json = await response.json();
  check(response.status === 502 && json.deleted !== true, "must fail closed");
  check(!JSON.stringify(json).includes("upstream details"), "no raw upstream errors");
});

Deno.test("missing server secret prevents all network calls", async () => {
  const response = await handleDeleteAccount(
    req("valid-jwt"), { ...environment, serviceRoleKey: undefined },
    async () => { throw new Error("must not be invoked"); },
  );
  check(response.status === 503, "no secret must not fall back");
});
