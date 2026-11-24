import { DomainError } from "../domain/errors/domainErrors.js";

export function sendError(res, error) {
  const isDomainError = error instanceof DomainError;
  const status = isDomainError ? error.status : 500;
  const code = isDomainError ? error.code : "INTERNAL_ERROR";
  const message = isDomainError ? error.message : "An unexpected error occurred";
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify({
    success: false,
    error: { code, message }
  }));
}
