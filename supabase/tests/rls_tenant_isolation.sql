BEGIN;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE ROLE customer_a NOLOGIN;
CREATE ROLE customer_b NOLOGIN;
CREATE ROLE merchant_a NOLOGIN;
CREATE ROLE merchant_b NOLOGIN;
CREATE ROLE outsider NOLOGIN;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT, UPDATE ON public.appointments TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.customer_relationships TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.customer_favourites TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.notifications TO authenticated;

INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES
  ('10000000-0000-4000-8000-000000000001', 'a@test.example', '{}'::jsonb),
  ('10000000-0000-4000-8000-000000000002', 'b@test.example', '{}'::jsonb),
  ('10000000-0000-4000-8000-000000000003', 'owner-a@test.example', '{}'::jsonb),
  ('10000000-0000-4000-8000-000000000004', 'owner-b@test.example', '{}'::jsonb),
  ('10000000-0000-4000-8000-000000000005', 'outsider@test.example', '{}'::jsonb)
ON CONFLICT DO NOTHING;

INSERT INTO public.profiles (id, display_name, email) VALUES
  ('10000000-0000-4000-8000-000000000001', 'Customer A', 'a@test.example'),
  ('10000000-0000-4000-8000-000000000002', 'Customer B', 'b@test.example'),
  ('10000000-0000-4000-8000-000000000003', 'Merchant A', 'owner-a@test.example'),
  ('10000000-0000-4000-8000-000000000004', 'Merchant B', 'owner-b@test.example'),
  ('10000000-0000-4000-8000-000000000005', 'Outsider', 'outsider@test.example')
ON CONFLICT DO NOTHING;

INSERT INTO public.tenants (id, business_name)
VALUES
  ('20000000-0000-4000-8000-000000000001', 'Tenant A'),
  ('20000000-0000-4000-8000-000000000002', 'Tenant B');

INSERT INTO public.tenant_memberships (tenant_id, profile_id, role, membership_status)
VALUES
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', 'owner', 'active'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000004', 'owner', 'active');

INSERT INTO public.locations (id, tenant_id, name, timezone)
VALUES
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'A Location', 'Africa/Johannesburg'),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'B Location', 'Africa/Johannesburg');

INSERT INTO public.staff (id, tenant_id, location_id, display_name)
VALUES
  ('40000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'Staff A'),
  ('40000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', 'Staff B');

INSERT INTO public.services (id, tenant_id, name, price_minor, duration_minutes, buffer_minutes)
VALUES
  ('50000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Cut A', 18000, 45, 0),
  ('50000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'Cut B', 18000, 45, 0);

INSERT INTO public.staff_services (staff_id, service_id)
VALUES
  ('40000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001'),
  ('40000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000002');

INSERT INTO public.appointments (
  id, tenant_id, location_id, customer_profile_id, staff_id, service_id,
  start_at, end_at, price_snapshot_minor, duration_snapshot_minutes,
  currency_code, status, hold_expires_at
) VALUES
  (
    '60000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001',
    '2027-11-22 08:00:00+00',
    '2027-11-22 08:45:00+00',
    18000, 45, 'ZAR', 'confirmed', NULL
  ),
  (
    '60000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002',
    '40000000-0000-4000-8000-000000000002',
    '50000000-0000-4000-8000-000000000002',
    '2027-11-22 09:00:00+00',
    '2027-11-22 09:45:00+00',
    18000, 45, 'ZAR', 'confirmed', NULL
  );

-- Customer A profile isolation.
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
DO $$
BEGIN
  IF (SELECT count(*) FROM public.profiles WHERE id = '10000000-0000-4000-8000-000000000002') <> 0 THEN
    RAISE EXCEPTION 'Customer A can read Customer B profile';
  END IF;
END;
$$;

-- Customer A cannot update Customer B appointment.
DO $$
BEGIN
  BEGIN
    UPDATE public.appointments
    SET status = 'cancelled'
    WHERE id = '60000000-0000-4000-8000-000000000002';
    IF EXISTS (SELECT 1 FROM public.appointments WHERE id = '60000000-0000-4000-8000-000000000002' AND status = 'cancelled') THEN
      RAISE EXCEPTION 'Customer A modified Customer B appointment';
    END IF;
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

-- Merchant A cannot read or update Tenant B appointments.
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.appointments WHERE tenant_id = '20000000-0000-4000-8000-000000000002') THEN
    RAISE EXCEPTION 'Merchant A read Tenant B appointment';
  END IF;
END;
$$;
DO $$
BEGIN
  BEGIN
    UPDATE public.appointments
    SET status = 'cancelled'
    WHERE id = '60000000-0000-4000-8000-000000000002';
    IF EXISTS (SELECT 1 FROM public.appointments WHERE id = '60000000-0000-4000-8000-000000000002' AND status = 'cancelled') THEN
      RAISE EXCEPTION 'Merchant A modified Tenant B appointment';
    END IF;
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

-- User without membership cannot read merchant data.
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000005';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.appointments WHERE tenant_id = '20000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'outsider read merchant appointment';
  END IF;
END;
$$;
RESET ROLE;

-- A member cannot insert their own elevated owner membership.
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
DO $$
BEGIN
  BEGIN
    INSERT INTO public.tenant_memberships (tenant_id, profile_id, role, membership_status)
    VALUES ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'owner', 'active');
    RAISE EXCEPTION 'membership role escalation unexpectedly succeeded';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
    WHEN raise_exception THEN
      IF SQLERRM = 'membership role escalation unexpectedly succeeded' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- A platform role cannot be inferred from merchant membership.
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
DO $$
BEGIN
  IF public.is_platform_administrator() THEN
    RAISE EXCEPTION 'merchant membership granted platform access';
  END IF;
END;
$$;
RESET ROLE;

ROLLBACK;
