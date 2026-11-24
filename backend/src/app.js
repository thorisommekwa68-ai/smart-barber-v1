import { loadConfig } from "./config/index.js";
import { InMemoryRepository } from "./repositories/memory/inMemoryRepository.js";
import { SupabaseRepository } from "./repositories/supabase/supabaseRepository.js";
import { MockIdentityProvider, SupabaseIdentityProvider } from "./middleware/auth.js";
import { sendError } from "./middleware/errors.js";
import { MarketplaceService } from "./services/MarketplaceService.js";
import { AvailabilityService } from "./services/AvailabilityService.js";
import { AppointmentService } from "./services/AppointmentService.js";
import { MediaService } from "./services/MediaService.js";
import { ApiController } from "./controllers/ApiController.js";
import { createRouter } from "./routes/apiRoutes.js";
import { readJson } from "./utils/http.js";
import { errors } from "./domain/errors/domainErrors.js";
import { createStructuredLogger } from "./utils/logger.js";

export function createApplication(options = {}) {
  const config = options.config ?? loadConfig();
  if (config.environment === "production") {
    if (config.repositoryType !== "supabase") throw new Error("Production requires the Supabase repository");
    if (config.identityProviderType !== "supabase") throw new Error("Production requires Supabase Auth");
    if (!config.supabaseUrl || !config.supabaseAnonKey) throw new Error("Production requires SUPABASE_URL and SUPABASE_ANON_KEY");
    if (!config.allowedOrigins.length || config.allowedOrigins.includes("*")) throw new Error("Production requires explicit CORS_ALLOWED_ORIGINS");
  }
  let repository = options.repository;
  if (!repository) {
    if (config.repositoryType === "supabase") {
      repository = new SupabaseRepository({
        supabaseUrl: config.supabaseUrl,
        supabaseAnonKey: config.supabaseAnonKey
      });
    } else {
      repository = new InMemoryRepository();
    }
  }
  let identityProvider = options.identityProvider;
  if (!identityProvider) {
    if (config.environment === "production" && config.identityProviderType !== "supabase") {
      throw new Error("Production requires a Supabase identity provider");
    }
    if (config.identityProviderType === "supabase") {
      identityProvider = new SupabaseIdentityProvider({
        repository,
        supabaseUrl: config.supabaseUrl,
        supabaseAnonKey: config.supabaseAnonKey
      });
    } else if (!config.mockAuthEnabled) {
      throw new Error("Mock authentication is disabled and no trusted identity provider is configured");
    } else {
      identityProvider = new MockIdentityProvider(repository, { enabled: true });
    }
  }
  const marketplace = new MarketplaceService(repository);
  const availability = new AvailabilityService(repository);
  const appointments = new AppointmentService(repository);
  let media = options.media;
  if (!media && config.repositoryType === "supabase") {
    media = new MediaService({
      supabaseUrl: config.supabaseUrl,
      supabaseAnonKey: config.supabaseAnonKey
    });
  }
  const controller = new ApiController({ marketplace, availability, appointments, media, identityProvider });
  const routes = createRouter(controller);
  const logger = createStructuredLogger();
  const rateBuckets = new Map();
  const rateLimit = 120;
  const rateWindowMs = 60_000;

  async function handleRequest(req, res) {
    const origin = req.headers.origin;
    const url = new URL(req.url, "http://localhost");
    if (req.method === "GET" && (url.pathname === "/health" || url.pathname === "/health/ready")) {
      res.setHeader("Content-Type", "application/json");
      const ready = config.environment !== "production"
        || (config.repositoryType === "supabase" && Boolean(config.supabaseUrl && config.supabaseAnonKey));
      res.statusCode = ready ? 200 : 503;
      res.end(JSON.stringify({
        success: ready,
        data: {
          status: ready ? "ok" : "not_ready",
          timezone: config.timezone,
          repository: config.repositoryType,
          identityProvider: config.identityProviderType
        },
        message: url.pathname === "/health/ready" ? "Readiness check completed" : "Backend is running"
      }));
      return;
    }
    const clientIp = req.headers["cf-connecting-ip"]
      || req.headers["x-forwarded-for"]?.split(",")[0]?.trim()
      || req.socket?.remoteAddress
      || "unknown";
    const now = Date.now();
    const bucket = rateBuckets.get(clientIp);
    const activeBucket = bucket && now - bucket.startedAt < rateWindowMs
      ? bucket
      : { startedAt: now, count: 0 };
    activeBucket.count += 1;
    rateBuckets.set(clientIp, activeBucket);
    if (activeBucket.count > rateLimit) {
      res.statusCode = 429;
      res.setHeader("Content-Type", "application/json");
      res.setHeader("Retry-After", "60");
      res.end(JSON.stringify({ success: false, error: { code: "RATE_LIMITED", message: "Too many requests" } }));
      logger.warn("rate_limit_exceeded", { method: req.method, path: url.pathname, clientIp });
      return;
    }
    if (rateBuckets.size > 10000) {
      for (const [key, value] of rateBuckets) {
        if (now - value.startedAt >= rateWindowMs) rateBuckets.delete(key);
      }
    }
    if (origin && config.allowedOrigins.includes(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
    } else if (origin) {
      res.statusCode = 403;
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ success: false, error: { code: "FORBIDDEN", message: "Origin is not allowed" } }));
      return;
    }
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.setHeader("Access-Control-Allow-Methods", "GET,POST,PATCH,DELETE,OPTIONS");
    if (req.method === "OPTIONS") { res.statusCode = 204; res.end(); return; }

    try {
      const route = routes.find((candidate) => candidate.method === req.method && candidate.pattern.test(url.pathname));
      if (!route) {
        const methodAllowed = routes.some((candidate) => candidate.pattern.test(url.pathname));
        throw methodAllowed ? errors.methodNotAllowed("Method not allowed") : errors.notFound("Endpoint not found");
      }
      if (req.method === "POST" || req.method === "PATCH") {
        const contentType = req.headers["content-type"];
        const contentLength = Number(req.headers["content-length"] || 0);
        if (req.method === "POST" && contentLength > 0 && (!contentType || !contentType.toLowerCase().startsWith("application/json"))) {
          throw errors.validation("Content-Type must be application/json");
        }
        if (req.method === "PATCH" && contentType && !contentType.toLowerCase().startsWith("application/json")) {
          throw errors.validation("Content-Type must be application/json");
        }
      }
      let body = null;
      if (req.method === "POST" || req.method === "PATCH") body = await readJson(req, config.maxRequestBodyBytes);
      const match = url.pathname.match(route.pattern);
      const query = Object.fromEntries(url.searchParams.entries());
      await route.handler(req, res, match, query, body);
    } catch (error) {
      logger.error("request_failed", {
        code: error?.code || "INTERNAL_ERROR",
        method: req.method,
        path: url?.pathname || "unknown"
      });
      sendError(res, error);
    }
  }

  return { handleRequest, repository, config };
}
