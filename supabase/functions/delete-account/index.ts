// Deploy only after separate owner approval, with JWT verification enabled.
// Supabase injects the privileged service-role key into the Edge runtime;
// it is never a client-side build setting or repository secret.
import { handleDeleteAccount } from "./handler.ts";

Deno.serve((request: Request) => handleDeleteAccount(request, {
  supabaseUrl: Deno.env.get("SUPABASE_URL"),
  anonKey: Deno.env.get("SUPABASE_ANON_KEY"),
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
}));
