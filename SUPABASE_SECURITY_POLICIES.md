# Smart Barber Supabase Security Policies

## Identity

The authenticated UUID is `auth.uid()`. Every private profile and customer record must be keyed or related to that UUID.

Merchant access is authorized only through an active `tenant_memberships` row. Tenant IDs supplied by the frontend do not grant membership.

## Table policy matrix

| Table | Public | Customer | Merchant | Platform |
|---|---|---|---|---|
| profiles | none | own row | none by default | controlled |
| tenants | active listings | no private writes | member read via membership context | admin |
| tenant_memberships | none | own memberships | owner manages | platform admin |
| locations | active public listings | read public | owner/manager manage | admin |
| staff | active public listings | read public | owner/manager manage | admin |
| services | active public catalogue | read public | owner/manager manage | admin |
| staff_services | active public assignments | read public | owner/manager manage | admin |
| operating_hours | active public schedule | read public | owner/manager manage | admin |
| staff_hours | active public schedule | read public | owner/manager manage | admin |
| staff_breaks | none | none | tenant member read; owner/manager manage | admin |
| staff_time_off | none | none | tenant member read; owner/manager manage | admin |
| business_holidays | active public holidays | read public | owner/manager manage | admin |
| appointments | none | own rows; create/cancel own | tenant member read; role update | admin |
| appointment_events | none | own appointment | tenant member appointment | admin |
| customer_relationships | none | own row | none | admin |
| customer_favourites | none | own row | none | admin |
| notifications | none | own recipient | own recipient | admin |
| subscription_plans | active public plans | public read | read through tenant context | admin |
| tenant_subscriptions | none | tenant member read | tenant member read | admin |
| payment_transactions | none | own transaction | tenant member read | admin |
| platform_administrators | none | none | none | platform admin |
| platform_role_assignments | none | none | none | platform owner |
| platform_audit_logs | none | none | none | platform admin/auditor |

## Role matrix

### Tenant roles

- owner: manage memberships, business configuration, staff, services and appointments
- manager: manage business configuration, staff, services and appointments
- receptionist: read and update allowed appointment operations
- stylist: read and update assigned/tenant appointments

### Platform roles

- platform_owner: assign platform roles
- platform_admin: platform administration
- platform_support: limited support operations
- platform_auditor: read-only audit access

Tenant membership does not imply platform role membership.

## Appointment rules

Customers may create appointments only for themselves. Customers may cancel their own appointment, but an update trigger rejects private-field changes, status changes other than cancellation and cross-customer updates.

Merchants may update appointment status only within a tenant membership. Receptions/managers/owners/stylists receive same broad tenant appointment update rights where the UI has not added finer stylist assignment rules. Production should narrow stylist access to assigned staff if required.

The database trigger rejects immutable appointment fields, including tenant, location, customer, staff, service, snapshots and currency.

## Membership rules

No user can assign themselves elevated tenant membership. Owner assignment is permitted only if no active owner exists or by an existing tenant owner/platform administrator.

The platform-role trigger prevents self-escalation and requires `platform_owner`.

## SECURITY DEFINER review

The RLS helper functions are `SECURITY DEFINER` and validate `auth.uid()` without accepting arbitrary identity parameters. Execute access is restricted to `authenticated`, and `anon`/`PUBLIC` are revoked where possible.

The Auth profile bootstrap function is `SECURITY DEFINER` because it runs after Auth insertion. It writes only the profile record and must remain protected.

Booking and reschedule RPCs are `SECURITY INVOKER`, use `auth.uid()` and rely on RLS plus explicit ownership checks.

## Elevated operations

The service-role key is not used to make ordinary repository calls. Server-side elevation is reserved for:

- profile bootstrap
- platform administration
- audit export or subscription operations
- scheduled pending-hold expiry
- storage administration

Every elevated operation requires independent application authorization.

## Storage

Until bucket policies are configured:

- tenant/portfolio assets require public-read only if intentionally marketing content
- staff and customer private assets require signed URLs
- verification documents require private buckets and server-issued access
- no bucket policy should infer tenant access from a filename or browser tenant ID

## Realtime

Publish only appointments, appointment_events and notifications with RLS. Verify channel authorization and row filtering before enabling publication. Do not publish platform audit or payment rows through public channels.
