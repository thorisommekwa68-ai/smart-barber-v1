# Security Guidelines

## Authentication

A production identity provider will authenticate browser users. Applications must check authorization and never treat hidden navigation as security.

Administrative operations must require server-side authorization and role checks. Business and customer data must be filtered and protected by tenant, branch and role policies.

## Secrets

Only public API URLs and public frontend configuration may use `VITE_` variables. Production identity credentials, D1 bindings and administrative secrets must never be placed in JavaScript or Pages public configuration.

Trusted server-side code may access secrets only from a protected runtime environment, and every privileged operation must have explicit authorization checks.

Local environment files are ignored by Git. `.env.example` contains names only.

## Tenant isolation

Each business will have a stable tenant ID. The user-to-tenant relationship should include ownership and role data. Branches and employees belong to tenants.

D1 repository queries must include tenant scope and derive access from verified identity membership. Browser-supplied tenant values must never authorize a request.

## Data operations

- Never trust a tenant ID sent only by the browser.
- Reject unauthorized reads and writes in repository and service authorization.
- Use trusted Workers for operations that require elevated privileges.
- Enable audit logs for administrative and sensitive business changes.
- Add constraints for appointment conflicts and other integrity rules.

## Local development

Mock headers are development-only and must fail closed outside local development. Production authentication must verify identity outside browser-supplied headers.

## Deployment

Cloudflare secrets must be configured through the Cloudflare secret mechanism and rotated outside source control. GitHub Actions should use repository or environment secrets rather than checked-in files.
