# Smart Barber Supabase Target Architecture

## Target direction

```text
Customer / Merchant / Deployment browser
                |
                v
Supabase Auth (verified JWT)
                |
                v
Node API (existing controllers/services/domain)
                |
       +--------+--------+
       |                 |
       v                 v
Supabase PostgreSQL  Supabase Storage
       |
       v
Supabase Realtime
```

The Node API remains the HTTP application boundary. Frontends preserve their HTML/CSS design and call the existing `/api/v1` contracts. Supabase is the persistent identity, database, storage and realtime provider.

## Identity architecture

Add a separate `profiles` table whose primary key is the UUID in `auth.users.id`:

- `profiles.id = auth.uid()`
- display name and contact fields
- active status
- created/updated timestamps

On first verified authentication, the server or Auth hook creates or verifies the profile. The backend must never infer a user profile from an email supplied by a browser.

## Authentication adapter

Replace `MockIdentityProvider` with a `SupabaseJwtIdentityProvider` that:

1. Extracts a bearer JWT.
2. Verifies it against Supabase JWT configuration.
3. Resolves `auth.users.id`.
4. Loads the application profile.
5. Loads active tenant memberships only through the server.
6. Returns an internal authenticated identity object.

The old `x-user-id` and `x-tenant-id` headers must be removed from production code and retained only behind an explicit local-development flag.

## Node API runtime

Keep `createApplication`, `ApiController`, `AppointmentService`, `AvailabilityService`, `MarketplaceService`, routes and domain rules. Inject a new `SupabaseRepository` through the existing repository interface.

The Node runtime should use Supabase server credentials only for operations that require elevated authorization or repository-wide joins. Browser-direct Supabase calls should use the public anon key and RLS.

## Supabase client strategy

Recommended runtime split:

- **Anon-key browser client**: public discovery and any intentionally browser-direct approved operations.
- **Verified-JWT Node client**: server operations using the caller's token for RLS-aware reads.
- **Service-role Node client**: only tightly scoped privileged operations that cannot safely use RLS and have explicit service-layer authorization.

The service-role key must stay server-side. A service-role client bypasses RLS and does not make the operation safe.

## Repository implementation

Implement `SupabaseRepository` with the same domain-shaped returns currently expected by services:

- tenant and public business queries
- tenant-scoped service/staff/location queries
- membership lookup
- profile lookup
- customer/tenant appointment queries
- operating/staff hours and time-off reads
- atomic booking creation
- lifecycle mutations

Tenant-owned methods must accept a resolved tenant ID and use either RLS or explicit SQL predicates. Repository results must not depend on frontend tenant fields.

## PostgreSQL business rules

The existing domain rules should remain:

- active tenant/service/staff checks
- location/staff relationship checks
- tenant and staff operating hours
- staff time-off
- timezone handling in Africa/Johannesburg
- ISO UTC timestamps
- integer ZAR minor units
- immutable price/duration snapshots
- appointment status transitions
- pending hold expiry

Price and duration snapshots should be server-derived; API request fields for status, price and duration must be ignored or rejected.

## Booking concurrency

Implement bookings in a PostgreSQL transaction or RPC:

- serialize the staff conflict interval
- validate tenant/location/service/staff relationships
- validate hours and time-off
- recheck overlapping active statuses
- insert appointment and initial event
- hold expiry timestamp

Use a staff booking serialization key with `pg_advisory_xact_lock`, an exclusion constraint with `tstzrange`, or both. PostgreSQL `SERIALIZABLE` isolation may supplement this design but is not a substitute for interval conflict protection.

## Supabase Storage

Create purpose-specific buckets only after UI requirements are approved:

- tenant logos/covers
- staff avatars
- portfolio images
- verification documents
- platform audit attachments, if required

Public marketing assets require public-read policies. Sensitive documents require private buckets and signed URLs or server-issued access.

## Supabase Realtime

Use Realtime for:

- merchant appointment changes
- customer appointment status changes
- platform operational notices
- notification records

Do not publish raw tenant or customer tables unless RLS and channel authorization are reviewed. Prefer event-shaped notification tables or server-published records.

## Cloudflare/runtime suitability

Cloudflare-compatible hosting can host the frontends and, if selected, the Node API behind an adapter. Cloudflare Workers must use a PostgreSQL connection strategy suitable for serverless execution.

Recommended options require a decision:

1. Keep the Node API on a conventional serverless/Node host, using Supabase SDK.
2. Adapt the existing Web handler to a Worker and use Supabase HTTP/JWT operations with a connection strategy approved for Workers.
3. Keep privileged PostgreSQL operations behind a Supabase RPC/Edge Function accessed by the Node API.

A direct database TCP/Postgres connection should not be assumed safe or stable from the current Worker unless connection pooling is explicitly configured.

## Environment variable plan

Public/browser variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_API_BASE_URL`

Server-only variables:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` or server JWT key configuration
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_JWT_SECRET`, only if JWT verification implementation requires it

No actual values or credentials should be added by migration planning.
