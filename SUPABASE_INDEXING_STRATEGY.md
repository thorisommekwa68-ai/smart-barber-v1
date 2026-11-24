# Smart Barber Supabase Indexing Strategy

## Tenant query indexes

- `tenant_memberships(profile_id, membership_status)`
- `tenant_memberships(tenant_id, membership_status)`
- `locations(tenant_id, active)`
- `staff(tenant_id, location_id, staff_status)`
- `services(tenant_id, service_status)`
- `operating_hours(tenant_id, day_of_week)`

## Availability indexes

- `staff_hours(staff_id, day_of_week)`
- `staff_time_off(staff_id, start_at, end_at)`
- `appointments(staff_id, start_at, status)`
- `appointments(staff_id, start_at)` for overlap reads

## Appointment indexes

- `(tenant_id, start_at)`
- `(customer_profile_id, start_at)`
- `(staff_id, start_at, status)`
- partial pending hold index on `hold_expires_at`

The exclusion constraint on staff and `tstzrange` protects overlap writes. Tenant, customer and staff indexes support the existing API queries without full-table scans.

## Notification and platform indexes

- notifications `(recipient_profile_id, read_at, created_at)`
- platform audit `(created_at)`

## Future review

High-volume production should measure:

- appointment range queries
- membership joins
- marketplace discovery joins
- notification recipient reads
- payment and audit retention

Add or replace indexes from actual `pg_stat_statements` and `EXPLAIN ANALYZE` results rather than pre-optimizing unknown cardinality.
