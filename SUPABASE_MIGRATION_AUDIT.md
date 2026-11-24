# Smart Barber Supabase Migration Audit

## Audit scope

This audit covers the npm workspaces, three Vite applications, Node API, in-memory repository, domain services, D1 migration draft, tests and existing documentation. No application source files were changed for this audit.

## Repository baseline

- Root workspace: `package.json`
- Customer app: `apps/customer-app`
- Merchant app: `apps/merchant-app`
- Deployment manager: `apps/deployment-manager`
- Backend: `backend`
- Shared packages: `packages`
- Documentation: `documentation`
- Legacy `supabase/` directory: no implementation

The root workspace has no Supabase dependency, PostgreSQL driver or Supabase client. The only runtime dependency is Vite at the root; the backend has no external package dependencies.

## Existing applications

### Customer application

`apps/customer-app/index.html` preserves the marketplace UI and includes a large prototype data array. `apps/customer-app/src/customer.js` now calls:

- `GET /api/v1/marketplace/tenants`
- `GET /api/v1/marketplace/tenants/:tenantId/services`
- `GET /api/v1/marketplace/tenants/:tenantId/staff`
- `GET /api/v1/me/appointments`
- `POST /api/v1/appointments`
- `POST /api/v1/appointments/:id/cancel`

The remaining provider cards, categories, imagery and many UI interactions retain prototype presentation data. Marketplace discovery is partly replaced, but it still merges backend tenants with local presentation fallbacks. Availability slots are not fully converted into the booking modal.

### Merchant application

`apps/merchant-app/index.html` retains large demo arrays for appointments, staff, services, customers and branches. `apps/merchant-app/src/merchant.js` loads and transitions appointment records through the backend. Team, services, customers, branches, marketing, financial and settings areas remain prototype data or local-only workspace logic.

### Deployment manager

`apps/deployment-manager/index.html` remains a sample platform-admin interface backed by inline demo businesses, subscriptions, licences, customers, appointments, tickets and sample analytics. Its existing `dataSdk` workflow is authoring-generated persistence, not Supabase persistence. Platform administration routes do not exist in the backend.

## Backend architecture

The backend is a layered Node application:

```text
HTTP adapter
  -> app.js
  -> routes/apiRoutes.js
  -> controllers/ApiController.js
  -> services
  -> RepositoryInterface
  -> InMemoryRepository
```

The request and service layers are runtime-neutral enough to retain. `server.js` is the Node adapter. `worker.js` and `cloudflare-worker.js` provide a Web Request/Response adapter and prepared Worker entry. They currently compose the in-memory application and are not Supabase-connected.

## Repository audit

`RepositoryInterface` defines:

- tenant lookup and listing
- service and staff lookup/listing
- location lookup
- membership lookup
- user lookup
- customer and tenant appointment listing
- appointment lookup
- atomic appointment creation
- appointment save
- operating/staff hours and time-off methods are implemented by the in-memory repository but are not declared in the interface

A PostgreSQL/Supabase implementation should extend the interface consistently and must not expose raw browser tenant IDs as authorization.

## Identity audit

`MockIdentityProvider` trusts `x-user-id` and optionally `x-tenant-id`. It validates a mock tenant membership before merchant access, but these headers are not cryptographic identity. The shared frontend `devAuth.js` contains fixed customer and merchant identities and is development-only.

Production should replace this provider with verified Supabase JWT claims and a profile/membership lookup. Browser-supplied tenant IDs must never establish tenant access.

## Persistent workflow inventory

| Workflow | Current state | Migration requirement |
|---|---|---|
| Marketplace discovery | Backend/in-memory | Supabase public or policy-protected read |
| Business profiles | Backend/in-memory | PostgreSQL tenant table plus public visibility rules |
| Services/staff | Backend/in-memory | Tenant, staff, staff-service and active-status models |
| Availability | Calculated by services | PostgreSQL schedules/time-off plus read queries |
| Customer booking | Backend/in-memory | Verified customer profile and atomic RPC/function |
| Booking history | Backend/in-memory | Customer-owned read policy/query |
| Cancellation | Backend/in-memory | Ownership and lifecycle RPC |
| Merchant appointment actions | Backend/in-memory | Tenant membership and role checks |
| Merchant team/services/branches | Mostly prototype | New repositories and Supabase mutations |
| Customer favourites/profile | Prototype or absent | profiles/customer favourites tables |
| Notifications | No API implementation | notifications table + Realtime publication |
| Platform tenants/plans/audit | Prototype/architecture only | platform-specific entities and server-only operations |
| Platform Storage | None | Supabase Storage buckets and metadata rules |
| Realtime | None | Publication and channel policy design |

## D1 and database-specific artifacts

`backend/migrations/0001_initial.sql` is a D1-oriented SQLite draft. It contains SQLite syntax and D1 comments. It is not safe to apply to Supabase PostgreSQL. `wrangler.toml` and `backend/src/cloudflare-worker.js` are D1/Worker preparation artifacts and are not database implementations.

The D1 draft must be treated as an entity and field inventory only. Supabase Phase 1 will replace it with PostgreSQL migrations.

## Concurrency findings

The in-memory `createAppointmentAtomically` method only checks an array and is not cross-process-safe. The booking service calculates server-side snapshots and checks hours/time-off before repository insertion. The future PostgreSQL implementation must:

1. Run relationship validation inside a transaction or server service.
2. Acquire/serialize on the staff or staff/day conflict key.
3. Recheck active pending, confirmed and in-progress overlaps while holding a transaction.
4. Insert one immutable appointment snapshot and event atomically.
5. Reject expired pending holds from blocking slots.
6. Add PostgreSQL exclusion or advisory-lock protection, not an application-only SELECT/INSERT sequence.

Recommended options are `pg_advisory_xact_lock` for staff booking serialization and/or a PostgreSQL exclusion constraint using `tstzrange`. The exclusion constraint should account only for active statuses and buffer semantics.

## Security weaknesses and inconsistencies

- Mock headers remain in frontend modules and tests.
- The `MockIdentityProvider` is development-only but can be enabled if misconfigured.
- The API client sends both identity headers and tenant IDs, and must stop doing so outside development.
- The deployment-manager UI still performs authoring-generated `dataSdk` updates.
- Platform operations lack backend routes and server-side role enforcement.
- Merchant team/service management remains prototype-only.
- Supabase environment variables are not yet included in an application package.
- Existing D1 documentation and SQL must not be reused as PostgreSQL migrations.

## Architecture decisions resolved by this audit

The following are recommended baselines for Supabase migration planning:

- Keep the Node API and service/domain layers.
- Use Supabase Auth for identity.
- Use a profile table keyed to `auth.users(id)`.
- Use tenant memberships for all merchant authorization.
- Use PostgreSQL RLS for browser-direct reads/writes only.
- Use server routes and PostgreSQL RPC/functions for privileged mutations.
- Keep the in-memory repository during Phase 1 migration.
- Do not deploy Supabase until a migration approval and cutover plan are approved.
