-- =============================================================================
-- SENTRA / WSF — ALIGN SCHEMA WITH APP CODE
-- Migration: 0003_align_schema_with_app_code
-- =============================================================================
-- 0002 noted that the hosted database had drifted from 0001 (incidents.severity
-- became text, trip_pings was reshaped, ...) without any of it being recorded.
-- This migration writes down the shapes the app code actually sends, so a
-- database built from these files (supabase start / db reset) accepts every
-- query the mobile app, dashboard and backend make:
--
--   mobile  home_screen.dart      incidents.severity = 'high'
--   mobile  home_screen.dart      trips.started_at
--   mobile  geofence_service.dart trip_pings (trip_id, user_id, latitude, longitude)
--
-- Idempotent — safe to run more than once.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- 1. INCIDENTS — severity is text: low | medium | high.
--    Old integer rows are converted (1=low 2=medium 3=high). `location` is a
--    generated column over latitude/longitude only, so it is unaffected.
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'incidents'
      and column_name  = 'severity'
      and data_type    = 'integer'
  ) then
    alter table public.incidents alter column severity drop default;
    alter table public.incidents alter column severity type text using (
      case severity when 1 then 'low' when 3 then 'high' else 'medium' end
    );
  end if;
end $$;

alter table public.incidents alter column severity set default 'medium';

-- -----------------------------------------------------------------------------
-- 2. TRIPS — the app stamps started_at when a journey begins.
-- -----------------------------------------------------------------------------
alter table public.trips add column if not exists started_at timestamptz;

-- -----------------------------------------------------------------------------
-- 3. TRIP_PINGS — the app sends plain latitude/longitude plus the user id.
--    current_location (0001) stays, nullable, for rows written the old way.
-- -----------------------------------------------------------------------------
alter table public.trip_pings
  add column if not exists user_id   uuid references auth.users (id) on delete cascade,
  add column if not exists latitude  double precision,
  add column if not exists longitude double precision;

-- -----------------------------------------------------------------------------
-- 4. BRIDGE: trip_pings → live_locations, reading either ping shape.
--    The user comes from the trip, never from the ping's own user_id, so a
--    ping cannot move someone else's beacon.
-- -----------------------------------------------------------------------------
create or replace function public.sync_trip_ping_to_live_location()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user uuid;
  v_lat  double precision := coalesce(new.latitude,  st_y(new.current_location));
  v_lng  double precision := coalesce(new.longitude, st_x(new.current_location));
begin
  select user_id into v_user from public.trips where id = new.trip_id;
  if v_user is null or v_lat is null or v_lng is null then
    return new;
  end if;

  insert into public.live_locations (
    user_id, latitude, longitude, source_type, mesh_hop_count, updated_at
  )
  values (v_user, v_lat, v_lng, 'online', 0, now())
  on conflict (user_id) do update set
    latitude    = excluded.latitude,
    longitude   = excluded.longitude,
    source_type = 'online',
    updated_at  = now();

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. BRIDGE: trips.status = 'sos' → incidents, at the latest ping (either
--    shape), falling back to where the trip started. Severity is now text.
-- -----------------------------------------------------------------------------
create or replace function public.sos_trip_to_incident()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lat  double precision;
  v_lng  double precision;
  v_name text;
begin
  if new.status = 'sos' and (old.status is distinct from 'sos') then
    select coalesce(latitude,  st_y(current_location)),
           coalesce(longitude, st_x(current_location))
      into v_lat, v_lng
    from public.trip_pings
    where trip_id = new.id
    order by created_at desc
    limit 1;

    if v_lat is null or v_lng is null then
      v_lat := st_y(new.start_location);
      v_lng := st_x(new.start_location);
    end if;
    if v_lat is null or v_lng is null then return new; end if;

    select full_name into v_name from public.profiles where id = new.user_id;

    insert into public.incidents (
      user_id, status, severity, latitude, longitude,
      source, display_name, notes
    )
    values (
      new.user_id::text,
      'open',
      'high',
      v_lat,
      v_lng,
      'device',
      coalesce(v_name, 'SENTRA user'),
      'Auto-created from trip SOS'
    );
  end if;
  return new;
end;
$$;
