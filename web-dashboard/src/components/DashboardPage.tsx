"use client";

import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

import MapView, { DynamicZone, MapPerson } from "./MapView";
import { StatusDome, type DomeSheet, type DomeStanding } from "./command/StatusDome";
import { CommandBar, CountCard, IncidentsCard, PeopleCard, Splash, Toast, statusLabel, type AlertItem, type Person, type Place } from "./command/panels";
import { useBackend } from "../hooks/useBackend";
import { useZones } from "../hooks/useZones";
import { useRealtimeLocations } from "../hooks/useRealtimeLocations";
import { useRealtimeIncidents } from "../hooks/useRealtimeIncidents";
import { DEMO_PROFILES } from "../data/demo";
import { TimeMode } from "../data/crimeZones";
import { countWord, timeAgo } from "../lib/format";
import { isPointInZone } from "../lib/geo";
import { PINE_TINT } from "../lib/theme";
import type { Incident } from "../types";

type Profile = { phone?: string; full_name?: string };

// Long enough for the wordmark to finish rising before the screen opens.
const SPLASH_MIN_MS = 1500;
const SPLASH_FADE_MS = 700;

// The chrome is drawn for this stage and scaled down to fit smaller windows
// (a projector, a split screen), so the layout never has to reflow.
const STAGE = { width: 1280, height: 720 };

// Stage space the chrome covers, kept out of the map's frame: the top bar, the
// two side columns, and the dome at whatever height it currently is. The dome
// heights mirror .wsf-dome in app/globals.css.
const FRAME = { top: 96, side: 372 };
const DOME_HEIGHT = { cap: 92, quiet: 206, raised: 304 };
const DOME_CLEARANCE = 36;

const TONE_RANK = { alert: 0, danger: 1, caution: 2, clear: 3 } as const;

const SOURCE_LABEL: Record<string, string> = {
  audio: "audio model",
  manual: "SOS button",
  device: "device",
  route: "route watch",
};

// What an incident is called when it arrives without notes.
const SOURCE_LINE: Record<string, string> = {
  audio: "Possible scream detected.",
  manual: "SOS button pressed.",
  device: "Entered a high-risk zone.",
  route: "Left the planned route.",
};

// "Green Circle - Sathuvachari" → "Green Circle"; "Sathuvachari (Burial Ground Area)" → "Sathuvachari"
const shortPlace = (name: string) => name.split(" - ")[0].replace(/\s*\(.*\)$/, "").replace(/\s+Area$/, "");

const motionWord = (speed?: number | null) => {
  if (speed == null) return undefined;
  if (speed < 0.3) return "standing still";
  if (speed < 2.5) return "walking";
  return "moving fast";
};

// High severity and nobody has acknowledged it yet
const isUrgent = (incident: Incident) => incident.severity === 'high' && incident.status === 'open';

// Queue order: unacknowledged high first, then anything still open, then the rest; newest first within each
const queueRank = (incident: Incident) => (isUrgent(incident) ? 0 : incident.status === 'open' ? 1 : 2);

function useNow(everyMs: number): Date | null {
  const [now, setNow] = useState<Date | null>(null);
  useEffect(() => {
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), everyMs);
    return () => clearInterval(id);
  }, [everyMs]);
  return now;
}

/** Scale that fits the stage into the window, and the stage's size at that scale. */
function useStage() {
  const [stage, setStage] = useState({ zoom: 1, width: STAGE.width, height: STAGE.height });
  // Layout effect: the first painted frame is already at the right scale.
  useLayoutEffect(() => {
    const fit = () => {
      const zoom = Math.min(1, window.innerWidth / STAGE.width, window.innerHeight / STAGE.height);
      setStage({ zoom, width: window.innerWidth / zoom, height: window.innerHeight / zoom });
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);
  return stage;
}

export const DashboardPage: React.FC = () => {
  const { supabase, mode } = useBackend();

  const [held, setHeld] = useState(true);
  useEffect(() => {
    const id = setTimeout(() => setHeld(false), SPLASH_MIN_MS);
    return () => clearTimeout(id);
  }, []);
  const ready = mode !== "checking" && !held;

  const [splashGone, setSplashGone] = useState(false);
  useEffect(() => {
    if (!ready) return;
    const id = setTimeout(() => setSplashGone(true), SPLASH_FADE_MS);
    return () => clearTimeout(id);
  }, [ready]);

  return (
    <div className="relative h-screen w-full overflow-hidden bg-ground font-sans text-fg">
      {ready && <CommandCenter supabase={supabase} demo={mode === "demo"} />}
      {!splashGone && <Splash leaving={ready} />}
    </div>
  );
};

const CommandCenter: React.FC<{ supabase: SupabaseClient | null; demo: boolean }> = ({ supabase, demo }) => {
  const timeMode: TimeMode = 'all';
  const { zones } = useZones(timeMode, demo);

  const { locations } = useRealtimeLocations(supabase);
  const { incidents, loading, acknowledgeIncident, resolveIncident } = useRealtimeIncidents(supabase);
  const now = useNow(30_000);
  const stage = useStage();

  const displayLocations = locations;
  const [flyToLocation, setFlyToLocation] = useState<{ lat: number; lng: number } | null>(null);
  const [profiles, setProfiles] = useState<Record<string, Profile>>(demo ? DEMO_PROFILES : {});

  useEffect(() => {
    if (!supabase) return;
    if (displayLocations.length === 0) {
      setProfiles({});
      return;
    }
    const ids = displayLocations.map(l => l.user_id);
    supabase
      .from('profiles')
      .select('id,full_name,phone')
      .in('id', ids)
      .order('id')
      .then(({ data, error }) => {
        if (error) console.error('profiles fetch error:', error.message);
        const next: Record<string, Profile> = {};
        ids.forEach(id => { next[id] = {}; });
        (data ?? []).forEach((p: any) => {
          next[p.id] = { full_name: p.full_name ?? undefined, phone: p.phone ?? undefined };
        });
        setProfiles(next);
      });
  }, [displayLocations, supabase]);

  const [dynamicZones, setDynamicZones] = useState<DynamicZone[]>([]);

  useEffect(() => {
    if (!supabase) return;
    supabase
      .from('dynamic_zones')
      .select('id,risk_level,boundary')
      .then(({ data, error }) => {
        if (error) { console.error('dynamic_zones fetch error:', error.message); return; }
        setDynamicZones((data as DynamicZone[]) ?? []);
      });
  }, [supabase]);

  // Anyone with an open audio or high-severity incident: coral beacon, sonar rings
  const usersInAlert = useMemo(() => new Set(
    incidents
      .filter(i => i.status === 'open' && i.user_id && (i.source === 'audio' || i.severity === 'high'))
      .map(i => i.user_id!)
  ), [incidents]);

  const people: Person[] = useMemo(() => displayLocations.map((loc): Person => {
    const profile = profiles[loc.user_id];
    const inside = zones.filter(z => isPointInZone(loc.latitude, loc.longitude, z));
    const worst = inside.find(z => z.severity === 'HIGH') ?? inside.find(z => z.severity === 'MODERATE');
    const zone = worst?.severity === 'HIGH' ? 'danger' : worst ? 'caution' : null;
    const here = worst ?? inside[0];
    return {
      id: loc.user_id,
      name: profile?.full_name ?? profile?.phone ?? `${loc.user_id.slice(0, 8)}…`,
      phone: profile?.phone,
      place: here ? shortPlace(here.location) : `${loc.latitude.toFixed(4)}, ${loc.longitude.toFixed(4)}`,
      motion: motionWord(loc.speed),
      tone: usersInAlert.has(loc.user_id) ? 'alert' : zone ?? 'clear',
      zone,
      lat: loc.latitude,
      lng: loc.longitude,
    };
  }).sort((a, b) => TONE_RANK[a.tone] - TONE_RANK[b.tone]), [displayLocations, profiles, zones, usersInAlert]);

  const mapPeople: MapPerson[] = useMemo(
    () => people.map(p => ({ user_id: p.id, name: p.name, phone: p.phone, tone: p.tone })),
    [people]
  );

  const places: Place[] = useMemo(() => [
    ...people.map((p): Place => ({ name: p.name, kind: 'Person', lat: p.lat, lng: p.lng })),
    ...zones.map((z): Place => ({ name: z.location, kind: 'Zone', lat: z.lat, lng: z.lng })),
  ], [people, zones]);

  // Everything unresolved, most pressing first
  const queue: AlertItem[] = useMemo(() => incidents
    .filter(i => i.status !== 'resolved')
    .sort((a, b) => queueRank(a) - queueRank(b) || new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .map((incident): AlertItem => {
      const profile = incident.user_id ? profiles[incident.user_id] : undefined;
      return {
        incident,
        title: incident.notes?.trim() || SOURCE_LINE[incident.source ?? ''] || 'Alert raised.',
        who: profile?.full_name || incident.display_name || 'Unknown person',
        phone: profile?.phone,
        source: SOURCE_LABEL[incident.source ?? ''],
        urgent: isUrgent(incident),
      };
    }), [incidents, profiles]);

  const urgent = useMemo(() => queue.filter(item => item.urgent), [queue]);

  const activeUsersCount = displayLocations.length;
  const usersInDangerCount = people.filter(p => p.zone !== null).length;

  const [toast, setToast] = useState<string | null>(null);
  const clearToast = useCallback(() => setToast(null), []);
  const [showZones, setShowZones] = useState(true);
  const [showPatrols, setShowPatrols] = useState(false);

  const flyTo = useCallback((target: { lat: number; lng: number }) => setFlyToLocation({ lat: target.lat, lng: target.lng }), []);
  const showIncident = useCallback((incident: Incident) => flyTo({ lat: incident.latitude, lng: incident.longitude }), [flyTo]);

  // ── The dome ──────────────────────────────────────────────────────────────
  // Down by default. It comes up for a new unacknowledged alert, or for an
  // incident the operator picks, and goes back down once that is dealt with.
  const [raised, setRaised] = useState(false);
  const [pickedId, setPickedId] = useState<string | null>(null);
  const focus = raised ? queue.find(item => item.incident.id === pickedId) ?? null : null;

  const openIncident = (item: AlertItem) => {
    setPickedId(item.incident.id);
    setRaised(true);
    showIncident(item.incident);
  };
  // Going down hands the screen back: the map eases out to the overview again
  const [overview, setOverview] = useState(0);
  const lower = useCallback(() => {
    setRaised(false);
    setOverview(n => n + 1);
  }, []);

  // A new unacknowledged alert brings the dome up by itself
  const seenUrgent = useRef<Set<string> | null>(null);
  useEffect(() => {
    if (loading) return;
    const firstLook = seenUrgent.current === null;
    const seen = (seenUrgent.current ??= new Set());
    const fresh = urgent.filter(item => !seen.has(item.incident.id));
    if (fresh.length === 0) return;
    fresh.forEach(item => seen.add(item.incident.id));
    setPickedId(fresh[0].incident.id);
    setRaised(true);
    // On first load the map keeps its overview; later alerts pull the map to them
    if (!firstLook) showIncident(fresh[0].incident);
  }, [urgent, loading, showIncident]);

  // If the incident on the dome is resolved from under it, the dome goes down
  useEffect(() => {
    if (raised && pickedId && !queue.some(item => item.incident.id === pickedId)) {
      lower();
      setPickedId(null);
    }
  }, [raised, pickedId, queue, lower]);

  useEffect(() => {
    if (!raised) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') lower(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [raised, lower]);

  const acknowledge = async (id: string) => {
    // Done with this one: move to the next alert that is waiting, or step out of the way
    const next = urgent.find(item => item.incident.id !== id);
    if (next) openIncident(next);
    else lower();
    const { error } = await acknowledgeIncident(id);
    if (error) setToast(`The alert was not acknowledged. ${error}`);
  };
  const resolve = async (id: string) => {
    lower();
    const { error } = await resolveIncident(id);
    if (error) setToast(`The alert was not marked resolved. ${error}`);
  };
  const nextAlert = () => {
    const others = urgent.filter(item => item.incident.id !== pickedId);
    if (others.length > 0) openIncident(others[0]);
  };
  const raise = () => {
    // From the cap: open whatever is most pressing, or the quiet dome if nothing is
    setPickedId(queue[0]?.incident.id ?? null);
    setRaised(true);
    if (queue[0]) showIncident(queue[0].incident);
    else setOverview(n => n + 1);
  };

  const quietLine =
    activeUsersCount === 0 ? 'nobody is out.'
    : usersInDangerCount > 0 ? `${countWord(activeUsersCount)} out, nothing open.`
    : activeUsersCount === 1 ? 'one out, doing fine.'
    : `${countWord(activeUsersCount)} out, ${countWord(activeUsersCount)} fine.`;

  const standing: DomeStanding =
    loading ? { tone: 'boot', lead: 'one moment.' }
    : urgent.length > 0 ? { tone: 'alert', lead: urgent.length === 1 ? 'alert waiting.' : `${countWord(urgent.length)} alerts waiting.`, note: 'Click to open' }
    : queue.length > 0 ? { tone: 'watch', lead: 'on watch.', note: `${queue.length} open` }
    : { tone: 'calm', lead: 'all quiet.', note: `${countWord(activeUsersCount)} out` };

  let sheet: DomeSheet | null = null;
  if (raised && !loading) {
    if (focus) {
      sheet = {
        kind: 'incident',
        id: focus.incident.id,
        urgent: focus.urgent,
        open: focus.incident.status === 'open',
        eyebrow: [statusLabel(focus), focus.source, now && timeAgo(focus.incident.created_at, now.getTime())].filter(Boolean).join(' · '),
        headline: focus.title,
        detail: [focus.who, focus.phone].filter(Boolean).join(' · '),
        waiting: urgent.filter(item => item.incident.id !== focus.incident.id).length,
      };
    } else if (!pickedId) {
      sheet = { kind: 'calm', lead: 'all quiet.', accent: quietLine };
    }
  }

  // Keep whatever the chrome covers out of the map's frame, dome included
  const domeHeight = !sheet ? DOME_HEIGHT.cap : sheet.kind === 'calm' ? DOME_HEIGHT.quiet : DOME_HEIGHT.raised;
  const framePadding = useMemo(() => ({
    top: FRAME.top * stage.zoom,
    right: FRAME.side * stage.zoom,
    bottom: (domeHeight + DOME_CLEARANCE) * stage.zoom,
    left: FRAME.side * stage.zoom,
  }), [stage.zoom, domeHeight]);

  return (
    <div className="absolute inset-0">

      {/* MAP: the whole screen */}
      <div className="wsf-fade absolute inset-0 z-0">
        <MapView
          incidents={incidents}
          locations={displayLocations}
          zones={zones}
          selectedIncidentId={focus?.incident.id ?? null}
          onSelectIncident={() => { }}
          loading={false}
          supabaseEnabled={true}
          mapStyle="mapbox://styles/mapbox/dark-v11"
          tint={PINE_TINT}
          showZones={showZones}
          showPatrolRoutes={showPatrols}
          flyToLocation={flyToLocation}
          dynamicZones={dynamicZones}
          usersWithAudioThreat={usersInAlert}
          people={mapPeople}
          fitToData
          framePadding={framePadding}
          overviewSignal={overview}
          onDispatch={(name) => setToast(`Patrol requested for ${name}. Dispatch is not connected yet, so nobody has been notified.`)}
        />
      </div>

      {/* CHROME: everything that floats on the map, scaled to the window */}
      <div
        className="pointer-events-none absolute inset-0 z-10"
        style={{ zoom: stage.zoom, '--stage-w': `${stage.width}px` } as React.CSSProperties}
        data-short={stage.height < 780 ? '' : undefined}
      >
        <CommandBar
          demo={demo}
          places={places}
          onPick={flyTo}
          showZones={showZones}
          onToggleZones={() => setShowZones(v => !v)}
          showPatrols={showPatrols}
          onTogglePatrols={() => setShowPatrols(v => !v)}
        />

        {/* LEFT: who is out */}
        <div className="pointer-events-none absolute bottom-6 left-7 top-[104px] z-10 flex w-[320px] flex-col gap-3">
          <PeopleCard people={people} onPick={flyTo} />
        </div>

        {/* RIGHT: the count, and everything still open */}
        <div className="pointer-events-none absolute bottom-6 right-7 top-[104px] z-10 flex w-[320px] flex-col gap-3">
          <CountCard demo={demo} now={now} count={activeUsersCount} inRiskZone={usersInDangerCount} />
          {queue.length > 0 && (
            <IncidentsCard items={queue} activeId={focus?.incident.id ?? null} now={now} onOpen={openIncident} />
          )}
        </div>

        <StatusDome
          standing={standing}
          sheet={sheet}
          onRaise={raise}
          onLower={lower}
          onAcknowledge={acknowledge}
          onResolve={resolve}
          onShow={() => focus && showIncident(focus.incident)}
          onNext={nextAlert}
        />

        {toast && <Toast message={toast} onDone={clearToast} />}
      </div>
    </div>
  );
};
