# Smart Barber Supabase Relationships

## Identity and membership

```text
auth.users
  -> profiles
  -> tenant_memberships
  -> tenants
```

Each profile can belong to multiple tenants. Membership roles are tenant-specific.

## Business hierarchy

```text
tenants
  -> locations
  -> staff
  -> services
  -> operating_hours
  -> tenant_subscriptions
  -> notifications
```

Staff must belong to a location and tenant. Staff-service assignments require staff and service to belong to the same tenant.

## Appointment relationships

```text
profile (customer)
  -> appointments
  <- tenant
  <- location
  <- staff
  <- service
  -> appointment_events
  -> payment_transactions
```

The appointment relationship triggers validate tenant consistency and staff/location/service assignments.

## Platform hierarchy

```text
profiles
  -> platform_administrators
  -> platform_role_assignments
  -> platform_audit_logs
```

Platform roles are separate from tenant membership roles.

## Foreign-key policy

Tenant-owned master data uses cascade delete where the entity is fully owned. Appointments and payments use restrict delete or set-null for historical references. Appointment events cascade with the appointment.
