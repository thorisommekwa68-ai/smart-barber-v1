import test from "node:test";
import assert from "node:assert/strict";
import { createApiClient } from "../apiClient.js";
import { formatZarMinor } from "../currency.js";
import { renderAuthView } from "../authView.js";

test("API client sends the current Supabase bearer token without development identity headers", async () => {
  const originalFetch = globalThis.fetch;
  let request;
  globalThis.fetch = async (url, options) => {
    request = { url, options };
    return Response.json({ success: true, data: { id: "appointment-1" } });
  };
  try {
    const api = createApiClient({ getAccessToken: async () => "verified-access-token" });
    const result = await api.post("/appointments", { tenantId: "tenant-1" });
    assert.deepEqual(result, { id: "appointment-1" });
    assert.equal(request.options.headers.Authorization, "Bearer verified-access-token");
    assert.equal(request.options.headers["x-user-id"], undefined);
    assert.equal(request.options.headers["x-tenant-id"], undefined);
    assert.equal(request.options.body, JSON.stringify({ tenantId: "tenant-1" }));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("API client reports expired authentication responses", async () => {
  const originalFetch = globalThis.fetch;
  let unauthorized = 0;
  globalThis.fetch = async () => Response.json({
    success: false,
    error: { code: "UNAUTHENTICATED", message: "Sign in again" }
  }, { status: 401 });
  try {
    const api = createApiClient({
      getAccessToken: async () => "expired-token",
      onUnauthorized: () => { unauthorized += 1; }
    });
    await assert.rejects(api.get("/me/profile"), { status: 401, code: "UNAUTHENTICATED" });
    assert.equal(unauthorized, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }

  let refreshFailures = 0;
  const api = createApiClient({
    getAccessToken: async () => { throw new Error("Refresh token expired"); },
    onUnauthorized: () => { refreshFailures += 1; }
  });
  await assert.rejects(api.get("/me/profile"), { status: 401, code: "AUTH_REFRESH_FAILED" });
  assert.equal(refreshFailures, 1);
});

test("ZAR formatter converts minor units to two-decimal currency", () => {
  const expected = new Intl.NumberFormat("en-ZA", {
    style: "currency", currency: "ZAR", minimumFractionDigits: 2, maximumFractionDigits: 2
  }).format(123.45);
  assert.equal(formatZarMinor(12345), expected);
  assert.throws(() => formatZarMinor(Number.NaN), TypeError);
});

test("admin authentication screen does not offer public registration", () => {
  const screen = renderAuthView("login", "", { allowRegistration: false });
  assert.match(screen, /name="email"/);
  assert.doesNotMatch(screen, /data-auth-mode="register"/);
});
