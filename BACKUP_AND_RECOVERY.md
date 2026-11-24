# Backup and Recovery

## PostgreSQL

Supabase-managed database backups must be enabled for the production project. The responsible operator must document retention, Point-in-Time Recovery availability, backup region, and restore authorization.

Before production migration:

1. Export or snapshot the production database.
2. Record migration and application versions.
3. Apply migrations to staging first.
4. Run schema, RLS, booking, and data integrity checks.

Recovery procedure:

1. Stop application writes or route traffic to maintenance mode.
2. Restore the database snapshot or PITR target to an isolated project.
3. Verify schema, constraints, RLS, Storage references, Auth identities, and migration state.
4. Run synthetic read and booking checks.
5. Promote only with explicit approval.

PostgreSQL backups do not include Supabase Storage object bytes.

## Storage

Document Supabase Storage backup/export availability and retention independently. Public and private buckets require separate operational review. For high-risk documents or portfolios, maintain provider-supported snapshots or a secure export bucket.

Recovery procedure:

1. Restore selected bucket objects in an isolated project.
2. Compare object paths against `public.media_assets`.
3. Remove or quarantine metadata with missing objects.
4. Restore missing entity references through reviewed reconciliation.
5. Verify public URLs and private signed URLs.

Tests must use synthetic placeholder files, never real customer photographs or production customer documents.
