export const createTenant = (input) => ({
  id: input.id,
  businessName: input.businessName,
  businessDescription: input.businessDescription ?? "",
  businessStatus: input.businessStatus ?? "active",
  timezone: input.timezone ?? "Africa/Johannesburg",
  createdAt: input.createdAt ?? new Date().toISOString()
});

export const createAppointment = (input) => ({
  id: input.id,
  tenantId: input.tenantId,
  locationId: input.locationId,
  customerId: input.customerId,
  staffId: input.staffId,
  serviceId: input.serviceId,
  startAt: input.startAt,
  endAt: input.endAt,
  priceSnapshot: input.priceSnapshot,
  durationSnapshot: input.durationSnapshot,
  status: input.status,
  customerNotes: input.customerNotes ?? "",
  holdExpiresAt: input.holdExpiresAt ?? null,
  createdAt: input.createdAt ?? new Date().toISOString(),
  updatedAt: input.updatedAt ?? new Date().toISOString()
});
