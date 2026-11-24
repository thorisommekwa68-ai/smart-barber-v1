# Smart Barber Supabase Migration Roadmap

## Phase 0: Approval and decision lock

Before implementation:

- Approve Supabase PostgreSQL as the system of record.
- Choose the Node API hosting runtime and PostgreSQL connection mode.
- Approve the Supabase Auth profile bootstrap method.
- Approve RLS versus server-only authorization boundaries.
- Define Storage buckets and public/private asset rules.
- Define Realtime event channels.
- Approve the platform-role and platform-administration model.
- Define rollback and data-seeding procedures.

## Phase 1: Local migration foundation

Implementation order:

1. Add a Supabase PostgreSQL migration tool and environment placeholders.
2. Add Supabase Auth packages only to the backend/auth package required.
3. Implement a verified-JWT identity adapter behind the existing identity-provider boundary.
4. Add `profiles`, `tenant_memberships`, tenant, location, staff and service tables.
5. Add availability and appointment tables.
6. Add appointment events and notifications.
7. Add platform administration and audit tables.
8. Keep `InMemoryRepository` as the default local repository.
9. Add a `SupabaseRepository` but do not replace the memory repository until tests pass.

## Phase 2: Repository parity

Before cutover, implement and test every existing repository method:

- tenant lookup/list
- public tenant discovery
- service lookup/list
- staff lookup/list
- location lookup
- membership lookup
- user/profile lookup
- customer appointment list
- tenant appointment list
- appointment lookup
- atomic booking creation
- appointment update
- operating hours
- staff hours
- staff time-off
- staff appointment list

Every tenant-owned query must include tenant scope or rely on explicitly tested RLS.

## Phase 3: Authentication cutover

1. Remove mock headers from production configuration.
2. Keep mock auth behind `NODE_ENV=development` and an explicit flag.
3. Reject requests with mock headers in production.
4. Verify JWT in the backend.
5. Resolve profile by `auth.users.id`.
6. Resolve tenant membership from PostgreSQL.
7. Remove `x-tenant-id` from frontend API calls.
8. Add tests for wrong JWT, missing profile, inactive membership and cross-tenant access.

## Phase 4: PostgreSQL booking engine

1. Add a migration for appointments and `tstzrange`/advisory-lock strategy.
2. Implement transactional relationship and hours/time-off validation.
3. Recheck overlapping pending/confirmed/in-progress appointments.
4. Ignore expired pending holds.
5. Insert immutable snapshots and the initial appointment event.
6. Test concurrent overlap attempts and expired holds.
7. Test tenant/customer ownership and lifecycle transitions.

## Phase 5: Frontend migration

1. Replace fixed customer and merchant development headers with bearer tokens.
2. Replace the local API client fallback only after auth is complete.
3. Remove prototype provider arrays where backend discovery is available.
4. Add availability slot loading to the customer booking flow.
5. Replace merchant sample appointments with API results.
6. Connect persistent team, branch, service and customer views only to new repository methods.
7. Replace deployment-manager `dataSdk` operations with protected platform APIs.
8. Preserve existing HTML/CSS and responsive layouts.

## Phase 6: Storage

1. Create private/public buckets.
2. Add signed/controlled asset access.
3. Add asset metadata tables.
4. Test cross-tenant file access.
5. Remove remote authoring or Pexels dependencies if not required.

## Phase 7: Realtime

1. Define notification and appointment event tables.
2. Test RLS on every publication.
3. Add customer and merchant channel subscriptions.
4. Add platform notification channels only after platform auth.
5. Do not publish broad sample tables.

## Phase 8: Platform administration

1. Implement explicit platform roles.
2. Implement platform repository and service boundaries.
3. Add platform API routes.
4. Require verified JWT and platform membership.
5. Add tenant suspension/reactivation and plan assignment mutations.
6. Add append-only audit logging.
7. Connect only the existing deployment-manager features that have implemented backend data.

## Phase 9: Cutover and rollback

1. Seed only safe development data.
2. Export/transform existing in-memory seed data if real records exist.
3. Run migration and smoke tests in a staging project.
4. Dual-read test the Node API where practical.
5. Switch repository injection to Supabase.
6. Monitor booking conflicts, auth failures and cross-tenant access.
7. Keep the in-memory adapter available for local development.
8. Document rollback to the Node/in-memory repository.

## Dependency map

```text
Supabase project
  -> Auth configuration
  -> PostgreSQL migrations
  -> profiles
  -> tenant memberships
  -> RLS/policies
  -> SupabaseRepository
  -> JWT identity provider
  -> Node API
  -> customer/merchant frontend bearer auth

PostgreSQL appointment tables
  -> advisory locks/exclusion constraints
  -> atomic booking RPC
  -> lifecycle events
  -> Realtime notifications

Platform roles
  -> platform repository
  -> platform API
  -> deployment-manager integration
  -> audit logs

Storage buckets
  -> public/private policies
  -> asset metadata
  -> frontend asset access
```

## Acceptance gates

Supabase migration Phase 1 should not begin implementation until:

- [ ] Runtime and database connection strategy are approved
- [ ] Auth/profile mapping is approved
- [ ] RLS and privileged RPC boundaries are approved
- [ ] D1 draft is clearly excluded from PostgreSQL migrations
- [ ] Booking concurrency approach is approved
- [ ] Storage buckets are approved
- [ ] Realtime channel boundaries are approved
- [ ] Platform roles and audit requirements are approved
- [ ] Rollback plan is approved

## Remaining unresolved decisions

1. Conventional Node host versus Cloudflare Worker API hosting.
2. Supabase SDK in Node versus direct PostgreSQL pooled connection.
3. Browser-direct RLS operations versus API-only access.
4. Profile bootstrap by database trigger, Auth hook or first API request.
5. Advisory lock, exclusion constraint or both for double-booking prevention.
6. Customer cancel permission rules and merchant cancellation responsibilities.
7. Realtime channel model and publication scope.
8. Storage bucket names and public asset policy.
9. Platform administrator bootstrapping and break-glass access.
10. Data migration/source of truth for existing prototype records.
