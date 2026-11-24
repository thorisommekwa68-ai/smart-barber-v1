# Smart Barber

## 1. Project purpose

Smart Barber is a multi-tenant appointment booking marketplace for barbers and personal-care businesses. The repository contains:

- a customer-facing marketplace prototype;
- a merchant/business management prototype;
- a platform deployment-manager prototype;
- a shared npm workspace;
- a Phase 1 database-independent backend scaffold.

The project is not production-ready. It does not currently provide real authentication, persistent data, production database isolation, Cloudflare deployment, or secret-backed integrations.

Primary development stage:

1. frontend preservation and workspace setup;
2. in-memory backend foundation;
3. future Cloudflare D1 migration;
4. future Cloudflare Worker and Pages deployment.

Do not move to or implement Phase 3 unless it is explicitly requested.

## 2. Technology

- HTML5 and CSS3
- JavaScript ES modules
- Vite for frontend development and builds
- Node.js 20 or newer
- npm workspaces
- Node built-in HTTP server for the backend
- in-memory arrays for the Phase 1 repository
- no Express dependency
- no D1 or external database dependency; Cloudflare is the documented future target

No real credentials are required to run the scaffold.

## 3. Repository layout

```text
/
├── apps/
│   ├── customer-app/          Customer marketplace Vite application
│   ├── merchant-app/          Merchant/business Vite application
│   └── deployment-manager/    Platform deployment-manager Vite application
├── backend/
│   ├── src/
│   │   ├── app.js             HTTP application composition
│   │   ├── server.js          Local backend entry point
│   │   ├── config/            Injectable application configuration
│   │   ├── routes/            Endpoint definitions
│   │   ├── controllers/       HTTP boundary and response mapping
│   │   ├── services/          Booking and marketplace workflows
│   │   ├── repositories/
│   │   │   ├── interfaces/    Database-independent contracts
│   │   │   └── memory/        Shared in-memory implementation
│   │   ├── domain/
│   │   │   ├── entities/      Domain object factories
│   │   │   ├── enums/         Status and membership constants
│   │   │   ├── errors/        Domain error types
│   │   │   └── rules/         Appointment transition/conflict rules
│   │   ├── middleware/        Mock auth and central error handling
│   │   ├── validators/        Reserved for reusable input validation
│   │   └── utils/             Web/API-compatible helpers
│   ├── tests/
│   │   ├── unit/              Domain and service tests
│   │   └── integration/       HTTP lifecycle tests
│   └── docs/                  Architecture, API and migration documents
├── packages/                  Shared future workspace packages
├── documentation/             Existing frontend and platform documentation
├── supabase/                  Legacy compatibility directory (not target infrastructure)
├── .env.example               Public and server variable examples
├── package.json               Root workspace scripts
└── PROJECT_STATUS.md          Earlier project status and pending frontend work
```

Do not assume that directories labelled “future” are implemented.

## 4. Existing frontend interfaces

The frontend HTML files are already mapped into Vite applications and must be preserved unless the user explicitly asks for frontend changes.

| Interface | Location | Intended purpose |
|---|---|---|
| Customer marketplace | `apps/customer-app/index.html` | Discovery, business profiles, services, staff, availability, booking history and customer profile |
| Merchant dashboard | `apps/merchant-app/index.html` | Appointments, services, staff, customers, availability and business settings |
| Deployment manager | `apps/deployment-manager/index.html` | Platform/deployment administration |

The HTML applications contain inline CSS, JavaScript and sample data. Generated SDK script paths, Google Fonts, jsDelivr, and Pexels resources may depend on external authoring/runtime resources. Do not silently treat prototype behavior as production behavior.

## 5. Backend architecture

The backend follows a layered dependency direction:

```text
HTTP request
  -> routes
  -> controllers
  -> services
  -> repository interface
  -> in-memory repository (Phase 1)

services/domain
  -> no Express
  -> no database implementation
  -> no filesystem dependency
```

### Routes

`backend/src/routes/apiRoutes.js` defines endpoint methods and URL patterns.

### Controllers

`backend/src/controllers/ApiController.js` coordinates authentication and service calls and returns the standard success format.

### Services

`backend/src/services/` contains application workflows:

- `MarketplaceService`: tenant, service and staff discovery
- `AvailabilityService`: available slot calculation
- `AppointmentService`: booking creation, snapshots, tenant isolation and status transitions

### Repository interfaces

`backend/src/repositories/interfaces/repositoryInterfaces.js` defines the replaceable data-access contract. It includes a `createAppointmentAtomically` method intended for future transaction implementations.

### In-memory repository

`backend/src/repositories/memory/inMemoryRepository.js` is the shared data source for local development. It is process-local and resets whenever the server restarts. It contains safe sample users and businesses. It contains no passwords or secrets.

### Domain

`backend/src/domain/` contains status enums, entity factories, domain errors and appointment transition/conflict rules.

## 6. Setup

### Requirements

- Node.js 20 or newer
- npm 10 or newer

### Install

```bash
npm install
cp .env.example .env.local
```

For the backend, `.env.local` is not automatically read by `node src/server.js`; use shell environment variables or add an environment loader only if explicitly needed.

The backend defaults to port `3001`.

### Start all frontends independently

```bash
npm run dev:customer
npm run dev:merchant
npm run dev:admin
```

Run frontend applications in separate terminals when needed.

### Start the backend

```bash
npm run dev:backend
```

Verify it:

```bash
curl http://127.0.0.1:3001/health
```

Health response shape:

```json
{
  "success": true,
  "data": {
    "status": "ok",
    "timezone": "Africa/Johannesburg",
    "mode": "memory"
  },
  "message": "Backend is running"
}
```

### Build frontends

```bash
npm run build
```

Individual builds:

```bash
npm run build:customer
npm run build:merchant
npm run build:admin
```

## 7. Development authentication

The backend uses `MockIdentityProvider`, not real authentication.

Authenticated endpoints require:

```http
x-user-id: customer-1
```

Merchant endpoints also require:

```http
x-tenant-id: tenant-crown
```

Development identities:

| Header value | Role/tenant |
|---|---|
| `customer-1` | Customer |
| `customer-2` | Customer |
| `merchant-owner-1` | Owner of `tenant-crown` |
| `merchant-owner-2` | Owner of `tenant-studio` |

Never expose the header-based mock provider in production. Never add passwords or credentials to mock data.

Future authentication must verify an identity token/session and derive the trusted user and tenant memberships.

## 8. API contract

Prefix: `/api/v1`

Timezone: `Africa/Johannesburg`

Currency: `ZAR`

Prices in the mock repository are stored as integer minor units/cents.

Success format:

```json
{
  "success": true,
  "data": {},
  "message": "Operation completed successfully"
}
```

Error format:

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable explanation"
  }
}
```

### Marketplace

| Method | Endpoint |
|---|---|
| GET | `/api/v1/marketplace/tenants` |
| GET | `/api/v1/marketplace/tenants/:tenantId` |
| GET | `/api/v1/marketplace/tenants/:tenantId/services` |
| GET | `/api/v1/marketplace/tenants/:tenantId/staff` |

### Availability

```http
GET /api/v1/availability
  ?tenantId=tenant-crown
  &locationId=location-crown-1
  &staffId=staff-crown-1
  &serviceId=service-crown-cut
  &date=2026-11-24
```

### Customer appointments

| Method | Endpoint |
|---|---|
| POST | `/api/v1/appointments` |
| GET | `/api/v1/me/appointments` |
| POST | `/api/v1/appointments/:appointmentId/cancel` |

Booking creation request example:

```json
{
  "tenantId": "tenant-crown",
  "locationId": "location-crown-1",
  "staffId": "staff-crown-1",
  "serviceId": "service-crown-cut",
  "startAt": "2026-11-24T10:00:00+02:00",
  "customerNotes": "Please use clippers"
}
```

The client must not send price, duration or status. The service loads those values from the repository and stores snapshots.

### Merchant appointments

Merchant endpoints require both `x-user-id` and `x-tenant-id`.

| Method | Endpoint |
|---|---|
| GET | `/api/v1/merchant/appointments` |
| PATCH | `/api/v1/merchant/appointments/:appointmentId/accept` |
| PATCH | `/api/v1/merchant/appointments/:appointmentId/decline` |
| PATCH | `/api/v1/merchant/appointments/:appointmentId/start` |
| PATCH | `/api/v1/merchant/appointments/:appointmentId/complete` |
| PATCH | `/api/v1/merchant/appointments/:appointmentId/no-show` |

## 9. Domain model

Core entities:

- `User`
- `Tenant`
- `TenantMembership`
- `Location`
- `Staff`
- `Service`
- `Appointment`

Multi-tenancy rules:

- a customer can book with multiple tenants;
- one tenant can have multiple locations and staff;
- a staff member is assigned to selected services;
- an appointment belongs to exactly one tenant;
- merchant operations require an active tenant membership;
- users must not receive or modify another tenant's appointments.

### Appointment statuses

- `pending`
- `confirmed`
- `in_progress`
- `completed`
- `declined`
- `cancelled`
- `expired`
- `no_show`

Important transitions:

- pending -> confirmed, declined, cancelled or expired
- confirmed -> in_progress, cancelled, no_show or expired
- in_progress -> completed or cancelled
- completed, declined, cancelled, expired and no_show are terminal

Invalid transitions return HTTP 409 with `INVALID_STATUS_TRANSITION`.

### Booking rules

The appointment service verifies:

- tenant exists and is active;
- location belongs to the tenant;
- service exists, is active and belongs to the tenant;
- staff exists, is active and belongs to the tenant/location;
- staff is assigned to the selected service;
- `startAt` is valid ISO 8601 with timezone information;
- operating and staff working hours allow the appointment;
- staff time off conflicts;
- existing or pending overlaps conflict.

`endAt` is calculated from service duration and the configured buffer. Price and duration are snapshotted on creation.

## 10. Testing

Run backend tests:

```bash
npm run test:backend
```

Direct workspace test command:

```bash
npm test -w @smart-barber/backend
```

Current tests cover HTTP and domain behavior for:

- successful marketplace discovery;
- successful appointment creation;
- mock identity rejection;
- missing request data;
- invalid service and staff selection;
- unavailable Sunday slots;
- appointment overlap;
- snapshot price and duration;
- merchant/cross-tenant isolation;
- accept and decline workflows;
- customer cancellation;
- invalid status transitions.

The test suite uses Node's built-in test runner and requires Node 20 or newer.

## 11. Security boundaries

The following are development safeguards, not production security:

- central domain errors;
- no stack traces sent to consumers;
- tenant membership checks in merchant services;
- customer ownership checks for cancellation;
- rejection of client-supplied prices, durations and statuses;
- input checks for required fields and timestamps;
- no passwords or secrets in mock data;
- no server credentials in browser code.

Before production:

- replace `x-user-id` mock authentication;
- verify identity server-side;
- add authorization middleware;
- add tenant-scoped repository policies;
- add secure cookies/tokens or an identity-provider adapter;
- add rate limiting and audit logging;
- add request limits and robust sanitization;
- establish deployment secrets outside source control.

## 12. Phase 1 limitations

- repository data is process-local;
- process restarts erase all bookings;
- conflict detection is not safe across multiple server instances;
- mock authentication is intentionally insecure and development-only;
- no database migrations exist;
- no D1 binding exists;
- no Cloudflare Worker entry point exists;
- no Cloudflare account, D1 binding or production identity provider is configured;
- availability data is limited to seeded hours;
- business/staff/service management mutations are incomplete;
- customer profiles and favourites are not persisted;
- no notifications, payments or calendar integrations exist.

These limitations are intentional for the scaffolding phase.

## 13. Cloudflare/D1 migration

Before database integration:

1. Define a D1 SQL schema for all domain entities and memberships.
2. Implement a D1 repository satisfying `RepositoryInterface`.
3. Replace `InMemoryRepository` during application composition.
4. Implement `createAppointmentAtomically` as a real transaction.
5. Implement database checks for tenant, service, staff and conflict constraints.
6. Replace `MockIdentityProvider` with verified identity/session verification.
7. Adapt `app.js` to a Worker `fetch(request, env, ctx)` entry point.
8. Inject configuration and bindings instead of reading process environment variables.
9. Add D1 migrations, tenant-scoped repository checks and observability.

Detailed guidance is in:

- `backend/docs/ARCHITECTURE.md`
- `backend/docs/API.md`
- `backend/docs/DATA_MODEL.md`
- `backend/docs/CLOUDFLARE_MIGRATION.md`

Do not implement Cloudflare or database work unless the next task explicitly requests it.

## 14. Recommended continuation order

For a future coding agent, continue in this order:

1. read `backend/docs/ARCHITECTURE.md`;
2. inspect `backend/src/app.js` and `backend/src/routes/apiRoutes.js`;
3. inspect domain rules and repository interfaces;
4. preserve existing HTML applications;
5. add or change one backend module at a time;
6. add a focused test for each behavior change;
7. run `npm run test:backend`;
8. run `npm run build`;
9. update relevant backend documentation;
10. do not introduce Cloudflare/D1 dependencies until explicitly requested.

## 15. Known existing-repository issues

- `_sdk/*` script references in prototype HTML are authoring-generated paths and may not exist in normal builds.
- Frontend code uses external Google Fonts, jsDelivr, and Pexels resources.
- Inline CSS and JavaScript should eventually be extracted.
- The frontends currently use sample data and do not consume the backend API yet.
- Existing prototype documentation is planning-only; Cloudflare Workers and D1 are the documented future direction.
