# Folder Structure

## `apps/`

Each application is independently developed and built by Vite.

- `deployment-manager/`: platform administration application.
- `merchant-app/`: business tenant application.
- `customer-app/`: customer marketplace application.

Within an application, `public/` contains static assets, `src/assets/` contains bundled media, `src/components/` contains reusable UI pieces, `src/layouts/` contains page shells, `src/pages/` contains route-level screens, `src/services/` contains backend clients and service calls, `src/styles/` contains app styles, `src/utils/` contains local helpers, and `src/main.js` is the future JavaScript entry module.

## `packages/`

Workspace packages contain code intentionally reused across applications. Packages should have clear, small responsibilities and avoid importing application-specific code.

## `supabase/`

Reserved for database migrations, Edge Functions and seed data.

## `infrastructure/`

Reserved for Cloudflare configuration, deployment automation and security policy.

## `documentation/`

Technical documentation grouped by architecture, database, applications, security, deployment and decisions.

## `scripts/` and `tests/`

`scripts/` contains repository automation. `tests/` contains cross-app and integration validation.

## Significant organisation decisions

The existing HTML files were moved directly into each application's `index.html` without extraction. This preserves their working appearance and behavior while establishing Vite compatibility. Inline CSS and JavaScript should be separated in a later implementation phase rather than rewritten during this architecture task.
