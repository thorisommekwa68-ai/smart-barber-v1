-- Storage security test checklist.
-- Execute in a non-production Supabase test project with synthetic identities and files.

BEGIN;

DO $$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(name, ', ') INTO missing
  FROM (VALUES
    ('business-logos'), ('staff-photos'), ('service-images'),
    ('customer-profile-images'), ('business-portfolios'), ('business-documents')
  ) expected(name)
  WHERE NOT EXISTS (SELECT 1 FROM storage.buckets b WHERE b.id = expected.name);

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'missing storage buckets: %', missing;
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'public_tenant_media_insert'
  ) THEN
    RAISE EXCEPTION 'tenant media insert policy is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'customer_profile_write'
  ) THEN
    RAISE EXCEPTION 'customer profile write policy is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'private_documents_read'
  ) THEN
    RAISE EXCEPTION 'private document read policy is missing';
  END IF;
END;
$$;

ROLLBACK;
