# Database Plan

This document describes the planned schema and relationships. No live database or migration is being created now.

## Core entities

### `platform_administrators`

Identifies authorized platform operators and their platform roles. Administrative access must be checked outside ordinary tenant query paths.

### `tenants`

Represents each registered salon or personal-care business. Key concepts include legal name, status, verification, owner and subscription.

### `tenant_memberships`

Links a user account to a tenant and defines role and active status.

### `branches`

Stores physical locations belonging to a tenant, including address and operating information.

### `profiles`

Stores common user profile information and links identity to customer or employee use.

### `employees`

Represents tenant staff, branch assignments and roles.

### `services`

Stores tenant service names, descriptions, durations and prices.

### `availability`

Stores recurring schedules and exceptions for branches or employees.

### `appointments`

Stores customer bookings, tenant and branch, employee, service, status and requested time.

### `customers`

Stores marketplace customer information independently of tenant-specific interactions.

### `reviews`

Stores customer ratings and comments associated with a completed appointment or tenant.

### `promotions`

Stores tenant promotional offers and validity periods.

### `memberships`

Stores customer membership or loyalty programs offered by tenants.

### `subscription_plans` and `tenant_subscriptions`

Manage platform licence tiers and each tenant's current subscription.

### `support_tickets`

Records support requests and administrative response state.

### `audit_logs`

Records privileged and sensitive changes for platform and business operations.

## Core relationships

- A tenant has many branches.
- A tenant has many memberships and employees.
- A tenant has many services, promotions and appointments.
- A branch belongs to one tenant and may host employees and appointments.
- An employee belongs to a tenant and may serve many appointments.
- A customer may have many appointments and reviews.
- An appointment belongs to one tenant, one branch, one customer and one selected service.
- A tenant subscription belongs to a tenant and a subscription plan.

## D1 tenant isolation

Every tenant-owned D1 query must include `tenant_id` in the SQL predicate and must be authorized from a verified identity. SQLite/D1 does not provide PostgreSQL Row Level Security; isolation must be enforced in repository queries and server-side authorization. Customer records must be scoped to customer ownership, and platform administrator records must use separate server-side role checks.
