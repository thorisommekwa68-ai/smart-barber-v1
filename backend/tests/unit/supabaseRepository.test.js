import test from "node:test";
import assert from "node:assert/strict";
import { SupabaseRepository } from "../../src/repositories/supabase/supabaseRepository.js";

function queryResult(table, records) {
  return {
    select() { return this; },
    eq() { return this; },
    is() { return this; },
    order() { return this; },
    range() { return Promise.resolve({ data: records, error: null }); },
    then(resolve, reject) {
      return Promise.resolve({ data: records, error: null }).then(resolve, reject);
    },
    maybeSingle() { return Promise.resolve({ data: records[0] || null, error: null }); },
    update() { return this; }
  };
}

test("Supabase repository maps profile and tenant domain records", async () => {
  const repository = new SupabaseRepository({
    clientFactory: (token) => ({
      from(table) {
        if (table === "profiles") {
          return queryResult(table, [{ id: "10000000-0000-4000-8000-000000000001", display_name: "Alex", email: "alex@test", phone: null, active: true, created_at: "2026-01-01T00:00:00Z" }]);
        }
        if (table === "tenants") {
          return queryResult(table, [{ id: "tenant-crown", business_name: "Crown", business_description: "Cuts", business_status: "active", timezone: "Africa/Johannesburg", created_at: "2026-01-01T00:00:00Z" }]);
        }
        return queryResult(table, []);
      }
    })
  });
  const profile = await repository.findUserById("10000000-0000-4000-8000-000000000001");
  assert.equal(profile.displayName, "Alex");
  const tenant = await repository.findTenantById("tenant-crown");
  assert.equal(tenant.businessName, "Crown");
});

test("Supabase repository maps memberships and enforces active membership query", async () => {
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      from(table) {
        assert.equal(table, "tenant_memberships");
        return queryResult(table, [{
          id: "membership-1",
          tenant_id: "tenant-crown",
          profile_id: "10000000-0000-4000-8000-000000000001",
          role: "owner",
          membership_status: "active"
        }]);
      }
    })
  });
  const memberships = await repository.findMembershipsByUser("10000000-0000-4000-8000-000000000001");
  assert.equal(memberships.length, 1);
  assert.equal(memberships[0].tenantId, "tenant-crown");
  assert.equal(memberships[0].role, "owner");
});

test("Supabase repository maps services and staff service assignments", async () => {
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      from(table) {
        if (table === "services") {
          return queryResult(table, [{
            id: "service-cut",
            tenant_id: "tenant-crown",
            name: "Signature Cut",
            description: "Cut",
            price_minor: 18000,
            duration_minutes: 45,
            buffer_minutes: 10,
            service_status: "active"
          }]);
        }
        if (table === "staff") {
          return queryResult(table, [{
            id: "staff-1",
            tenant_id: "tenant-crown",
            location_id: "location-1",
            display_name: "Thabo",
            staff_status: "active",
            staff_services: [{ service_id: "service-cut" }]
          }]);
        }
        return queryResult(table, []);
      }
    })
  });
  const services = await repository.listServicesByTenant("tenant-crown");
  assert.equal(services[0].price, 18000);
  const staff = await repository.listStaffByTenant("tenant-crown");
  assert.deepEqual(staff[0].assignedServiceIds, ["service-cut"]);
});

test("Supabase repository forwards atomic booking RPC and maps result", async () => {
  let rpcArguments = null;
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      rpc(name, args) {
        assert.equal(name, "create_appointment");
        rpcArguments = args;
        return Promise.resolve({
          data: {
            id: "appointment-1",
            tenant_id: "tenant-crown",
            location_id: "location-1",
            customer_profile_id: "10000000-0000-4000-8000-000000000001",
            staff_id: "staff-1",
            service_id: "service-cut",
            start_at: "2026-11-24T08:00:00Z",
            end_at: "2026-11-24T08:45:00Z",
            price_snapshot_minor: 18000,
            duration_snapshot_minutes: 45,
            status: "pending",
            customer_notes: "Test",
            hold_expires_at: "2026-11-24T08:15:00Z",
            created_at: "2026-11-24T08:00:00Z",
            updated_at: "2026-11-24T08:00:00Z"
          },
          error: null
        });
      }
    })
  });
  const appointment = await repository.createAppointmentAtomically({
    tenantId: "tenant-crown",
    locationId: "location-1",
    customerId: "10000000-0000-4000-8000-000000000001",
    staffId: "staff-1",
    serviceId: "service-cut",
    startAt: "2026-11-24T08:00:00Z",
    endAt: "2026-11-24T08:45:00Z",
    priceSnapshot: 18000,
    durationSnapshot: 45,
    customerNotes: "Test"
  }, { accessToken: "verified-token" });
  assert.equal(rpcArguments.p_tenant_id, "tenant-crown");
  assert.equal(appointment.status, "pending");
  assert.equal(appointment.priceSnapshot, 18000);
});

test("Supabase repository translates overlap and permission database errors", async () => {
  const repository = new SupabaseRepository({ clientFactory: () => ({ rpc: () => Promise.resolve({ data: null, error: { code: "23P01", message: "raw SQL" } }) }) });
  await assert.rejects(
    () => repository.createAppointmentAtomically({}),
    (error) => error.code === "CONFLICT" && !error.message.includes("raw SQL")
  );
});

test("Supabase repository exposes tenant pagination and customer history", async () => {
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      from(table) {
        assert.ok(table === "appointments");
        return queryResult(table, []);
      }
    })
  });
  const customer = await repository.listAppointmentsByCustomer("customer-1", { limit: 10, offset: 20 });
  assert.deepEqual(customer, []);
  const tenant = await repository.listAppointmentsByTenant("tenant-crown", { limit: 10, offset: 20 });
  assert.deepEqual(tenant, []);
});

test("Supabase repository rejects cross-tenant row access through normal query mapping", async () => {
  let filters = [];
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      from(table) {
        const client = queryResult(table, []);
        const originalEq = client.eq;
        client.eq = (column, value) => {
          filters.push([column, value]);
          return originalEq.call(client, column, value);
        };
        return client;
      }
    })
  });
  await repository.listAppointmentsByTenant("tenant-crown");
  assert.ok(filters.some(([column, value]) => column === "tenant_id" && value === "tenant-crown"));
});

test("Supabase repository forwards rescheduling through the database RPC", async () => {
  let rpcArguments = null;
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      rpc(name, args) {
        rpcArguments = { name, args };
        return Promise.resolve({
          data: {
            id: "appointment-1",
            tenant_id: "tenant-crown",
            location_id: "location-1",
            customer_profile_id: "10000000-0000-4000-8000-000000000001",
            staff_id: "staff-1",
            service_id: "service-cut",
            start_at: args.p_start_at,
            end_at: "2026-11-24T09:00:00Z",
            price_snapshot_minor: 18000,
            duration_snapshot_minutes: 45,
            status: "confirmed",
            customer_notes: "",
            created_at: "2026-11-24T08:00:00Z",
            updated_at: "2026-11-24T08:30:00Z"
          },
          error: null
        });
      }
    })
  });
  const result = await repository.rescheduleAppointment(
    "appointment-1",
    "2026-11-24T09:00:00Z",
    "2026-11-24T09:45:00Z",
    { accessToken: "verified-token" }
  );
  assert.equal(rpcArguments.name, "reschedule_appointment");
  assert.equal(rpcArguments.args.p_appointment_id, "appointment-1");
  assert.equal(result.startAt, "2026-11-24T09:00:00Z");
});

test("Supabase repository forwards appointment status changes through the database RPC", async () => {
  let rpcArguments = null;
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      rpc(name, args) {
        rpcArguments = { name, args };
        return Promise.resolve({
          data: {
            id: "appointment-1",
            tenant_id: "tenant-crown",
            location_id: "location-1",
            customer_profile_id: "10000000-0000-4000-8000-000000000001",
            staff_id: "staff-1",
            service_id: "service-cut",
            start_at: "2026-11-24T09:00:00Z",
            end_at: "2026-11-24T09:55:00Z",
            price_snapshot_minor: 18000,
            duration_snapshot_minutes: 45,
            status: "in_progress",
            customer_notes: "",
            created_at: "2026-11-24T08:00:00Z",
            updated_at: "2026-11-24T08:30:00Z"
          },
          error: null
        });
      }
    })
  });

  const result = await repository.saveAppointment({
    id: "appointment-1",
    status: "in-progress"
  }, { accessToken: "verified-token" });

  assert.equal(rpcArguments.name, "transition_appointment");
  assert.equal(rpcArguments.args.p_appointment_id, "appointment-1");
  assert.equal(rpcArguments.args.p_next_status, "in_progress");
  assert.equal(result.status, "in-progress");
});

test("Supabase repository requests public availability without reading appointment rows", async () => {
  let rpcArguments = null;
  const repository = new SupabaseRepository({
    clientFactory: () => ({
      rpc(name, args) {
        rpcArguments = { name, args };
        return Promise.resolve({
          data: [{
            start_at: "2026-11-24T08:00:00Z",
            end_at: "2026-11-24T08:55:00Z"
          }],
          error: null
        });
      }
    })
  });

  const busyIntervals = await repository.listAppointmentsByStaff("staff-1", {
    date: "2026-11-24",
    accessToken: "verified-token"
  });

  assert.equal(rpcArguments.name, "public_staff_busy_intervals");
  assert.deepEqual(rpcArguments.args, {
    p_staff_id: "staff-1",
    p_local_date: "2026-11-24"
  });
  assert.deepEqual(busyIntervals, [{
    startAt: "2026-11-24T08:00:00Z",
    endAt: "2026-11-24T08:55:00Z"
  }]);
});
