# Supabase Frontend Integration

## Browser configuration

Set these public variables for each Vite application:

```text
VITE_SUPABASE_URL=https://<project>.supabase.co
VITE_SUPABASE_ANON_KEY=<publishable-or-anon-key>
VITE_API_BASE_URL=https://<smart-barber-api>
```

The Supabase anon/publishable key is public. Never put a service-role key or a
database password in a Vite variable or browser bundle. Supabase Auth persists
and refreshes the browser session; the shared API client obtains the current
access token for each request and sends it as `Authorization: Bearer ...`.
Protected requests no longer send the development `x-user-id` or `x-tenant-id`
headers.

Configure Supabase email/password sign-up, email verification, password-reset
redirect origins and templates in the project dashboard. The backend requires
the corresponding `profiles` row to be provisioned before protected API calls
are accepted.

## Integrated workflows

- Customer registration, email verification, sign-in, sign-out, session
  restoration, password recovery and password update use the Supabase browser
  SDK.
- Customer profile and active memberships are fetched from the authenticated
  `GET /api/v1/me/profile` endpoint. Business, service and staff discovery,
  availability, booking, rescheduling, cancellation and booking history use
  the Smart Barber API.
- Booking submissions are guarded against repeated clicks. Availability comes
  from the backend and only staff assigned to the selected service are offered.
- Merchant appointments, services and staff are read from the API. Business
  selection is limited to memberships returned for the verified user.
  Appointment accept, decline, start, completion and no-show actions use the
  merchant API and refresh persisted data after success.
- Booking prices are API integer minor units and display as ZAR with two
  decimal places.
- The deployment manager requires a Supabase session and the
  `app_metadata.role=platform_admin` or `app_metadata.platform_admin=true`
  claim. This is a UI gate, not a substitute for server-side authorization.

## Current API limitations

The existing API does not provide writes for merchant services, staff,
availability, business settings, customer records, notification preferences or
favourites. Those screens do not report local changes as successful. Customer
favourites are retained in browser storage, per authenticated user, and are not
synced across devices.

The deployment manager has no platform-administration API. Its businesses,
applications, subscriptions, licences, customers, platform appointments,
financials, analytics, monitoring and support data remain illustrative
read-only sample screens; registration and administrative changes are disabled.
Merchant customer details, marketing, branch and business-settings screens
remain unavailable or read-only until matching backend endpoints are added.
Customer business category, address, ratings, reviews, photos and opening-time
summaries are not currently provided by the API; discovery uses live business,
service and staff records, while visual assets are presentation-only.

## Verification

Run:

```sh
node --test packages/shared-utils/tests/frontend-integration.test.js
npm test --workspace @smart-barber/backend
npm run build
```

The browser integration requires configured Supabase and API environments for
live end-to-end testing. Unit tests cover bearer-token propagation, absence of
mock identity headers, unauthorized responses and minor-unit currency
formatting.
