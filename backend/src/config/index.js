export function loadConfig(env = globalThis.process?.env ?? {}) {
  const environment = env.NODE_ENV || "development";
  const mockAuthEnabled = environment !== "production" && env.MOCK_AUTH_ENABLED !== "false";
  const allowedOrigins = (env.CORS_ALLOWED_ORIGINS || "http://localhost:5173,http://localhost:5174,http://localhost:5175")
    .split(",").map((value) => value.trim()).filter(Boolean);
  return Object.freeze({
    port: Number(env.PORT || 3001),
    timezone: "Africa/Johannesburg",
    currency: "ZAR",
    environment,
    mockAuthEnabled,
    identityProviderType: environment === "production" ? "supabase" : (env.IDENTITY_PROVIDER_TYPE || "development-mock"),
    supabaseUrl: env.SUPABASE_URL || "",
    supabaseAnonKey: env.SUPABASE_ANON_KEY || "",
    supabaseServiceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY || "",
    repositoryType: environment === "production" ? "supabase" : (env.REPOSITORY_TYPE || "memory"),
    allowedOrigins,
    maxRequestBodyBytes: Number(env.MAX_REQUEST_BODY_BYTES || 1048576)
  });
}
