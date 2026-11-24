import { createApiClient } from "../../../packages/shared-utils/apiClient.js";
import { createSupabaseBrowserAuth } from "../../../packages/shared-utils/supabaseAuth.js";

export { renderAuthView, submitAuthForm } from "../../../packages/shared-utils/authView.js";
export { formatZarMinor } from "../../../packages/shared-utils/currency.js";
export { createRealtimeSubscriptionService } from "../../../packages/shared-utils/realtimeService.js";

export const auth = createSupabaseBrowserAuth();
const api = createApiClient({
  getAccessToken: auth.getAccessToken,
  onUnauthorized: () => globalThis.document?.dispatchEvent(new CustomEvent("smartbarber:auth-required"))
});

export async function loadMarketplace() {
  const tenants = await api.get("/marketplace/tenants");
  return Promise.all(tenants.map(async (tenant) => {
    const [services, staff] = await Promise.all([
      api.get(`/marketplace/tenants/${encodeURIComponent(tenant.id)}/services`),
      api.get(`/marketplace/tenants/${encodeURIComponent(tenant.id)}/staff`)
    ]);
    return {
      id: tenant.id,
      name: tenant.businessName,
      description: tenant.businessDescription,
      services: services.map((service) => [
        service.name,
        service.price,
        service.durationMinutes,
        service.description
      ]),
      tenantServices: services,
      staff,
      locationId: staff[0]?.locationId,
      tenant
    };
  }));
}

export function getAppointments() {
  return api.get("/me/appointments");
}

export function getProfile() {
  return api.get("/me/profile");
}

export function getAvailability({ tenantId, locationId, staffId, serviceId, date }) {
  const query = new URLSearchParams({ tenantId, locationId, staffId, serviceId, date });
  return api.get(`/availability?${query}`);
}

export function createAppointment(input) {
  return api.post("/appointments", input);
}

export function getNotifications() {
  return api.get("/me/notifications");
}

export function cancelAppointment(id) {
  return api.post(`/appointments/${encodeURIComponent(id)}/cancel`);
}

export function rescheduleAppointment(id, startAt) {
  return api.patch(`/appointments/${encodeURIComponent(id)}/reschedule`, { startAt });
}
