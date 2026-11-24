import { errors } from "../domain/errors/domainErrors.js";
import { appointmentsOverlap } from "../domain/rules/appointmentRules.js";
import { localDateParts, minutesFromTime, strictDateKey, zonedDateTimeToIso } from "../utils/time.js";

export class AvailabilityService {
  constructor(repository) { this.repository = repository; }

  async getSlots({ tenantId, locationId, staffId, serviceId, date }) {
    if (!tenantId || !staffId || !serviceId || !date) {
      throw errors.validation("tenantId, staffId, serviceId and date are required");
    }
    if (!strictDateKey(date)) throw errors.validation("date must be a valid YYYY-MM-DD value");
    const tenant = await this.repository.findTenantById(tenantId);
    const staff = await this.repository.findStaffById(staffId);
    const service = await this.repository.findServiceById(serviceId);
    if (!tenant || tenant.businessStatus !== "active") throw errors.notFound("Active business not found");
    if (!service || service.tenantId !== tenantId || service.serviceStatus !== "active") {
      throw errors.validation("The selected service is inactive or does not belong to this tenant");
    }
    if (!staff || staff.tenantId !== tenantId || staff.staffStatus !== "active") {
      throw errors.validation("The selected staff member is inactive or does not belong to this tenant");
    }
    if (!staff.assignedServiceIds.includes(serviceId)) {
      throw errors.validation("The selected service is not provided by this staff member");
    }
    if (!locationId) throw errors.validation("locationId is required");
    const location = await this.repository.findLocationById(locationId);
    if (!location || location.tenantId !== tenantId || location.id !== staff.locationId) {
      throw errors.validation("The location and staff member do not belong to this tenant");
    }
    const noon = zonedDateTimeToIso(date, "12:00", tenant.timezone);
    const day = localDateParts(new Date(noon), tenant.timezone).dayOfWeek;
    const tenantHours = await this.repository.getOperatingHours(tenantId, day);
    const hours = await this.repository.getStaffHours(staffId, day);
    if (!tenantHours || !hours) return [];
    const slots = [];
    let minutes = Math.max(minutesFromTime(hours.startTime), minutesFromTime(tenantHours.openTime));
    const endMinutes = Math.min(minutesFromTime(hours.endTime), minutesFromTime(tenantHours.closeTime));
    const appointments = await this.repository.listAppointmentsByStaff(staffId, { date });
    const timeOff = await this.repository.listTimeOff(staffId);
    const now = Date.now();
    const { year, month, day: dateDay } = strictDateKey(date);
    while (minutes + service.durationMinutes + service.bufferMinutes <= endMinutes) {
      const hour = String(Math.floor(minutes / 60)).padStart(2, "0");
      const minute = String(minutes % 60).padStart(2, "0");
      const iso = zonedDateTimeToIso(`${year}-${String(month).padStart(2,"0")}-${String(dateDay).padStart(2,"0")}`, `${hour}:${minute}`, tenant.timezone);
      const serviceEnd = new Date(new Date(iso).getTime() + service.durationMinutes * 60000).toISOString();
      const busyEnd = new Date(new Date(iso).getTime() + (service.durationMinutes + service.bufferMinutes) * 60000).toISOString();
      const isPast = new Date(iso).getTime() <= now;
      const busy = isPast
        || appointments.some((appointment) => appointmentsOverlap(iso, busyEnd, appointment.startAt, appointment.endAt))
        || timeOff.some((period) => appointmentsOverlap(iso, busyEnd, period.startAt, period.endAt));
      if (!busy) slots.push({ startAt: iso, endAt: serviceEnd, durationMinutes: service.durationMinutes });
      minutes += 30;
    }
    return slots;
  }
}
