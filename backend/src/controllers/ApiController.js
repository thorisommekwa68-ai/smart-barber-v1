import { AppointmentStatus } from "../domain/enums/appointmentStatus.js";

export class ApiController {
  constructor({ marketplace, availability, appointments, media, identityProvider }) {
    this.marketplace = marketplace;
    this.availability = availability;
    this.appointments = appointments;
    this.media = media;
    this.identityProvider = identityProvider;
  }

  success(res, data, message = "Operation completed successfully", status = 200) {
    res.statusCode = status;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ success: true, data, message }));
  }

  async authenticate(req) { return this.identityProvider.authenticate(req); }

  async listTenants(req, res) { this.success(res, await this.marketplace.listTenants(), "Businesses retrieved successfully"); }
  async myProfile(req, res) {
    const identity = await this.authenticate(req);
    this.success(res, {
      id: identity.id,
      displayName: identity.displayName,
      email: identity.email ?? null,
      phone: identity.phone ?? null,
      memberships: identity.memberships ?? []
    }, "Profile retrieved successfully");
  }
  async getTenant(req, res, params) { this.success(res, await this.marketplace.getTenant(params.tenantId)); }
  async listServices(req, res, params) { this.success(res, await this.marketplace.listServices(params.tenantId)); }
  async listStaff(req, res, params) { this.success(res, await this.marketplace.listStaff(params.tenantId)); }

  async getAvailability(req, res, query) {
    this.success(res, await this.availability.getSlots({
      tenantId: query.tenantId,
      locationId: query.locationId,
      staffId: query.staffId,
      serviceId: query.serviceId,
      date: query.date
    }));
  }

  async createAppointment(req, res, body) {
    const identity = await this.authenticate(req);
    const appointment = await this.appointments.createBooking(identity, body);
    this.success(res, appointment, "Booking request created successfully", 201);
  }

  async myAppointments(req, res) {
    const identity = await this.authenticate(req);
    this.success(res, await this.appointments.listMyAppointments(identity));
  }

  async merchantAppointments(req, res, query = {}) {
    const identity = await this.authenticate(req);
    const tenantId = identity.provider === "supabase"
      ? (query.tenantId || identity.tenantId)
      : identity.tenantId;
    this.success(res, await this.appointments.listMerchantAppointments(identity, tenantId));
  }

  async merchantTransition(req, res, params, tenantId, nextStatus) {
    const identity = await this.authenticate(req);
    const resolvedTenantId = tenantId ?? identity.tenantId;
    const appointment = await this.appointments.merchantTransition(identity, resolvedTenantId, params.appointmentId, nextStatus);
    this.success(res, appointment, "Appointment updated successfully");
  }

  async accept(req, res, params, tenantId) { await this.merchantTransition(req, res, params, tenantId, AppointmentStatus.CONFIRMED); }
  async decline(req, res, params, tenantId) { await this.merchantTransition(req, res, params, tenantId, AppointmentStatus.DECLINED); }
  async start(req, res, params, tenantId) { await this.merchantTransition(req, res, params, tenantId, AppointmentStatus.IN_PROGRESS); }
  async complete(req, res, params, tenantId) { await this.merchantTransition(req, res, params, tenantId, AppointmentStatus.COMPLETED); }
  async noShow(req, res, params, tenantId) { await this.merchantTransition(req, res, params, tenantId, AppointmentStatus.NO_SHOW); }

  async cancel(req, res, params) {
    const identity = await this.authenticate(req);
    const appointment = await this.appointments.cancelAppointment(identity, params.appointmentId);
    this.success(res, appointment, "Appointment cancelled successfully");
  }

  async reschedule(req, res, params, body) {
    const identity = await this.authenticate(req);
    const appointment = await this.appointments.rescheduleAppointment(identity, params.appointmentId, body?.startAt);
    this.success(res, appointment, "Appointment rescheduled successfully");
  }

  async createMediaUpload(req, res, body) {
    const identity = await this.authenticate(req);
    if (!this.media) throw new Error("Storage is unavailable");
    const result = await this.media.createUpload(identity, body);
    this.success(res, result, "Secure media upload prepared", 201);
  }

  async createMediaSignedUrl(req, res, params) {
    const identity = await this.authenticate(req);
    if (!this.media) throw new Error("Storage is unavailable");
    const result = await this.media.createSignedReadUrl(identity, params.assetId);
    this.success(res, result, "Signed media URL created");
  }

  async deleteMedia(req, res, params) {
    const identity = await this.authenticate(req);
    if (!this.media) throw new Error("Storage is unavailable");
    await this.media.deleteMedia(identity, params.assetId);
    this.success(res, { assetId: params.assetId }, "Media deleted successfully");
  }

  async myNotifications(req, res) {
    const identity = await this.authenticate(req);
    const notifications = await this.marketplace.repository?.listNotifications?.(identity.id, {
      accessToken: identity.accessToken
    });
    this.success(res, notifications || [], "Notifications retrieved successfully");
  }

  async merchantNotifications(req, res) {
    const identity = await this.authenticate(req);
    const notifications = await this.marketplace.repository?.listNotifications?.(identity.id, {
      accessToken: identity.accessToken
    });
    this.success(res, notifications || [], "Notifications retrieved successfully");
  }
}
