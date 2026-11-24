# Smart Barber Supabase Security Review

## Trust boundary

Supabase Auth identities are trusted only after JWT verification. The current `x-user-id` and `x-tenant-id` headers are development mock inputs and must not reach production middleware.

No frontend tenant selector, navigation state or `x-tenant-id` value is authorization.

## Auth-to-profile mapping

Use:

```text
auth.users.id -> profiles.id -> tenant_memberships.profile_id
```

Do not generate a second browser-supplied application user ID. A trigger or server bootstrap can create a profile after Supabase Auth registration. If profile creation fails, return a controlled authentication error rather than a fallback mock user.

## Tenant authorization

All merchant operations require:

- verified profile
- active `tenant_memberships` row
- tenant role appropriate to the operation

The existing role model includes owner, manager, receptionist and stylist. Platform roles must remain distinct:

- platform_owner
- platform_admin
- platform_support
- platform_auditor

No tenant owner or membership should imply platform access.

## RLS strategy

Browser-direct operations should use:

- profiles readable by the signed-in profile
- public tenant/service/staff discovery for active records
- appointment/customer reads restricted to owner or authorized tenant membership
- tenant mutations restricted to authorized tenant roles
- platform tables excluded from ordinary browser policies

RLS must never be bypassed by a browser Supabase anon key with a service-role key.

The service-role key does not enforce RLS. It bypasses RLS and creates a trusted-server privilege boundary. Each privileged operation must be independently authorized in Node, RPC or Edge Functions.

## JWT verification

The backend must verify the JWT issuer, audience, signature and expiry. A Supabase JWT payload is not authorization; `sub` identifies the Auth user. Tenant and platform authorization must come from PostgreSQL membership and role rows.

## API security

Retain:

- JSON body limits
- CORS allowlists
- malformed JSON handling
- content-type validation
- method/status consistency
- stack-trace suppression

Production bearer authentication must replace the mock header branch. Browser request tenant IDs should be ignored or used only to locate a public marketplace record.

## Booking security

Server-side booking creation must:

- derive customer from verified identity
- derive all price/duration snapshots from `services`
- validate tenant, location, staff and service relationships
- reject past starts
- validate timezone and hours
- check time-off
- recheck conflicts within the same transaction
- append an audit/event record
- never trust status, price or duration from the request

## Storage security

Bucket rules:

- public marketing assets: public-read only
- staff profile assets: tenant/role controlled
- private verification documents: private bucket with signed URLs
- appointment documents: customer/merchant authorized reads

Never expose signed URLs longer than necessary and do not store service-role credentials in frontend code.

## Realtime security

Before enabling Realtime:

- decide whether direct table subscriptions or notification channels are used
- enable RLS for every published table
- publish only needed columns
- test cross-tenant and cross-customer channel access
- avoid broadcasting service snapshots or platform audit payloads publicly

## Platform security

Platform routes must remain disabled until:

- a verified platform identity exists
- explicit platform role assignments exist
- server-side role checks are implemented
- all sensitive mutations are audited
- tenant suspension/reactivation is transactional
- plan and configuration changes are constrained

## Secret handling

Public:

- Supabase URL
- Supabase anon key
- API base URL

Server-only:

- service-role key
- any database connection string
- JWT secret only if used by a custom verifier
- Cloudflare credentials

Secrets should be supplied through provider secret managers and rotateable environment bindings, never checked into files or frontend variables.

## Audit requirements

Record:

- auth profile created
- membership granted/revoked
- tenant suspended/reactivated
- role changed
- plan changed
- platform configuration changed
- appointment status changes
- cancellation/decline/no-show events

Audit records should be append-only where operationally possible and include actor, target, before/after state and timestamp.

## Migration security risks

1. Leaving mock auth enabled in any deployed environment.
2. Treating `x-tenant-id` as authorization after Supabase cutover.
3. Using a service-role client for every backend query.
4. Assuming the D1 migration draft or PostgreSQL RLS-compatible syntax is ready.
5. Publishing sample deployment-manager data as real platform views.
6. Using direct email/display-name matching instead of `auth.users.id`.
7. Allowing an appointment insert to execute without transactional conflict locking.
