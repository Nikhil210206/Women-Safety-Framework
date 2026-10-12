import React, { useEffect, useRef, useState } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import { Incident, LiveLocation } from '../types';
import { Zone } from '../hooks/useZones';
import { REAL_USER_PROFILES, PATROL_ROUTES } from '../data/velloreRealData';
import { BAYER4 } from '../lib/dither';
import { circleRing, isPointInZone } from '../lib/geo';
import { WSF, type MapTint } from '../lib/theme';
import { PillButton, Receipt } from './command/kit';

mapboxgl.accessToken = process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN || '';

export interface HeatmapZone {
  id: string;
  area_name: string;
  latitude: number;
  longitude: number;
  radius_m: number;
  risk_level: 'high' | 'medium' | 'low';
  risk_score: number;
  city?: string;
  active_hours?: string;
}

export interface DynamicZone {
  id: string;
  risk_level: string;
  boundary: string | object;
}

/** What the map needs to know about a person beyond their position. */
export interface MapPerson {
  user_id: string;
  name: string;
  phone?: string;
  tone?: 'alert' | 'danger' | 'caution' | 'clear';
}

const EMPTY_USER_THREAT_SET = new Set<string>();
const EMPTY_PEOPLE: MapPerson[] = [];

// Where the map opens before there is any data to fit: Vellore.
const FALLBACK_CENTER: [number, number] = [79.1559, 12.9692];
const FIT_MAX_ZOOM = 15.4;
// Above this many people, only those who need attention get a name label.
const MAX_LABELS = 8;
const ZONE_BEAT_MS = 1500;
const PERSON_CARD = { width: 288, height: 236 };

const ZONE_SOURCE = 'wsf-zones';
const ZONE_LAYERS = ['wsf-zones-wash', 'wsf-zones-dots', 'wsf-zones-glow', 'wsf-zones-edge'];
const INCIDENT_SOURCE = 'wsf-incident';
const TONE_COLOR = ['match', ['get', 'tone'], 'amber', WSF.caution, WSF.danger];
const EMPTY_COLLECTION: GeoJSON.FeatureCollection = { type: 'FeatureCollection', features: [] };

interface MapViewProps {
  incidents?: Incident[];
  locations?: LiveLocation[];
  zones?: Zone[];
  selectedIncidentId?: string | null;
  onSelectIncident?: (id: string) => void;
  loading?: boolean;
  supabaseEnabled?: boolean;
  showHeatmap?: boolean;
  heatmapZones?: HeatmapZone[];
  mapStyle?: string;
  showPatrolRoutes?: boolean;
  flyToLocation?: { lat: number; lng: number } | null;
  dynamicZones?: DynamicZone[];
  usersWithAudioThreat?: Set<string>;
  /** Recolours the base style so the map shares the UI's ground. */
  tint?: MapTint;
  showZones?: boolean;
  /** Names and state for labels and the person card. */
  people?: MapPerson[];
  /** Open on wherever the people (or, failing that, the zones) are. */
  fitToData?: boolean;
  /** Screen space covered by floating UI, kept clear when framing. */
  framePadding?: Partial<mapboxgl.PaddingOptions>;
  /** Bump to ease back to the overview, unless the user has moved the map by hand since. */
  overviewSignal?: number;
  onDispatch?: (name: string) => void;
}

const prefersReducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/** Repaints a stock Mapbox style in the given colours, layer by layer. */
function tintStyle(map: mapboxgl.Map, t: MapTint) {
  const roadColor = [
    'match', ['get', 'class'],
    ['motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary', 'primary_link'], t.roadMajor,
    ['secondary', 'secondary_link', 'tertiary', 'tertiary_link'], t.roadMid,
    t.roadMinor,
  ];
  for (const layer of map.getStyle()?.layers ?? []) {
    // Only the base style: layers we add ourselves have their own sources.
    const source = (layer as { source?: unknown }).source;
    if (typeof source === 'string' && source !== 'composite') continue;
    const id = layer.id;
    const paint = (prop: string, value: unknown) => {
      try {
        (map as any).setPaintProperty(id, prop, value);
      } catch {
        // Not every layer of a type has every property; skip the ones that do not.
      }
    };
    switch (layer.type) {
      case 'background':
        paint('background-color', t.land);
        break;
      case 'fill':
        if (/water/.test(id)) paint('fill-color', t.water);
        else if (/building/.test(id)) {
          paint('fill-color', t.building);
          paint('fill-outline-color', t.building);
        } else if (/park|landuse|landcover|pitch/.test(id)) paint('fill-color', t.park);
        else paint('fill-color', t.land);
        break;
      case 'line':
        if (/water/.test(id)) paint('line-color', t.water);
        else if (/rail/.test(id)) paint('line-color', t.rail);
        else if (/admin|boundary/.test(id)) paint('line-color', t.boundary);
        else if (/road|bridge|tunnel/.test(id)) paint('line-color', /case/.test(id) ? t.land : roadColor);
        else paint('line-color', t.roadMinor);
        break;
      case 'symbol':
        paint('text-color', t.label);
        paint('text-halo-color', t.land);
        break;
      case 'fill-extrusion':
        paint('fill-extrusion-color', t.building);
        break;
    }
  }
}

type DotBand = 'lo' | 'mid' | 'hi';

/** One repeat of the ordered-dither dot pattern, at 3× for crisp edges. */
function dotTile(color: string, band: DotBand): ImageData {
  const scale = 3;
  const pitch = 5;
  const n = 4;
  const px = pitch * n * scale;
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = px;
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = color;
  for (let j = 0; j < n; j++) {
    for (let i = 0; i < n; i++) {
      const t = BAYER4[j * 4 + i] / 15;
      if (band === 'lo' && t > 0.5) continue;
      const r = band === 'hi' ? 0.22 + 0.24 * (1 - t) : band === 'mid' ? 0.15 + 0.27 * (1 - t) : 0.12 + 0.2 * (1 - t);
      ctx.beginPath();
      ctx.arc((i + 0.5) * pitch * scale, (j + 0.5) * pitch * scale, pitch * scale * r, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  return ctx.getImageData(0, 0, px, px);
}

/**
 * Zones as features for the zone layers. Each zone is drawn whole (`full`:
 * wash, glow, edge) and as dot-filled `band`s. Circles get three bands so the
 * dots thicken toward the centre; drawn polygons get one.
 */
function zoneFeatures(zones: Zone[], dynamicZones: DynamicZone[]): GeoJSON.Feature[] {
  const features: GeoJSON.Feature[] = [];
  const polygon = (coordinates: number[][][], properties: Record<string, string>): GeoJSON.Feature => ({
    type: 'Feature',
    geometry: { type: 'Polygon', coordinates },
    properties,
  });

  for (const zone of zones) {
    const tone = zone.severity === 'HIGH' ? 'red' : 'amber';
    const radius = zone.radius || 200;
    const outer = circleRing(zone.lat, zone.lng, radius);
    const middle = circleRing(zone.lat, zone.lng, radius * 0.74);
    const inner = circleRing(zone.lat, zone.lng, radius * 0.42);
    features.push(
      polygon([outer], { kind: 'full', tone }),
      polygon([outer, middle], { kind: 'band', band: 'lo', tone }),
      polygon([middle, inner], { kind: 'band', band: 'mid', tone }),
      polygon([inner], { kind: 'band', band: 'hi', tone }),
    );
  }

  for (const z of dynamicZones) {
    try {
      const geometry = (typeof z.boundary === 'string' ? JSON.parse(z.boundary) : z.boundary) as GeoJSON.Geometry;
      const tone = z.risk_level === 'yellow' ? 'amber' : 'red';
      features.push(
        { type: 'Feature', geometry, properties: { kind: 'full', tone } },
        { type: 'Feature', geometry, properties: { kind: 'band', band: 'mid', tone } },
      );
    } catch (e) {
      console.warn('[MapView] Failed to parse boundary for zone', z.id, e);
    }
  }
  return features;
}

const MapView: React.FC<MapViewProps> = ({
  incidents = [],
  locations = [],
  zones = [],
  selectedIncidentId,
  onSelectIncident,
  loading = false,
  supabaseEnabled = false,
  showHeatmap = false,
  heatmapZones = [],
  mapStyle = 'mapbox://styles/mapbox/dark-v11',
  showPatrolRoutes = false,
  flyToLocation = null,
  dynamicZones = [],
  usersWithAudioThreat = EMPTY_USER_THREAT_SET,
  tint,
  showZones = true,
  people = EMPTY_PEOPLE,
  fitToData = false,
  framePadding,
  overviewSignal = 0,
  onDispatch,
}) => {
  const mapContainer = useRef<HTMLDivElement>(null);
  const map = useRef<mapboxgl.Map | null>(null);
  const labelMarkers = useRef(new Map<string, mapboxgl.Marker>());
  const fittedTo = useRef<'zones' | 'people' | null>(null);
  // True once the user pans or zooms by hand; cleared by every camera move we make
  const userMoved = useRef(false);
  const tintRef = useRef(tint);
  tintRef.current = tint;
  const peopleRef = useRef(people);
  peopleRef.current = people;
  // State for popup
  const [popupInfo, setPopupInfo] = useState<{ x: number, y: number, user: any } | null>(null);
  const [mapLoaded, setMapLoaded] = useState(false);

  // Initialize map
  useEffect(() => {
    if (map.current || !mapContainer.current) return;

    const m = new mapboxgl.Map({
      container: mapContainer.current,
      style: mapStyle,
      center: FALLBACK_CENTER,
      zoom: 13.5,
      pitch: 0,
      attributionControl: false,
      renderWorldCopies: false // Prevent coordinate confusion
    });
    map.current = m;
    // Only moves that come from a pointer or the keyboard carry an originalEvent
    m.on('movestart', (e) => {
      if ((e as { originalEvent?: unknown }).originalEvent) userMoved.current = true;
    });
    const markers = labelMarkers.current;

    // Set up on style load, not full load, so the tint and our layers are in
    // place before the first tiles paint.
    m.once('style.load', () => {
      if (tintRef.current) tintStyle(m, tintRef.current);

      // Add patrol routes (lines)
      PATROL_ROUTES.forEach((route, idx) => {
        m.addSource(`patrol-route-${idx}`, {
          type: 'geojson',
          data: {
            type: 'Feature',
            geometry: {
              type: 'LineString',
              coordinates: route.coordinates
            },
            properties: { name: route.name, officer: route.officer }
          }
        });

        m.addLayer({
          id: `patrol-route-line-${idx}`,
          type: 'line',
          source: `patrol-route-${idx}`,
          paint: {
            'line-color': WSF.text,
            'line-width': 2.5,
            'line-opacity': 0.6,
            'line-dasharray': [2, 2]
          }
        });
      });

      // Zones: a faint wash, an ordered-dither dot fill, a blurred glow and a
      // crisp edge. The same recipe as the app's ZoneLayers. Dots and glow
      // breathe through paint transitions: one style call per beat, not per frame.
      for (const [tone, color] of [['red', WSF.danger], ['amber', WSF.caution]] as const) {
        for (const band of ['lo', 'mid', 'hi'] as const) {
          m.addImage(`wsf-dots-${tone}-${band}`, dotTile(color, band), { pixelRatio: 3 });
        }
      }
      m.addSource(ZONE_SOURCE, { type: 'geojson', data: EMPTY_COLLECTION });
      const isFull = ['==', ['get', 'kind'], 'full'];
      const beat = { duration: ZONE_BEAT_MS, delay: 0 };
      m.addLayer({
        id: 'wsf-zones-wash',
        type: 'fill',
        source: ZONE_SOURCE,
        filter: isFull,
        paint: { 'fill-color': TONE_COLOR, 'fill-opacity': 0.13 }
      } as any);
      m.addLayer({
        id: 'wsf-zones-dots',
        type: 'fill',
        source: ZONE_SOURCE,
        filter: ['==', ['get', 'kind'], 'band'],
        paint: {
          'fill-pattern': ['concat', 'wsf-dots-', ['get', 'tone'], '-', ['get', 'band']],
          'fill-opacity': 0.92,
          'fill-opacity-transition': beat
        }
      } as any);
      m.addLayer({
        id: 'wsf-zones-glow',
        type: 'line',
        source: ZONE_SOURCE,
        filter: isFull,
        layout: { 'line-join': 'round' },
        paint: {
          'line-color': TONE_COLOR,
          'line-width': 16,
          'line-blur': 12,
          'line-opacity': 0.5,
          'line-opacity-transition': beat,
          'line-width-transition': beat
        }
      } as any);
      m.addLayer({
        id: 'wsf-zones-edge',
        type: 'line',
        source: ZONE_SOURCE,
        filter: isFull,
        layout: { 'line-join': 'round' },
        paint: { 'line-color': TONE_COLOR, 'line-width': 2.2 }
      } as any);

      // Where the selected incident was raised
      m.addSource(INCIDENT_SOURCE, { type: 'geojson', data: EMPTY_COLLECTION });
      m.addLayer({
        id: 'wsf-incident-ring',
        type: 'circle',
        source: INCIDENT_SOURCE,
        paint: {
          'circle-radius': 17,
          'circle-color': 'transparent',
          'circle-stroke-color': ['case', ['boolean', ['get', 'urgent'], false], WSF.danger, WSF.text],
          'circle-stroke-width': 1.5,
          'circle-stroke-opacity': 0.9
        }
      });

      // Add single source for users
      m.addSource('users-source', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] }
      });

      // Audio threat sonar ripple rings — rendered behind the dot, animated via setPaintProperty
      ['audio-ripple-1', 'audio-ripple-2', 'audio-ripple-3'].forEach(id => {
        m.addLayer({
          id,
          type: 'circle',
          source: 'users-source',
          filter: ['==', ['get', 'hasAudioThreat'], true],
          paint: {
            'circle-radius': 6,
            'circle-color': 'transparent',
            'circle-stroke-color': WSF.danger,
            'circle-stroke-width': 2,
            'circle-stroke-opacity': 0,
          }
        });
      });

      // Danger Zone Pulsing Ring - Outer
      m.addLayer({
        id: 'users-pulse-red',
        type: 'circle',
        source: 'users-source',
        filter: ['==', ['get', 'inRedZone'], true],
        paint: {
          'circle-radius': 10,
          'circle-color': 'transparent',
          'circle-stroke-color': WSF.danger,
          'circle-stroke-width': 2,
          'circle-stroke-opacity': 0.7
        }
      });

      m.addLayer({
        id: 'users-pulse-yellow',
        type: 'circle',
        source: 'users-source',
        filter: ['all', ['==', ['get', 'inYellowZone'], true], ['!=', ['get', 'inRedZone'], true]],
        paint: {
          'circle-radius': 9,
          'circle-color': 'transparent',
          'circle-stroke-color': WSF.caution,
          'circle-stroke-width': 1.5,
          'circle-stroke-opacity': 0.6
        }
      });

      // User beacon: coral when a threat is active, volt otherwise, ringed in
      // the ground colour so it reads on top of a zone's dots.
      m.addLayer({
        id: 'users-layer',
        type: 'circle',
        source: 'users-source',
        paint: {
          'circle-radius': 6.5,
          'circle-color': [
            'case',
            ['boolean', ['get', 'hasAudioThreat'], false],
            WSF.danger,
            WSF.accent
          ],
          'circle-stroke-color': WSF.ground,
          'circle-stroke-width': 3
        }
      });

      // --- INTERACTION ---

      // Change cursor on hover
      m.on('mouseenter', 'users-layer', () => {
        m.getCanvas().style.cursor = 'pointer';
      });
      m.on('mouseleave', 'users-layer', () => {
        m.getCanvas().style.cursor = '';
      });

      const openPersonCard = (e: mapboxgl.MapMouseEvent): boolean => {
        const feature = m.queryRenderedFeatures(e.point, { layers: ['users-layer'] })[0];
        if (!feature) return false;

        const userId = feature.properties?.userId;
        const person = peopleRef.current.find(p => p.user_id === userId);
        const sample = REAL_USER_PROFILES.find(u => u.user_id === userId);

        setPopupInfo({
          x: e.point.x,
          y: e.point.y,
          user: {
            user_id: userId,
            name: person?.name ?? sample?.name ?? 'Unknown user',
            phone: person?.phone ?? sample?.phone,
            emergencyContact: sample?.emergencyContact,
            tone: person?.tone ?? 'clear',
          }
        });
        return true;
      };

      // Click or right-click a person to open their card; click elsewhere to close it
      m.on('click', (e) => {
        if (!openPersonCard(e)) setPopupInfo(null);
      });
      m.on('contextmenu', (e) => {
        if (openPersonCard(e)) e.preventDefault();
      });

      setMapLoaded(true);
    });

    return () => {
      markers.forEach(marker => marker.remove());
      markers.clear();
      fittedTo.current = null;
      m.remove();
      map.current = null;
      setMapLoaded(false);
    };
  }, [mapStyle]);

  // Re-tint if the palette changes after load
  useEffect(() => {
    if (!map.current || !mapLoaded || !tint) return;
    tintStyle(map.current, tint);
  }, [tint, mapLoaded]);

  // The part of the viewport not covered by floating UI, as camera padding.
  // Capped as a share of the viewport so small windows keep a usable frame.
  const framing = (m: mapboxgl.Map) => {
    const { clientWidth: w, clientHeight: h } = m.getContainer();
    return {
      top: Math.min(framePadding?.top ?? 0, h * 0.2),
      bottom: Math.min(framePadding?.bottom ?? 0, h * 0.48),
      left: Math.min(framePadding?.left ?? 0, w * 0.3),
      right: Math.min(framePadding?.right ?? 0, w * 0.28),
    };
  };

  // Update User Beacons (Single Source Update)
  useEffect(() => {
    if (!map.current || !mapLoaded) return;
    const source = map.current.getSource('users-source') as mapboxgl.GeoJSONSource;
    if (!source) return;

    const features: any[] = locations.map(loc => {
      // Check zones
      let inRedZone = false;
      let inYellowZone = false;
      zones.forEach(zone => {
        if (isPointInZone(loc.latitude, loc.longitude, zone)) {
          if (zone.severity === 'HIGH') inRedZone = true;
          if (zone.severity === 'MODERATE') inYellowZone = true;
        }
      });

      return {
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [loc.longitude, loc.latitude]
        },
        properties: {
          userId: loc.user_id,
          inRedZone,
          inYellowZone,
          hasAudioThreat: usersWithAudioThreat.has(loc.user_id),
        }
      };
    });

    source.setData({
      type: 'FeatureCollection',
      features: features
    });
  }, [locations, mapLoaded, zones, usersWithAudioThreat]);

  // Name labels beside the beacons
  useEffect(() => {
    const m = map.current;
    if (!m || !mapLoaded) return;
    const markers = labelMarkers.current;
    const byId = new Map(people.map(p => [p.user_id, p]));
    const labelEveryone = people.length <= MAX_LABELS;
    const seen = new Set<string>();

    for (const loc of locations) {
      const person = byId.get(loc.user_id);
      const tone = person?.tone ?? 'clear';
      if (!person || !(labelEveryone || tone !== 'clear')) continue;
      seen.add(loc.user_id);

      let marker = markers.get(loc.user_id);
      if (!marker) {
        const el = document.createElement('div');
        el.className = 'wsf-map-label';
        marker = new mapboxgl.Marker({ element: el, anchor: 'left', offset: [15, 0] })
          .setLngLat([loc.longitude, loc.latitude])
          .addTo(m);
        markers.set(loc.user_id, marker);
      } else {
        marker.setLngLat([loc.longitude, loc.latitude]);
      }
      const el = marker.getElement();
      const firstName = person.name.split(' ')[0];
      el.textContent = tone === 'alert' ? `${firstName} · alert` : firstName;
      el.dataset.tone = tone;
    }

    markers.forEach((marker, id) => {
      if (seen.has(id)) return;
      marker.remove();
      markers.delete(id);
    });
  }, [people, locations, mapLoaded]);

  // Frames the people if there are any, otherwise the zones. Returns what it framed.
  const frameData = (m: mapboxgl.Map, duration: number): 'zones' | 'people' | null => {
    const target = locations.length > 0 ? 'people' : 'zones';
    const points: [number, number][] = target === 'people'
      ? locations.map(l => [l.longitude, l.latitude])
      : zones.map(z => [z.lng, z.lat]);
    if (points.length === 0) return null;

    const bounds = new mapboxgl.LngLatBounds();
    points.forEach(p => bounds.extend(p));
    userMoved.current = false;
    m.fitBounds(bounds, { padding: framing(m), maxZoom: FIT_MAX_ZOOM, duration });
    return target;
  };

  // Open on the data, and again once people arrive if it first opened on zones
  useEffect(() => {
    const m = map.current;
    if (!m || !mapLoaded || !fitToData || fittedTo.current === 'people') return;
    if (fittedTo.current === (locations.length > 0 ? 'people' : 'zones')) return;
    fittedTo.current = frameData(m, 0) ?? fittedTo.current;
  }, [locations, zones, mapLoaded, fitToData]);

  // Ease back to the overview when asked, unless the user has taken the map somewhere
  const lastOverview = useRef(overviewSignal);
  useEffect(() => {
    const m = map.current;
    if (lastOverview.current === overviewSignal) return;
    lastOverview.current = overviewSignal;
    if (!m || !mapLoaded || userMoved.current) return;
    frameData(m, 1100);
  }, [overviewSignal, mapLoaded]);

  // Ring animation: in-zone pulse and the alert sonar, driven by one timer
  useEffect(() => {
    const m = map.current;
    if (!m || !mapLoaded) return;

    const paintRings = (pulsePhase: number) => {
      // Calculate pulse values (oscillate radius and opacity)
      const t = pulsePhase / 60;
      const pulseRadius = 10 + Math.sin(t * Math.PI * 2) * 4; // 6-14 range
      const sinVal = (1 + Math.sin(t * Math.PI * 2)) / 2; // 0-1, never negative
      const pulseOpacity = 0.3 + sinVal * 0.4; // 0.3-0.7 range

      // Update red pulse layer
      if (m.getLayer('users-pulse-red')) {
        m.setPaintProperty('users-pulse-red', 'circle-radius', pulseRadius);
        m.setPaintProperty('users-pulse-red', 'circle-stroke-opacity', pulseOpacity);
      }

      // Update yellow pulse layer (slightly smaller)
      if (m.getLayer('users-pulse-yellow')) {
        m.setPaintProperty('users-pulse-yellow', 'circle-radius', pulseRadius - 2);
        m.setPaintProperty('users-pulse-yellow', 'circle-stroke-opacity', pulseOpacity * 0.8);
      }

      // Audio threat sonar rings — 3 rings staggered 1/3 cycle apart, expanding outward
      ['audio-ripple-1', 'audio-ripple-2', 'audio-ripple-3'].forEach((layerId, i) => {
        if (!m.getLayer(layerId)) return;
        const phase = ((pulsePhase + i * 20) % 60) / 60; // 0..1, each ring offset by 1/3
        const ringRadius = 8 + phase * 30;               // 8 → 38 px (sonar expansion)
        const ringOpacity = (1 - phase) * 0.85;          // 0.85 → 0 (fade as it expands)
        m.setPaintProperty(layerId, 'circle-radius', ringRadius);
        m.setPaintProperty(layerId, 'circle-stroke-opacity', ringOpacity);
      });
    };

    // Reduced motion: rings drawn once, at rest
    if (prefersReducedMotion()) {
      paintRings(15);
      return;
    }

    let pulsePhase = 0;
    const interval = setInterval(() => {
      pulsePhase = (pulsePhase + 1) % 60; // 60 frames cycle
      paintRings(pulsePhase);
    }, 50); // 20 FPS
    return () => clearInterval(interval);
  }, [mapLoaded]);

  // Zone breathing: dots dim and the glow tightens on alternate beats
  useEffect(() => {
    const m = map.current;
    if (!m || !mapLoaded || prefersReducedMotion()) return;
    let beat = false;
    const interval = setInterval(() => {
      if (!m.getLayer('wsf-zones-dots')) return;
      beat = !beat;
      m.setPaintProperty('wsf-zones-dots', 'fill-opacity', beat ? 0.5 : 0.92);
      m.setPaintProperty('wsf-zones-glow', 'line-opacity', beat ? 0.18 : 0.55);
      m.setPaintProperty('wsf-zones-glow', 'line-width', beat ? 10 : 18);
    }, ZONE_BEAT_MS);
    return () => clearInterval(interval);
  }, [mapLoaded]);

  // Fly to location when sidebar user is clicked
  useEffect(() => {
    if (!map.current || !mapLoaded || !flyToLocation) return;
    // Camera padding lands the target in the clear area, above the dome and between the cards
    userMoved.current = false;
    map.current.flyTo({
      center: [flyToLocation.lng, flyToLocation.lat],
      zoom: 15.7,
      padding: framing(map.current),
      duration: 1200
    });
  }, [flyToLocation, mapLoaded]);

  // Toggle patrol routes visibility based on prop
  useEffect(() => {
    if (!map.current || !mapLoaded) return;

    PATROL_ROUTES.forEach((_, idx) => {
      const layerId = `patrol-route-line-${idx}`;
      if (map.current?.getLayer(layerId)) {
        map.current.setLayoutProperty(layerId, 'visibility', showPatrolRoutes ? 'visible' : 'none');
      }
    });
  }, [showPatrolRoutes, mapLoaded]);

  // Heatmap layer — rendered as polygon fills matching dynamic zone style
  useEffect(() => {
    if (!map.current || !mapLoaded) return;

    const removeHeatmap = () => {
      if (map.current?.getLayer('heatmap-fill')) map.current.removeLayer('heatmap-fill');
      if (map.current?.getLayer('heatmap-outline')) map.current.removeLayer('heatmap-outline');
      if (map.current?.getSource('heatmap-source')) map.current.removeSource('heatmap-source');
    };

    removeHeatmap();
    if (!showHeatmap || heatmapZones.length === 0) return;

    // Convert each lat/lng/radius_m into a GeoJSON polygon (approximated circle)
    const features: GeoJSON.Feature[] = heatmapZones.map(z => ({
      type: 'Feature',
      geometry: { type: 'Polygon', coordinates: [circleRing(z.latitude, z.longitude, z.radius_m || 300)] },
      properties: { area_name: z.area_name, risk_score: z.risk_score, risk_level: z.risk_level }
    }));

    map.current.addSource('heatmap-source', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features }
    });

    const heatColor = ['match', ['get', 'risk_level'], 'high', WSF.danger, WSF.caution];

    map.current.addLayer({
      id: 'heatmap-fill',
      type: 'fill',
      source: 'heatmap-source',
      paint: { 'fill-color': heatColor, 'fill-opacity': 0.2 }
    } as any, 'users-pulse-red');

    map.current.addLayer({
      id: 'heatmap-outline',
      type: 'line',
      source: 'heatmap-source',
      paint: { 'line-color': heatColor, 'line-width': 2, 'line-opacity': 0.85 }
    } as any, 'users-pulse-red');

    // Hover tooltip
    const onMouseEnter = (e: mapboxgl.MapMouseEvent) => {
      map.current!.getCanvas().style.cursor = 'pointer';
      const props = e.features?.[0]?.properties;
      if (!props) return;
      new mapboxgl.Popup({ closeButton: false, closeOnClick: false })
        .setLngLat(e.lngLat)
        .setHTML(`<strong>${props.area_name}</strong><br/>Risk Score: ${props.risk_score}`)
        .addTo(map.current!);
    };
    const onMouseLeave = () => {
      map.current!.getCanvas().style.cursor = '';
      document.querySelectorAll('.mapboxgl-popup').forEach(p => p.remove());
    };

    map.current.on('mouseenter', 'heatmap-fill', onMouseEnter);
    map.current.on('mouseleave', 'heatmap-fill', onMouseLeave);

    return () => {
      map.current?.off('mouseenter', 'heatmap-fill', onMouseEnter);
      map.current?.off('mouseleave', 'heatmap-fill', onMouseLeave);
      removeHeatmap();
    };
  }, [showHeatmap, heatmapZones, mapLoaded]);

  // Feed the zone layers: circles from the `zones` table, polygons from dynamic_zones
  useEffect(() => {
    if (!map.current || !mapLoaded) return;
    const source = map.current.getSource(ZONE_SOURCE) as mapboxgl.GeoJSONSource | undefined;
    source?.setData({ type: 'FeatureCollection', features: zoneFeatures(zones, dynamicZones) });
  }, [zones, dynamicZones, mapLoaded]);

  // Mark where the selected incident was raised
  useEffect(() => {
    if (!map.current || !mapLoaded) return;
    const source = map.current.getSource(INCIDENT_SOURCE) as mapboxgl.GeoJSONSource | undefined;
    const incident = incidents.find(i => i.id === selectedIncidentId);
    source?.setData({
      type: 'FeatureCollection',
      features: incident ? [{
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [incident.longitude, incident.latitude] },
        properties: { urgent: incident.severity === 'high' && incident.status === 'open' }
      }] : []
    });
  }, [incidents, selectedIncidentId, mapLoaded]);

  // Toggle the zone layers
  useEffect(() => {
    if (!map.current || !mapLoaded) return;
    ZONE_LAYERS.forEach(layerId => {
      if (map.current?.getLayer(layerId)) {
        map.current.setLayoutProperty(layerId, 'visibility', showZones ? 'visible' : 'none');
      }
    });
  }, [showZones, mapLoaded]);

  const dispatchPatrol = (user: { user_id?: string; name: string }) => {
    console.log('Dispatch triggered for user:', user.user_id || user.name);
    // TODO: Call dispatch API when implemented
    if (onDispatch) onDispatch(user.name);
    else alert(`Dispatch initiated for ${user.name}`);
    setPopupInfo(null);
  };

  // Keep the person card inside the clear frame so the floating UI never covers it
  const cardPosition = (() => {
    const m = map.current;
    if (!popupInfo || !m) return { left: 0, top: 0 };
    const { clientWidth: w, clientHeight: h } = m.getContainer();
    const frame = framing(m);
    const clamp = (v: number, min: number, max: number) => Math.max(min, Math.min(v, Math.max(min, max)));
    return {
      left: clamp(popupInfo.x + 12, frame.left, w - frame.right - PERSON_CARD.width),
      top: clamp(popupInfo.y + 12, frame.top, h - frame.bottom - PERSON_CARD.height),
    };
  })();

  return (
    <>
      <div ref={mapContainer} style={{ width: '100%', height: '100%', position: 'relative', background: tint?.land }} />

      {/* Person card */}
      {popupInfo && (
        <div
          style={{
            position: 'absolute',
            left: cardPosition.left,
            top: cardPosition.top,
            zIndex: 20,
            width: PERSON_CARD.width
          }}
          className="wsf-in"
        >
          <Receipt
            className="!bg-ground-2"
            strip={<><span>Person</span><span>{popupInfo.user.tone === 'alert' ? 'Alert open' : 'Sharing location'}</span></>}
          >
            <div className="px-[18px] pb-[18px] pt-4">
              <h3 className="wsf-display wsf-display--plain truncate text-[24px]">{popupInfo.user.name}</h3>
              <dl className="mt-3 grid grid-cols-[88px_1fr] gap-x-3 gap-y-1.5 text-[13px]">
                <dt className="text-dim">Mobile</dt>
                <dd className="truncate font-medium">{popupInfo.user.phone ?? 'Not on file'}</dd>
                <dt className="text-dim">SOS contact</dt>
                <dd className="truncate font-medium">{popupInfo.user.emergencyContact ?? 'Not on file'}</dd>
              </dl>
              <PillButton className="mt-4 w-full" onClick={() => dispatchPatrol(popupInfo.user)}>
                Send a patrol
              </PillButton>
            </div>
          </Receipt>
        </div>
      )}
    </>
  );
};

export default MapView;
