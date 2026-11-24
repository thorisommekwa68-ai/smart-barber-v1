# Deployment Plan

## Cloudflare database direction

Smart Barber's future backend is Cloudflare Workers with Cloudflare D1. SQLite-compatible migrations will be versioned and applied to D1. PostgreSQL and RLS are not the target architecture.

## Cloudflare Pages

Each frontend application should be deployed as a separate Cloudflare Pages project or separate route:

- Deployment Manager
- Smart Barber Business
- Smart Barber

Cloudflare Pages build settings should point to the root workspace and use the corresponding build script.

Environment variables in Cloudflare Pages must contain public values only. Privileged operations should use protected Cloudflare Workers.

## Cloudflare Workers

Workers provide routing, public APIs and server-side integrations. Workers must not expose D1 bindings or administrative secrets to Pages/browser applications and must use least-privilege environment bindings and secrets.

## Android

Capacitor will eventually package the customer-facing application and selected mobile surfaces. Native permissions and signing configuration must be managed separately. Android build artifacts and signing keys must remain untracked.

## GitHub

Pull requests should run dependency installation and focused builds before deployment. Production credentials must use protected GitHub environments or provider-side secret managers.
