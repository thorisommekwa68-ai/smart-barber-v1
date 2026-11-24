import { createClient } from "@supabase/supabase-js";

export function createSupabaseBrowserAuth(env = import.meta.env) {
  if (!env.VITE_SUPABASE_URL || !env.VITE_SUPABASE_ANON_KEY) {
    throw new Error("VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are required");
  }

  const supabase = createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });

  async function register({ email, password, displayName }) {
    return supabase.auth.signUp({
      email,
      password,
      options: { data: { display_name: displayName } }
    });
  }

  async function login({ email, password }) {
    return supabase.auth.signInWithPassword({ email, password });
  }

  async function logout() { return supabase.auth.signOut(); }

  async function validateSession() {
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    return data.session;
  }

  async function getAccessToken() {
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    const session = data.session;
    if (!session) return null;
    if (session.expires_at && session.expires_at * 1000 <= Date.now() + 30_000) {
      const refreshed = await supabase.auth.refreshSession();
      if (refreshed.error) throw refreshed.error;
      return refreshed.data.session?.access_token ?? null;
    }
    return session.access_token;
  }

  async function recoverPassword(email, redirectTo = globalThis.location?.origin) {
    return supabase.auth.resetPasswordForEmail(email, { redirectTo });
  }

  async function updatePassword(password) {
    return supabase.auth.updateUser({ password });
  }

  function onAuthStateChange(callback) {
    return supabase.auth.onAuthStateChange((event, session) => callback(event, session));
  }

  return { supabase, register, login, logout, validateSession, getAccessToken, recoverPassword, updatePassword, onAuthStateChange };
}
