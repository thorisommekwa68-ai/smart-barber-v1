CREATE OR REPLACE FUNCTION public.create_appointment(
  p_tenant_id uuid,
  p_location_id uuid,
  p_staff_id uuid,
  p_service_id uuid,
  p_start_at timestamptz,
  p_customer_notes text DEFAULT ''
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_profile_id uuid := auth.uid();
  v_tenant public.tenants%ROWTYPE;
  v_location public.locations%ROWTYPE;
  v_staff public.staff%ROWTYPE;
  v_service public.services%ROWTYPE;
  v_end_at timestamptz;
  v_hold_expires_at timestamptz := now() + interval '15 minutes';
  v_day smallint;
  v_tenant_hours public.operating_hours%ROWTYPE;
  v_staff_hours public.staff_hours%ROWTYPE;
  v_local_start time;
  v_local_end time;
  v_local_date date;
  v_appointment public.appointments;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  IF p_customer_notes IS NULL THEN p_customer_notes := ''; END IF;
  IF length(p_customer_notes) > 1000 THEN RAISE EXCEPTION 'customer notes exceed 1000 characters'; END IF;
  IF p_start_at IS NULL OR p_start_at <= now() THEN RAISE EXCEPTION 'booking start time must be in the future'; END IF;

  SELECT * INTO v_tenant FROM public.tenants WHERE id = p_tenant_id;
  IF NOT FOUND OR v_tenant.business_status <> 'active' THEN RAISE EXCEPTION 'active business not found'; END IF;
  SELECT * INTO v_location FROM public.locations WHERE id = p_location_id;
  IF NOT FOUND OR v_location.tenant_id <> p_tenant_id OR NOT v_location.active THEN RAISE EXCEPTION 'invalid location selection'; END IF;
  SELECT * INTO v_staff FROM public.staff WHERE id = p_staff_id;
  IF NOT FOUND OR v_staff.tenant_id <> p_tenant_id OR v_staff.location_id <> p_location_id OR v_staff.staff_status <> 'active' THEN RAISE EXCEPTION 'invalid staff selection'; END IF;
  SELECT * INTO v_service FROM public.services WHERE id = p_service_id;
  IF NOT FOUND OR v_service.tenant_id <> p_tenant_id OR v_service.service_status <> 'active' THEN RAISE EXCEPTION 'invalid service selection'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.staff_services ss WHERE ss.staff_id = p_staff_id AND ss.service_id = p_service_id) THEN RAISE EXCEPTION 'staff member is not assigned to the selected service'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_staff_id::text, 0));
  v_end_at := p_start_at + make_interval(mins => v_service.duration_minutes + v_service.buffer_minutes);
  v_local_date := (p_start_at AT TIME ZONE v_tenant.timezone)::date;
  v_day := (EXTRACT(ISODOW FROM p_start_at AT TIME ZONE v_tenant.timezone))::smallint;
  v_local_start := (p_start_at AT TIME ZONE v_tenant.timezone)::time;
  v_local_end := (v_end_at AT TIME ZONE v_tenant.timezone)::time;

  IF EXISTS (
    SELECT 1 FROM public.business_holidays bh
    WHERE bh.tenant_id = p_tenant_id AND bh.holiday_date = v_local_date AND bh.closed
  ) THEN RAISE EXCEPTION 'business is closed for a holiday'; END IF;

  SELECT * INTO v_tenant_hours FROM public.operating_hours
  WHERE tenant_id = p_tenant_id AND day_of_week = v_day;
  IF NOT FOUND THEN RAISE EXCEPTION 'business unavailable at this time'; END IF;
  SELECT * INTO v_staff_hours FROM public.staff_hours
  WHERE staff_id = p_staff_id AND day_of_week = v_day;
  IF NOT FOUND THEN RAISE EXCEPTION 'staff unavailable at this time'; END IF;
  IF v_local_start < v_tenant_hours.open_time
     OR v_local_end > v_tenant_hours.close_time
     OR v_local_start < v_staff_hours.start_time
     OR v_local_end > v_staff_hours.end_time THEN
    RAISE EXCEPTION 'appointment outside operating or staff working hours';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.staff_time_off sto
    WHERE sto.staff_id = p_staff_id
      AND tstzrange(sto.start_at, sto.end_at, '[)') && tstzrange(p_start_at, v_end_at, '[)')
  ) THEN RAISE EXCEPTION 'staff member is unavailable at this time'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.staff_breaks sb
    WHERE sb.staff_id = p_staff_id
      AND (
        (sb.start_at IS NOT NULL AND sb.end_at IS NOT NULL
          AND tstzrange(sb.start_at, sb.end_at, '[)') && tstzrange(p_start_at, v_end_at, '[)')
        )
        OR (
          sb.day_of_week = v_day
          AND sb.recurring_start_time IS NOT NULL
          AND sb.recurring_end_time IS NOT NULL
          AND v_local_start < sb.recurring_end_time
          AND v_local_end > sb.recurring_start_time
        )
      )
  ) THEN RAISE EXCEPTION 'staff member is on break at this time'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.appointments a
    WHERE a.staff_id = p_staff_id
      AND a.status IN ('pending', 'confirmed', 'in_progress')
      AND (a.status <> 'pending' OR (a.hold_expires_at IS NOT NULL AND a.hold_expires_at > now()))
      AND tstzrange(a.start_at, a.end_at, '[)') && tstzrange(p_start_at, v_end_at, '[)')
  ) THEN RAISE EXCEPTION 'selected staff member already has an overlapping appointment'; END IF;

  INSERT INTO public.appointments (
    tenant_id, location_id, customer_profile_id, staff_id, service_id,
    start_at, end_at, price_snapshot_minor, duration_snapshot_minutes,
    currency_code, status, customer_notes, hold_expires_at
  )
  VALUES (
    p_tenant_id, p_location_id, v_profile_id, p_staff_id, p_service_id,
    p_start_at, v_end_at, v_service.price_minor, v_service.duration_minutes,
    'ZAR', 'pending', left(p_customer_notes, 1000), v_hold_expires_at
  )
  RETURNING * INTO v_appointment;

  RETURN v_appointment;
END;
$$;

CREATE OR REPLACE FUNCTION public.reschedule_appointment(
  p_appointment_id uuid,
  p_start_at timestamptz
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_profile_id uuid := auth.uid();
  v_appointment public.appointments%ROWTYPE;
  v_staff public.staff%ROWTYPE;
  v_service public.services%ROWTYPE;
  v_tenant public.tenants%ROWTYPE;
  v_end_at timestamptz;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  SELECT * INTO v_appointment FROM public.appointments WHERE id = p_appointment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'appointment not found'; END IF;
  IF v_appointment.customer_profile_id <> v_profile_id THEN RAISE EXCEPTION 'cannot reschedule another customer appointment'; END IF;
  IF v_appointment.status IN ('completed', 'declined', 'cancelled', 'expired', 'no_show') THEN
    RAISE EXCEPTION 'terminal appointment cannot be rescheduled';
  END IF;
  IF p_start_at IS NULL OR p_start_at <= now() THEN RAISE EXCEPTION 'rescheduled start time must be in the future'; END IF;

  SELECT * INTO v_staff FROM public.staff WHERE id = v_appointment.staff_id;
  SELECT * INTO v_service FROM public.services WHERE id = v_appointment.service_id;
  SELECT * INTO v_tenant FROM public.tenants WHERE id = v_appointment.tenant_id;
  v_end_at := p_start_at + make_interval(mins => v_service.duration_minutes + v_service.buffer_minutes);

  PERFORM pg_advisory_xact_lock(hashtextextended(v_appointment.staff_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM public.appointments a
    WHERE a.id <> p_appointment_id
      AND a.staff_id = v_appointment.staff_id
      AND a.status IN ('pending', 'confirmed', 'in_progress')
      AND (a.status <> 'pending' OR (a.hold_expires_at IS NOT NULL AND a.hold_expires_at > now()))
      AND tstzrange(a.start_at, a.end_at, '[)') && tstzrange(p_start_at, v_end_at, '[)')
  ) THEN RAISE EXCEPTION 'the new time conflicts with another appointment'; END IF;

  PERFORM set_config('smart_barber.reschedule', 'true', true);
  UPDATE public.appointments
  SET start_at = p_start_at,
      end_at = p_start_at + make_interval(mins => v_service.duration_minutes),
      updated_at = now()
  WHERE id = p_appointment_id
  RETURNING * INTO v_appointment;

  RETURN v_appointment;
END;
$$;

REVOKE ALL ON FUNCTION public.reschedule_appointment(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment(uuid, timestamptz) TO authenticated;
