/**
 * WSF command palette. The same roles as the app's Night volt, on a pine-black
 * ground. These hex values mirror the CSS variables in app/globals.css; they
 * live here too because Mapbox paint cannot read CSS variables.
 */
export const WSF = {
  ground: "#06110d",
  ground2: "#0b1a14",
  ground3: "#11261d",
  line: "#21402f",
  text: "#f3f1e7",
  textDim: "#9fb5a8",
  accent: "#d4ff3a",
  onAccent: "#1a2400",
  danger: "#ff5a3c",
  onDanger: "#2e0a03",
  caution: "#ffb627",
  onCaution: "#2e1f00",
  positive: "#41d58c",
} as const;

/** Recolours a stock Mapbox style so the map sits on the same ground as the UI. */
export interface MapTint {
  land: string;
  park: string;
  water: string;
  building: string;
  roadMinor: string;
  roadMid: string;
  roadMajor: string;
  rail: string;
  label: string;
  boundary: string;
}

export const PINE_TINT: MapTint = {
  land: WSF.ground,
  park: "#081812",
  water: "#081a18",
  building: "#0a1d15",
  roadMinor: "#0f241a",
  roadMid: "#153224",
  roadMajor: "#1d4331",
  rail: "#2a5440",
  label: "#6a8f7d",
  boundary: WSF.line,
};
