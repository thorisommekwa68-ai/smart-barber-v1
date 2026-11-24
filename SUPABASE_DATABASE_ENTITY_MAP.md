# Smart Barber Supabase Database Entity Map

## Core identity entities

### profiles

Maps internal application users to Supabase Auth UUIDs.

Recommended key:

- `id uuid primary key references auth.users(id)`
- display_name
- email
- phone
- active
- timestamps

This entity replaces the in-memory `users` records and is the application profile, not an authorization token.

## Tenant entities

### tenants

- id uuid
- business_name
- business_description
- business_status
- timezone
- created_at
- updated_at

### tenant_memberships

- id uuid
- tenant_id
- profile_id
- role: owner, manager, receptionist, stylist
- membership_status
- timestamps

Unique `(tenant_id, profile_id)`.

### locations

- id uuid
- tenant_id
- name
- address
- latitude
- longitude
- timezone
- timestamps

### staff

- id uuid
- tenant_id
- location_id
- profile_id optional
- display_name
- staff_status
- timestamps

### staff_services

- staff_id
- service_id
- unique pair

### services

- id uuid
- tenant_id
- name
- description
- price_minor integer
- duration_minutes integer
- buffer_minutes integer
- service_status
- timestamps

## Availability entities

### operating_hours

- tenant_id
- day_of_week
- open_time
- close_time

### staff_hours

- staff_id
- day_of_week
- start_time
- end_time

### staff_time_off

- id uuid
- staff_id
- start_at timestamptz
- end_at timestamptz
- reason

Staff time-off must be tenant-consistent and time-zone aware.

## Appointment entities

### appointments

- id uuid
- tenant_id
- location_id
- customer_profile_id
- staff_id
- service_id
- start_at timestamptz
- end_at timestamptz
- price_snapshot_minor integer
- duration_snapshot_minutes integer
- status
- hold_expires_at timestamptz
- customer_notes
- timestamps

PostgreSQL-safe status values should correspond to the existing lifecycle:

- pending
- confirmed
- in_progress
- completed
- declined
- cancelled
- expired
- no_show

### appointment_events

- id uuid
- appointment_id
- from_status
- to_status
- actor_profile_id
- created_at

Every lifecycle mutation should append an event.

## Customer entities

### customer_favourites

- customer_profile_id
- tenant_id
- service_id
- timestamps

### customer_preferences, optional

Only create if the UI has a defined persistent requirement.

## Notification entities

### notifications

- id uuid
- tenant_id
- recipient_profile_id
- type
- payload jsonb
- read_at
- timestamps

Realtime should subscribe to notifications or appointment events, not expose broad tenant tables without authorization review.

## Commerce and platform entities

### subscription_plans

- id uuid
- name
- entitlements jsonb
- limits jsonb
- price_minor
- active
- timestamps

### tenant_subscriptions

- tenant_id
- plan_id
- status
- starts_at
- ends_at
- timestamps

### platform_administrators

- profile_id
- status
- timestamps

### platform_role_assignments

- profile_id
- role
- granted_by
- revoked_at
- timestamps

### platform_audit_logs

- actor_profile_id
- action
- tenant_id nullable
- target_type
- target_id
- before_json
- after_json
- created_at

### support_tickets

If retained, add tenant_id, requester_profile_id, status, category, assigned_profile_id and timestamps.

## Storage metadata

Store storage object keys in application tables rather than only in URLs:

- tenant_assets
- staff_assets
- customer/appointment documents if approved

## Required indexes

- tenant_id on every tenant-owned table
- customer_profile_id/start_at on appointments
- staff_id/start_at/status on appointments
- tenant_id/status on appointments
- membership profile_id/tenant_id/status
- staff/time-off staff_id/start_at/end_at
- operating/staff hours tenant/staff and day
- notification recipient/read_at/created_at

## PostgreSQL data types

- UUID for application and Auth identities
- `timestamptz` for UTC timestamps
- `time` or integer minutes for recurring local time, with tenant timezone separately
- integer minor units for ZAR
- `jsonb` only for payload/entitlements, not as a substitute for stable relationships
