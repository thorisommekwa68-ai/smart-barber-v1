# Smart Barber Supabase Database Schema

## Migration files

Apply only to a development/staging Supabase project:

- `supabase/migrations/20261123052800_create_smart_barber_schema.sql`
- `supabase/migrations/20261123052900_add_smart_barber_rls.sql`
- `supabase/migrations/20261123053000_create_booking_rpc.sql`
- `supabase/migrations/20261123053100_realtime_and_audit_helpers.sql`
- `supabase/migrations/202611230532_booking_availability_constraints.sql`

The SQL validation fixture is `supabase/tests/schema_validation.sql`. The migration is not deployed and no Supabase credentials or live database are referenced.

## Identity

`profiles.id` references `auth.users(id)`. An Auth trigger bootstraps display name, email and phone. The profile is the internal application identity; it is not a browser-generated identifier.

## Core tables

- profiles
- tenants
- tenant_memberships
- locations
- staff
- services
- staff_services
- operating_hours
- staff_hours
- staff_breaks
- staff_time_off
- business_holidays
- appointments
- appointment_events
- customer_relationships
- customer_favourites
- notifications
- subscription_plans
- tenant_subscriptions
- payment_transactions
- platform_administrators
- platform_role_assignments
- platform_audit_logs

## Status and lifecycle

Appointment statuses preserve existing domain values:

`pending -> confirmed -> in_progress -> completed`

Branches:

- pending -> declined/cancelled/expired
- confirmed -> cancelled/no_show/expired
- in_progress -> completed/cancelled

Terminal statuses cannot transition further.

## Money and time

- ZAR is explicit using `currency_code char(3)`.
- Money is stored in integer minor units as `bigint`.
- Appointment timestamps use `timestamptz`.
- Recurring operating hours use `time` plus the tenant timezone.
- Tenant timezone is retained for local scheduling and availability conversion.

## Seed data

No fabricated production seed data is inserted. Test fixture data is scoped to a transaction in `supabase/tests/schema_validation.sql` and is rolled back.
