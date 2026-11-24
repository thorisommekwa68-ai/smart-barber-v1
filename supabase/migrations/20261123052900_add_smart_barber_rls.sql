CREATE OR REPLACE FUNCTION public.is_tenant_member(target_tenant uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tenant_memberships tm
    WHERE tm.tenant_id = target_tenant
      AND tm.profile_id = auth.uid()
      AND tm.membership_status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.has_tenant_role(target_tenant uuid, allowed_roles text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tenant_memberships tm
    WHERE tm.tenant_id = target_tenant
      AND tm.profile_id = auth.uid()
      AND tm.membership_status = 'active'
      AND tm.role::text = ANY (allowed_roles)
  );
$$;

CREATE OR REPLACE FUNCTION public.is_platform_administrator()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_administrators pa
    JOIN public.platform_role_assignments pra ON pra.profile_id = pa.profile_id
    WHERE pa.profile_id = auth.uid()
      AND pa.status = 'active'
      AND pra.revoked_at IS NULL
  );
$$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operating_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_breaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_time_off ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_favourites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_administrators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_role_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_self_select ON public.profiles
FOR SELECT USING (id = auth.uid());

CREATE POLICY profiles_self_update ON public.profiles
FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY tenants_public_select ON public.tenants
FOR SELECT USING (business_status = 'active');

CREATE POLICY tenant_memberships_self_select ON public.tenant_memberships
FOR SELECT USING (profile_id = auth.uid() OR public.is_platform_administrator());

CREATE POLICY tenant_memberships_owner_manage ON public.tenant_memberships
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner'])
  OR public.is_platform_administrator()
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner'])
  OR public.is_platform_administrator()
);

CREATE POLICY public_active_locations ON public.locations
FOR SELECT USING (
  active = true
  AND EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = locations.tenant_id AND t.business_status = 'active'
  )
);

CREATE POLICY tenant_location_manage ON public.locations
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
);

CREATE POLICY public_active_services ON public.services
FOR SELECT USING (
  service_status = 'active'
  AND EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = services.tenant_id AND t.business_status = 'active'
  )
);

CREATE POLICY tenant_service_manage ON public.services
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
);

CREATE POLICY public_active_staff ON public.staff
FOR SELECT USING (
  staff_status = 'active'
  AND EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = staff.tenant_id AND t.business_status = 'active'
  )
);

CREATE POLICY tenant_staff_manage ON public.staff
FOR ALL USING (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
) WITH CHECK (
  public.has_tenant_role(tenant_id, ARRAY['owner', 'manager'])
);

CREATE POLICY staff_services_public_select ON public.staff_services
FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM public.staff s
    JOIN public.services sv ON sv.id = staff_services.service_id
    WHERE s.id = staff_services.staff_id
      AND s.tenant_id = sv.tenant_id
      AND s.staff_status = 'active'
      AND sv.service_status = 'active'
  )
);

CREATE POLICY staff_services_manage ON public.staff_services
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.id = staff_services.staff_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.staff s
    JOIN public.services sv ON sv.id = staff_services.service_id
    WHERE s.id = staff_services.staff_id
      AND s.tenant_id = sv.tenant_id
      AND public.has_tenant_role(s.tenant_id, ARRAY['owner', 'manager'])
  )
);

CREATE POLICY appointments_customer_select ON public.appointments
FOR SELECT USING (
  customer_profile_id = auth.uid()
  OR public.is_tenant_member(tenant_id)
  OR public.is_platform_administrator()
);

CREATE POLICY appointments_customer_insert ON public.appointments
FOR INSERT WITH CHECK (
  customer_profile_id = auth.uid()
);

CREATE POLICY appointments_customer_cancel ON public.appointments
FOR UPDATE USING (
  customer_profile_id = auth.uid()
) WITH CHECK (
  customer_profile_id = auth.uid()
);

CREATE POLICY appointments_tenant_manage ON public.appointments
FOR ALL USING (
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

CREATE POLICY appointment_events_read ON public.appointment_events
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.appointments a
    WHERE a.id = appointment_events.appointment_id
      AND (
        a.customer_profile_id = auth.uid()
        OR public.is_tenant_member(a.tenant_id)
        OR public.is_platform_administrator()
      )
  )
);

CREATE POLICY relationships_customer ON public.customer_relationships
FOR ALL USING (customer_profile_id = auth.uid())
WITH CHECK (customer_profile_id = auth.uid());

CREATE POLICY favourites_customer ON public.customer_favourites
FOR ALL USING (customer_profile_id = auth.uid())
WITH CHECK (customer_profile_id = auth.uid());

CREATE POLICY notifications_recipient ON public.notifications
FOR ALL USING (recipient_profile_id = auth.uid())
WITH CHECK (recipient_profile_id = auth.uid());

CREATE POLICY public_active_plans ON public.subscription_plans
FOR SELECT USING (active = true);

CREATE POLICY tenant_subscription_select ON public.tenant_subscriptions
FOR SELECT USING (
  public.is_tenant_member(tenant_id)
  OR public.is_platform_administrator()
);

CREATE POLICY payment_transaction_select ON public.payment_transactions
FOR SELECT USING (
  customer_profile_id = auth.uid()
  OR public.is_tenant_member(tenant_id)
  OR public.is_platform_administrator()
);

CREATE POLICY platform_administrators_own ON public.platform_administrators
FOR SELECT USING (
  profile_id = auth.uid()
  OR public.is_platform_administrator()
);

CREATE POLICY platform_role_assignments_admin ON public.platform_role_assignments
FOR ALL USING (public.is_platform_administrator())
WITH CHECK (public.is_platform_administrator());

CREATE POLICY platform_audit_admin ON public.platform_audit_logs
FOR SELECT USING (public.is_platform_administrator());
