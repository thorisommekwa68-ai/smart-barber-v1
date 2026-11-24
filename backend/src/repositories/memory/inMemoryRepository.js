import { RepositoryInterface } from "../interfaces/repositoryInterfaces.js";
import { AppointmentStatus } from "../../domain/enums/appointmentStatus.js";
import { MembershipRole, MembershipStatus } from "../../domain/enums/membership.js";
import { createAppointment } from "../../domain/entities/entities.js";
import { appointmentsOverlap } from "../../domain/rules/appointmentRules.js";
import { errors } from "../../domain/errors/domainErrors.js";

const clone = (value) => value == null ? value : JSON.parse(JSON.stringify(value));

export class InMemoryRepository extends RepositoryInterface {
  constructor({ seed = true } = {}) {
    super();
    this.tenants = [];
    this.locations = [];
    this.staff = [];
    this.services = [];
    this.users = [];
    this.memberships = [];
    this.appointments = [];
    this.timeOff = [];
    this.operatingHours = [];
    this.staffHours = [];
    if (seed) this.seed();
  }

  seed() {
    const now = "2026-11-23T04:40:08.775Z";
    this.users.push(
      { id: "customer-1", email: "customer@example.test", phone: "+27 82 000 0001", displayName: "Alex Customer", createdAt: now },
      { id: "customer-2", email: "second@example.test", phone: "+27 82 000 0002", displayName: "Sam Customer", createdAt: now },
      { id: "merchant-owner-1", email: "owner@crown.test", phone: null, displayName: "Crown Owner", createdAt: now },
      { id: "merchant-owner-2", email: "owner@studio.test", phone: null, displayName: "Studio Owner", createdAt: now }
    );
    this.tenants.push(
      { id: "tenant-crown", businessName: "Crown & Blade", businessDescription: "Precision cuts and grooming.", businessStatus: "active", timezone: "Africa/Johannesburg", createdAt: now },
      { id: "tenant-studio", businessName: "Studio 54 Barbers", businessDescription: "Modern barbering in the heart of the city.", businessStatus: "active", timezone: "Africa/Johannesburg", createdAt: now }
    );
    this.locations.push(
      { id: "location-crown-1", tenantId: "tenant-crown", name: "Rosebank", address: "Rosebank, Johannesburg", latitude: -26.145, longitude: 28.042, timezone: "Africa/Johannesburg" },
      { id: "location-studio-1", tenantId: "tenant-studio", name: "Braamfontein", address: "Braamfontein, Johannesburg", latitude: -26.194, longitude: 28.034, timezone: "Africa/Johannesburg" }
    );
    this.staff.push(
      { id: "staff-crown-1", tenantId: "tenant-crown", locationId: "location-crown-1", displayName: "Thabo M.", staffStatus: "active", assignedServiceIds: ["service-crown-cut", "service-crown-beard"] },
      { id: "staff-studio-1", tenantId: "tenant-studio", locationId: "location-studio-1", displayName: "Lerato K.", staffStatus: "active", assignedServiceIds: ["service-studio-cut"] }
    );
    this.services.push(
      { id: "service-crown-cut", tenantId: "tenant-crown", name: "Signature Haircut", description: "Cut, style and finish.", price: 18000, durationMinutes: 45, bufferMinutes: 10, serviceStatus: "active" },
      { id: "service-crown-beard", tenantId: "tenant-crown", name: "Beard Sculpt", description: "Beard trim and shaping.", price: 9000, durationMinutes: 30, bufferMinutes: 5, serviceStatus: "active" },
      { id: "service-studio-cut", tenantId: "tenant-studio", name: "Classic Cut", description: "Classic haircut.", price: 16000, durationMinutes: 40, bufferMinutes: 10, serviceStatus: "active" }
    );
    this.memberships.push(
      { id: "membership-crown-owner", tenantId: "tenant-crown", userId: "merchant-owner-1", role: MembershipRole.OWNER, membershipStatus: MembershipStatus.ACTIVE },
      { id: "membership-studio-owner", tenantId: "tenant-studio", userId: "merchant-owner-2", role: MembershipRole.OWNER, membershipStatus: MembershipStatus.ACTIVE }
    );
    for (const tenantId of ["tenant-crown", "tenant-studio"]) {
      for (let day = 1; day <= 6; day++) {
        this.operatingHours.push({ tenantId, dayOfWeek: day, openTime: "09:00", closeTime: "18:00" });
      }
    }
    this.staffHours.push(
      { staffId: "staff-crown-1", dayOfWeek: 1, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-crown-1", dayOfWeek: 2, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-crown-1", dayOfWeek: 3, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-crown-1", dayOfWeek: 4, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-crown-1", dayOfWeek: 5, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-crown-1", dayOfWeek: 6, startTime: "09:00", endTime: "13:00" },
      { staffId: "staff-studio-1", dayOfWeek: 1, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-studio-1", dayOfWeek: 2, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-studio-1", dayOfWeek: 3, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-studio-1", dayOfWeek: 4, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-studio-1", dayOfWeek: 5, startTime: "09:00", endTime: "18:00" },
      { staffId: "staff-studio-1", dayOfWeek: 6, startTime: "09:00", endTime: "13:00" }
    );
  }

  async findTenantById(id) { return clone(this.tenants.find((x) => x.id === id) ?? null); }
  async listTenants() { return clone(this.tenants.filter((x) => x.businessStatus === "active")); }
  async listServicesByTenant(tenantId) { return clone(this.services.filter((x) => x.tenantId === tenantId && x.serviceStatus === "active")); }
  async listStaffByTenant(tenantId) { return clone(this.staff.filter((x) => x.tenantId === tenantId && x.staffStatus === "active")); }
  async findServiceById(id) { return clone(this.services.find((x) => x.id === id) ?? null); }
  async findStaffById(id) { return clone(this.staff.find((x) => x.id === id) ?? null); }
  async findLocationById(id) { return clone(this.locations.find((x) => x.id === id) ?? null); }
  async findMembership(userId, tenantId) { return clone(this.memberships.find((x) => x.userId === userId && x.tenantId === tenantId && x.membershipStatus === MembershipStatus.ACTIVE) ?? null); }
  async findMembershipsByUser(userId) { return clone(this.memberships.filter((x) => x.userId === userId && x.membershipStatus === MembershipStatus.ACTIVE)); }
  async findUserById(id) { return clone(this.users.find((x) => x.id === id) ?? null); }
  async listAppointmentsByCustomer(customerId) { return clone(this.appointments.filter((x) => x.customerId === customerId)); }
  async listAppointmentsByTenant(tenantId) { return clone(this.appointments.filter((x) => x.tenantId === tenantId)); }
  async findAppointmentById(id) { return clone(this.appointments.find((x) => x.id === id) ?? null); }

  async createAppointmentAtomically(input) {
    const now = Date.now();
    const conflicts = this.appointments.filter((x) => {
      if (x.staffId !== input.staffId) return false;
      if ([AppointmentStatus.CANCELLED, AppointmentStatus.DECLINED, AppointmentStatus.EXPIRED, AppointmentStatus.NO_SHOW].includes(x.status)) return false;
      if (x.status === AppointmentStatus.PENDING && (!x.holdExpiresAt || new Date(x.holdExpiresAt).getTime() <= now)) return false;
      return appointmentsOverlap(input.startAt, input.endAt, x.startAt, x.endAt);
    });
    if (conflicts.length) throw errors.conflict("The selected staff member already has an overlapping appointment");
    const holdExpiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
    const appointment = createAppointment({
      ...input,
      id: input.id ?? crypto.randomUUID(),
      status: AppointmentStatus.PENDING,
      holdExpiresAt,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    this.appointments.push(clone(appointment));
    return clone(appointment);
  }

  async saveAppointment(appointment) {
    const index = this.appointments.findIndex((x) => x.id === appointment.id);
    if (index < 0) throw errors.notFound("Appointment not found");
    const updated = { ...appointment, updatedAt: new Date().toISOString() };
    this.appointments[index] = clone(updated);
    return clone(updated);
  }

  async rescheduleAppointment(appointmentId, startAt, endAt) {
    const index = this.appointments.findIndex((appointment) => appointment.id === appointmentId);
    if (index < 0) throw errors.notFound("Appointment not found");
    const appointment = this.appointments[index];
    if ([AppointmentStatus.COMPLETED, AppointmentStatus.DECLINED, AppointmentStatus.CANCELLED, AppointmentStatus.EXPIRED, AppointmentStatus.NO_SHOW].includes(appointment.status)) {
      throw errors.conflict("A terminal appointment cannot be rescheduled");
    }
    const conflict = this.appointments.some((candidate) =>
      candidate.id !== appointmentId &&
      candidate.staffId === appointment.staffId &&
      ![AppointmentStatus.CANCELLED, AppointmentStatus.DECLINED, AppointmentStatus.EXPIRED, AppointmentStatus.NO_SHOW].includes(candidate.status) &&
      (candidate.status !== AppointmentStatus.PENDING || (candidate.holdExpiresAt && new Date(candidate.holdExpiresAt).getTime() > Date.now())) &&
      appointmentsOverlap(startAt, endAt, candidate.startAt, candidate.endAt)
    );
    if (conflict) throw errors.conflict("The new time conflicts with another appointment");
    const updated = { ...appointment, startAt, endAt, updatedAt: new Date().toISOString() };
    this.appointments[index] = clone(updated);
    return clone(updated);
  }

  async getOperatingHours(tenantId, dayOfWeek) {
    return clone(this.operatingHours.find((x) => x.tenantId === tenantId && x.dayOfWeek === dayOfWeek) ?? null);
  }

  async getStaffHours(staffId, dayOfWeek) {
    return clone(this.staffHours.find((x) => x.staffId === staffId && x.dayOfWeek === dayOfWeek) ?? null);
  }

  async listTimeOff(staffId) {
    return clone(this.timeOff.filter((x) => x.staffId === staffId));
  }

  async listAppointmentsByStaff(staffId) {
    const now = Date.now();
    return clone(this.appointments.filter((appointment) =>
      appointment.staffId === staffId
      && (
        [AppointmentStatus.CONFIRMED, AppointmentStatus.IN_PROGRESS].includes(appointment.status)
        || (
          appointment.status === AppointmentStatus.PENDING
          && appointment.holdExpiresAt
          && new Date(appointment.holdExpiresAt).getTime() > now
        )
      )
    ));
  }
}
