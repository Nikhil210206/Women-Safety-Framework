"use client";

import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getSupabaseClient } from "../lib/supabaseClient";

export type BackendMode = "checking" | "live" | "demo";

const PROBE_TIMEOUT_MS = 6000;

// supabase-js reports a failed request (DNS, offline, CORS) as an error with no
// Postgres code. Anything with a code means the server answered.
const isUnreachable = (error: { message?: string; code?: string }) =>
  !error.code && /fetch|network|load failed/i.test(error.message ?? "");

/**
 * Decides once, on mount, whether the dashboard runs on Supabase or on demo
 * data. `supabase` is only handed out in live mode, so demo mode never opens
 * requests or sockets against a host that is not there.
 */
export function useBackend(): { supabase: SupabaseClient | null; mode: BackendMode } {
  const [client] = useState<SupabaseClient | null>(() => getSupabaseClient());
  const [mode, setMode] = useState<BackendMode>(client ? "checking" : "demo");

  useEffect(() => {
    if (!client) return;
    let settled = false;
    const settle = (next: BackendMode) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      setMode(next);
    };
    const timer = setTimeout(() => settle("demo"), PROBE_TIMEOUT_MS);

    client
      .from("live_locations")
      .select("user_id")
      .limit(1)
      .then(
        ({ error }) => settle(error && isUnreachable(error) ? "demo" : "live"),
        () => settle("demo")
      );

    return () => {
      settled = true;
      clearTimeout(timer);
    };
  }, [client]);

  return { supabase: mode === "live" ? client : null, mode };
}
