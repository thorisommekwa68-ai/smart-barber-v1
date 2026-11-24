-- Rollback Smart Barber Supabase migrations 52800 through 535.
-- Run this only in a disposable or explicitly approved rollback environment.

BEGIN;

-- Remove publication and realtime-created trigger dependencies first.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'appointments'
    ) THEN
      ALTER PUBLICATION supabase_realtime DROP TABLE public.appointments;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'appointment_events'
    ) THEN
      ALTER PUBLICATION supabase_realtime DROP TABLE public.appointment_events;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'notifications'
    ) THEN
      ALTER PUBLICATION supabase_realtime DROP TABLE public.notifications;
    END IF;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
DROP TRIGGER IF EXISTS set_tenants_updated_at ON public.tenants;
DROP TRIGGER IF EXISTS set_locations_updated_at ON public.locations;
DROP TRIGGER IF EXISTS set_staff_updated_at ON public.staff;
DROP TRIGGER IF EXISTS set_services_updated_at ON public.services;
DROP TRIGGER IF EXISTS set_appointments_updated_at ON public.appointments;
DROP TRIGGER IF EXISTS set_plans_updated_at ON public.subscription_plans;
DROP TRIGGER IF EXISTS set_subscriptions_updated_at ON public.tenant_subscriptions;
DROP TRIGGER IF EXISTS set_payments_updated_at ON public.payment_transactions;
DROP TRIGGER IF EXISTS set_platform_admin_updated_at ON public.platform_administrators;
DROP TRIGGER IF EXISTS expire_pending_appointment_hold_before_write ON public.appointments;
DROP TRIGGER IF EXISTS validate_appointment_lifecycle_before_update ON public.appointments;
DROP TRIGGER IF EXISTS validate_appointment_relationships_before_write ON public.appointments;
DROP TRIGGER IF EXISTS record_appointment_event_after_write ON public.appointments;
DROP TRIGGER IF EXISTS notify_appointment_change_after_write ON public.appointments;
DROP TRIGGER IF EXISTS validate_appointment_write_before_update ON public.appointments;
DROP TRIGGER IF EXISTS validate_profile_write_before_update ON public.profiles;
DROP TRIGGER IF EXISTS validate_membership_write_before_insert ON public.tenant_memberships;
DROP TRIGGER IF EXISTS validate_membership_write_before_update ON public.tenant_memberships;
DROP TRIGGER IF EXISTS validate_platform_role_assignment_before_insert ON public.platform_role_assignments;
DROP TRIGGER IF EXISTS validate_platform_role_assignment_before_update ON public.platform_role_assignments;
DROP TRIGGER IF EXISTS validate_staff_location_before_write ON public.staff;
DROP TRIGGER IF EXISTS validate_staff_service_before_write ON public.staff_services;

-- Appointment RPCs must be dropped before public.appointments because
-- their return types or row types depend on that table.
DROP FUNCTION IF EXISTS public.reschedule_appointment(uuid, timestamptz);
DROP FUNCTION IF EXISTS public.transition_appointment(uuid, smart_barber_appointment_status);
DROP FUNCTION IF EXISTS public.create_appointment(uuid, uuid, uuid, uuid, timestamptz, text);
DROP FUNCTION IF EXISTS public.expire_pending_appointment_holds();
DROP FUNCTION IF EXISTS public.expire_pending_appointment_hold();
DROP FUNCTION IF EXISTS public.record_appointment_event();
DROP FUNCTION IF EXISTS public.notify_appointment_change();
DROP FUNCTION IF EXISTS public.validate_appointment_lifecycle();
DROP FUNCTION IF EXISTS public.validate_appointment_relationships();
DROP FUNCTION IF EXISTS public.validate_appointment_write();
DROP FUNCTION IF EXISTS public.validate_profile_write();
DROP FUNCTION IF EXISTS public.validate_membership_write();
DROP FUNCTION IF EXISTS public.validate_platform_role_assignment();
DROP FUNCTION IF EXISTS public.validate_staff_location();
DROP FUNCTION IF EXISTS public.validate_staff_service();
DROP FUNCTION IF EXISTS public.set_updated_at();
DROP FUNCTION IF EXISTS public.handle_auth_user_created();
DROP FUNCTION IF EXISTS public.is_platform_administrator();
DROP FUNCTION IF EXISTS public.has_tenant_role(uuid, text[]);
DROP FUNCTION IF EXISTS public.is_tenant_member(uuid);

-- Remove Storage policies and synthetic objects.
DROP POLICY IF EXISTS public_logos_read ON storage.objects;
DROP POLICY IF EXISTS public_staff_read ON storage.objects;
DROP POLICY IF EXISTS public_services_read ON storage.objects;
DROP POLICY IF EXISTS public_portfolios_read ON storage.objects;
DROP POLICY IF EXISTS public_tenant_media_insert ON storage.objects;
DROP POLICY IF EXISTS public_tenant_media_update ON storage.objects;
DROP POLICY IF EXISTS public_tenant_media_delete ON storage.objects;
DROP POLICY IF EXISTS customer_profile_read ON storage.objects;
DROP POLICY IF EXISTS customer_profile_write ON storage.objects;
DROP POLICY IF EXISTS customer_profile_update ON storage.objects;
DROP POLICY IF EXISTS customer_profile_delete ON storage.objects;
DROP POLICY IF EXISTS private_documents_read ON storage.objects;
DROP POLICY IF EXISTS private_documents_write ON storage.objects;
DROP POLICY IF EXISTS private_documents_update ON storage.objects;
DROP POLICY IF EXISTS private_documents_delete ON storage.objects;

DELETE FROM storage.objects
WHERE bucket_id IN (
  'business-logos',
  'staff-photos',
  'service-images',
  'customer-profile-images',
  'business-portfolios',
  'business-documents'
);
DELETE FROM storage.buckets
WHERE id IN (
  'business-logos',
  'staff-photos',
  'service-images',
  'customer-profile-images',
  'business-portfolios',
  'business-documents'
);

-- Remove media references before media_assets to avoid FK dependency errors.
ALTER TABLE IF EXISTS public.tenants DROP COLUMN IF EXISTS logo_media_id;
ALTER TABLE IF EXISTS public.staff DROP COLUMN IF EXISTS photo_media_id;
ALTER TABLE IF EXISTS public.services DROP COLUMN IF EXISTS image_media_id;
ALTER TABLE IF EXISTS public.profiles DROP COLUMN IF EXISTS avatar_media_id;
DROP TABLE IF EXISTS public.business_documents;
DROP TABLE IF EXISTS public.business_portfolio_items;
DROP TABLE IF EXISTS public.media_assets;

-- Domain tables.
DROP TABLE IF EXISTS public.platform_audit_logs;
DROP TABLE IF EXISTS public.platform_role_assignments;
DROP TABLE IF EXISTS public.platform_administrators;
DROP TABLE IF EXISTS public.payment_transactions;
DROP TABLE IF EXISTS public.tenant_subscriptions;
DROP TABLE IF EXISTS public.subscription_plans;
DROP TABLE IF EXISTS public.notifications;
DROP TABLE IF EXISTS public.customer_favourites;
DROP TABLE IF EXISTS public.customer_relationships;
DROP TABLE IF EXISTS public.appointment_events;
DROP TABLE IF EXISTS public.appointments;
DROP TABLE IF EXISTS public.business_holidays;
DROP TABLE IF EXISTS public.staff_time_off;
DROP TABLE IF EXISTS public.staff_breaks;
DROP TABLE IF EXISTS public.staff_hours;
DROP TABLE IF EXISTS public.operating_hours;
DROP TABLE IF EXISTS public.staff_services;
DROP TABLE IF EXISTS public.services;
DROP TABLE IF EXISTS public.staff;
DROP TABLE IF EXISTS public.locations;
DROP TABLE IF EXISTS public.tenant_memberships;
DROP TABLE IF EXISTS public.tenants;
DROP TABLE IF EXISTS public.profiles;

DROP TYPE IF EXISTS smart_barber_platform_status;
DROP TYPE IF EXISTS smart_barber_platform_role;
DROP TYPE IF EXISTS smart_barber_appointment_status;
DROP TYPE IF EXISTS smart_barber_staff_status;
DROP TYPE IF EXISTS smart_barber_service_status;
DROP TYPE IF EXISTS smart_barber_business_status;
DROP TYPE IF EXISTS smart_barber_member_status;
DROP TYPE IF EXISTS smart_barber_member_role;

COMMIT;
