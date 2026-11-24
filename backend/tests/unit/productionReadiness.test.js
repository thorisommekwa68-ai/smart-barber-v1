import test from "node:test";
import assert from "node:assert/strict";
import { createApplication } from "../../src/app.js";

test("production configuration rejects memory persistence", () => {
  const config = Object.freeze({
    environment: "production",
    repositoryType: "memory",
    identityProviderType: "supabase",
    supabaseUrl: "https://project.supabase.co",
    supabaseAnonKey: "public-anon-test-key",
    allowedOrigins: ["https://app.example.com"],
    mockAuthEnabled: false,
    timezone: "Africa/Johannesburg"
  });
  assert.throws(
    () => createApplication({ config }),
    /Production requires the Supabase repository/
  );
});

test("production configuration rejects mock identity", () => {
  const config = Object.freeze({
    environment: "production",
    repositoryType: "supabase",
    identityProviderType: "development-mock",
    supabaseUrl: "https://project.supabase.co",
    supabaseAnonKey: "public-anon-test-key",
    allowedOrigins: ["https://app.example.com"],
    mockAuthEnabled: false,
    timezone: "Africa/Johannesburg"
  });
  assert.throws(
    () => createApplication({ config }),
    /Production requires Supabase Auth/
  );
});

test("production configuration rejects wildcard CORS", () => {
  const config = Object.freeze({
    environment: "production",
    repositoryType: "supabase",
    identityProviderType: "supabase",
    supabaseUrl: "https://project.supabase.co",
    supabaseAnonKey: "public-anon-test-key",
    allowedOrigins: ["*"],
    mockAuthEnabled: false,
    timezone: "Africa/Johannesburg"
  });
  assert.throws(
    () => createApplication({ config }),
    /explicit CORS_ALLOWED_ORIGINS/
  );
});
