# Smart Barber RLS Test Report

## Validation environment

The policy suite was applied to a clean PostgreSQL 16 temporary container with:

- Supabase-compatible `auth.uid()` stub
- `authenticated` and `anon` roles
- complete Phase 2/5 migrations
- transaction rollback for every fixture

No live Supabase database was contacted.

## Tests executed

The fixture in `supabase/tests/rls_tenant_isolation.sql` validated:

1. Customer A cannot read Customer B profile.
2. Customer A cannot cancel or modify Customer B appointment.
3. Merchant A cannot read Tenant B appointments.
4. Merchant A cannot update Tenant B appointments.
5. Outsider cannot read merchant appointment records.
6. A customer cannot insert themselves as owner.
7. Merchant membership does not create platform-administrator status.

## Result

All adversarial fixture assertions passed. The PostgreSQL transaction was rolled back after validation.

## Remaining policy conflicts

- Stylist appointment access is currently tenant-wide. If the product requires stylist-only assigned appointments, add a staff/profile assignment predicate.
- Initial tenant owner provisioning depends on the no-active-owner bootstrap exception. Production provisioning should use a platform-authenticated server operation if stronger auditability is required.
- Payment update policies are not yet separated from read-only policies. Implement writes only in a trusted server/RPC service.
- Supabase Storage and Realtime policies require project/dashboard configuration and live policy testing.
- The local report uses compatibility roles and `auth.uid()`; final Supabase roles, JWT claims and migrations should be re-run in a development project.
