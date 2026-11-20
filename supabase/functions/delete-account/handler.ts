/**
 * Pipo account deletion. No HTTP field chooses the deleted user:
 * the ONLY deletion subject comes from the Supabase Auth /user response
 * for the caller's bearer token. This module has no SDK dependencies.
 */
export type DeletionEnvironment = {
  supabaseUrl?: string;
  anonKey?: string;
  serviceRoleKey?: string;
};

const noStore = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: noStore });
}

export async function handleDeleteAccount(
  request: Request,
  environment: DeletionEnvironment,
  http: typeof fetch = fetch,
): Promise<Response> {
  if (request.method !== "POST") {
    return reply(405, { error: "Method not allowed." });
  }

  const bearer = /^Bearer\s+([^\s]+)$/i.exec(
    request.headers.get("authorization") ?? "",
  );
  if (!bearer) {
    return reply(401, { error: "Sign in to delete your Pipo account." });
  }

  const { supabaseUrl, anonKey, serviceRoleKey } = environment;
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    // Never include environment values or exception stacktraces in responses.
    return reply(503, { error: "Account deletion is unavailable." });
  }

  let origin: string;
  try {
    const configured = new URL(supabaseUrl);
    if (configured.protocol !== "https:") throw new Error("Insecure URL");
    origin = configured.origin;
  } catch {
    return reply(503, { error: "Account deletion is unavailable." });
  }

  try {
    // This request validates the real signed-in user at the Auth service.
    // Do not infer identity from decoded-but-unverified JWT claims, headers,
    // query strings, request bodies, or client-supplied account IDs.
    const lookup = await http(`${origin}/auth/v1/user`, {
      method: "GET",
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${bearer[1]}`,
      },
    });
    if (!lookup.ok) {
      return reply(401, { error: "Session expired. Sign in and try again." });
    }
    const user = await lookup.json() as {
      id?: unknown;
      app_metadata?: { provider?: unknown; providers?: unknown };
      identities?: Array<{ provider?: unknown }>;
    };
    if (typeof user.id !== "string" || !/^[0-9a-f-]{36}$/i.test(user.id)) {
      return reply(401, { error: "Could not verify the signed-in account." });
    }

    // Sign in with Apple requires revoking its authorization on deletion.
    // Do not irrevocably delete Auth credentials before the Apple provider
    // revocation is implemented and verified with real Apple credentials.
    const providers = [
      user.app_metadata?.provider,
      ...(Array.isArray(user.app_metadata?.providers)
        ? user.app_metadata.providers : []),
      ...(Array.isArray(user.identities)
        ? user.identities.map((identity) => identity.provider) : []),
    ];
    if (providers.some((provider) =>
      typeof provider === "string" && provider.toLowerCase() === "apple"
    )) {
      return reply(409, {
        error: "Apple account deletion is not available yet. Contact support before deleting this account.",
      });
    }

    // This ID is NOT the authorization subject. It is a second, restrictive
    // confirmation that the app has not switched accounts since opening its
    // confirmation screen. Always delete the user resolved by Auth, never the
    // caller-supplied expected ID.
    let expected: unknown;
    try {
      const payload = await request.json() as { expected_user_id?: unknown };
      expected = payload?.expected_user_id;
    } catch {
      return reply(400, { error: "Account confirmation is missing." });
    }
    if (
      typeof expected !== "string" ||
      expected.toLowerCase() !== user.id.toLowerCase()
    ) {
      return reply(409, { error: "Account changed. Sign in and try again." });
    }

    // Hard delete, not a soft-delete or a client-side sign-out. Pipo's
    // account-owned public tables have ON DELETE CASCADE references to
    // auth.users. The service role key NEVER leaves this Edge Function.
    const deletion = await http(
      `${origin}/auth/v1/admin/users/${encodeURIComponent(user.id)}`,
      {
        method: "DELETE",
        headers: {
          apikey: serviceRoleKey,
          authorization: `Bearer ${serviceRoleKey}`,
        },
      },
    );
    if (!deletion.ok) {
      return reply(502, {
        error: "Server deletion could not be confirmed. Try again.",
      });
    }
    return reply(200, { deleted: true, user_id: user.id });
  } catch {
    return reply(503, {
      error: "Could not confirm account deletion. Try again.",
    });
  }
}
