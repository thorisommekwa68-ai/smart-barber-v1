# Storage and Media Management

## Schema

The migration `202611230534_storage_and_media.sql` adds:

- Six Supabase Storage buckets.
- `public.media_assets` for bucket, object path, MIME type, size, dimensions, and thumbnails.
- `public.business_portfolio_items` for ordered public portfolio records.
- `public.business_documents` for private tenant documents.
- Media references on profiles, tenants, staff, and services.

Binary contents remain in Storage. PostgreSQL stores metadata and references only.

## File conventions

Every object includes the tenant UUID or user UUID in its path. New asset IDs are UUIDs and original filenames are never used as object names. This prevents path traversal and cross-tenant guessing.

## Application services

- `backend/src/services/MediaService.js` validates uploads, creates signed upload URLs, creates private signed read URLs, and deletes authorized Storage/metadata records.
- `packages/shared-utils/mediaService.js` validates browser files, compresses images, resizes thumbnails, uploads through signed URLs, and retrieves public or signed URLs.

## Manual configuration

Run the Supabase migration in the target project. Confirm the six bucket IDs, public flags, MIME allowlists, and size limits in the Storage dashboard. No real customer media should be uploaded while configuring development or test projects.

## Backup and retention

Storage backups are independent of PostgreSQL backups. Configure and document a Supabase Storage backup/export schedule that includes object versions or a provider-supported snapshot policy. PostgreSQL backups protect `media_assets` and entity references, but do not contain object bytes. Retention for public portfolios and private documents must follow business policy, and deletion must remove both object bytes and dependent metadata.
