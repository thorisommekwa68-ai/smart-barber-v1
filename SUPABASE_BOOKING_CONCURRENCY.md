# Smart Barber Booking Concurrency Strategy

## Database-level protection

Appointments use a PostgreSQL exclusion constraint:

```text
staff_id = 
and tstzrange(start_at, end_at, '[)') overlaps
where status IN (pending, confirmed, in_progress)
```

This excludes overlap only for active booking statuses.

The booking RPC additionally:

- acquires `pg_advisory_xact_lock` for the staff UUID
- derives end time from server-side service duration and buffer
- validates tenant/location/staff/service relationships
- checks tenant and staff hours
- checks holidays, breaks and time-off
- rechecks overlapping active appointments
- ignores expired pending holds
- inserts one appointment snapshot and event transactionally

## Pending holds

Pending appointments require `hold_expires_at`. The RPC excludes pending holds whose hold expires at or before `now()`. The `expire_pending_appointment_holds()` function can update expired holds to `expired`. A scheduled invocation is still required in production.

## Buffer handling

The service duration and buffer are added to `p_start_at` for the hold/conflict interval. The returned appointment `end_at` is the duration-only end. The RPC currently uses the duration-plus-buffer interval for overlap protection.

## Concurrency behavior

Advisory locking serializes one staff across concurrent RPC transactions. The exclusion constraint remains the final database guard if an insert occurs outside the RPC or in a concurrent code path.

## Invalid relationship protection

Before insert/update, triggers verify:

- location belongs to appointment tenant
- staff belongs to appointment tenant and location
- service belongs to appointment tenant
- staff is assigned to service
- appointment time range is valid

The lifecycle trigger preserves existing pending/confirmed/in-progress terminal transition rules.
