-- supabase/seed.sql
-- Sample data for the LOCAL stack only. Runs after the migrations on
-- `supabase start` (first boot) and `supabase db reset`. Never runs against a
-- hosted project.
--
-- The places are the dashboard's own default zones around Vellore
-- (web-dashboard/src/data/crimeZones.ts — keep the two in step), so the mobile
-- map and the dashboard agree out of the box:
--   zones          the dashboard's defaults, in the shape useZones.ts writes
--   heatmap_zones  one row per place (mobile heatmap, backend /heatmap)
--   dynamic_zones  a circle around each place (mobile danger zones, safe routing)
--
-- Users are not seeded: sign in from the app with a test number from
-- config.toml ([auth.sms.test_otp]).
--
-- For the Hyderabad crime set and real DBSCAN zones instead:
--   cd backend-ai && .venv/bin/python data/seed_all.py
-- That replaces everything in dynamic_zones, and its 747 incidents arrive with
-- status 'open', so they all show up in the dashboard feed.

set search_path = public, extensions;

with places (area_name, latitude, longitude, risk, radius_m, reason, active_hours, description) as (
  values
    ('Sathuvachari (Burial Ground Area)', 12.9490, 79.1650, 'high', 250, 'Violence/Abduction', '18-06', 'Critical Red Zone along NH 48. High risk of share autos diverting to secluded areas after dark.'),
    ('Green Circle Junction', 12.9716, 79.1594, 'high', 200, 'Harassment/Abduction', '21-05', 'High transit friction zone. Funnel for drunkards moving between TASMAC outlets late at night.'),
    ('Katpadi Railway Station', 12.9796, 79.1374, 'high', 300, 'Assault/Robbery', null, 'Epicenter of transit crime. Risk of assault on moving trains near station approaches.'),
    ('VIT Road (UGD Works)', 12.9750, 79.1500, 'high', 180, 'Chain Snatching', null, 'Construction-induced traffic slowdowns create a ''natural trap'' for women on two-wheelers.'),
    ('Chittoor Bus Stand (Katpadi)', 12.9760, 79.1350, 'high', 220, 'Vehicle Theft/Harassment', null, 'Hotspot for juvenile crime rings targeting two-wheelers. General atmosphere of lawlessness.'),
    ('Kagithapattarai (Palar River Bank)', 12.9550, 79.1450, 'high', 280, 'Public Nuisance/Harassment', '19-05', 'Extreme density of liquor outlets. Streets colonized by intoxicated men after 7 PM.'),
    ('Vellore Fort Park (Moat Area)', 12.9204, 79.1325, 'high', 260, 'Sexual Assault', '18-06', 'Predatory zone after dark. Secluded corners near the moat obscure visibility.'),
    ('Vellore New Bus Stand', 12.9350, 79.1450, 'high', 240, 'Trafficking/Theft', null, 'Dark corners and lack of police patrolling inside the terminus. High density of transient offenders.'),
    ('Viruthampet (Student Housing)', 12.9600, 79.1400, 'medium', 150, 'Stalking/Snatching', null, 'Narrow residential lanes. High density of students attracts stalkers.'),
    ('Gandhi Nagar (Residential)', 12.9500, 79.1350, 'medium', 160, 'Chain Snatching', '13-17', 'Wide, tree-lined streets are desolate in afternoons. Ideal hunting ground for snatchers.'),
    ('Bagayam (Southern Fringe)', 12.8900, 79.1200, 'medium', 200, 'Rowdyism', null, 'Stronghold of gangs. Inter-gang violence creates a volatile environment.'),
    ('Ariyur', 12.8800, 79.1000, 'medium', 180, 'Domestic Violence', null, 'Semi-rural settlement. High incidence of domestic violence.')
),
manual as (
  insert into public.zones (name, risk_level, description, polygon_geojson, active_hours)
  select
    area_name,
    case risk when 'high' then 'red' else 'yellow' end,
    description,
    jsonb_build_object(
      'type', 'Feature',
      'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(longitude, latitude))
    ),
    active_hours
  from places
),
heat as (
  insert into public.heatmap_zones (area_name, city, latitude, longitude, radius_m, risk_level, reason)
  select area_name, 'Vellore', latitude, longitude, radius_m, risk, reason
  from places
)
insert into public.dynamic_zones (risk_level, source, boundary)
select
  case risk when 'high' then 'red' else 'yellow' end,
  'seed',
  st_asgeojson(
    st_buffer(st_setsrid(st_makepoint(longitude, latitude), 4326)::geography, radius_m, 8)::geometry,
    6
  )::jsonb
from places;
