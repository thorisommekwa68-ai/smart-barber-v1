import { createClient } from "@supabase/supabase-js";
import { RepositoryInterface } from "../interfaces/repositoryInterfaces.js";
import { errors } from "../../domain/errors/domainErrors.js";
import { createAppointment } from "../../domain/entities/entities.js";

const APPOINTMENT_COLUMNS = [
  "id",
  "tenant_id",
  "location_id",
  "customer_profile_id",
  "staff_id",
  "service_id",
  "start_at",
  "end_at",
  "price_snapshot_minor",
  "duration_snapshot_minutes",
  "currency_code",
  "status",
  "customer_notes",
  "hold_expires_at",
  "created_at",
  "updated_at"
].join(",");

export class SupabaseRepository extends RepositoryInterface {
  constructor({ supabaseUrl, supabaseAnonKey, accessToken = null, clientFactory = null } = {}) {
    super();
    if (!clientFactory && (!supabaseUrl || !supabaseAnonKey)) throw new Error("SUPABASE_URL and SUPABASE_ANON_KEY are required");
    this.supabaseUrl = supabaseUrl;
    this.supabaseAnonKey = supabaseAnonKey;
    this.defaultAccessToken = accessToken;
    this.clientFactory = clientFactory;
  }

  client(accessToken = null) {
    const token = accessToken || this.defaultAccessToken;
    if (this.clientFactory) return this.clientFactory(token);
    return createClient(this.supabaseUrl, this.supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: token ? { headers: { Authorization: `Bearer ${token}` } } : {}
    });
  }

  translate(error, fallback = "Database operation failed") {
    if (!error) return null;
    if (error.code === "23505") throw errors.conflict("The requested record already exists");
    if (error.code === "23P01") throw errors.conflict("The selected time conflicts with another appointment");
    if (error.code === "42501") throw errors.forbidden("You do not have permission for this operation");
    if (error.code === "PGRST116") throw errors.notFound("Resource not found");
    throw errors.conflict(fallback);
  }

  async findTenantById(id) {
    const { data, error } = await this.client().from("tenants").select("*").eq("id", id).maybeSingle();
    this.translate(error);
    return data ? {
      id: data.id,
      businessName: data.business_name,
      businessDescription: data.business_description,
      businessStatus: data.business_status,
      timezone: data.timezone,
      createdAt: data.created_at
    } : null;
  }

  async listTenants({ limit = 50, offset = 0 } = {}) {
    const { data, error } = await this.client().from("tenants")
      .select("id,business_name,business_description,business_status,timezone,created_at")
      .eq("business_status", "active")
      .order("business_name")
      .range(offset, offset + limit - 1);
    this.translate(error);
    return (data || []).map((data) => ({
      id: data.id,
      businessName: data.business_name,
      businessDescription: data.business_description,
      businessStatus: data.business_status,
      timezone: data.timezone,
      createdAt: data.created_at
    }));
  }

  async listServicesByTenant(tenantId, { limit = 100, offset = 0 } = {}) {
    const { data, error } = await this.client().from("services")
      .select("*").eq("tenant_id", tenantId).eq("service_status", "active")
      .order("name").range(offset, offset + limit - 1);
    this.translate(error);
    return (data || []).map((service) => ({
      id: service.id,
      tenantId: service.tenant_id,
      name: service.name,
      description: service.description,
      price: Number(service.price_minor),
      durationMinutes: service.duration_minutes,
      bufferMinutes: service.buffer_minutes,
      serviceStatus: service.service_status
    }));
  }

  async listStaffByTenant(tenantId, { limit = 100, offset = 0 } = {}) {
    const { data, error } = await this.client().from("staff")
      .select("*,staff_services(service_id)").eq("tenant_id", tenantId).eq("staff_status", "active")
      .order("display_name").range(offset, offset + limit - 1);
    this.translate(error);
    return (data || []).map((staff) => ({
      id: staff.id,
      tenantId: staff.tenant_id,
      locationId: staff.location_id,
      displayName: staff.display_name,
      staffStatus: staff.staff_status,
      assignedServiceIds: (staff.staff_services || []).map((assignment) => assignment.service_id)
    }));
  }

  async findServiceById(id) {
    const { data, error } = await this.client().from("services").select("*").eq("id", id).maybeSingle();
    this.translate(error);
    if (!data) return null;
    return {
      id: data.id,
      tenantId: data.tenant_id,
      name: data.name,
      description: data.description,
      price: Number(data.price_minor),
      durationMinutes: data.duration_minutes,
      bufferMinutes: data.buffer_minutes,
      serviceStatus: data.service_status
    };
  }

  async findStaffById(id) {
    const { data, error } = await this.client().from("staff")
      .select("*,staff_services(service_id)").eq("id", id).maybeSingle();
    this.translate(error);
    if (!data) return null;
    return {
      id: data.id,
      tenantId: data.tenant_id,
      locationId: data.location_id,
      displayName: data.display_name,
      staffStatus: data.staff_status,
      assignedServiceIds: (data.staff_services || []).map((assignment) => assignment.service_id)
    };
  }

  async findLocationById(id) {
    const { data, error } = await this.client().from("locations").select("*").eq("id", id).maybeSingle();
    this.translate(error);
    return data ? {
      id: data.id,
      tenantId: data.tenant_id,
      name: data.name,
      address: data.address,
      latitude: data.latitude,
      longitude: data.longitude,
      timezone: data.timezone
    } : null;
  }

  async findUserById(id, { accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("profiles").select("*").eq("id", id).maybeSingle();
    this.translate(error);
    return data ? {
      id: data.id,
      email: data.email,
      phone: data.phone,
      displayName: data.display_name,
      active: data.active,
      createdAt: data.created_at
    } : null;
  }

  async findMembership(userId, tenantId, { accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("tenant_memberships")
      .select("*").eq("profile_id", userId).eq("tenant_id", tenantId)
      .eq("membership_status", "active").maybeSingle();
    this.translate(error);
    return data ? {
      id: data.id,
      tenantId: data.tenant_id,
      userId: data.profile_id,
      role: data.role,
      membershipStatus: data.membership_status
    } : null;
  }

  async findMembershipsByUser(userId, { accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("tenant_memberships")
      .select("*").eq("profile_id", userId).eq("membership_status", "active");
    this.translate(error);
    return (data || []).map((membership) => ({
      id: membership.id,
      tenantId: membership.tenant_id,
      userId: membership.profile_id,
      role: membership.role,
      membershipStatus: membership.membership_status
    }));
  }

  mapAppointment(row) {
    if (!row) return null;
    return createAppointment({
      id: row.id,
      tenantId: row.tenant_id,
      locationId: row.location_id,
      customerId: row.customer_profile_id,
      staffId: row.staff_id,
      serviceId: row.service_id,
      startAt: row.start_at,
      endAt: row.end_at,
      priceSnapshot: Number(row.price_snapshot_minor),
      durationSnapshot: row.duration_snapshot_minutes,
      status: row.status === "in_progress" ? "in-progress" : row.status === "no_show" ? "no-show" : row.status,
      customerNotes: row.customer_notes,
      holdExpiresAt: row.hold_expires_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    });
  }

  async listAppointmentsByCustomer(customerId, { limit = 50, offset = 0, accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("appointments")
      .select(APPOINTMENT_COLUMNS).eq("customer_profile_id", customerId)
      .order("start_at", { ascending: false }).range(offset, offset + limit - 1);
    this.translate(error);
    return (data || []).map((row) => this.mapAppointment(row));
  }

  async listAppointmentsByTenant(tenantId, { limit = 50, offset = 0, accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("appointments")
      .select(APPOINTMENT_COLUMNS).eq("tenant_id", tenantId)
      .order("start_at", { ascending: true }).range(offset, offset + limit - 1);
    this.translate(error);
    return (data || []).map((row) => this.mapAppointment(row));
  }

  async listAppointmentsByStaff(staffId, { date, accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).rpc("public_staff_busy_intervals", {
      p_staff_id: staffId,
      p_local_date: date
    });
    this.translate(error);
    return (data || []).map((row) => ({
      startAt: row.start_at,
      endAt: row.end_at
    }));
  }

  async findAppointmentById(id, { accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("appointments")
      .select(APPOINTMENT_COLUMNS).eq("id", id).maybeSingle();
    this.translate(error);
    return this.mapAppointment(data);
  }

  async createAppointmentAtomically(input, { accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).rpc("create_appointment", {
      p_tenant_id: input.tenantId,
      p_location_id: input.locationId,
      p_staff_id: input.staffId,
      p_service_id: input.serviceId,
      p_start_at: input.startAt,
      p_customer_notes: input.customerNotes || ""
    });
    if (error) {
      if (error.code === "P0001") throw errors.conflict("The booking could not be created");
      this.translate(error);
    }
    return this.mapAppointment(data);
  }

  async saveAppointment(appointment, { accessToken = null } = {}) {
    const status = appointment.status === "in-progress" ? "in_progress" : appointment.status === "no-show" ? "no_show" : appointment.status;
    const { data, error } = await this.client(accessToken).rpc("transition_appointment", {
      p_appointment_id: appointment.id,
      p_next_status: status
    });
    if (error) this.translate(error);
    if (!data) throw errors.notFound("Appointment not found");
    return this.mapAppointment(data);
  }

  async rescheduleAppointment(appointmentId, startAt, endAt, { accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).rpc("reschedule_appointment", {
      p_appointment_id: appointmentId,
      p_start_at: startAt
    });
    if (error) {
      if (error.code === "23P01") throw errors.conflict("The new time conflicts with another appointment");
      this.translate(error);
    }
    if (!data) throw errors.notFound("Appointment not found");
    return this.mapAppointment(data);
  }

  async getOperatingHours(tenantId, dayOfWeek) {
    const { data, error } = await this.client().from("operating_hours")
      .select("*").eq("tenant_id", tenantId).eq("day_of_week", dayOfWeek).maybeSingle();
    this.translate(error);
    return data ? { tenantId: data.tenant_id, dayOfWeek: data.day_of_week, openTime: data.open_time, closeTime: data.close_time } : null;
  }

  async getStaffHours(staffId, dayOfWeek) {
    const { data, error } = await this.client().from("staff_hours")
      .select("*").eq("staff_id", staffId).eq("day_of_week", dayOfWeek).maybeSingle();
    this.translate(error);
    return data ? { staffId: data.staff_id, dayOfWeek: data.day_of_week, startTime: data.start_time, endTime: data.end_time } : null;
  }

  async listTimeOff(staffId) {
    const { data, error } = await this.client().from("staff_time_off").select("*").eq("staff_id", staffId);
    this.translate(error);
    return (data || []).map((period) => ({ id: period.id, staffId: period.staff_id, startAt: period.start_at, endAt: period.end_at, reason: period.reason }));
  }

  async listFavourites(customerId, { limit = 50, offset = 0, accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("customer_favourites")
      .select("*").eq("customer_profile_id", customerId)
      .range(offset, offset + limit - 1);
    this.translate(error);
    return data || [];
  }

  async listNotifications(recipientProfileId, { limit = 50, offset = 0, accessToken = null } = {}) {
    const { data, error } = await this.client(accessToken).from("notifications")
      .select("*").eq("recipient_profile_id", recipientProfileId)
      .is("read_at", null).order("created_at", { ascending: false })
      .range(offset, offset + limit - 1);
    this.translate(error);
    return data || [];
  }
}
