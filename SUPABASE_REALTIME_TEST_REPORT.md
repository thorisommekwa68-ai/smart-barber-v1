# Supabase Realtime Test Report

## Scope

The realtime implementation publishes only `public.appointment_events` and `public.notifications`. Raw `appointments`, payments, audit logs, and static tables are not published.

## Critical workflows

| Test | Expected result |
|---|---|
| Customer receives status update | Customer's recipient notification arrives and the UI reloads appointments through the backend API |
| Merchant receives booking creation | Every active tenant member receives one `booking_created` notification |
| Cross-tenant subscription | RLS and recipient filters prevent another tenant's private events |
| Disconnection recovery | Channel status reloads authoritative state after reconnect |
| Duplicate events | Notification UUID deduplication suppresses duplicate UI updates |
| Logout/account switch | `removeChannel` removes notification subscriptions and clears deduplication |
| Rescheduling | Appointment event and customer/merchant notifications are created once per change |
| Cancellation | Customer and merchant receive a cancellation notification |

## Access controls

- Customer subscriptions filter `notifications.recipient_profile_id` by the authenticated profile UUID.
- Merchant subscriptions use the same recipient filter; tenant members receive only notifications generated for their profile.
- `appointment_events` remains protected by existing appointment RLS.
- Notification writes are server-generated through a security-definer trigger.
- Realtime payloads are updates only. UI state is reloaded from `/api/v1/me/appointments` or `/api/v1/merchant/appointments`.

## Manual verification

Run `supabase/tests/realtime_security.sql` in a non-production Supabase test project. Create synthetic appointment records as owner, customer, and unauthorized identities. Verify browser network activity, channel status, duplicate event handling, reconnect, logout cleanup, and persistent notification rows.

No real customer or production appointments should be used during testing.
