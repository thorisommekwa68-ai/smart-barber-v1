import { AppointmentStatus } from "../enums/appointmentStatus.js";
import { DomainError } from "../errors/domainErrors.js";

const allowedTransitions = {
  [AppointmentStatus.PENDING]: [AppointmentStatus.CONFIRMED, AppointmentStatus.DECLINED, AppointmentStatus.CANCELLED, AppointmentStatus.EXPIRED],
  [AppointmentStatus.CONFIRMED]: [AppointmentStatus.IN_PROGRESS, AppointmentStatus.CANCELLED, AppointmentStatus.NO_SHOW, AppointmentStatus.EXPIRED],
  [AppointmentStatus.IN_PROGRESS]: [AppointmentStatus.COMPLETED, AppointmentStatus.CANCELLED],
  [AppointmentStatus.COMPLETED]: [],
  [AppointmentStatus.DECLINED]: [],
  [AppointmentStatus.CANCELLED]: [],
  [AppointmentStatus.EXPIRED]: [],
  [AppointmentStatus.NO_SHOW]: []
};

export function assertValidTransition(currentStatus, nextStatus) {
  if (!Object.values(AppointmentStatus).includes(nextStatus)) {
    throw new DomainError("VALIDATION_ERROR", "Unknown appointment status", 400);
  }
  if (!allowedTransitions[currentStatus]?.includes(nextStatus)) {
    throw new DomainError("INVALID_STATUS_TRANSITION",
      `Cannot change appointment from ${currentStatus} to ${nextStatus}`, 409);
  }
}

export function appointmentsOverlap(startA, endA, startB, endB) {
  return new Date(startA) < new Date(endB) && new Date(startB) < new Date(endA);
}

