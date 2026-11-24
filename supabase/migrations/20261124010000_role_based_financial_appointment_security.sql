-- Review draft: role-based appointment and payment security.
-- Source-audited against migrations 52800-535. Do not deploy until the
-- preflight queries and unresolved workflow decisions in the review report
-- have been reviewed against the target Supabase database.
--
-- Preflight (run manually before this migration):
-- SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename IN ('appointments', 'appointment_events', 'notifications', 'payment_transactions')
-- ORDER BY tablename, policyname;
-- SELECT grantee, table_name, privilege_type
-- FROM information_schema.role_table_grants
-- WHERE table_schema = 'public'
--   AND table_name IN ('appointments', 'appointment_events', 'notifications', 'payment_transactions')
-- ORDER BY table_name, grantee, privilege_type;
-- SELECT grantee, table_name, column_name, privilege_type
-- FROM information_schema.column_privileges
-- WHERE table_schema = 'public'
--   AND table_name IN ('appointments', 'appointment_events', 'notifications', 'payment_transactions')
-- ORDER BY table_name, grantee, column_name, privilege_type;
-- SELECT defaclrole::regrole AS grantor, defaclnamespace::regnamespace AS schema_name,
--        defaclobjtype AS object_type, defaclacl
-- FROM pg_default_acl
-- WHERE defaclnamespace = 'public'::regnamespace;
-- SELECT p.oid::regprocedure AS function_signature,
--        pg_get_userbyid(p.proowner) AS owner,
--        p.prosecdef AS security_definer,
--        p.proconfig AS function_settings,
--        pg_get_functiondef(p.oid) AS definition
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname IN ('create_appointment', 'transition_appointment',
--       'reschedule_appointment', 'validate_appointment_write',
--       'validate_appointment_lifecycle', 'validate_appointment_relationships',
--       'expire_pending_appointment_hold', 'expire_pending_appointment_holds',
--       'record_appointment_event', 'notify_appointment_change');
-- SELECT roleid::regrole AS granted_role, member::regrole AS member_role
-- FROM pg_auth_members
-- WHERE member IN ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole);
-- Retain a schema-only dump (no application rows) as a rollback reference:
-- pg_dump --schema-only --schema=public --file=pre_security_schema.sql <connection-string>

BEGIN;

-- Remove every existing policy on the protected tables so no permissive policy
-- can continue granting access through PostgreSQL's OR policy semantics.
DO $$
DECLARE
  v_policy record;
BEGIN
  FOR v_policy IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('appointments', 'appointment_events', 'notifications', 'payment_transactions')
  LOOP
    EXECUTE format(
      'DROP POLICY %I ON %I.%I',
      v_policy.policyname,
      v_policy.schemaname,
      v_policy.tablename
    );
  END LOOP;
END;
$$;

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Remove table and column ACLs from client roles. Column ACLs must be cleared
-- separately because revoking table privileges does not remove them.
REVOKE ALL PRIVILEGES ON TABLE public.appointments FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.appointment_events FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.payment_transactions FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_table regclass;
  v_column record;
  v_role text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'public.appointments'::regclass,
    'public.appointment_events'::regclass,
    'public.payment_transactions'::regclass
  ]
  LOOP
    FOR v_column IN
      SELECT a.attname
      FROM pg_attribute a
      WHERE a.attrelid = v_table
        AND a.attnum > 0
        AND NOT a.attisdropped
    LOOP
      EXECUTE format(
        'REVOKE ALL PRIVILEGES (%I) ON TABLE %s FROM PUBLIC',
        v_column.attname,
        v_table
      );
      FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated']
      LOOP
        EXECUTE format(
          'REVOKE ALL PRIVILEGES (%I) ON TABLE %s FROM %I',
          v_column.attname,
          v_table,
          v_role
        );
      END LOOP;
    END LOOP;
  END LOOP;
END;
$$;

-- A private, one-use transaction capability distinguishes validated schedule
-- changes from status changes. Application roles have neither schema access
-- nor table privileges, and the validating trigger consumes the capability.
CREATE SCHEMA IF NOT EXISTS smart_barber_private AUTHORIZATION postgres;
ALTER SCHEMA smart_barber_private OWNER TO postgres;
REVOKE ALL ON SCHEMA smart_barber_private FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS smart_barber_private.appointment_operation_guard (
  transaction_id bigint NOT NULL,
  appointment_id uuid NOT NULL,
  actor_profile_id uuid NOT NULL,
  operation text NOT NULL CHECK (operation = 'reschedule'),
  PRIMARY KEY (transaction_id, appointment_id, operation)
);
ALTER TABLE smart_barber_private.appointment_operation_guard OWNER TO postgres;
ALTER TABLE smart_barber_private.appointment_operation_guard ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE smart_barber_private.appointment_operation_guard
  FROM PUBLIC, anon, authenticated, service_role;

-- Appointment rows may be read only through customer ownership, an active
-- merchant role, an assigned stylist identity, or separate platform admin.
CREATE POLICY appointments_customer_select ON public.appointments
FOR SELECT TO authenticated
USING (customer_profile_id = auth.uid());

CREATE POLICY appointments_merchant_select ON public.appointments
FOR SELECT TO authenticated
USING (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager', 'receptionist'])
  OR (
    public.has_tenant_role(tenant_id, ARRAY['stylist'])
    AND EXISTS (
      SELECT 1
      FROM public.staff s
      WHERE s.id = appointments.staff_id
        AND s.tenant_id = appointments.tenant_id
        AND s.profile_id = auth.uid()
    )
  )
);

CREATE POLICY appointments_platform_admin_select ON public.appointments
FOR SELECT TO authenticated
USING (public.is_platform_administrator());

-- Event records follow appointment-level visibility; tenant membership alone
-- does not expose another stylist's history.
CREATE POLICY appointment_events_read ON public.appointment_events
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.id = appointment_events.appointment_id
      AND (
        a.customer_profile_id = auth.uid()
        OR public.has_tenant_role(a.tenant_id, ARRAY['owner', 'manager', 'receptionist'])
        OR (
          public.has_tenant_role(a.tenant_id, ARRAY['stylist'])
          AND EXISTS (
            SELECT 1
            FROM public.staff s
            WHERE s.id = a.staff_id
              AND s.tenant_id = a.tenant_id
              AND s.profile_id = auth.uid()
          )
        )
        OR public.is_platform_administrator()
      )
  )
);

-- Appointment notifications are subject to the same assignment-aware scope as
-- appointment rows; unrelated notifications remain recipient-private.
DROP POLICY IF EXISTS notifications_recipient ON public.notifications;
CREATE POLICY notifications_recipient_select ON public.notifications
FOR SELECT TO authenticated
USING (
  recipient_profile_id = auth.uid()
  AND (
    NOT (payload ? 'appointment_id')
    OR EXISTS (
      SELECT 1
      FROM public.appointments a
      WHERE a.id::text = payload ->> 'appointment_id'
        AND (
          a.customer_profile_id = auth.uid()
          OR public.has_tenant_role(a.tenant_id, ARRAY['owner', 'manager', 'receptionist'])
          OR (
            public.has_tenant_role(a.tenant_id, ARRAY['stylist'])
            AND EXISTS (
              SELECT 1 FROM public.staff s
              WHERE s.id = a.staff_id
                AND s.tenant_id = a.tenant_id
                AND s.profile_id = auth.uid()
            )
          )
          OR public.is_platform_administrator()
        )
    )
  )
);
CREATE POLICY notifications_recipient_insert ON public.notifications
FOR INSERT TO authenticated
WITH CHECK (recipient_profile_id = auth.uid());
CREATE POLICY notifications_recipient_update ON public.notifications
FOR UPDATE TO authenticated
USING (recipient_profile_id = auth.uid())
WITH CHECK (recipient_profile_id = auth.uid());
CREATE POLICY notifications_recipient_delete ON public.notifications
FOR DELETE TO authenticated
USING (recipient_profile_id = auth.uid());

-- Customers see their own transactions. Only owners/managers see tenant
-- financial records. Platform administration remains a separate policy.
CREATE POLICY payment_transactions_customer_select ON public.payment_transactions
FOR SELECT TO authenticated
USING (customer_profile_id = auth.uid());

CREATE POLICY payment_transactions_merchant_select ON public.payment_transactions
FOR SELECT TO authenticated
USING (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
);

CREATE POLICY payment_transactions_platform_admin_select ON public.payment_transactions
FOR SELECT TO authenticated
USING (public.is_platform_administrator());

-- Current appointments columns are id, tenant_id, location_id,
-- customer_profile_id, staff_id, service_id, start_at, end_at,
-- price_snapshot_minor, duration_snapshot_minutes, currency_code, status,
-- customer_notes, hold_expires_at, created_at, updated_at.
-- All 16 are read by existing appointment workflows. No payment state, internal
-- merchant note, or audit/lifecycle metadata column exists on this table.
-- Writes are separately allowlisted by the trigger: status transitions change
-- only status; rescheduling changes only start_at/end_at; updated_at is trigger-
-- maintained. All identity, relationship, price, duration, currency, hold,
-- notes, creation and unknown future fields are immutable after INSERT.
-- Column-level SELECT allowlists also keep future columns private by default.
GRANT SELECT (
  id,
  tenant_id,
  location_id,
  customer_profile_id,
  staff_id,
  service_id,
  start_at,
  end_at,
  price_snapshot_minor,
  duration_snapshot_minutes,
  currency_code,
  status,
  customer_notes,
  hold_expires_at,
  created_at,
  updated_at
) ON TABLE public.appointments TO authenticated;

GRANT SELECT (
  id,
  appointment_id,
  from_status,
  to_status,
  actor_profile_id,
  metadata,
  created_at
) ON TABLE public.appointment_events TO authenticated;

-- Payment rows expose only non-secret fields to client roles. In particular,
-- provider_reference and arbitrary metadata are not available through PostgREST.
GRANT SELECT (
  id,
  appointment_id,
  tenant_id,
  customer_profile_id,
  provider,
  amount_minor,
  currency_code,
  status,
  created_at,
  updated_at
) ON TABLE public.payment_transactions TO authenticated;

-- Public availability needs only occupied intervals, never appointment rows or
-- customer identifiers. Bound the query to one future local business day.
CREATE OR REPLACE FUNCTION public.public_staff_busy_intervals(
  p_staff_id uuid,
  p_local_date date
)
RETURNS TABLE(start_at timestamptz, end_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
  v_timezone text;
  v_day_start timestamptz;
  v_day_end timestamptz;
BEGIN
  IF p_staff_id IS NULL OR p_local_date IS NULL THEN
    RAISE EXCEPTION 'staff and local date are required';
  END IF;

  SELECT t.timezone
  INTO v_timezone
  FROM public.staff s
  JOIN public.tenants t ON t.id = s.tenant_id
  WHERE s.id = p_staff_id
    AND s.staff_status = 'active'
    AND t.business_status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active staff member not found';
  END IF;
  IF p_local_date < (now() AT TIME ZONE v_timezone)::date THEN
    RAISE EXCEPTION 'availability date must not be in the past';
  END IF;

  v_day_start := p_local_date::timestamp AT TIME ZONE v_timezone;
  v_day_end := (p_local_date + 1)::timestamp AT TIME ZONE v_timezone;

  RETURN QUERY
  SELECT a.start_at, a.end_at
  FROM public.appointments a
  WHERE a.staff_id = p_staff_id
    AND a.status IN ('confirmed', 'in_progress')
    AND tstzrange(a.start_at, a.end_at, '[)')
        && tstzrange(v_day_start, v_day_end, '[)')
  UNION ALL
  SELECT a.start_at, a.end_at
  FROM public.appointments a
  WHERE a.staff_id = p_staff_id
    AND a.status = 'pending'
    AND a.hold_expires_at > now()
    AND tstzrange(a.start_at, a.end_at, '[)')
        && tstzrange(v_day_start, v_day_end, '[)');
END;
$$;
ALTER FUNCTION public.public_staff_busy_intervals(uuid, date)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.public_staff_busy_intervals(uuid, date)
  FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.public_staff_busy_intervals(uuid, date)
  TO anon, authenticated;

-- Do not grant client INSERT/UPDATE/DELETE/TRUNCATE on either table. Existing
-- service_role and database-owner privileges are deliberately left untouched.

-- Harden existing identity helper function paths without changing their API.
ALTER FUNCTION public.is_tenant_member(uuid) OWNER TO postgres;
ALTER FUNCTION public.is_tenant_member(uuid)
  SET search_path = pg_catalog, public, auth, pg_temp;
ALTER FUNCTION public.has_tenant_role(uuid, text[]) OWNER TO postgres;
ALTER FUNCTION public.has_tenant_role(uuid, text[])
  SET search_path = pg_catalog, public, auth, pg_temp;
ALTER FUNCTION public.is_platform_administrator() OWNER TO postgres;
ALTER FUNCTION public.is_platform_administrator()
  SET search_path = pg_catalog, public, auth, pg_temp;
REVOKE ALL ON FUNCTION public.is_tenant_member(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.has_tenant_role(uuid, text[]) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.is_platform_administrator() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.is_tenant_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_tenant_role(uuid, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_administrator() TO authenticated;

-- Harden existing trigger SECURITY DEFINER functions. Trigger execution does
-- not require client EXECUTE privileges.
ALTER FUNCTION public.handle_auth_user_created() OWNER TO postgres;
ALTER FUNCTION public.handle_auth_user_created()
  SET search_path = pg_catalog, public, auth, pg_temp;
REVOKE ALL ON FUNCTION public.handle_auth_user_created()
  FROM PUBLIC, anon, authenticated, service_role;
ALTER FUNCTION public.record_appointment_event() OWNER TO postgres;
ALTER FUNCTION public.record_appointment_event()
  SET search_path = pg_catalog, public, auth, pg_temp;
REVOKE ALL ON FUNCTION public.record_appointment_event()
  FROM PUBLIC, anon, authenticated, service_role;
ALTER FUNCTION public.notify_appointment_change() OWNER TO postgres;
ALTER FUNCTION public.notify_appointment_change()
  SET search_path = pg_catalog, public, auth, pg_temp;
REVOKE ALL ON FUNCTION public.notify_appointment_change()
  FROM PUBLIC, anon, authenticated, service_role;

-- Booking remains customer-self-service. SECURITY DEFINER is necessary now
-- that authenticated has no direct INSERT privilege; the function derives the
-- customer from auth.uid() and validates the selected tenant resources.
ALTER FUNCTION public.create_appointment(uuid, uuid, uuid, uuid, timestamptz, text)
  OWNER TO postgres;
ALTER FUNCTION public.create_appointment(uuid, uuid, uuid, uuid, timestamptz, text)
  SECURITY DEFINER;
ALTER FUNCTION public.create_appointment(uuid, uuid, uuid, uuid, timestamptz, text)
  SET search_path = pg_catalog, public, auth, pg_temp;
REVOKE ALL ON FUNCTION public.create_appointment(
  uuid, uuid, uuid, uuid, timestamptz, text
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_appointment(
  uuid, uuid, uuid, uuid, timestamptz, text
) TO authenticated;

-- All merchant/customer status changes pass through this role-aware operation.
CREATE OR REPLACE FUNCTION public.transition_appointment(
  p_appointment_id uuid,
  p_next_status smart_barber_appointment_status
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
  v_profile_id uuid := auth.uid();
  v_appointment public.appointments%ROWTYPE;
  v_is_assigned_stylist boolean;
  v_is_owner_manager boolean;
  v_is_receptionist boolean;
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_appointment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment not found';
  END IF;

  IF v_appointment.status = 'pending'
     AND v_appointment.hold_expires_at <= now()
     AND p_next_status <> 'cancelled' THEN
    RAISE EXCEPTION 'expired appointment hold cannot be transitioned';
  END IF;

  IF v_appointment.customer_profile_id = v_profile_id THEN
    IF p_next_status <> 'cancelled'
       OR v_appointment.status NOT IN ('pending', 'confirmed') THEN
      RAISE EXCEPTION 'customers may only cancel eligible appointments';
    END IF;
  ELSIF public.is_platform_administrator() THEN
    NULL;
  ELSE
    v_is_owner_manager := public.has_tenant_role(
      v_appointment.tenant_id,
      ARRAY['owner', 'manager']
    );
    v_is_receptionist := public.has_tenant_role(
      v_appointment.tenant_id,
      ARRAY['receptionist']
    );
    v_is_assigned_stylist :=
      public.has_tenant_role(v_appointment.tenant_id, ARRAY['stylist'])
      AND EXISTS (
        SELECT 1
        FROM public.staff s
        WHERE s.id = v_appointment.staff_id
          AND s.tenant_id = v_appointment.tenant_id
          AND s.profile_id = v_profile_id
      );

    IF v_is_owner_manager THEN
      IF p_next_status NOT IN (
        'confirmed', 'declined', 'cancelled', 'in_progress', 'completed', 'no_show'
      ) THEN
        RAISE EXCEPTION 'invalid owner or manager appointment operation';
      END IF;
    ELSIF v_is_receptionist THEN
      IF p_next_status NOT IN ('confirmed', 'declined', 'cancelled') THEN
        RAISE EXCEPTION 'receptionists cannot perform this appointment operation';
      END IF;
    ELSIF v_is_assigned_stylist THEN
      IF p_next_status NOT IN ('in_progress', 'completed', 'cancelled') THEN
        RAISE EXCEPTION 'stylists may only work on or cancel assigned appointments';
      END IF;
    ELSE
      RAISE EXCEPTION 'not authorized to update appointment';
    END IF;
  END IF;

  UPDATE public.appointments
  SET status = p_next_status
  WHERE id = p_appointment_id
  RETURNING * INTO v_appointment;

  RETURN v_appointment;
END;
$$;

ALTER FUNCTION public.transition_appointment(
  uuid, smart_barber_appointment_status
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.transition_appointment(
  uuid, smart_barber_appointment_status
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.transition_appointment(
  uuid, smart_barber_appointment_status
) TO authenticated;

-- The trigger independently authorizes status changes and consumes the private
-- one-use capability created only by the validated reschedule RPC.
CREATE OR REPLACE FUNCTION public.validate_appointment_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, smart_barber_private, pg_temp
AS $$
DECLARE
  v_profile uuid := auth.uid();
  v_operation text;
  v_operation_actor uuid;
  v_is_assigned_stylist boolean;
  v_is_owner_manager boolean;
  v_is_receptionist boolean;
BEGIN
  -- Expiration is an automatic, single-field transition only after a hold is
  -- actually expired. This permits the existing batch expiry routine.
  IF OLD.status = 'pending'
     AND NEW.status = 'expired'
     AND OLD.hold_expires_at IS NOT NULL
     AND OLD.hold_expires_at <= now()
     AND (to_jsonb(NEW) - ARRAY['status', 'updated_at'])
         IS NOT DISTINCT FROM
         (to_jsonb(OLD) - ARRAY['status', 'updated_at']) THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'pending'
     AND OLD.hold_expires_at IS NOT NULL
     AND OLD.hold_expires_at <= now()
     AND NEW.status NOT IN ('cancelled', 'expired') THEN
    RAISE EXCEPTION 'expired appointment hold cannot be confirmed or declined';
  END IF;

  IF v_profile IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  SELECT g.operation, g.actor_profile_id
  INTO v_operation, v_operation_actor
  FROM smart_barber_private.appointment_operation_guard g
  WHERE g.transaction_id = txid_current()
    AND g.appointment_id = OLD.id
  FOR UPDATE;

  IF FOUND THEN
    DELETE FROM smart_barber_private.appointment_operation_guard
    WHERE transaction_id = txid_current()
      AND appointment_id = OLD.id
      AND operation = v_operation;

    IF v_operation <> 'reschedule'
       OR v_operation_actor <> v_profile
       OR OLD.status NOT IN ('pending', 'confirmed')
       OR (
         OLD.status = 'pending'
         AND (
           OLD.hold_expires_at IS NULL
           OR OLD.hold_expires_at <= now()
         )
       )
       OR NEW.status IS DISTINCT FROM OLD.status
       OR (to_jsonb(NEW) - ARRAY['start_at', 'end_at', 'updated_at'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['start_at', 'end_at', 'updated_at']) THEN
      RAISE EXCEPTION 'invalid reschedule operation fields';
    END IF;

    v_is_assigned_stylist :=
      public.has_tenant_role(OLD.tenant_id, ARRAY['stylist'])
      AND EXISTS (
        SELECT 1 FROM public.staff s
        WHERE s.id = OLD.staff_id
          AND s.tenant_id = OLD.tenant_id
          AND s.profile_id = v_profile
      );
    IF OLD.customer_profile_id <> v_profile
       AND NOT public.is_platform_administrator()
       AND NOT public.has_tenant_role(
         OLD.tenant_id,
         ARRAY['owner', 'manager', 'receptionist']
       )
       AND NOT v_is_assigned_stylist THEN
      RAISE EXCEPTION 'not authorized to reschedule appointment';
    END IF;
    RETURN NEW;
  END IF;

  -- Status operations may change status and the updated_at trigger's timestamp
  -- only. This JSON allowlist also rejects newly-added columns by default.
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR (to_jsonb(NEW) - ARRAY['status', 'updated_at'])
        IS DISTINCT FROM
        (to_jsonb(OLD) - ARRAY['status', 'updated_at']) THEN
    RAISE EXCEPTION 'only an authorized status change or reschedule is allowed';
  END IF;

  IF OLD.customer_profile_id = v_profile THEN
    IF NEW.status <> 'cancelled'
       OR OLD.status NOT IN ('pending', 'confirmed') THEN
      RAISE EXCEPTION 'customers may only cancel eligible appointments';
    END IF;
    RETURN NEW;
  END IF;

  IF public.is_platform_administrator() THEN
    RETURN NEW;
  END IF;

  v_is_owner_manager := public.has_tenant_role(
    OLD.tenant_id,
    ARRAY['owner', 'manager']
  );
  v_is_receptionist := public.has_tenant_role(
    OLD.tenant_id,
    ARRAY['receptionist']
  );
  v_is_assigned_stylist :=
    public.has_tenant_role(OLD.tenant_id, ARRAY['stylist'])
    AND EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.id = OLD.staff_id
        AND s.tenant_id = OLD.tenant_id
        AND s.profile_id = v_profile
    );

  IF v_is_owner_manager
     AND NEW.status IN (
       'confirmed', 'declined', 'cancelled', 'in_progress', 'completed', 'no_show'
     ) THEN
    RETURN NEW;
  ELSIF v_is_receptionist
     AND NEW.status IN ('confirmed', 'declined', 'cancelled') THEN
    RETURN NEW;
  ELSIF v_is_assigned_stylist
     AND NEW.status IN ('in_progress', 'completed', 'cancelled') THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'not authorized for this appointment status change';
END;
$$;
ALTER FUNCTION public.validate_appointment_write()
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.validate_appointment_write()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reschedule_appointment(
  p_appointment_id uuid,
  p_start_at timestamptz
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, smart_barber_private, pg_temp
AS $$
DECLARE
  v_profile_id uuid := auth.uid();
  v_appointment public.appointments%ROWTYPE;
  v_staff public.staff%ROWTYPE;
  v_location public.locations%ROWTYPE;
  v_service public.services%ROWTYPE;
  v_tenant public.tenants%ROWTYPE;
  v_tenant_hours public.operating_hours%ROWTYPE;
  v_staff_hours public.staff_hours%ROWTYPE;
  v_end_at timestamptz;
  v_local_date date;
  v_end_local_date date;
  v_day smallint;
  v_local_start time;
  v_local_end time;
  v_is_assigned_stylist boolean;
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;
  IF p_start_at IS NULL OR p_start_at <= now() THEN
    RAISE EXCEPTION 'rescheduled start time must be in the future';
  END IF;

  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_appointment_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment not found';
  END IF;
  IF v_appointment.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'only pending or confirmed appointments may be rescheduled';
  END IF;
  IF v_appointment.status = 'pending'
     AND (
       v_appointment.hold_expires_at IS NULL
       OR v_appointment.hold_expires_at <= now()
     ) THEN
    RAISE EXCEPTION 'expired appointment hold cannot be rescheduled';
  END IF;

  v_is_assigned_stylist :=
    public.has_tenant_role(v_appointment.tenant_id, ARRAY['stylist'])
    AND EXISTS (
      SELECT 1
      FROM public.staff s
      WHERE s.id = v_appointment.staff_id
        AND s.tenant_id = v_appointment.tenant_id
        AND s.profile_id = v_profile_id
    );
  IF v_appointment.customer_profile_id <> v_profile_id
     AND NOT public.is_platform_administrator()
     AND NOT public.has_tenant_role(
       v_appointment.tenant_id,
       ARRAY['owner', 'manager', 'receptionist']
     )
     AND NOT v_is_assigned_stylist THEN
    RAISE EXCEPTION 'not authorized to reschedule appointment';
  END IF;
  IF p_start_at = v_appointment.start_at THEN
    RETURN v_appointment;
  END IF;

  SELECT * INTO v_staff
  FROM public.staff
  WHERE id = v_appointment.staff_id
    AND tenant_id = v_appointment.tenant_id
    AND staff_status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment staff member is unavailable';
  END IF;
  SELECT * INTO v_location
  FROM public.locations
  WHERE id = v_appointment.location_id
    AND tenant_id = v_appointment.tenant_id
    AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment location is unavailable';
  END IF;
  SELECT * INTO v_service
  FROM public.services
  WHERE id = v_appointment.service_id
    AND tenant_id = v_appointment.tenant_id
    AND service_status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment service is unavailable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.staff_services ss
    WHERE ss.staff_id = v_appointment.staff_id
      AND ss.service_id = v_appointment.service_id
  ) THEN
    RAISE EXCEPTION 'appointment staff member is not assigned to its service';
  END IF;
  SELECT * INTO v_tenant
  FROM public.tenants
  WHERE id = v_appointment.tenant_id
    AND business_status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment business is unavailable';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_appointment.staff_id::text, 0));

  v_end_at := p_start_at
    + make_interval(mins => v_appointment.duration_snapshot_minutes + v_service.buffer_minutes);
  v_local_date := (p_start_at AT TIME ZONE v_tenant.timezone)::date;
  v_end_local_date := (v_end_at AT TIME ZONE v_tenant.timezone)::date;
  v_day := EXTRACT(ISODOW FROM p_start_at AT TIME ZONE v_tenant.timezone)::smallint;
  v_local_start := (p_start_at AT TIME ZONE v_tenant.timezone)::time;
  v_local_end := (v_end_at AT TIME ZONE v_tenant.timezone)::time;

  IF v_local_date <> v_end_local_date THEN
    RAISE EXCEPTION 'appointment must fit within one local business day';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.business_holidays bh
    WHERE bh.tenant_id = v_appointment.tenant_id
      AND bh.holiday_date = v_local_date
      AND bh.closed
  ) THEN
    RAISE EXCEPTION 'business is closed for a holiday';
  END IF;

  SELECT * INTO v_tenant_hours
  FROM public.operating_hours
  WHERE tenant_id = v_appointment.tenant_id
    AND day_of_week = v_day;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'business unavailable at this time';
  END IF;
  SELECT * INTO v_staff_hours
  FROM public.staff_hours
  WHERE staff_id = v_appointment.staff_id
    AND day_of_week = v_day;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'staff unavailable at this time';
  END IF;
  IF v_local_start < v_tenant_hours.open_time
     OR v_local_end > v_tenant_hours.close_time
     OR v_local_start < v_staff_hours.start_time
     OR v_local_end > v_staff_hours.end_time THEN
    RAISE EXCEPTION 'appointment outside operating or staff working hours';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.staff_time_off sto
    WHERE sto.staff_id = v_appointment.staff_id
      AND tstzrange(sto.start_at, sto.end_at, '[)')
          && tstzrange(p_start_at, v_end_at, '[)')
  ) OR EXISTS (
    SELECT 1 FROM public.staff_breaks sb
    WHERE sb.staff_id = v_appointment.staff_id
      AND (
        (
          sb.start_at IS NOT NULL
          AND sb.end_at IS NOT NULL
          AND tstzrange(sb.start_at, sb.end_at, '[)')
              && tstzrange(p_start_at, v_end_at, '[)')
        )
        OR (
          sb.day_of_week = v_day
          AND sb.recurring_start_time IS NOT NULL
          AND sb.recurring_end_time IS NOT NULL
          AND v_local_start < sb.recurring_end_time
          AND v_local_end > sb.recurring_start_time
        )
      )
  ) THEN
    RAISE EXCEPTION 'staff member is unavailable at this time';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.id <> v_appointment.id
      AND a.staff_id = v_appointment.staff_id
      AND a.status IN ('pending', 'confirmed', 'in_progress')
      AND (
        a.status <> 'pending'
        OR (a.hold_expires_at IS NOT NULL AND a.hold_expires_at > now())
      )
      AND tstzrange(a.start_at, a.end_at, '[)')
          && tstzrange(p_start_at, v_end_at, '[)')
  ) THEN
    RAISE EXCEPTION 'the new time conflicts with another appointment';
  END IF;

  -- The trigger consumes this private, one-use row in the same transaction.
  INSERT INTO smart_barber_private.appointment_operation_guard (
    transaction_id,
    appointment_id,
    actor_profile_id,
    operation
  )
  VALUES (
    txid_current(),
    v_appointment.id,
    v_profile_id,
    'reschedule'
  );

  UPDATE public.appointments
  SET start_at = p_start_at,
      end_at = v_end_at
  WHERE id = v_appointment.id
  RETURNING * INTO v_appointment;

  RETURN v_appointment;
END;
$$;

ALTER FUNCTION public.reschedule_appointment(uuid, timestamptz)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.reschedule_appointment(uuid, timestamptz)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment(uuid, timestamptz)
  TO authenticated;

-- Keep the existing expiry job callable only by the trusted service role.
-- Its row updates pass the same single-field expiry exception in the validator.
REVOKE ALL ON FUNCTION public.expire_pending_appointment_holds()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_pending_appointment_holds()
  TO service_role;

-- Preserve event recording while attributing each new event to auth.uid().
-- Existing event rows and the existing trigger are untouched.
CREATE OR REPLACE FUNCTION public.record_appointment_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.appointment_events (
      appointment_id, from_status, to_status, actor_profile_id, metadata
    )
    VALUES (
      NEW.id, NULL, NEW.status, auth.uid(),
      jsonb_build_object(
        'action', 'created',
        'start_at', NEW.start_at,
        'end_at', NEW.end_at
      )
    );
  ELSE
    INSERT INTO public.appointment_events (
      appointment_id, from_status, to_status, actor_profile_id, metadata
    )
    VALUES (
      NEW.id,
      OLD.status,
      NEW.status,
      auth.uid(),
      CASE
        WHEN NEW.status IS DISTINCT FROM OLD.status THEN
          jsonb_build_object(
            'action', 'status_changed',
            'start_at', NEW.start_at,
            'end_at', NEW.end_at
          )
        ELSE
          jsonb_build_object(
            'action', 'rescheduled',
            'start_at', NEW.start_at,
            'end_at', NEW.end_at
          )
      END
    );
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.record_appointment_event() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_appointment_event()
  FROM PUBLIC, anon, authenticated;

-- Refresh the one existing notification for each recipient/type/appointment
-- so repeated reschedules do not leave stale times or remain marked read.
CREATE OR REPLACE FUNCTION public.notify_appointment_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
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
        AND tm.role::text IN ('owner', 'manager', 'receptionist', 'stylist')
        AND (
          tm.role::text <> 'stylist'
          OR EXISTS (
            SELECT 1
            FROM public.staff s
            WHERE s.id = NEW.staff_id
              AND s.tenant_id = NEW.tenant_id
              AND s.profile_id = tm.profile_id
          )
        )
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

  IF NEW.start_at IS DISTINCT FROM OLD.start_at
     OR NEW.end_at IS DISTINCT FROM OLD.end_at THEN
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

  UPDATE public.notifications
  SET payload = v_payload,
      read_at = NULL,
      created_at = now()
  WHERE recipient_profile_id = NEW.customer_profile_id
    AND type = v_type
    AND payload ->> 'appointment_id' = NEW.id::text;
  IF NOT FOUND THEN
    INSERT INTO public.notifications (tenant_id, recipient_profile_id, type, payload)
    VALUES (NEW.tenant_id, NEW.customer_profile_id, v_type, v_payload);
  END IF;

  IF v_type IN ('appointment_cancelled', 'appointment_rescheduled') THEN
    FOR v_member IN
      SELECT tm.profile_id
      FROM public.tenant_memberships tm
      WHERE tm.tenant_id = NEW.tenant_id
        AND tm.membership_status = 'active'
        AND tm.role::text IN ('owner', 'manager', 'receptionist', 'stylist')
        AND (
          tm.role::text <> 'stylist'
          OR EXISTS (
            SELECT 1
            FROM public.staff s
            WHERE s.id = NEW.staff_id
              AND s.tenant_id = NEW.tenant_id
              AND s.profile_id = tm.profile_id
          )
        )
    LOOP
      UPDATE public.notifications
      SET payload = v_payload,
          read_at = NULL,
          created_at = now()
      WHERE recipient_profile_id = v_member
        AND type = v_type
        AND payload ->> 'appointment_id' = NEW.id::text;
      IF NOT FOUND THEN
        INSERT INTO public.notifications (tenant_id, recipient_profile_id, type, payload)
        VALUES (NEW.tenant_id, v_member, v_type, v_payload);
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;
ALTER FUNCTION public.notify_appointment_change() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.notify_appointment_change()
  FROM PUBLIC, anon, authenticated, service_role;

-- Safe verification queries (run after applying to a disposable/staging DB):
-- SELECT * FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename IN ('appointments', 'appointment_events', 'notifications', 'payment_transactions')
-- ORDER BY tablename, policyname;
-- SELECT grantee, table_name, privilege_type
-- FROM information_schema.role_table_grants
-- WHERE table_schema = 'public'
--   AND table_name IN ('appointments', 'appointment_events', 'payment_transactions')
-- ORDER BY table_name, grantee, privilege_type;
-- SELECT grantee, table_name, column_name, privilege_type
-- FROM information_schema.column_privileges
-- WHERE table_schema = 'public'
--   AND table_name IN ('appointments', 'appointment_events', 'payment_transactions')
-- ORDER BY table_name, grantee, column_name, privilege_type;
-- SELECT has_table_privilege('anon', 'public.appointments', 'SELECT') AS anon_table_select,
--        has_any_column_privilege('anon', 'public.appointments', 'SELECT') AS anon_column_select,
--        has_table_privilege('authenticated', 'public.appointments', 'UPDATE') AS auth_table_update,
--        has_any_column_privilege('authenticated', 'public.appointments', 'UPDATE') AS auth_column_update;
-- SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
--        pg_get_userbyid(p.proowner) AS owner, p.prosecdef AS security_definer,
--        p.proconfig AS function_settings, p.proacl AS function_acl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
--        has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname IN ('public', 'smart_barber_private')
--   AND (p.prosecdef OR p.proname IN ('transition_appointment',
--        'reschedule_appointment', 'create_appointment',
--        'public_staff_busy_intervals'));
-- SELECT count(*) AS unconsumed_reschedule_capabilities
-- FROM smart_barber_private.appointment_operation_guard;
-- SELECT has_function_privilege('anon',
--   'public.transition_appointment(uuid,smart_barber_appointment_status)', 'EXECUTE')
--   AS anon_can_transition,
--   has_function_privilege('authenticated',
--   'public.transition_appointment(uuid,smart_barber_appointment_status)', 'EXECUTE')
--   AS authenticated_can_transition,
--   has_function_privilege('anon',
--   'public.reschedule_appointment(uuid,timestamp with time zone)', 'EXECUTE')
--   AS anon_can_reschedule,
--   has_function_privilege('anon',
--   'public.public_staff_busy_intervals(uuid,date)', 'EXECUTE')
--   AS anon_can_read_busy_intervals,
--   has_function_privilege('service_role',
--   'public.public_staff_busy_intervals(uuid,date)', 'EXECUTE')
--   AS service_role_can_read_busy_intervals;

-- Rollback guidance:
-- Before approval/deployment, retain a schema-only pg_dump plus the preflight
-- policy/ACL/function-owner query results. On rollback, use those snapshots to
-- restore the prior policy definitions and exact table/column grants; restore
-- function definitions from migrations 20261123053000, 20261123053100,
-- 202611230532_booking_availability_constraints.sql, and
-- 202611230533_harden_rls_policies.sql. Restore the former SECURITY INVOKER
-- mode for create_appointment and the pre-migration function owners/settings.
-- Revoke access to the private guard schema and leave its now-empty table in
-- place; do not touch appointment, event, notification, or payment rows.
-- This rollback restores the pre-migration security posture (including its
-- known weaknesses), not a hardened fallback configuration.

COMMIT;
