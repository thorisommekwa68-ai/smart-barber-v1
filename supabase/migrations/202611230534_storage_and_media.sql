-- Storage buckets are public only where the media is intentionally public.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('business-logos', 'business-logos', true, 5242880, ARRAY['image/jpeg','image/png','image/webp']),
  ('staff-photos', 'staff-photos', true, 5242880, ARRAY['image/jpeg','image/png','image/webp']),
  ('service-images', 'service-images', true, 5242880, ARRAY['image/jpeg','image/png','image/webp']),
  ('customer-profile-images', 'customer-profile-images', false, 5242880, ARRAY['image/jpeg','image/png','image/webp']),
  ('business-portfolios', 'business-portfolios', true, 10485760, ARRAY['image/jpeg','image/png','image/webp']),
  ('business-documents', 'business-documents', false, 20971520,
   ARRAY['application/pdf','image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE TABLE public.media_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  owner_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  bucket text NOT NULL,
  object_path text NOT NULL UNIQUE,
  media_type text NOT NULL CHECK (media_type IN (
    'business_logo','staff_photo','service_image','customer_profile',
    'portfolio_image','business_document','thumbnail'
  )),
  mime_type text NOT NULL,
  byte_size bigint NOT NULL CHECK (byte_size >= 0),
  width integer,
  height integer,
  thumbnail_path text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_assets_tenant_or_profile CHECK (
    tenant_id IS NOT NULL OR owner_profile_id IS NOT NULL
  )
);

CREATE TABLE public.business_portfolio_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  media_asset_id uuid NOT NULL REFERENCES public.media_assets(id) ON DELETE RESTRICT,
  sort_order integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.business_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  media_asset_id uuid NOT NULL REFERENCES public.media_assets(id) ON DELETE RESTRICT,
  document_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS logo_media_id uuid
  REFERENCES public.media_assets(id) ON DELETE SET NULL;
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS photo_media_id uuid
  REFERENCES public.media_assets(id) ON DELETE SET NULL;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS image_media_id uuid
  REFERENCES public.media_assets(id) ON DELETE SET NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_media_id uuid
  REFERENCES public.media_assets(id) ON DELETE SET NULL;

ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_portfolio_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY media_assets_public_read ON public.media_assets
FOR SELECT USING (
  bucket IN ('business-logos','staff-photos','service-images','business-portfolios')
  OR (bucket = 'customer-profile-images' AND owner_profile_id = auth.uid())
);

CREATE POLICY media_assets_tenant_manage ON public.media_assets
FOR ALL USING (
  (tenant_id IS NOT NULL AND public.has_tenant_role(tenant_id, ARRAY['owner','manager']))
  OR (owner_profile_id = auth.uid())
) WITH CHECK (
  (tenant_id IS NOT NULL AND public.has_tenant_role(tenant_id, ARRAY['owner','manager']))
  OR (owner_profile_id = auth.uid())
);

CREATE POLICY portfolio_public_read ON public.business_portfolio_items
FOR SELECT USING (
  active = true AND EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = business_portfolio_items.tenant_id AND t.business_status = 'active'
  )
);

CREATE POLICY portfolio_tenant_manage ON public.business_portfolio_items
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner','manager'])
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner','manager'])
);

CREATE POLICY documents_tenant_manage ON public.business_documents
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner','manager'])
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner','manager'])
);

-- Public storage objects
CREATE POLICY public_logos_read ON storage.objects FOR SELECT TO public
USING (bucket_id = 'business-logos');
CREATE POLICY public_staff_read ON storage.objects FOR SELECT TO public
USING (bucket_id = 'staff-photos');
CREATE POLICY public_services_read ON storage.objects FOR SELECT TO public
USING (bucket_id = 'service-images');
CREATE POLICY public_portfolios_read ON storage.objects FOR SELECT TO public
USING (bucket_id = 'business-portfolios');

-- Public-bucket tenant writes. Folder: business/<tenant_uuid>/<kind>/<asset_uuid>.webp
CREATE POLICY public_tenant_media_insert ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id IN ('business-logos','staff-photos','service-images','business-portfolios')
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(
    ((storage.foldername(name))[2])::uuid,
    ARRAY['owner','manager']
  )
);

CREATE POLICY public_tenant_media_update ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id IN ('business-logos','staff-photos','service-images','business-portfolios')
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
) WITH CHECK (
  bucket_id IN ('business-logos','staff-photos','service-images','business-portfolios')
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
);

CREATE POLICY public_tenant_media_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id IN ('business-logos','staff-photos','service-images','business-portfolios')
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
);

-- Customer profile images are private and confined to the customer's own UUID folder.
CREATE POLICY customer_profile_read ON storage.objects
FOR SELECT TO authenticated USING (
  bucket_id = 'customer-profile-images'
  AND (storage.foldername(name))[1] = 'customer'
  AND (storage.foldername(name))[2] = auth.uid()::text
);

CREATE POLICY customer_profile_write ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'customer-profile-images'
  AND (storage.foldername(name))[1] = 'customer'
  AND (storage.foldername(name))[2] = auth.uid()::text
);

CREATE POLICY customer_profile_update ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'customer-profile-images'
  AND (storage.foldername(name))[1] = 'customer'
  AND (storage.foldername(name))[2] = auth.uid()::text
) WITH CHECK (
  bucket_id = 'customer-profile-images'
  AND (storage.foldername(name))[1] = 'customer'
  AND (storage.foldername(name))[2] = auth.uid()::text
);

CREATE POLICY customer_profile_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'customer-profile-images'
  AND (storage.foldername(name))[1] = 'customer'
  AND (storage.foldername(name))[2] = auth.uid()::text
);

-- Private business documents require owner or manager membership.
CREATE POLICY private_documents_read ON storage.objects
FOR SELECT TO authenticated USING (
  bucket_id = 'business-documents'
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
);

CREATE POLICY private_documents_write ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'business-documents'
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
);

CREATE POLICY private_documents_update ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'business-documents'
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
) WITH CHECK (
  bucket_id = 'business-documents'
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
);

CREATE POLICY private_documents_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'business-documents'
  AND (storage.foldername(name))[1] = 'business'
  AND public.has_tenant_role(((storage.foldername(name))[2])::uuid, ARRAY['owner','manager'])
);

CREATE INDEX media_assets_tenant_idx ON public.media_assets(tenant_id);
CREATE INDEX media_assets_owner_idx ON public.media_assets(owner_profile_id);
CREATE INDEX portfolio_tenant_active_idx ON public.business_portfolio_items(tenant_id, active, sort_order);
