# Platform administration architecture

Platform administration is a separate authorization domain from merchant tenant access. Tenant owners and staff must not gain platform privileges.

## Roles

- `platform_owner`: full platform and security administration
- `platform_admin`: tenant, plan and configuration administration
- `platform_support`: inspect-only and limited operational support
- `platform_auditor`: audit and monitoring read access

Platform roles are distinct from tenant roles: `owner`, `manager`, `receptionist` and `stylist`. Platform authorization must use explicit platform role assignments and must never infer privileges from `x-tenant-id` or tenant ownership.

## Domain entities

- PlatformAdministrator
- PlatformRoleAssignment
- TenantAdministrationRecord
- SubscriptionPlan
- TenantPlanAssignment
- PlatformAuditLog

## Repository contract

A platform repository should support administrator lookup, role assignment, tenant inspection/status changes, plan management, plan assignments and transactional audit insertion.

## Proposed API

- `GET /api/v1/platform/me`
- `GET /api/v1/platform/administrators`
- `PATCH /api/v1/platform/administrators/:id/status`
- `GET /api/v1/platform/tenants`
- `PATCH /api/v1/platform/tenants/:tenantId/status`
- `GET /api/v1/platform/plans`
- `POST /api/v1/platform/plans`
- `GET /api/v1/platform/monitoring/health`
- `GET /api/v1/platform/audit`

All routes remain disabled until trusted server-side authentication exists. Administrative secrets stay server-side, and sensitive mutations require audit records.
