export async function handleWebRequest(request, application) {
  const url = new URL(request.url);
  const bodyText = request.method === "GET" || request.method === "HEAD" ? null : await request.text();
  const headers = Object.fromEntries(request.headers.entries());
  const req = {
    method: request.method,
    url: `${url.pathname}${url.search}`,
    headers,
    async *[Symbol.asyncIterator]() {
      if (bodyText) yield new TextEncoder().encode(bodyText);
    }
  };
  let statusCode = 200;
  const responseHeaders = new Map();
  const res = {
    statusCode,
    setHeader(name, value) { responseHeaders.set(name.toLowerCase(), String(value)); },
    get statusCode() { return statusCode; },
    set statusCode(value) { statusCode = value; },
    end(body = "") {
      this.body = body;
    }
  };
  await application.handleRequest(req, res);
  return new Response(res.body || "", {
    status: statusCode,
    headers: Object.fromEntries(responseHeaders)
  });
}

export function createWorkerFetch(createApplication) {
  return async function fetch(request, env) {
    const environment = env.NODE_ENV || "development";
    if (environment === "production") {
      if (env.MOCK_AUTH_ENABLED === "true") {
        return new Response(JSON.stringify({ success: false, error: { code: "MISCONFIGURED", message: "Mock authentication is forbidden in production" } }), {
          status: 503,
          headers: { "Content-Type": "application/json" }
        });
      }
      if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
        return new Response(JSON.stringify({ success: false, error: { code: "MISCONFIGURED", message: "Supabase production configuration is incomplete" } }), {
          status: 503,
          headers: { "Content-Type": "application/json" }
        });
      }
    }
    const config = {
      port: 3001,
      timezone: "Africa/Johannesburg",
      currency: "ZAR",
      environment,
      mockAuthEnabled: environment !== "production" && env.MOCK_AUTH_ENABLED !== "false",
      identityProviderType: environment === "production" ? "supabase" : (env.IDENTITY_PROVIDER_TYPE || "development-mock"),
      supabaseUrl: env.SUPABASE_URL || "",
      supabaseAnonKey: env.SUPABASE_ANON_KEY || "",
      repositoryType: environment === "production" ? "supabase" : (env.REPOSITORY_TYPE || "memory"),
      allowedOrigins: (env.CORS_ALLOWED_ORIGINS || (environment === "production" ? "" : "*"))
        .split(",").map((value) => value.trim()).filter(Boolean),
      maxRequestBodyBytes: Number(env.MAX_REQUEST_BODY_BYTES || 1048576)
    };
    const application = createApplication({ config });
    return handleWebRequest(request, application);
  };
}
