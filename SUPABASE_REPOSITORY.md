# Supabase Repository

## Adapter

`backend/src/repositories/supabase/supabaseRepository.js` implements `RepositoryInterface` for PostgreSQL/Supabase data.

The in-memory repository remains the default and remains available for tests and local development.

## Repository selection

Set `REPOSITORY_TYPE=supabase` and provide:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Do not configure `SUPABASE_SERVICE_ROLE_KEY` for normal request repositories.

The Supabase client is request-scoped with the verified bearer access token. This allows RLS-aware operations and prevents a shared process token from crossing user boundaries.

## Domain mapping

The adapter maps snake_case PostgreSQL fields to existing camelCase/domain fields:

- tenant, location, staff and service records
- profile and membership records
- appointments and snapshots
- operating/staff hours and time-off
- favourites and notifications

## Atomic booking

Booking creation calls the PostgreSQL `create_appointment` RPC. The RPC uses:

- server-side relationship checks
- staff advisory locking
- operating/time-off/break validation
- overlap recheck
- the appointment exclusion constraint
- immutable server-derived price/duration snapshots

## Tenant isolation

Every tenant-owned repository method includes `tenant_id` filtering or membership lookup. User appointment queries include `customer_profile_id`. Authorization remains revalidated in the service and by RLS/database policies.

## Pagination

Tenant and customer list methods accept `limit` and `offset`. Notifications and favourites have the same pagination pattern.

## Error handling

PostgreSQL and Supabase codes are translated into domain conflicts, permissions or not-found errors. Raw SQL messages are not returned to clients.

## Worker persistence

The Worker must select `REPOSITORY_TYPE=supabase` and must not use `InMemoryRepository` as persistent state. A Worker direct-Postgres or pooled connection strategy requires separate hosting approval; the Supabase SDK/RPC path is the recommended HTTP-compatible implementation.
