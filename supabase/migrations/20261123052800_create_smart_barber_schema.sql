CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE smart_barber_member_role AS ENUM ('owner', 'manager', 'receptionist', 'stylist');
CREATE TYPE smart_barber_member_status AS ENUM ('active', 'inactive', 'invited');
CREATE TYPE smart_barber_business_status AS ENUM ('active', 'inactive', 'suspended');
CREATE TYPE smart_barber_service_status AS ENUM ('active', 'inactive');
CREATE TYPE smart_barber_staff_status AS ENUM ('active', 'inactive');
CREATE TYPE smart_barber_appointment_status AS ENUM (
  'pending', 'confirmed', 'in_progress', 'completed', 'declined', 'cancelled', 'expired', 'no_show'
);
CREATE TYPE smart_barber_platform_role AS ENUM ('platform_owner', 'platform_admin', 'platform_support', 'platform_auditor');
CREATE TYPE smart_barber_platform_status AS ENUM ('active', 'inactive', 'suspended');

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  email text,
  phone text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_name text NOT NULL,
  business_description text NOT NULL DEFAULT '',
  business_status smart_barber_business_status NOT NULL DEFAULT 'active',
  timezone text NOT NULL DEFAULT 'Africa/Johannesburg',
  currency_code char(3) NOT NULL DEFAULT 'ZAR',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tenants_currency_zar CHECK (currency_code = 'ZAR')
);

CREATE TABLE public.tenant_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role smart_barber_member_role NOT NULL,
  membership_status smart_barber_member_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, profile_id)
);

CREATE TABLE public.locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text NOT NULL DEFAULT '',
  latitude double precision,
  longitude double precision,
  timezone text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT locations_timezone_matches_tenant CHECK (timezone <> '')
);

CREATE TABLE public.staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
  profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  display_name text NOT NULL,
  staff_status smart_barber_staff_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  price_minor bigint NOT NULL CHECK (price_minor >= 0),
  duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
  buffer_minutes integer NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0),
  service_status smart_barber_service_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.staff_services (
  staff_id uuid NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (staff_id, service_id)
);

CREATE TABLE public.operating_hours (
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  day_of_week smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
  open_time time NOT NULL,
  close_time time NOT NULL,
  PRIMARY KEY (tenant_id, day_of_week),
  CONSTRAINT operating_hours_order CHECK (open_time < close_time)
);

CREATE TABLE public.staff_hours (
  staff_id uuid NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
  day_of_week smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
  start_time time NOT NULL,
  end_time time NOT NULL,
  PRIMARY KEY (staff_id, day_of_week),
  CONSTRAINT staff_hours_order CHECK (start_time < end_time)
);

CREATE TABLE public.staff_breaks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
  day_of_week smallint CHECK (day_of_week BETWEEN 1 AND 7),
  start_at timestamptz,
  end_at timestamptz,
  recurring_start_time time,
  recurring_end_time time,
  CONSTRAINT staff_break_range CHECK (
    (start_at IS NOT NULL AND end_at IS NOT NULL AND start_at < end_at)
    OR (recurring_start_time IS NOT NULL AND recurring_end_time IS NOT NULL AND recurring_start_time < recurring_end_time)
  )
);

CREATE TABLE public.staff_time_off (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT staff_time_off_order CHECK (start_at < end_at)
);

CREATE TABLE public.business_holidays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  holiday_date date NOT NULL,
  name text,
  closed boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, holiday_date)
);

CREATE TABLE public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
  customer_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  staff_id uuid NOT NULL REFERENCES public.staff(id) ON DELETE RESTRICT,
  service_id uuid NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  price_snapshot_minor bigint NOT NULL CHECK (price_snapshot_minor >= 0),
  duration_snapshot_minutes integer NOT NULL CHECK (duration_snapshot_minutes > 0),
  currency_code char(3) NOT NULL DEFAULT 'ZAR',
  status smart_barber_appointment_status NOT NULL DEFAULT 'pending',
  customer_notes text NOT NULL DEFAULT '',
  hold_expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT appointments_time_order CHECK (start_at < end_at),
  CONSTRAINT appointments_currency_zar CHECK (currency_code = 'ZAR'),
  CONSTRAINT appointments_pending_hold CHECK (status <> 'pending' OR hold_expires_at IS NOT NULL),
  EXCLUDE USING gist (
    staff_id WITH =,
    tstzrange(start_at, end_at, '[)') WITH &&
  ) WHERE (status IN ('pending', 'confirmed', 'in_progress'))
);

CREATE TABLE public.appointment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id uuid NOT NULL REFERENCES public.appointments(id) ON DELETE CASCADE,
  from_status smart_barber_appointment_status,
  to_status smart_barber_appointment_status NOT NULL,
  actor_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.customer_relationships (
  customer_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  relationship_type text NOT NULL DEFAULT 'customer',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_profile_id, tenant_id)
);

CREATE TABLE public.customer_favourites (
  customer_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_profile_id, tenant_id, service_id)
);

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  recipient_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.subscription_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  description text NOT NULL DEFAULT '',
  price_minor bigint NOT NULL CHECK (price_minor >= 0),
  currency_code char(3) NOT NULL DEFAULT 'ZAR',
  entitlements jsonb NOT NULL DEFAULT '{}'::jsonb,
  usage_limits jsonb NOT NULL DEFAULT '{}'::jsonb,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT subscription_plans_currency_zar CHECK (currency_code = 'ZAR')
);

CREATE TABLE public.tenant_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  plan_id uuid NOT NULL REFERENCES public.subscription_plans(id) ON DELETE RESTRICT,
  status text NOT NULL CHECK (status IN ('trialing', 'active', 'past_due', 'cancelled', 'expired')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, plan_id, starts_at)
);

CREATE TABLE public.payment_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id uuid REFERENCES public.appointments(id) ON DELETE SET NULL,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  provider text NOT NULL,
  provider_reference text,
  amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
  currency_code char(3) NOT NULL DEFAULT 'ZAR',
  status text NOT NULL CHECK (status IN ('pending', 'authorized', 'captured', 'refunded', 'failed', 'cancelled')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payment_transactions_currency_zar CHECK (currency_code = 'ZAR')
);

CREATE TABLE public.platform_administrators (
  profile_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  status smart_barber_platform_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.platform_role_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role smart_barber_platform_role NOT NULL,
  granted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (profile_id, role)
);

CREATE TABLE public.platform_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  target_type text,
  target_id text,
  before_json jsonb,
  after_json jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_tenants_updated_at BEFORE UPDATE ON public.tenants
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_locations_updated_at BEFORE UPDATE ON public.locations
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_staff_updated_at BEFORE UPDATE ON public.staff
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_services_updated_at BEFORE UPDATE ON public.services
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_appointments_updated_at BEFORE UPDATE ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_plans_updated_at BEFORE UPDATE ON public.subscription_plans
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_subscriptions_updated_at BEFORE UPDATE ON public.tenant_subscriptions
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_payments_updated_at BEFORE UPDATE ON public.payment_transactions
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_platform_admin_updated_at BEFORE UPDATE ON public.platform_administrators
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.handle_auth_user_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, email, phone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(COALESCE(NEW.email, 'User'), '@', 1)),
    NEW.email,
    NEW.phone
  )
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      phone = EXCLUDED.phone,
      display_name = CASE WHEN public.profiles.display_name IS NULL THEN EXCLUDED.display_name ELSE public.profiles.display_name END;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_auth_user_created();

CREATE OR REPLACE FUNCTION public.expire_pending_appointment_hold()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'pending'
     AND NEW.hold_expires_at IS NOT NULL
     AND NEW.hold_expires_at <= now() THEN
    NEW.status = 'expired';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER expire_pending_appointment_hold_before_write
BEFORE INSERT OR UPDATE ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.expire_pending_appointment_hold();

CREATE OR REPLACE FUNCTION public.validate_appointment_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF OLD.status::text = 'pending' AND NEW.status::text NOT IN ('confirmed', 'declined', 'cancelled', 'expired') THEN
    RAISE EXCEPTION 'invalid appointment transition: % -> %', OLD.status, NEW.status;
  END IF;
  IF OLD.status::text = 'confirmed' AND NEW.status::text NOT IN ('in_progress', 'cancelled', 'no_show', 'expired') THEN
    RAISE EXCEPTION 'invalid appointment transition: % -> %', OLD.status, NEW.status;
  END IF;
  IF OLD.status::text = 'in_progress' AND NEW.status::text NOT IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'invalid appointment transition: % -> %', OLD.status, NEW.status;
  END IF;
  IF OLD.status::text IN ('completed', 'declined', 'cancelled', 'expired', 'no_show') THEN
    RAISE EXCEPTION 'invalid appointment transition from terminal status: %', OLD.status;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_appointment_lifecycle_before_update
BEFORE UPDATE OF status ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.validate_appointment_lifecycle();

CREATE OR REPLACE FUNCTION public.validate_appointment_relationships()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  location_tenant uuid;
  staff_tenant uuid;
  staff_location uuid;
  service_tenant uuid;
BEGIN
  SELECT tenant_id INTO location_tenant FROM public.locations WHERE id = NEW.location_id;
  SELECT tenant_id, location_id INTO staff_tenant, staff_location FROM public.staff WHERE id = NEW.staff_id;
  SELECT tenant_id INTO service_tenant FROM public.services WHERE id = NEW.service_id;

  IF location_tenant IS NULL OR staff_tenant IS NULL OR service_tenant IS NULL THEN
    RAISE EXCEPTION 'invalid appointment relationship';
  END IF;
  IF location_tenant <> NEW.tenant_id OR staff_tenant <> NEW.tenant_id OR service_tenant <> NEW.tenant_id THEN
    RAISE EXCEPTION 'appointment entities belong to different tenants';
  END IF;
  IF staff_location <> NEW.location_id THEN
    RAISE EXCEPTION 'staff member does not belong to the selected location';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.staff_services ss
    WHERE ss.staff_id = NEW.staff_id AND ss.service_id = NEW.service_id
  ) THEN
    RAISE EXCEPTION 'staff member is not assigned to the selected service';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_appointment_relationships_before_write
BEFORE INSERT OR UPDATE OF tenant_id, location_id, staff_id, service_id ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.validate_appointment_relationships();

CREATE OR REPLACE FUNCTION public.record_appointment_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.appointment_events (appointment_id, from_status, to_status, metadata)
    VALUES (NEW.id, NULL, NEW.status, '{}'::jsonb);
  ELSE
    INSERT INTO public.appointment_events (appointment_id, from_status, to_status, metadata)
    VALUES (NEW.id, OLD.status, NEW.status, '{}'::jsonb);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER record_appointment_event_after_write
AFTER INSERT OR UPDATE OF status ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.record_appointment_event();

CREATE OR REPLACE FUNCTION public.validate_staff_location()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  location_tenant uuid;
BEGIN
  SELECT tenant_id INTO location_tenant FROM public.locations WHERE id = NEW.location_id;
  IF location_tenant IS NULL OR location_tenant <> NEW.tenant_id THEN
    RAISE EXCEPTION 'staff member location does not belong to the staff tenant';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_staff_location_before_write
BEFORE INSERT OR UPDATE OF tenant_id, location_id ON public.staff
FOR EACH ROW EXECUTE FUNCTION public.validate_staff_location();

CREATE OR REPLACE FUNCTION public.validate_staff_service()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  staff_tenant uuid;
  service_tenant uuid;
BEGIN
  SELECT tenant_id INTO staff_tenant FROM public.staff WHERE id = NEW.staff_id;
  SELECT tenant_id INTO service_tenant FROM public.services WHERE id = NEW.service_id;
  IF staff_tenant IS NULL OR service_tenant IS NULL OR staff_tenant <> service_tenant THEN
    RAISE EXCEPTION 'staff and service must belong to the same tenant';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_staff_service_before_write
BEFORE INSERT OR UPDATE ON public.staff_services
FOR EACH ROW EXECUTE FUNCTION public.validate_staff_service();

CREATE OR REPLACE FUNCTION public.expire_pending_appointment_holds()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  changed_count integer;
BEGIN
  UPDATE public.appointments
  SET status = 'expired'
  WHERE status = 'pending'
    AND hold_expires_at IS NOT NULL
    AND hold_expires_at <= now();
  GET DIAGNOSTICS changed_count = ROW_COUNT;
  RETURN changed_count;
END;
$$;

CREATE INDEX ix_tenant_memberships_profile ON public.tenant_memberships(profile_id, membership_status);
CREATE INDEX ix_tenant_memberships_tenant ON public.tenant_memberships(tenant_id, membership_status);
CREATE INDEX ix_locations_tenant ON public.locations(tenant_id, active);
CREATE INDEX ix_staff_tenant_location ON public.staff(tenant_id, location_id, staff_status);
CREATE INDEX ix_services_tenant_status ON public.services(tenant_id, service_status);
CREATE INDEX ix_operating_hours_tenant_day ON public.operating_hours(tenant_id, day_of_week);
CREATE INDEX ix_staff_hours_staff_day ON public.staff_hours(staff_id, day_of_week);
CREATE INDEX ix_staff_time_off_staff_range ON public.staff_time_off(staff_id, start_at, end_at);
CREATE INDEX ix_appointments_tenant_start ON public.appointments(tenant_id, start_at);
CREATE INDEX ix_appointments_customer_start ON public.appointments(customer_profile_id, start_at);
CREATE INDEX ix_appointments_staff_start_status ON public.appointments(staff_id, start_at, status);
CREATE INDEX ix_appointments_pending_holds ON public.appointments(hold_expires_at) WHERE status = 'pending';
CREATE INDEX ix_notifications_recipient_read ON public.notifications(recipient_profile_id, read_at, created_at);
CREATE INDEX ix_platform_audit_created ON public.platform_audit_logs(created_at);
