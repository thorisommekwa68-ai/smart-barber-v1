# System Architecture

## Applications

The ecosystem consists of three independent Vite frontend applications:

- **Deployment Manager** is restricted to platform administrators.
- **Smart Barber Business** is used by employees and owners of tenant businesses.
- **Smart Barber** is used by customers.

Each application has its own build and local development command, but they consume shared packages and the same backend contracts.

## Shared backend

Cloudflare D1 is the documented future system of record. Cloudflare Workers provide trusted server-side operations. A production identity provider verifies browser identities and maps them to internal users and memberships.

Application boundaries do not replace database isolation. Browser applications receive public configuration only. Tenant and platform authorization are server-enforced; D1 does not provide PostgreSQL Row Level Security.

## Communication flow

```text
Customer / Merchant / Admin browser
                |
                v
  Production identity adapter
                |
                v
       Cloudflare Worker
                |
                v
        Cloudflare D1
                |
                v
      Tenant-scoped repositories
```

The browser should call Cloudflare Workers only for operations that require trusted logic or privileged server-side access. No frontend code will receive D1 bindings or administrative secrets.

## Shared packages

- `shared-ui`: reusable visual styles and interface components.
- `shared-utils`: non-domain common functions.
- `validation`: shared input and data validation.
- `authentication`: future browser auth helpers.
- `booking-engine`: future availability and booking rules.
- `tenant-management`: tenant membership and branch concepts.
- `shared-config`: shared constants and environment-safe configuration.
