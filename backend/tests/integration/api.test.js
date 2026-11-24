import test from "node:test";
import assert from "node:assert/strict";
import { createApplication } from "../../src/app.js";
import { createNodeServer } from "../../src/server.js";
import { handleWebRequest } from "../../src/worker.js";
import { loadConfig } from "../../src/config/index.js";

async function request(server, method, path, { body, userId, tenantId } = {}) {
  const headers = {};
  if (userId) headers["x-user-id"] = userId;
  if (tenantId) headers["x-tenant-id"] = tenantId;
  if (body !== undefined) headers["content-type"] = "application/json";
  const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return { status: response.status, json: await response.json() };
}

test("API supports marketplace discovery and the booking lifecycle", async (t) => {
  const application = createApplication();
  const server = createNodeServer(application);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const health = await request(server, "GET", "/health");
  assert.equal(health.status, 200);
  assert.equal(health.json.success, true);

  const unauthenticated = await request(server, "POST", "/api/v1/appointments", {
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-crown-1",
      serviceId: "service-crown-cut",
      startAt: "2026-11-24T10:00:00+02:00"
    }
  });
  assert.equal(unauthenticated.status, 401);

  const missingData = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-1",
    body: {}
  });
  assert.equal(missingData.status, 400);

  const invalidService = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-1",
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-crown-1",
      serviceId: "service-studio-cut",
      startAt: "2026-11-24T10:00:00+02:00"
    }
  });
  assert.equal(invalidService.status, 400);

  const invalidStaff = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-1",
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-studio-1",
      serviceId: "service-crown-cut",
      startAt: "2026-11-24T10:00:00+02:00"
    }
  });
  assert.equal(invalidStaff.status, 400);

  const tenants = await request(server, "GET", "/api/v1/marketplace/tenants");
  assert.equal(tenants.status, 200);
  assert.equal(tenants.json.data.length, 2);

  const anonymousProfile = await request(server, "GET", "/api/v1/me/profile");
  assert.equal(anonymousProfile.status, 401);
  const profile = await request(server, "GET", "/api/v1/me/profile", { userId: "merchant-owner-1" });
  assert.equal(profile.status, 200);
  assert.equal(profile.json.data.displayName, "Crown Owner");
  assert.deepEqual(profile.json.data.memberships.map(({ tenantId }) => tenantId), ["tenant-crown"]);

  const unavailable = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-1",
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-crown-1",
      serviceId: "service-crown-cut",
      startAt: "2026-11-29T10:00:00+02:00"
    }
  });
  assert.equal(unavailable.status, 409);

  const booking = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-1",
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-crown-1",
      serviceId: "service-crown-cut",
      startAt: "2026-11-24T10:00:00+02:00",
      customerNotes: "Please use clippers"
    }
  });
  assert.equal(booking.status, 201);
  assert.equal(booking.json.data.status, "pending");
  assert.equal(booking.json.data.priceSnapshot, 18000);
  assert.equal(booking.json.data.durationSnapshot, 45);

  const appointmentId = booking.json.data.id;
  const wrongTenant = await request(server, "GET", "/api/v1/merchant/appointments", {
    userId: "merchant-owner-1",
    tenantId: "tenant-studio"
  });
  assert.equal(wrongTenant.status, 403);

  const merchant = await request(server, "GET", "/api/v1/merchant/appointments", {
    userId: "merchant-owner-1",
    tenantId: "tenant-crown"
  });
  assert.equal(merchant.status, 200);
  assert.equal(merchant.json.data.length, 1);

  const accepted = await request(server, "PATCH", `/api/v1/merchant/appointments/${appointmentId}/accept?tenantId=tenant-crown`, {
    userId: "merchant-owner-1"
  });
  assert.equal(accepted.status, 200);
  assert.equal(accepted.json.data.status, "confirmed");

  const customerAppointments = await request(server, "GET", "/api/v1/me/appointments", {
    userId: "customer-1"
  });
  assert.equal(customerAppointments.status, 200);
  assert.equal(customerAppointments.json.data[0].status, "confirmed");

  const rejectedBooking = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-1",
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-crown-1",
      serviceId: "service-crown-cut",
      startAt: "2026-11-24T12:00:00+02:00"
    }
  });
  assert.equal(rejectedBooking.status, 201);
  const rejected = await request(server, "PATCH", `/api/v1/merchant/appointments/${rejectedBooking.json.data.id}/decline`, {
    userId: "merchant-owner-1",
    tenantId: "tenant-crown"
  });
  assert.equal(rejected.status, 200);
  assert.equal(rejected.json.data.status, "declined");

  const overlap = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-2",
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-crown-1",
      serviceId: "service-crown-cut",
      startAt: "2026-11-24T10:30:00+02:00"
    }
  });
  assert.equal(overlap.status, 409);

  const cancel = await request(server, "POST", `/api/v1/appointments/${appointmentId}/cancel`, {
    userId: "customer-1"
  });
  assert.equal(cancel.status, 200);
  assert.equal(cancel.json.data.status, "cancelled");

  const badTransition = await request(server, "PATCH", `/api/v1/merchant/appointments/${appointmentId}/start`, {
    userId: "merchant-owner-1",
    tenantId: "tenant-crown"
  });
  assert.equal(badTransition.status, 409);
});

test("availability rejects invalid dates, inactive resources and past bookings", async (t) => {
  const application = createApplication();
  const { repository } = application;
  const server = createNodeServer(application);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const invalidDate = await request(server, "GET", "/api/v1/availability?tenantId=tenant-crown&locationId=location-crown-1&staffId=staff-crown-1&serviceId=service-crown-cut&date=2026-02-30");
  assert.equal(invalidDate.status, 400);

  repository.tenants.find((tenant) => tenant.id === "tenant-crown").businessStatus = "inactive";
  const inactive = await request(server, "GET", "/api/v1/availability?tenantId=tenant-crown&locationId=location-crown-1&staffId=staff-crown-1&serviceId=service-crown-cut&date=2026-11-24");
  assert.equal(inactive.status, 404);

  repository.tenants.find((tenant) => tenant.id === "tenant-crown").businessStatus = "active";
  const past = await request(server, "POST", "/api/v1/appointments", {
    userId: "customer-1",
    body: {
      tenantId: "tenant-crown",
      locationId: "location-crown-1",
      staffId: "staff-crown-1",
      serviceId: "service-crown-cut",
      startAt: "2020-01-01T10:00:00+02:00"
    }
  });
  assert.equal(past.status, 409);
});

test("HTTP security rejects disallowed origins, malformed JSON and oversized bodies", async (t) => {
  const application = createApplication({ config: (await import("../../src/config/index.js")).loadConfig({
    CORS_ALLOWED_ORIGINS: "http://localhost:5173",
    MAX_REQUEST_BODY_BYTES: "64"
  }) });
  const server = createNodeServer(application);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;

  const cors = await fetch(`${base}/api/v1/marketplace/tenants`, { headers: { Origin: "https://evil.example" } });
  assert.equal(cors.status, 403);

  const malformed = await fetch(`${base}/api/v1/appointments`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-user-id": "customer-1" },
    body: "{bad"
  });
  assert.equal(malformed.status, 400);

  const oversized = await fetch(`${base}/api/v1/appointments`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-user-id": "customer-1" },
    body: JSON.stringify({ tenantId: "tenant-crown", padding: "x".repeat(100) })
  });
  assert.equal(oversized.status, 413);
});

test("mock authentication is fail closed when disabled", () => {
  assert.throws(() => createApplication({
    config: loadConfig({ MOCK_AUTH_ENABLED: "false", IDENTITY_PROVIDER_TYPE: "development-mock" })
  }), /no trusted identity provider/i);
});

test("Web Request adapter returns standard Worker responses", async () => {
  const application = createApplication();
  const request = new Request("http://localhost/health");
  const response = await handleWebRequest(request, application);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json");
  const payload = await response.json();
  assert.equal(payload.success, true);
  assert.equal(payload.data.timezone, "Africa/Johannesburg");
});
