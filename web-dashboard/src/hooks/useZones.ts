import { useState, useEffect, useCallback } from 'react';
import { CRIME_ZONES, getZonesByTimeMode, TimeMode, CrimeZone } from '../data/crimeZones';
import { getSupabaseClient } from '../lib/supabaseClient';
import { DEMO_ZONES } from '../data/demo';

export interface Zone extends CrimeZone {
    isDefault?: boolean; // True for predefined zones, false/undefined for custom zones
}

export function useZones(timeMode: TimeMode = 'all', demo = false) {
    const [zones, setZones] = useState<Zone[]>([]);
    const [loading, setLoading] = useState(true);
    const supabase = getSupabaseClient();

    // Fetch zones function - can be called to refetch
    const fetchZones = useCallback(async () => {
        setLoading(true);

        // Demo mode: sample zones, and never touch Supabase
        if (demo) {
            setZones(DEMO_ZONES);
            setLoading(false);
            return;
        }

        if (!supabase) {
            console.warn("Supabase not connected - no zones available");
            setZones([]);
            setLoading(false);
            return;
        }

        // Fetch zones from Supabase ONLY
        const { data, error } = await supabase
            .from('zones' as any)
            .select('*');

        if (error) {
            console.error("Error fetching zones:", error);
            setZones([]);
            setLoading(false);
            return;
        }

        // Check for duplicates and gather valid names
        const uniqueNames = new Set();
        const duplicatesToDelete: any[] = [];
        const validZones: any[] = [];

        (data || []).forEach((z: any) => {
            if (uniqueNames.has(z.name)) {
                duplicatesToDelete.push(z.id);
            } else {
                uniqueNames.add(z.name);
                validZones.push(z);
            }
        });

        // Delete duplicates if found
        if (duplicatesToDelete.length > 0) {
            console.log(`🧹 Cleaning up ${duplicatesToDelete.length} duplicate zones...`);
            await supabase.from('zones' as any).delete().in('id', duplicatesToDelete);
        }

        // Check which default zones are missing from the VALID set
        const missingDefaults = CRIME_ZONES.filter(cz => !uniqueNames.has(cz.location));

        // If any default zones are missing, seed them
        if (missingDefaults.length > 0) {
            console.log(`📍 Found ${missingDefaults.length} missing default zones - seeding...`);
            await seedMissingZones(missingDefaults);

            // Refetch after seeding
            const { data: newData } = await supabase.from('zones' as any).select('*');
            if (newData) {
                setZones(mapSupabaseZonesToCrimeZones(newData));
            }
        } else {
            // Map Supabase zones to CrimeZone format
            setZones(mapSupabaseZonesToCrimeZones(data || []));
        }

        setLoading(false);
    }, [supabase, demo]);

    // Helper function to map Supabase data to CrimeZone format
    const mapSupabaseZonesToCrimeZones = (data: any[]): Zone[] => {
        return data.map((z: any) => {
            let lat = 12.9692;
            let lng = 79.1559;
            let radius = 200; // Default

            if (z.polygon_geojson?.geometry?.type === 'Point') {
                const coords = z.polygon_geojson.geometry.coordinates;
                if (coords && coords.length >= 2) {
                    lng = coords[0];
                    lat = coords[1];
                }
            } else if (z.polygon_geojson?.geometry?.type === 'Polygon') {
                const coords = z.polygon_geojson.geometry.coordinates[0];
                if (coords && coords.length > 0) {
                    // Calculate Centroid
                    lat = coords.reduce((sum: number, p: number[]) => sum + p[1], 0) / coords.length;
                    lng = coords.reduce((sum: number, p: number[]) => sum + p[0], 0) / coords.length;

                    // Calculate Radius from Center to First Point (Haversine approximation)
                    const p0 = coords[0];
                    if (p0) {
                        const R = 6371e3; // meters
                        const φ1 = lat * Math.PI / 180;
                        const φ2 = p0[1] * Math.PI / 180;
                        const Δφ = (p0[1] - lat) * Math.PI / 180;
                        const Δλ = (p0[0] - lng) * Math.PI / 180;

                        const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
                            Math.cos(φ1) * Math.cos(φ2) *
                            Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
                        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                        radius = Math.round(R * c);
                    }
                }
            }

            // Determine if zone is default based on name matching
            const isDefault = CRIME_ZONES.some(cz => cz.location === z.name);

            return {
                id: z.id,
                location: z.name || "Custom Zone",
                lat,
                lng,
                severity: (z.risk_level === 'red' ? 'HIGH' : z.risk_level === 'yellow' ? 'MODERATE' : 'LOW') as 'HIGH' | 'MODERATE' | 'LOW',
                type: z.description?.split('.')[0] || 'Custom',
                description: z.description || "Added by Authority",
                radius, // Use calculated radius
                active_hours: z.active_hours,
                isDefault
            };
        });
    };

    // Function to seed MISSING default zones
    const seedMissingZones = async (zonesToSeed: typeof CRIME_ZONES) => {
        if (!supabase) return;

        console.log(`🌱 Seeding ${zonesToSeed.length} missing default zones...`);

        for (const zone of zonesToSeed) {
            const zoneData = {
                name: zone.location,
                risk_level: zone.severity === 'HIGH' ? 'red' : zone.severity === 'MODERATE' ? 'yellow' : 'green',
                description: zone.description,
                polygon_geojson: {
                    type: 'Feature',
                    geometry: {
                        type: 'Point',
                        coordinates: [zone.lng, zone.lat]
                    }
                },
                active_hours: zone.active_hours || null
            };

            // @ts-ignore
            const { error } = await supabase.from('zones' as any).insert(zoneData);
            if (error) {
                console.error(`❌ Error seeding zone "${zone.location}":`, error);
            } else {
                console.log(`✅ Seeded: ${zone.location}`);
            }
        }
    };

    // Fetch on mount and timeMode change
    useEffect(() => {
        fetchZones();
    }, [fetchZones]);

    // Function to add a new zone
    const addZone = async (newZone: Omit<Zone, 'id'>) => {
        if (!supabase) {
            console.error("Supabase not connected");
            return;
        }

        // Create circular polygon GeoJSON
        const radius = newZone.radius || 200;
        const points = 32;
        const coords: number[][] = [];
        for (let i = 0; i < points; i++) {
            const angle = (i / points) * 2 * Math.PI;
            const dx = (radius / 1000) * Math.cos(angle);
            const dy = (radius / 1000) * Math.sin(angle);
            const deltaLat = dy / 111.32;
            const deltaLng = dx / (111.32 * Math.cos(newZone.lat * Math.PI / 180));
            coords.push([newZone.lng + deltaLng, newZone.lat + deltaLat]);
        }
        coords.push(coords[0]); // Close the polygon

        console.log('Adding zone to Supabase:', newZone.location);

        // @ts-ignore
        const { data, error } = await supabase.from('zones' as any).insert({
            name: newZone.location,
            risk_level: newZone.severity === 'HIGH' ? 'red' : 'yellow',
            description: newZone.description || 'Added via Dashboard',
            polygon_geojson: {
                type: 'Feature',
                geometry: {
                    type: 'Polygon',
                    coordinates: [coords]
                }
            },
            active_hours: newZone.active_hours || null
        }).select();

        if (error) {
            console.error("❌ Failed to save zone:", error);
            alert(`Failed to save zone: ${error.message}`);
        } else {
            console.log("✅ Zone saved:", data);
            // Refetch zones to get updated list
            await fetchZones();
        }
    };

    // Function to delete a zone
    const deleteZone = async (zoneId: string | number) => {
        if (!supabase) {
            console.error("Supabase not connected");
            return;
        }

        // Check if it's a static zone (number IDs from crimeZones.ts)
        if (typeof zoneId === 'number' && zoneId < 1000) {
            alert("Cannot delete predefined zones from the crime audit data.");
            return;
        }

        console.log('Deleting zone:', zoneId);

        const { error } = await supabase
            .from('zones' as any)
            .delete()
            .eq('id', zoneId);

        if (error) {
            console.error("❌ Failed to delete zone:", error);
            alert(`Failed to delete zone: ${error.message}`);
        } else {
            console.log("✅ Zone deleted successfully");

            // Immediately update local state to remove the zone
            setZones(prevZones => prevZones.filter(z => z.id !== zoneId));

            // Also refetch to ensure sync with database
            await fetchZones();
        }
    };

    return { zones, loading, addZone, deleteZone, refetch: fetchZones };
}
