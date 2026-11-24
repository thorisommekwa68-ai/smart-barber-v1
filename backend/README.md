# Smart Barber Backend Foundation

This is a Phase 1, database-independent backend scaffold. It uses a single shared in-memory repository and a development-only header-based identity provider.

## Run

```bash
npm run dev:backend
curl http://localhost:3001/health
npm run test:backend
```

## Mock identity headers

Development requests use `x-user-id`:

- `customer-1` and `customer-2`: customer identities
- `merchant-owner-1`: owner of `tenant-crown`
- `merchant-owner-2`: owner of `tenant-studio`

Merchant endpoints also require `x-tenant-id`.

The identity provider is intentionally mock-only. It must be replaced by a verified identity adapter before production use.

## Phase 1 limitations

- Data is process-local and resets when the server stops.
- Conflict detection is not concurrency-safe across server instances.
- Mock authentication does not establish cryptographically verified sessions.
- No Cloudflare bindings, D1 database or production secrets are configured.
- Cloudflare Workers and D1 are the future runtime/database targets.
