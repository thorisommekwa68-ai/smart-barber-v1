-- Realtime security validation for a non-production Supabase test project.
BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'appointments'
  ) THEN
    RAISE EXCEPTION 'raw appointments must not be published';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'appointment_events'
  ) THEN
    RAISE EXCEPTION 'appointment_events publication is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    RAISE EXCEPTION 'notifications publication is missing';
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notifications'
      AND policyname = 'notifications_recipient'
  ) THEN
    RAISE EXCEPTION 'notification recipient RLS policy is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'appointment_events'
      AND policyname = 'appointment_events_read'
  ) THEN
    RAISE EXCEPTION 'appointment event RLS policy is missing';
  END IF;
END;
$$;

ROLLBACK;
