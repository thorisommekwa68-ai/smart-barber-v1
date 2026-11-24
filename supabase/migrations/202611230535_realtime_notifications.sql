-- Realtime is intentionally limited to authorization-safe event-shaped rows.
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.appointments;
  EXCEPTION
    WHEN undefined_table THEN NULL;
    WHEN undefined_object THEN NULL;
  END;
END;
$$;

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE
      public.appointment_events,
      public.notifications;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN undefined_object THEN NULL;
  END;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_recipient_type_appointment
ON public.notifications (
  recipient_profile_id,
  type,
  ((payload ->> 'appointment_id'))
)
WHERE payload ? 'appointment_id';

CREATE OR REPLACE FUNCTION public.record_appointment_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.appointment_events (appointment_id, from_status, to_status, metadata)
    VALUES (NEW.id, NULL, NEW.status,
      jsonb_build_object('action', 'created', 'start_at', NEW.start_at, 'end_at', NEW.end_at));
  ELSE
    INSERT INTO public.appointment_events (appointment_id, from_status, to_status, metadata)
    VALUES (
      NEW.id,
      OLD.status,
      NEW.status,
      CASE
        WHEN NEW.status IS DISTINCT FROM OLD.status THEN
          jsonb_build_object('action', 'status_changed',
            'start_at', NEW.start_at, 'end_at', NEW.end_at)
        ELSE
          jsonb_build_object('action', 'rescheduled',
            'start_at', NEW.start_at, 'end_at', NEW.end_at)
      END
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS record_appointment_event_after_write ON public.appointments;
CREATE TRIGGER record_appointment_event_after_write
AFTER INSERT OR UPDATE OF status, start_at, end_at ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.record_appointment_event();

CREATE OR REPLACE FUNCTION public.notify_appointment_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member uuid;
  v_type text;
  v_payload jsonb;
  v_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_payload := jsonb_build_object(
      'appointment_id', NEW.id,
      'tenant_id', NEW.tenant_id,
      'status', NEW.status,
      'action', 'created',
      'start_at', NEW.start_at,
      'end_at', NEW.end_at
    );

    INSERT INTO public.notifications (tenant_id, recipient_profile_id, type, payload)
    SELECT NEW.tenant_id, NEW.customer_profile_id, 'appointment_created', v_payload
    WHERE NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_profile_id = NEW.customer_profile_id
        AND n.type = 'appointment_created'
        AND n.payload ->> 'appointment_id' = NEW.id::text
    );

    FOR v_member IN
      SELECT tm.profile_id
      FROM public.tenant_memberships tm
      WHERE tm.tenant_id = NEW.tenant_id
        AND tm.membership_status = 'active'
        AND tm.role::text IN ('owner','manager','receptionist','stylist')
    LOOP
      INSERT INTO public.notifications (tenant_id, recipient_profile_id, type, payload)
      SELECT NEW.tenant_id, v_member, 'booking_created', v_payload
      WHERE NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_profile_id = v_member
          AND n.type = 'booking_created'
          AND n.payload ->> 'appointment_id' = NEW.id::text
      );
    END LOOP;
    RETURN NEW;
  END IF;

  v_changed := NEW.status IS DISTINCT FROM OLD.status
    OR NEW.start_at IS DISTINCT FROM OLD.start_at
    OR NEW.end_at IS DISTINCT FROM OLD.end_at;
  IF NOT v_changed THEN
    RETURN NEW;
  END IF;

  IF NEW.start_at IS DISTINCT FROM OLD.start_at OR NEW.end_at IS DISTINCT FROM OLD.end_at THEN
    v_type := 'appointment_rescheduled';
  ELSE
    v_type := CASE NEW.status::text
      WHEN 'confirmed' THEN 'appointment_accepted'
      WHEN 'declined' THEN 'appointment_rejected'
      WHEN 'cancelled' THEN 'appointment_cancelled'
      ELSE 'appointment_status'
    END;
  END IF;

  v_payload := jsonb_build_object(
    'appointment_id', NEW.id,
    'tenant_id', NEW.tenant_id,
    'status', NEW.status,
    'action', v_type,
    'start_at', NEW.start_at,
    'end_at', NEW.end_at
  );

  INSERT INTO public.notifications (tenant_id, recipient_profile_id, type, payload)
  SELECT NEW.tenant_id, NEW.customer_profile_id, v_type, v_payload
  WHERE NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.recipient_profile_id = NEW.customer_profile_id
      AND n.type = v_type
      AND n.payload ->> 'appointment_id' = NEW.id::text
  );

  IF v_type IN ('appointment_cancelled','appointment_rescheduled') THEN
    FOR v_member IN
      SELECT tm.profile_id
      FROM public.tenant_memberships tm
      WHERE tm.tenant_id = NEW.tenant_id
        AND tm.membership_status = 'active'
        AND tm.role::text IN ('owner','manager','receptionist','stylist')
    LOOP
      INSERT INTO public.notifications (tenant_id, recipient_profile_id, type, payload)
      SELECT NEW.tenant_id, v_member, v_type, v_payload
      WHERE NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_profile_id = v_member
          AND n.type = v_type
          AND n.payload ->> 'appointment_id' = NEW.id::text
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_appointment_change_after_write ON public.appointments;
CREATE TRIGGER notify_appointment_change_after_write
AFTER INSERT OR UPDATE OF status, start_at, end_at ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.notify_appointment_change();
