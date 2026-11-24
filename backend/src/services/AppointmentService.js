import { AppointmentStatus } from "../domain/enums/appointmentStatus.js";
import { MembershipStatus } from "../domain/enums/membership.js";
import { errors } from "../domain/errors/domainErrors.js";
import { assertValidTransition, appointmentsOverlap } from "../domain/rules/appointmentRules.js";
import { localDateParts, minutesFromTime } from "../utils/time.js";

export class AppointmentService {
  constructor(repository) { this.repository = repository; }

  async createBooking(identity, input) {
    if (!input || typeof input !== "object") throw errors.validation("Request body is required");
    const required = ["tenantId", "locationId", "staffId", "serviceId", "startAt"];
    for (const field of required) {
      if (!input[field] || typeof input[field] !== "string") throw errors.validation(`${field} is required`);
    }
    if (!/(Z|[+-]\d{2}:\d{2})$/.test(input.startAt)) throw errors.validation("startAt must include ISO 8601 timezone information");
    const start = new Date(input.startAt);
    if (Number.isNaN(start.getTime())) throw errors.validation("startAt is not a valid ISO 8601 timestamp");
    if (start.getTime() <= Date.now()) throw errors.conflict("Bookings cannot be created in the past");

    const tenant = await this.repository.findTenantById(input.tenantId);
    const location = await this.repository.findLocationById(input.locationId);
    const service = await this.repository.findServiceById(input.serviceId);
    const staff = await this.repository.findStaffById(input.staffId);
    if (!tenant || tenant.businessStatus !== "active") throw errors.notFound("Business not found");
    if (!location || location.tenantId !== input.tenantId) throw errors.validation("Invalid location selection");
    if (!service || service.tenantId !== input.tenantId || service.serviceStatus !== "active") throw errors.validation("Invalid service selection");
    if (!staff || staff.tenantId !== input.tenantId || staff.locationId !== input.locationId || staff.staffStatus !== "active") {
      throw errors.validation("Invalid staff selection");
    }
    if (!staff.assignedServiceIds.includes(service.id)) throw errors.validation("The selected staff member cannot perform this service");

    const totalMinutes = service.durationMinutes + service.bufferMinutes;
    const end = new Date(start.getTime() + totalMinutes * 60000);
    const endAt = end.toISOString();

    const local = localDateParts(start, tenant.timezone);
    const dayOfWeek = local.dayOfWeek;
    const tenantHours = await this.repository.getOperatingHours(input.tenantId, dayOfWeek);
    const staffHours = await this.repository.getStaffHours(staff.id, dayOfWeek);
    if (!tenantHours || !staffHours) throw errors.conflict("The business or staff member is unavailable at this time");

    const startMinutes = minutesFromTime(local.time);
    const localEnd = localDateParts(end, tenant.timezone);
    const endMinutes = minutesFromTime(localEnd.time);
    if (startMinutes < minutesFromTime(tenantHours.openTime) || endMinutes > minutesFromTime(tenantHours.closeTime) ||
        startMinutes < minutesFromTime(staffHours.startTime) || endMinutes > minutesFromTime(staffHours.endTime)) {
      throw errors.conflict("The appointment is outside operating or staff working hours");
    }

    const timeOff = await this.repository.listTimeOff(staff.id);
    if (timeOff.some((period) => appointmentsOverlap(start, end, period.startAt, period.endAt))) {
      throw errors.conflict("The staff member is unavailable at this time");
    }

    return this.repository.createAppointmentAtomically({
      tenantId: tenant.id,
      locationId: location.id,
      customerId: identity.id,
      staffId: staff.id,
      serviceId: service.id,
      startAt: start.toISOString(),
      endAt,
      priceSnapshot: service.price,
      durationSnapshot: service.durationMinutes,
      customerNotes: typeof input.customerNotes === "string" ? input.customerNotes.trim().slice(0, 1000) : ""
    }, { accessToken: identity.accessToken });
  }

  async listMyAppointments(identity) {
    return this.repository.listAppointmentsByCustomer(identity.id, { accessToken: identity.accessToken });
  }

  async assertMerchant(identity, tenantId) {
    const membership = await this.repository.findMembership(identity.id, tenantId, { accessToken: identity.accessToken });
    if (!membership || membership.membershipStatus !== MembershipStatus.ACTIVE) {
      throw errors.forbidden("User is not an active member of this tenant");
    }
    return membership;
  }

  async listMerchantAppointments(identity, tenantId) {
    await this.assertMerchant(identity, tenantId);
    return this.repository.listAppointmentsByTenant(tenantId, { accessToken: identity.accessToken });
  }

  async merchantTransition(identity, tenantId, appointmentId, nextStatus) {
    await this.assertMerchant(identity, tenantId);
    const appointment = await this.repository.findAppointmentById(appointmentId, { accessToken: identity.accessToken });
    if (!appointment) throw errors.notFound("Appointment not found");
    if (appointment.tenantId !== tenantId) throw errors.forbidden("Appointment belongs to another tenant");
    assertValidTransition(appointment.status, nextStatus);
    appointment.status = nextStatus;
    return this.repository.saveAppointment(appointment, { accessToken: identity.accessToken });
  }

  async cancelAppointment(identity, appointmentId) {
    const appointment = await this.repository.findAppointmentById(appointmentId, { accessToken: identity.accessToken });
    if (!appointment) throw errors.notFound("Appointment not found");
    if (appointment.customerId !== identity.id) throw errors.forbidden("Cannot cancel another customer's appointment");
    assertValidTransition(appointment.status, AppointmentStatus.CANCELLED);
    appointment.status = AppointmentStatus.CANCELLED;
    return this.repository.saveAppointment(appointment, { accessToken: identity.accessToken });
  }

  async rescheduleAppointment(identity, appointmentId, startAt) {
    const appointment = await this.repository.findAppointmentById(appointmentId, { accessToken: identity.accessToken });
    if (!appointment) throw errors.notFound("Appointment not found");
    if (appointment.customerId !== identity.id) throw errors.forbidden("Cannot reschedule another customer's appointment");
    const start = new Date(startAt);
    if (Number.isNaN(start.getTime()) || start.getTime() <= Date.now()) throw errors.conflict("Rescheduled start time must be in the future");
    const end = new Date(start.getTime() + appointment.durationSnapshot * 60000);
    return this.repository.rescheduleAppointment(appointmentId, start.toISOString(), end.toISOString(), { accessToken: identity.accessToken });
  }
}
