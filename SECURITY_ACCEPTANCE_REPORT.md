# Security Acceptance Report

Status: **PENDING hosted verification**

## Repository controls

- Supabase identity is mandatory when `NODE_ENV=production`.
- Supabase PostgreSQL repository is mandatory when `NODE_ENV=production`.
- Mock identity headers are development-only.
- Explicit CORS origins are mandatory in production.
- Node request JSON/body and file validation are implemented.
- Storage and RLS policies are tenant/profile scoped.
- Raw appointment tables are removed from Realtime publication.
- Realtime notifications filter by recipient profile and rely on RLS.
- Basic IP request throttling is implemented; distributed rate limiting remains a provider configuration decision.
- Structured logs avoid authorization, cookies, request bodies, and secret fields.

## SQL acceptance

The following hosted checks remain:

- RLS cross-tenant read/write rejection.
- Storage cross-tenant object upload/deletion rejection.
- Private signed URL access only for owner/tenant roles.
- Public URL access only for deliberate public buckets.
- Realtime recipient isolation and raw appointment publication exclusion.
- Platform and tenant role boundaries.

## Outstanding critical items

- Hosted credentials and project configuration.
- Supabase Auth redirect allowlist.
- Exact HTTPS CORS origin list.
- Provider-managed WAF/rate limit configuration.
- Monitoring/alert destination.
- Backup restore evidence.
