# Cloudflare migration preparation

The Node in-memory implementation remains the local adapter. A standard Web Request/Response entry is prepared in `backend/src/worker.js`, and `backend/src/cloudflare-worker.js` is the Worker entry.

## D1 migration

Run the versioned migration with Wrangler after creating a D1 database in the target account:

```bash
npx wrangler d1 create smart-barber
npx wrangler d1 migrations apply smart-barber --local
npx wrangler d1 migrations apply smart-barber
```

No account ID or database ID is stored in source control.

The migration currently under `backend/migrations/` defines the core domain, membership, appointment, notification and platform audit tables. D1 foreign keys and tenant-scoped indexes must be retained.

## Repository replacement

Implement a D1 repository satisfying `RepositoryInterface`, with SQL for each method. Replace `InMemoryRepository` during application composition. Add a transaction-backed `createAppointmentAtomically` implementation that checks conflicts and inserts the booking in a single database transaction.

## Worker entry point

Adapt `createApplication()` or the HTTP routing layer to the Worker `fetch(request, env, ctx)` API. The service and domain layers should remain unchanged. Inject configuration and repositories from `env`.

## Authentication

Replace `MockIdentityProvider` with an adapter that verifies a production identity token or session and maps it to a trusted internal user identity. Never accept `x-user-id` in production.

## Known incomplete work

- Production identity and session issuance
- Persistent D1 schema and migrations
- Atomic cross-instance conflict prevention
- Staff/location/service management mutations
- Customer profile and favourites
- Real availability slot endpoint persistence
- Concurrency, rate limiting and audit logging
