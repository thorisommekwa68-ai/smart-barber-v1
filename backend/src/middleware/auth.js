import { errors } from "../domain/errors/domainErrors.js";
import { createClient } from "@supabase/supabase-js";

export class MockIdentityProvider {
  constructor(repository, { enabled = true } = {}) {
    this.repository = repository;
    this.enabled = enabled;
  }
  async authenticate(request) {
    if (!this.enabled) throw errors.unauthorised("Mock authentication is disabled");
    const userId = request.headers["x-user-id"];
    if (!userId) throw errors.unauthorised();
    const user = await this.repository.findUserById(userId);
    if (!user) throw errors.unauthorised("Unknown mock identity");
    const memberships = await this.repository.findMembershipsByUser(user.id);
    const requestedTenantId = request.headers["x-tenant-id"];
    let tenantId = requestedTenantId;
    if (!tenantId && memberships.length === 1) tenantId = memberships[0].tenantId;
    if (tenantId && !memberships.some((membership) => membership.tenantId === tenantId)) {
      throw errors.forbidden("User is not an active member of this tenant");
    }
    return {
      id: user.id,
      displayName: user.displayName,
      email: user.email,
      phone: user.phone,
      provider: "development-mock",
      tenantId,
      memberships: memberships.map((membership) => ({
        tenantId: membership.tenantId,
        role: membership.role,
        status: membership.membershipStatus
      }))
    };
  }
}

export class SupabaseIdentityProvider {
  constructor({ repository, supabaseUrl, supabaseAnonKey, verifier = null }) {
    if (verifier) {
      this.repository = repository;
      this.verifier = verifier;
      return;
    }
    if (!supabaseUrl || !supabaseAnonKey) throw new Error("SUPABASE_URL and SUPABASE_ANON_KEY are required");
    this.repository = repository;
    this.supabase = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false }
    });
    this.verifier = (accessToken) => this.supabase.auth.getUser(accessToken);
  }

  extractBearerToken(request) {
    const authorization = request.headers.authorization;
    if (!authorization || typeof authorization !== "string") throw errors.unauthorised("Bearer access token required");
    const match = /^Bearer ([^\s]+)$/i.exec(authorization.trim());
    if (!match) throw errors.unauthorised("Bearer access token required");
    return match[1];
  }

  async authenticate(request) {
    const accessToken = this.extractBearerToken(request);
    let authResult;
    try {
      authResult = await this.verifier(accessToken);
    } catch {
      throw errors.unauthorised("Invalid or expired access token");
    }
    if (authResult.error || !authResult.data?.user) {
      throw errors.unauthorised("Invalid or expired access token");
    }

    const user = authResult.data.user;
    if (!user.id) throw errors.unauthorised("Invalid Supabase identity");
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(user.id)) {
      throw errors.unauthorised("Invalid Supabase user UUID");
    }
    if (user.aud && user.aud !== "authenticated") throw errors.unauthorised("Invalid Supabase identity");

    const profile = await this.repository.findUserById(user.id, { accessToken });
    if (!profile) throw errors.unauthorised("Application profile not provisioned");
    const memberships = await this.repository.findMembershipsByUser(user.id, { accessToken });

    if (request.headers["x-tenant-id"]) {
      throw errors.forbidden("Tenant header is not accepted by production authentication");
    }

    let tenantId = null;
    const membershipsWithRoles = memberships.map((membership) => ({
      tenantId: membership.tenantId,
      role: membership.role,
      status: membership.membershipStatus
    }));
    if (membershipsWithRoles.length === 1) tenantId = membershipsWithRoles[0].tenantId;

    return {
      id: profile.id,
      displayName: profile.displayName,
      email: profile.email,
      phone: profile.phone,
      provider: "supabase",
      tenantId,
      memberships: membershipsWithRoles,
      accessToken
    };
  }
}

export async function requireAuth(request, identityProvider) {
  return identityProvider.authenticate(request);
}
