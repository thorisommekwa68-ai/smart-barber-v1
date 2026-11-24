# Deployment Guide

## Deployment restrictions

Do not deploy to production until the staging acceptance report is complete and a human approver signs off. The old database architecture must remain available until migration reconciliation is verified.

## 1. Prepare Supabase

1. Create staging and production projects.
2. Apply Supabase migrations in filename order.
3. Run `supabase/tests/schema_validation.sql`, `supabase/tests/rls_tenant_isolation.sql`, `storage_security.sql`, and `realtime_security.sql`.
4. Create/verify all Storage buckets and allowed MIME types.
5. Verify Auth URL redirect configuration.
6. Verify Realtime publication contains only `appointment_events` and `notifications`.
7. Configure database and Storage backup schedules.

## 2. Prepare hosting secrets

Set secrets in the provider secret manager:

- `NODE_ENV=production`
- `IDENTITY_PROVIDER_TYPE=supabase`
- `REPOSITORY_TYPE=supabase`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `CORS_ALLOWED_ORIGINS`
- `MAX_REQUEST_BODY_BYTES`
- `MOCK_AUTH_ENABLED=false`

Never set `SUPABASE_SERVICE_ROLE_KEY` in a frontend build or public repository.

## 3. Deploy staging

1. Deploy the Node backend or Cloudflare Worker.
2. Deploy each frontend build with staging `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, and `VITE_API_BASE_URL`.
3. Verify `/health` and `/health/ready`.
4. Verify HTTPS-only origins.
5. Run synthetic registration, booking, merchant, media, realtime, and concurrency tests.

## 4. Cloudflare Worker

The Worker uses the Supabase REST/PostgREST client over HTTPS. It does not use direct PostgreSQL TCP connections, so Hyperdrive is not required for the current implementation. If direct PostgreSQL access is introduced later, evaluate Cloudflare Hyperdrive and transaction pool settings before deploying.

The Wrangler file must not contain production domains or secrets. Configure `CORS_ALLOWED_ORIGINS` and production environment variables through the Cloudflare dashboard or encrypted environment variables.

## 5. Production promotion

Promotion requires:

- staging acceptance report approved;
- backup restore test approved;
- RLS, Storage, and Realtime test reports approved;
- concurrency test passing;
- no unresolved critical security issues;
- explicit human approval.
