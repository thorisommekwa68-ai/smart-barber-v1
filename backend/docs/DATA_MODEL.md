# Data Model

## Entities

User, Tenant, TenantMembership, Location, Staff, Service and Appointment are represented by plain JavaScript objects.

## Important relationships

- Every appointment belongs to one tenant and references one location, customer, staff member and service.
- Tenant memberships grant merchant roles and tenant scope.
- Services and staff belong to tenants. Staff may be assigned to selected services.
- Appointment price and duration are snapshots stored at booking creation.
- Appointment timestamps are ISO 8601 strings with timezone information.

## Status transitions

Pending can become confirmed, declined, cancelled or expired. Confirmed can become in progress, cancelled, no-show or expired. In-progress can become completed or cancelled. Terminal statuses cannot transition further.
