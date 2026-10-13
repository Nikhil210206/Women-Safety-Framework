# SENTRA / WSF — Database

The backend, mobile app and dashboard share one Supabase project. The files in
`migrations/` are its schema, applied in order:

| Migration | What it does |
|---|---|
| `0001_unified_schema.sql` | All tables, the two live bridges, realtime, RLS |
| `0002_user_domain_hardening.sql` | Onboarding columns on `profiles`, `emergency_contacts` |
| `0003_align_schema_with_app_code.sql` | Column shapes the app code sends (`severity` as text, `trips.started_at`, `trip_pings` lat/lng) |

## Run it locally (Docker)

You need Docker Desktop running and Node. From the repo root:

```bash
npx supabase start
```

The first run downloads the images (a few minutes). After that it prints the
local URLs. `seed.sql` loads sample danger zones around Vellore.

| What | Where |
|---|---|
| API (use as `SUPABASE_URL`) | http://127.0.0.1:54321 |
| Studio (browse tables, users) | http://127.0.0.1:54323 |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |

Print the keys for the `.env` files:

```bash
npx supabase status -o env
```

| App | File | Set |
|---|---|---|
| mobile | `mobile-app/.env` | `SUPABASE_URL`, `SUPABASE_ANON_KEY` = `ANON_KEY` |
| dashboard | `web-dashboard/.env` | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` = `ANON_KEY` |
| backend | `backend-ai/.env` | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` = `SERVICE_ROLE_KEY` |

On a real phone or an Android emulator `127.0.0.1` is the device itself.

- **Real phone:** use the computer's network name, `http://<computer-name>.local:54321`
  (on a Mac: `scutil --get LocalHostName`). A numeric address such as
  `192.168.x.x` also works but changes with every Wi-Fi, and the app then hangs
  on its loading screen until it is rebuilt. The phone must be on the same
  network as the computer, or the computer on the phone's hotspot.
- **Android emulator:** `http://10.0.2.2:54321`.

The same host goes in `BACKEND_API_BASE_URL` (port 8000), and the backend has
to listen on all interfaces: `uvicorn main:app --host 0.0.0.0 --port 8000`.

### Signing in

No SMS is sent locally. These numbers always accept the code `123456`:

`90000 00001`, `90000 00002`, `90000 00003`

Add more under `[auth.sms.test_otp]` in `config.toml`, then restart the stack.

### Everyday commands

```bash
npx supabase stop
```

Stops the containers and keeps the data.

```bash
npx supabase db reset
```

Wipes the local database and rebuilds it from the migrations and `seed.sql`.
Run it after adding or changing a migration.

```bash
npx supabase migration new <name>
```

Creates the next migration file. Put schema changes there instead of running
them by hand in Studio, so everyone's database matches.

## Apply to a hosted project

Link the project once, then push the migrations:

```bash
npx supabase link --project-ref <project-ref>
```

```bash
npx supabase db push
```

In **Authentication → Providers**, enable **Phone** with an SMS provider (such
as Twilio) for the mobile OTP login.

## What the schema holds

| Table / object | Used by | Notes |
|---|---|---|
| `profiles` (+ `on_auth_user_created` trigger) | mobile, dashboard | Auto-filled from OTP signup `full_name` + phone; `registration_complete` gates onboarding |
| `emergency_contacts` | mobile | One per user (`unique (user_id)`) |
| `trips` | mobile | Escort sessions; `status` drives SOS |
| `trip_pings` | mobile | Location pings (`latitude`, `longitude`) |
| `dynamic_zones` | mobile, dashboard, backend | DBSCAN output as GeoJSON; written with the service-role key |
| `heatmap_zones` | mobile, backend | Curated danger areas per city |
| `zones` | dashboard | Manual zones (GeoJSON); dashboard auto-seeds defaults |
| `incidents` | all three | lat/lon floats **and** a generated `location` geometry; `severity` is `low`/`medium`/`high` |
| `live_locations` | mobile, dashboard | Latest position per user |
| `responders` | dashboard | Patrol units |
| `get_active_zones()` RPC | — | Returns zone `boundary` as GeoJSON |

## Live bridges (so mobile data appears on the dashboard)
- **`trip_pings` INSERT → `live_locations` upsert** — moving users show on the map.
- **`trips.status='sos'` → new `incidents` row** — SOS appears in the incident feed.

## ⚠️ Security
The dashboard has no login gate yet, so it queries Supabase as the **anon** role.
The dashboard-facing tables therefore use **permissive anon RLS policies** — this is
**demo-grade**. See the `HARDENING` block at the bottom of `0001` for how to
lock it down once you add authority login to the dashboard.
