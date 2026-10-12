export interface CircleZone {
  lat: number;
  lng: number;
  radius?: number;
}

const DEFAULT_RADIUS_M = 200;

/** Great-circle distance in metres. */
export function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function isPointInZone(lat: number, lng: number, zone: CircleZone): boolean {
  return distanceMeters(lat, lng, zone.lat, zone.lng) <= (zone.radius || DEFAULT_RADIUS_M);
}

/** A closed ring of [lng, lat] pairs approximating a circle of `radiusM` metres. */
export function circleRing(lat: number, lng: number, radiusM: number, points = 64): number[][] {
  const radiusKm = radiusM / 1000;
  const ring: number[][] = [];
  for (let i = 0; i < points; i++) {
    const angle = (i / points) * 2 * Math.PI;
    const deltaLat = (radiusKm * Math.sin(angle)) / 111.32;
    const deltaLng = (radiusKm * Math.cos(angle)) / (111.32 * Math.cos((lat * Math.PI) / 180));
    ring.push([lng + deltaLng, lat + deltaLat]);
  }
  ring.push(ring[0]);
  return ring;
}
