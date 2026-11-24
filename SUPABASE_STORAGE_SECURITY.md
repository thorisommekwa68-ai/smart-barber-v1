# Supabase Storage Security

## Buckets

| Bucket | Access | MIME types | Maximum file |
|---|---|---|---:|
| `business-logos` | Public | JPEG, PNG, WebP | 5 MB |
| `staff-photos` | Public | JPEG, PNG, WebP | 5 MB |
| `service-images` | Public | JPEG, PNG, WebP | 5 MB |
| `customer-profile-images` | Private | JPEG, PNG, WebP | 5 MB |
| `business-portfolios` | Public | JPEG, PNG, WebP | 10 MB |
| `business-documents` | Private | PDF, JPEG, PNG, WebP | 20 MB |

The migration sets the Supabase bucket MIME allowlists and size limits. Verify these settings in the hosted Storage dashboard after deployment because dashboard and migration configuration must agree.

## Object naming

Business objects use `business/<tenant_uuid>/<category>/<entity_uuid>/<asset_uuid>.webp`.

- Logos: `business/<tenant>/logo/<asset_uuid>.webp`
- Staff: `business/<tenant>/staff/<staff_uuid>/<asset_uuid>.webp`
- Services: `business/<tenant>/service/<service_uuid>/<asset_uuid>.webp`
- Portfolios: `business/<tenant>/portfolio/<asset_uuid>.webp`
- Documents: `business/<tenant>/documents/<document_uuid>/<asset_uuid>.<ext>`
- Customer profiles: `customer/<profile_uuid>/<asset_uuid>.webp`
- Thumbnails: `business/<tenant>/thumbnails/<asset_uuid>.webp`

## Authorization

Only authenticated users can write objects. Owner and manager roles may manage objects for their tenant. Customer profile objects may only be written or read by the matching authenticated profile. Public-bucket policies provide read access for public media; private-bucket policies require membership or ownership.

Storage and PostgreSQL policies both enforce authorization. Do not add service-role bypass policies for normal application requests.

## Upload workflow

1. The backend validates media type, size, tenant, profile, and entity identifiers.
2. The backend creates a signed upload URL and inserts a `public.media_assets` metadata row.
3. The browser uploads directly to Supabase Storage using that short-lived URL.
4. The application stores a reference to `media_assets.id` on the relevant entity.
5. The backend issues signed read URLs for private media.

Never trust browser MIME or size validation alone. Bucket limits and server-side validation are mandatory.

## Image efficiency

Frontend image handling resizes images to at most 1600 pixels, prefers WebP, and generates a 320-pixel thumbnail for gallery/listing use. Documents are never resized or renamed. Portfolio listing cards must use thumbnails or a compact transformation rather than full-resolution objects. Use pagination or lazy loading for galleries.

## Deletion and consistency

Deletion is performed only after authorization. Storage objects are removed first and metadata is removed second. Thumbnail objects and metadata are removed with their parent asset. Entity foreign keys use `ON DELETE SET NULL` or restricted portfolio/document foreign keys so accidental deletion cannot leave an entity pointing to missing media. Reconciliation should check for media metadata without Storage objects and Storage objects without metadata.

## Signed URL and public URL rules

Use signed URLs for `customer-profile-images` and `business-documents`. Use public URLs only for `business-logos`, `staff-photos`, `service-images`, and `business-portfolios`. Signed URLs should expire quickly and must not be cached indefinitely.

## Testing requirements

- Authorized tenant owner/manager upload.
- Unauthorized role rejection.
- Cross-tenant object and metadata rejection.
- MIME allowlist rejection.
- Size limit rejection.
- Customer profile signed URL access.
- Public bucket public URL access.
- Storage deletion and metadata consistency.

Do not upload real customer photographs or production files during tests. Development tests must use generated placeholder images and synthetic PDFs.
