/**
 * Demo data for when Supabase is missing or unreachable. Built from the sample
 * Vellore data so people, alerts and zones line up with each other.
 */
import type { Incident } from "../types";
import type { Zone } from "../hooks/useZones";
import { REAL_USER_PROFILES, VELLORE_CRIME_HOTSPOTS } from "./velloreRealData";

const [PRIYA, ANJALI, SNEHA, DIVYA] = REAL_USER_PROFILES;

const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();

/** A function, so the timestamps are relative to when the dashboard opens. */
export const demoIncidents = (): Incident[] => [
  {
    id: "demo-1",
    user_id: PRIYA.user_id,
    status: "open",
    severity: "high",
    latitude: 12.9724,
    longitude: 79.1551,
    created_at: minutesAgo(5),
    notes: "Scream detected near Katpadi Station.",
    source: "audio",
    display_name: PRIYA.name,
  },
  {
    id: "demo-2",
    user_id: ANJALI.user_id,
    status: "acknowledged",
    severity: "high",
    latitude: 12.9692,
    longitude: 79.1559,
    created_at: minutesAgo(25),
    notes: "SOS button pressed at VIT Main Gate.",
    source: "manual",
    display_name: ANJALI.name,
  },
  {
    id: "demo-3",
    user_id: SNEHA.user_id,
    status: "open",
    severity: "medium",
    latitude: 12.968,
    longitude: 79.157,
    created_at: minutesAgo(50),
    notes: "Entered a high-risk zone after 8 pm.",
    source: "device",
    display_name: SNEHA.name,
  },
  {
    id: "demo-4",
    user_id: DIVYA.user_id,
    status: "resolved",
    severity: "low",
    latitude: 12.97,
    longitude: 79.1545,
    created_at: minutesAgo(120),
    resolved_at: minutesAgo(95),
    notes: "Left the planned route, then returned to it.",
    source: "route",
    display_name: DIVYA.name,
  },
];

export const DEMO_ZONES: Zone[] = VELLORE_CRIME_HOTSPOTS.map((h, i) => ({
  id: 900 + i,
  location: h.location,
  lat: h.coordinates.lat,
  lng: h.coordinates.lng,
  severity: h.severity,
  type: h.crimeTypes[0],
  active_hours: h.activeHours,
  description: h.description,
  radius: h.radius,
  isDefault: true,
}));

export const DEMO_PROFILES: Record<string, { full_name?: string; phone?: string }> = Object.fromEntries(
  REAL_USER_PROFILES.map((p) => [p.user_id, { full_name: p.name, phone: p.phone }])
);
