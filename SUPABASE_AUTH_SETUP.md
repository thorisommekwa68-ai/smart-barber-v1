# Supabase Auth Setup

## Server configuration

Set these variables in the trusted Node/Worker runtime:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `NODE_ENV=production`

Optional:

- `IDENTITY_PROVIDER_TYPE=supabase`

Do not set `SUPABASE_SERVICE_ROLE_KEY` in source, Vite variables or browser code.

## Public frontend configuration

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_API_BASE_URL`

The anon key is public configuration. It does not prove identity by itself. The API verifies the bearer access token and database memberships.

## Supabase Dashboard configuration

Manual configuration is required for:

1. Email/password authentication.
2. Email verification.
3. Password recovery redirect URLs.
4. Allowed redirect origins.
5. Session/refresh token policy.
6. Auth provider email templates.
7. Profile bootstrap migration and test auth users.

## Browser authentication module

`packages/shared-utils/supabaseAuth.js` supports registration, login, logout, session validation, refresh and password recovery using the current Supabase browser SDK.

## API authentication

Requests to protected endpoints send:

```text
Authorization: Bearer <Supabase access token>
```

The backend derives the profile UUID from the verified Supabase user. It never derives identity from `x-user-id`. `GET /api/v1/me/profile` returns the authenticated profile and active memberships for the frontend.

## Tenant selection

Merchant tenant IDs may be selected from a trusted membership list only. `x-tenant-id` is rejected by the Supabase identity provider. The service layer revalidates membership from repository data before tenant operations.

## Development mock

`MockIdentityProvider` remains available only when:

- `NODE_ENV` is not `production`
- `MOCK_AUTH_ENABLED=true`

Production always selects Supabase and never enables mock authentication.

See [SUPABASE_FRONTEND_INTEGRATION.md](./SUPABASE_FRONTEND_INTEGRATION.md) for
the application workflows, configuration and outstanding API limitations.
