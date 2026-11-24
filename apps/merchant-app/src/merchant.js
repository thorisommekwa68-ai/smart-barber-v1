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

export function getTenants() {
  return api.get("/marketplace/tenants");
}

export function getProfile() {
  return api.get("/me/profile");
}

export function getTenant(id) {
  return api.get(`/marketplace/tenants/${encodeURIComponent(id)}`);
}

export function getAppointments(tenantId) {
  return api.get(tenantId ? `/merchant/appointments?tenantId=${encodeURIComponent(tenantId)}` : "/merchant/appointments");
}

export function getServices(tenantId) {
  return api.get(`/marketplace/tenants/${encodeURIComponent(tenantId)}/services`);
}

export function getStaff(tenantId) {
  return api.get(`/marketplace/tenants/${encodeURIComponent(tenantId)}/staff`);
}

export function transitionAppointment(id, action, tenantId) {
  const tenantQuery = tenantId ? `?tenantId=${encodeURIComponent(tenantId)}` : "";
  return api.patch(`/merchant/appointments/${encodeURIComponent(id)}/${action}${tenantQuery}`);
}

export function getNotifications() {
  return api.get("/merchant/notifications");
}
