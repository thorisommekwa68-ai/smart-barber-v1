DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE
      public.appointments,
      public.appointment_events,
      public.notifications;
  EXCEPTION
    WHEN undefined_object THEN
      RAISE NOTICE 'supabase_realtime publication is unavailable outside Supabase';
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_appointment(
  p_appointment_id uuid,
  p_next_status smart_barber_appointment_status
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_appointment public.appointments%ROWTYPE;
  v_profile_id uuid := auth.uid();
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment not found';
  END IF;

  IF v_appointment.customer_profile_id <> v_profile_id
     AND NOT public.is_tenant_member(v_appointment.tenant_id)
     AND NOT public.is_platform_administrator() THEN
    RAISE EXCEPTION 'not authorized to update appointment';
  END IF;

  IF v_appointment.customer_profile_id = v_profile_id
     AND p_next_status <> 'cancelled' THEN
    RAISE EXCEPTION 'customer may only cancel an appointment';
  END IF;

  IF v_appointment.customer_profile_id <> v_profile_id
     AND NOT public.has_tenant_role(
       v_appointment.tenant_id,
       ARRAY['owner', 'manager', 'receptionist', 'stylist']
     ) THEN
    RAISE EXCEPTION 'not authorized for merchant appointment transition';
  END IF;

  UPDATE public.appointments
  SET status = p_next_status
  WHERE id = p_appointment_id
  RETURNING * INTO v_appointment;

  RETURN v_appointment;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_appointment(
  uuid, smart_barber_appointment_status
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_appointment(
  uuid, smart_barber_appointment_status
) TO authenticated;
