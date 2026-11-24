export class DomainError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.name = "DomainError";
    this.code = code;
    this.status = status;
  }
}

export const errors = {
  validation: (message) => new DomainError("VALIDATION_ERROR", message, 400),
  payloadTooLarge: (message) => new DomainError("PAYLOAD_TOO_LARGE", message, 413),
  methodNotAllowed: (message) => new DomainError("METHOD_NOT_ALLOWED", message, 405),
  unauthorised: (message = "Authentication required") => new DomainError("UNAUTHORISED", message, 401),
  forbidden: (message = "Access denied") => new DomainError("FORBIDDEN", message, 403),
  notFound: (message = "Resource not found") => new DomainError("NOT_FOUND", message, 404),
  conflict: (message) => new DomainError("CONFLICT", message, 409)
};

