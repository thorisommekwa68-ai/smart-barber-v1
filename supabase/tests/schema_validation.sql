BEGIN;

INSERT INTO auth.users (id, email, phone, raw_user_meta_data)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'customer@example.test', '+27...', '{}'::jsonb),
  ('10000000-0000-0000-0000-000000000002', 'owner@example.test', NULL, '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Auth trigger creates profiles in a Supabase database; compatibility insert for local validation.
INSERT INTO public.profiles (id, display_name, email)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'Customer', 'customer@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'Owner', 'owner@example.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenants (id, business_name, timezone, currency_code)
VALUES ('20000000-0000-0000-0000-000000000001', 'Crown Test', 'Africa/Johannesburg', 'ZAR');

INSERT INTO public.locations (id, tenant_id, name, address, timezone)
VALUES ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Rosebank', 'Rosebank', 'Africa/Johannesburg');

INSERT INTO public.staff (id, tenant_id, location_id, display_name)
VALUES ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Thabo');

INSERT INTO public.services (id, tenant_id, name, price_minor, duration_minutes, buffer_minutes)
VALUES ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Cut', 18000, 45, 10);

INSERT INTO public.staff_services (staff_id, service_id)
VALUES ('40000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001');

INSERT INTO public.operating_hours (tenant_id, day_of_week, open_time, close_time)
VALUES ('20000000-0000-0000-0000-000000000001', 1, '09:00', '18:00');

INSERT INTO public.staff_hours (staff_id, day_of_week, start_time, end_time)
VALUES ('40000000-0000-0000-0000-000000000001', 1, '09:00', '18:00');

INSERT INTO public.appointments (
  tenant_id, location_id, customer_profile_id, staff_id, service_id,
  start_at, end_at, price_snapshot_minor, duration_snapshot_minutes,
  currency_code, status, hold_expires_at
) VALUES (
  '20000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  '2027-11-22 08:00:00+00',
  '2027-11-22 08:45:00+00',
  18000,
  45,
  'ZAR',
  'confirmed',
  NULL
);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.appointments (
      tenant_id, location_id, customer_profile_id, staff_id, service_id,
      start_at, end_at, price_snapshot_minor, duration_snapshot_minutes,
      currency_code, status, hold_expires_at
    ) VALUES (
      '20000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000001',
      '50000000-0000-0000-0000-000000000001',
      '2027-11-22 08:30:00+00',
      '2027-11-22 09:15:00+00',
      18000,
      45,
      'ZAR',
      'confirmed',
      NULL
    );
    RAISE EXCEPTION 'overlapping appointment unexpectedly accepted';
  EXCEPTION
    WHEN exclusion_violation THEN
      NULL;
  END;
END;
$$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.services (tenant_id, name, price_minor, duration_minutes)
    VALUES ('20000000-0000-0000-0000-000000000001', 'Invalid currency test', -1, 30);
    RAISE EXCEPTION 'negative price unexpectedly accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
END;
$$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.appointments (
      tenant_id, location_id, customer_profile_id, staff_id, service_id,
      start_at, end_at, price_snapshot_minor, duration_snapshot_minutes,
      currency_code, status
    ) VALUES (
      '20000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000001',
      '50000000-0000-0000-0000-000000000001',
      '2027-11-23 08:00:00+00',
      '2027-11-23 07:00:00+00',
      18000,
      45,
      'ZAR',
      'confirmed'
    );
    RAISE EXCEPTION 'invalid time range unexpectedly accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
END;
$$;

DO $$
DECLARE
  v_profile_id uuid := '10000000-0000-0000-0000-000000000001';
  v_tenant_name text;
BEGIN
  SELECT business_name INTO v_tenant_name
  FROM public.tenants
  WHERE id = '20000000-0000-0000-0000-000000000001';
  IF v_tenant_name IS NULL THEN RAISE EXCEPTION 'timezone/tenant seed validation failed'; END IF;
  IF (SELECT timezone FROM public.tenants WHERE id = '20000000-0000-0000-0000-000000000001') <> 'Africa/Johannesburg'
  THEN RAISE EXCEPTION 'tenant timezone mismatch'; END IF;
  IF (SELECT price_minor FROM public.services WHERE id = '50000000-0000-0000-0000-000000000001') <> 18000
  THEN RAISE EXCEPTION 'ZAR minor-unit mismatch'; END IF;
END;
$$;

ROLLBACK;
