-- Replace broad appointment policies with operation-specific policies.
DROP POLICY IF EXISTS appointments_customer_cancel ON public.appointments;
DROP POLICY IF EXISTS appointments_tenant_manage ON public.appointments;

CREATE POLICY appointments_customer_update ON public.appointments
FOR UPDATE USING (customer_profile_id = auth.uid())
WITH CHECK (customer_profile_id = auth.uid());

CREATE POLICY appointments_merchant_select ON public.appointments
FOR SELECT USING (
  public.has_tenant_role(
    tenant_id,
    ARRAY['owner', 'manager', 'receptionist', 'stylist']
  )
);

CREATE POLICY appointments_merchant_update ON public.appointments
FOR UPDATE USING (
  public.has_tenant_role(
    tenant_id,
    ARRAY['owner', 'manager', 'receptionist', 'stylist']
  )
) WITH CHECK (
  public.has_tenant_role(
    tenant_id,
    ARRAY['owner', 'manager', 'receptionist', 'stylist']
  )
);

-- Public availability read policies. Private schedule details remain merchant-only.
CREATE POLICY operating_hours_public_select ON public.operating_hours
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = operating_hours.tenant_id
      AND t.business_status = 'active'
  )
);

CREATE POLICY operating_hours_tenant_manage ON public.operating_hours
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
);

CREATE POLICY staff_hours_public_select ON public.staff_hours
FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM public.staff s
    JOIN public.tenants t ON t.id = s.tenant_id
    WHERE s.id = staff_hours.staff_id
      AND s.staff_status = 'active'
      AND t.business_status = 'active'
  )
);

CREATE POLICY staff_hours_tenant_manage ON public.staff_hours
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_hours.staff_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_hours.staff_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
);

CREATE POLICY staff_breaks_merchant_select ON public.staff_breaks
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_breaks.staff_id
      AND public.is_tenant_member(s.tenant_id)
  )
);

CREATE POLICY staff_breaks_merchant_manage ON public.staff_breaks
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_breaks.staff_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_breaks.staff_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
);

CREATE POLICY staff_time_off_merchant_select ON public.staff_time_off
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_time_off.staff_id
      AND public.is_tenant_member(s.tenant_id)
  )
);

CREATE POLICY staff_time_off_merchant_manage ON public.staff_time_off
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_time_off.staff_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_time_off.staff_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
);

CREATE POLICY holidays_public_select ON public.business_holidays
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = business_holidays.tenant_id
      AND t.business_status = 'active'
  )
);

CREATE POLICY holidays_merchant_manage ON public.business_holidays
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
);

-- Prevent customers and merchants from changing immutable appointment fields.
CREATE OR REPLACE FUNCTION public.validate_appointment_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_profile uuid := auth.uid();
  v_reschedule boolean := COALESCE(current_setting('smart_barber.reschedule', true) = 'true', false);
BEGIN
  IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
     OR NEW.location_id IS DISTINCT FROM OLD.location_id
     OR NEW.customer_profile_id IS DISTINCT FROM OLD.customer_profile_id
     OR NEW.staff_id IS DISTINCT FROM OLD.staff_id
     OR NEW.service_id IS DISTINCT FROM OLD.service_id
     OR NEW.price_snapshot_minor IS DISTINCT FROM OLD.price_snapshot_minor
     OR NEW.duration_snapshot_minutes IS DISTINCT FROM OLD.duration_snapshot_minutes
     OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
     OR NEW.hold_expires_at IS DISTINCT FROM OLD.hold_expires_at
  THEN
    RAISE EXCEPTION 'immutable appointment fields cannot be changed';
  END IF;

  IF v_reschedule THEN
    IF v_profile IS NULL OR v_profile <> OLD.customer_profile_id THEN
      RAISE EXCEPTION 'only the customer can reschedule this appointment';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'reschedule operation cannot change appointment status';
    END IF;
  ELSE
    IF v_profile IS NULL THEN
      RAISE EXCEPTION 'authentication required';
    END IF;

    IF v_profile = OLD.customer_profile_id THEN
      IF NEW.status::text <> 'cancelled'
         OR NEW.start_at IS DISTINCT FROM OLD.start_at
         OR NEW.end_at IS DISTINCT FROM OLD.end_at
         OR NEW.customer_notes IS DISTINCT FROM OLD.customer_notes THEN
        RAISE EXCEPTION 'customers may only cancel an appointment';
      END IF;
    ELSE
      IF NOT public.has_tenant_role(
        OLD.tenant_id,
        ARRAY['owner', 'manager', 'receptionist', 'stylist']
      ) THEN
        RAISE EXCEPTION 'merchant is not authorized to update this appointment';
      END IF;
      IF NEW.start_at IS DISTINCT FROM OLD.start_at
         OR NEW.end_at IS DISTINCT FROM OLD.end_at
         OR NEW.customer_notes IS DISTINCT FROM OLD.customer_notes THEN
        RAISE EXCEPTION 'merchant status updates cannot modify immutable booking details';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_appointment_write_before_update ON public.appointments;
CREATE TRIGGER validate_appointment_write_before_update
BEFORE UPDATE ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.validate_appointment_write();

-- Prevent a profile from changing its own account-active flag.
CREATE OR REPLACE FUNCTION public.validate_profile_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.active IS DISTINCT FROM OLD.active
     AND NOT public.is_platform_administrator() THEN
    RAISE EXCEPTION 'only platform administrators may change profile active status';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_profile_write_before_update ON public.profiles;
CREATE TRIGGER validate_profile_write_before_update
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.validate_profile_write();

-- Prevent membership role self-escalation and tenant role assignment by non-owners.
CREATE OR REPLACE FUNCTION public.validate_membership_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_profile uuid := auth.uid();
  v_has_owner boolean;
BEGIN
  IF TG_OP = 'INSERT' OR NEW.role IS DISTINCT FROM OLD.role THEN
    IF NEW.profile_id = v_profile
       AND NEW.role::text <> COALESCE(OLD.role::text, '') THEN
      RAISE EXCEPTION 'users cannot assign themselves elevated roles';
    END IF;
    SELECT NOT EXISTS (
      SELECT 1
      FROM public.tenant_memberships tm
      WHERE tm.tenant_id = NEW.tenant_id
        AND tm.role = 'owner'
        AND tm.membership_status = 'active'
    ) INTO v_has_owner;
    IF NOT v_has_owner
       AND NOT public.has_tenant_role(NEW.tenant_id, ARRAY['owner'])
       AND NOT public.is_platform_administrator() THEN
      RAISE EXCEPTION 'only a tenant owner or platform administrator can assign membership roles';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_membership_write_before_insert ON public.tenant_memberships;
CREATE TRIGGER validate_membership_write_before_insert
BEFORE INSERT ON public.tenant_memberships
FOR EACH ROW EXECUTE FUNCTION public.validate_membership_write();

DROP TRIGGER IF EXISTS validate_membership_write_before_update ON public.tenant_memberships;
CREATE TRIGGER validate_membership_write_before_update
BEFORE UPDATE ON public.tenant_memberships
FOR EACH ROW EXECUTE FUNCTION public.validate_membership_write();

-- Keep platform role assignment restricted to platform_owner.
CREATE OR REPLACE FUNCTION public.validate_platform_role_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_profile uuid := auth.uid();
  v_owner boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_administrators pa
    JOIN public.platform_role_assignments pra ON pra.profile_id = pa.profile_id
    WHERE pa.profile_id = v_profile
      AND pa.status = 'active'
      AND pra.role = 'platform_owner'
      AND pra.revoked_at IS NULL
  ) INTO v_owner;

  IF NOT v_owner THEN
    RAISE EXCEPTION 'only platform_owner may assign platform roles';
  END IF;
  IF NEW.profile_id = v_profile THEN
    RAISE EXCEPTION 'platform administrators cannot self-escalate';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_platform_role_assignment_before_insert ON public.platform_role_assignments;
CREATE TRIGGER validate_platform_role_assignment_before_insert
BEFORE INSERT ON public.platform_role_assignments
FOR EACH ROW EXECUTE FUNCTION public.validate_platform_role_assignment();

DROP TRIGGER IF EXISTS validate_platform_role_assignment_before_update ON public.platform_role_assignments;
CREATE TRIGGER validate_platform_role_assignment_before_update
BEFORE UPDATE ON public.platform_role_assignments
FOR EACH ROW EXECUTE FUNCTION public.validate_platform_role_assignment();

REVOKE ALL ON FUNCTION public.is_tenant_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_tenant_role(uuid, text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_platform_administrator() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_tenant_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_tenant_role(uuid, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_administrator() TO authenticated;
