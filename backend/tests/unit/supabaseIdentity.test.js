import test from "node:test";
import assert from "node:assert/strict";
import { SupabaseIdentityProvider, MockIdentityProvider } from "../../src/middleware/auth.js";
import { InMemoryRepository } from "../../src/repositories/memory/inMemoryRepository.js";
import { loadConfig } from "../../src/config/index.js";
import { createApplication } from "../../src/app.js";

test("Supabase provider maps verified user UUID to profile", async () => {
  const repository = new InMemoryRepository();
  repository.users.push({
    id: "10000000-0000-4000-8000-000000000001",
    displayName: "Verified Customer",
    createdAt: new Date().toISOString()
  });
  const provider = new SupabaseIdentityProvider({
    repository,
    verifier: async () => ({
      data: { user: { id: "10000000-0000-4000-8000-000000000001", aud: "authenticated" } },
      error: null
    })
  });
  const identity = await provider.authenticate({ headers: { authorization: "Bearer valid-token" } });
  assert.equal(identity.id, "10000000-0000-4000-8000-000000000001");
  assert.equal(identity.provider, "supabase");
});

test("Supabase provider rejects missing authorization", async () => {
  const provider = new SupabaseIdentityProvider({
    repository: new InMemoryRepository(),
    verifier: async () => ({ data: { user: null }, error: null })
  });
  await assert.rejects(
    () => provider.authenticate({ headers: {} }),
    (error) => error.code === "UNAUTHORISED"
  );
});

test("Supabase provider rejects invalid or expired tokens", async () => {
  for (const error of [new Error("invalid"), { message: "expired" }]) {
    const provider = new SupabaseIdentityProvider({
      repository: new InMemoryRepository(),
      verifier: async () => ({
        data: { user: null },
        error
      })
    });
    await assert.rejects(
      () => provider.authenticate({ headers: { authorization: "Bearer bad-token" } }),
      (errorResponse) => errorResponse.code === "UNAUTHORISED"
    );
  }
});

test("Supabase provider rejects tenant impersonation header", async () => {
  const repository = new InMemoryRepository();
  repository.users.push({ id: "10000000-0000-4000-8000-000000000002", displayName: "No Tenant", createdAt: new Date().toISOString() });
  const provider = new SupabaseIdentityProvider({
    repository,
    verifier: async () => ({
      data: { user: { id: "10000000-0000-4000-8000-000000000002", aud: "authenticated" } },
      error: null
    })
  });
  await assert.rejects(
    () => provider.authenticate({
      headers: {
        authorization: "Bearer valid-token",
        "x-tenant-id": "tenant-crown"
      }
    }),
    (error) => error.code === "FORBIDDEN"
  );
});

test("Supabase provider maps a valid user without memberships", async () => {
  const repository = new InMemoryRepository();
  repository.users.push({ id: "10000000-0000-4000-8000-000000000003", displayName: "No Membership", createdAt: new Date().toISOString() });
  const provider = new SupabaseIdentityProvider({
    repository,
    verifier: async () => ({
      data: { user: { id: "10000000-0000-4000-8000-000000000003", aud: "authenticated" } },
      error: null
    })
  });
  const identity = await provider.authenticate({ headers: { authorization: "Bearer valid-token" } });
  assert.equal(identity.memberships.length, 0);
  assert.equal(identity.tenantId, null);
});

test("Supabase provider supports multiple memberships without choosing an unauthorized tenant", async () => {
  const repository = new InMemoryRepository();
  repository.users.push({ id: "10000000-0000-4000-8000-000000000004", displayName: "Multiple", createdAt: new Date().toISOString() });
  repository.memberships.push(
    { id: "member-a", tenantId: "tenant-a", userId: "10000000-0000-4000-8000-000000000004", role: "owner", membershipStatus: "active" },
    { id: "member-b", tenantId: "tenant-b", userId: "10000000-0000-4000-8000-000000000004", role: "manager", membershipStatus: "active" }
  );
  const provider = new SupabaseIdentityProvider({
    repository,
    verifier: async () => ({
      data: { user: { id: "10000000-0000-4000-8000-000000000004", aud: "authenticated" } },
      error: null
    })
  });
  const identity = await provider.authenticate({ headers: { authorization: "Bearer valid-token" } });
  assert.equal(identity.memberships.length, 2);
  assert.equal(identity.tenantId, null);
});

test("Supabase provider resolves a valid business membership", async () => {
  const repository = new InMemoryRepository();
  repository.users.push({ id: "10000000-0000-4000-8000-000000000005", displayName: "Merchant", createdAt: new Date().toISOString() });
  repository.memberships.push({
    id: "member-c",
    tenantId: "tenant-crown",
    userId: "10000000-0000-4000-8000-000000000005",
    role: "owner",
    membershipStatus: "active"
  });
  const provider = new SupabaseIdentityProvider({
    repository,
    verifier: async () => ({
      data: { user: { id: "10000000-0000-4000-8000-000000000005", aud: "authenticated" } },
      error: null
    })
  });
  const identity = await provider.authenticate({ headers: { authorization: "Bearer valid-token" } });
  assert.equal(identity.tenantId, "tenant-crown");
  assert.equal(identity.memberships[0].role, "owner");
});

test("mock provider is disabled in production configuration", () => {
  const config = loadConfig({
    NODE_ENV: "production",
    MOCK_AUTH_ENABLED: "true",
    IDENTITY_PROVIDER_TYPE: "development-mock",
    SUPABASE_URL: "",
    SUPABASE_ANON_KEY: ""
  });
  assert.equal(config.mockAuthEnabled, false);
  assert.equal(config.identityProviderType, "supabase");
  assert.throws(
    () => createApplication({
      config,
      repository: new InMemoryRepository()
    }),
    /SUPABASE/
  );
});

test("mock provider can remain available in local development", async () => {
  const provider = new MockIdentityProvider(new InMemoryRepository(), { enabled: true });
  const identity = await provider.authenticate({ headers: { "x-user-id": "customer-1" } });
  assert.equal(identity.id, "customer-1");
  assert.equal(identity.provider, "development-mock");
});
