"use client";

import React, { useEffect, useState } from "react";
import { Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { clockTime, countWord, pad2, timeAgo } from "@/lib/format";
import { WSF } from "@/lib/theme";
import type { Incident } from "../../types";
import { GuardianOrb } from "./GuardianOrb";
import { Chip, Receipt, Reveal, Tag, type TagTone } from "./kit";

/* The floating pieces of the command screen: top bar, people, count, the open
   incidents, the toast and the splash. */

export type PersonTone = "alert" | "danger" | "caution" | "clear";

export interface Person {
  id: string;
  name: string;
  phone?: string;
  /** Zone name if they are inside one, coordinates otherwise. */
  place: string;
  motion?: string;
  tone: PersonTone;
  /** Zone they are standing in, whatever else is going on. */
  zone: "danger" | "caution" | null;
  lat: number;
  lng: number;
}

/** An unresolved incident, with the text the screen shows for it. */
export interface AlertItem {
  incident: Incident;
  title: string;
  who: string;
  phone?: string;
  source?: string;
  /** High severity and not yet acknowledged. */
  urgent: boolean;
}

export interface Place {
  name: string;
  kind: "Person" | "Zone";
  lat: number;
  lng: number;
}

const delay = (ms: number) => ({ "--d": `${ms}ms` }) as React.CSSProperties;

const PERSON_TAG: Record<PersonTone, { tone: TagTone; label: string }> = {
  alert: { tone: "danger", label: "Alert" },
  danger: { tone: "danger-outline", label: "High risk" },
  caution: { tone: "caution", label: "Caution" },
  clear: { tone: "clear", label: "Clear" },
};

const STATUS_TAG: Record<string, { tone: TagTone; label: string }> = {
  open: { tone: "caution", label: "Open" },
  acknowledged: { tone: "line", label: "Acknowledged" },
  monitoring: { tone: "line", label: "Monitoring" },
  escalated: { tone: "danger-outline", label: "Escalated" },
};

export const statusLabel = (item: AlertItem) => (item.urgent ? "Alert" : (STATUS_TAG[item.incident.status] ?? STATUS_TAG.open).label);

// ── Top bar ────────────────────────────────────────────────────────────────

interface CommandBarProps {
  demo: boolean;
  places: Place[];
  onPick: (place: Place) => void;
  showZones: boolean;
  onToggleZones: () => void;
  showPatrols: boolean;
  onTogglePatrols: () => void;
}

export function CommandBar({ demo, places, onPick, showZones, onToggleZones, showPatrols, onTogglePatrols }: CommandBarProps) {
  const [query, setQuery] = useState("");
  const needle = query.trim().toLowerCase();
  const results = needle ? places.filter((p) => p.name.toLowerCase().includes(needle)).slice(0, 6) : [];

  const pick = (place: Place) => {
    onPick(place);
    setQuery("");
  };

  return (
    <header className="pointer-events-none absolute inset-x-7 top-6 z-30 flex items-start justify-between gap-4">
      <div className="wsf-in pointer-events-auto flex h-[52px] items-center gap-3">
        <span className="wsf-display text-[44px]">wsf</span>
        <Tag tone="line">Command</Tag>
      </div>

      <div className="pointer-events-auto absolute left-1/2 w-[420px] -translate-x-1/2">
        <div className="wsf-in" style={delay(80)}>
          <label className="wsf-search">
            <Search size={18} strokeWidth={2.2} aria-hidden />
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && results[0]) pick(results[0]);
                if (e.key === "Escape") setQuery("");
              }}
              placeholder="find a person or a place"
              aria-label="Find a person or a place"
            />
          </label>
          {needle && (
            <div className="wsf-receipt mt-2">
              {results.length === 0 ? (
                <p className="px-[18px] py-4 text-[15px] text-dim">nobody and nowhere by that name.</p>
              ) : (
                results.map((place) => (
                  <button key={`${place.kind}-${place.name}`} type="button" className="wsf-row" onClick={() => pick(place)}>
                    <span className="min-w-0 flex-1 truncate text-base font-medium tracking-[-0.011em]">{place.name}</span>
                    <Tag tone="line">{place.kind}</Tag>
                  </button>
                ))
              )}
            </div>
          )}
        </div>
      </div>

      <div className="wsf-in pointer-events-auto flex h-[52px] items-center gap-2" style={delay(160)}>
        {demo ? (
          <span title="Supabase could not be reached. These are sample people, zones and alerts.">
            <Tag tone="caution" className="mr-2">
              Demo data
            </Tag>
          </span>
        ) : (
          <Tag tone="clear" className="mr-2">
            Live
          </Tag>
        )}
        <Chip on={showZones} onToggle={onToggleZones}>
          zones
        </Chip>
        {/* Patrol routes only exist as sample data, so the chip is demo-only. */}
        {demo && (
          <Chip on={showPatrols} onToggle={onTogglePatrols}>
            patrols
          </Chip>
        )}
      </div>
    </header>
  );
}

// ── People ─────────────────────────────────────────────────────────────────

export function PeopleCard({ people, onPick }: { people: Person[]; onPick: (person: Person) => void }) {
  return (
    <Receipt
      className="wsf-in pointer-events-auto flex min-h-0 flex-col"
      style={delay(300)}
      strip={
        <>
          <span>People · {people.length} live</span>
          {people.length > 0 && <span>Click to fly there</span>}
        </>
      }
    >
      {people.length === 0 ? (
        <p className="px-[18px] py-5 text-[15px] leading-snug text-dim">nobody is sharing a location right now.</p>
      ) : (
        <div className="min-h-0 overflow-y-auto">
          {people.map((person) => (
            <button key={person.id} type="button" className="wsf-row" onClick={() => onPick(person)}>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-base font-medium tracking-[-0.011em] text-fg">{person.name}</span>
                <span className="mt-0.5 block truncate text-[13px] text-dim">
                  {person.place}
                  {person.motion && ` · ${person.motion}`}
                </span>
              </span>
              <Tag tone={PERSON_TAG[person.tone].tone}>{PERSON_TAG[person.tone].label}</Tag>
            </button>
          ))}
        </div>
      )}
    </Receipt>
  );
}

// ── Count ──────────────────────────────────────────────────────────────────

export function CountCard({ demo, now, count, inRiskZone }: { demo: boolean; now: Date | null; count: number; inRiskZone: number }) {
  const hour = now?.getHours() ?? 12;
  const night = hour >= 18 || hour < 6;
  const accent = inRiskZone > 0 ? `${countWord(inRiskZone)} in a risk zone.` : count > 0 ? "all in the clear." : "nobody yet.";

  return (
    <section className="wsf-in pointer-events-auto shrink-0 rounded-card bg-block px-6 pb-6 pt-5 text-on-block" style={delay(380)}>
      <div className="wsf-eyebrow text-on-block-dim">
        {demo ? "Sample" : "Live"}
        {now && ` · ${clockTime(now)}`}
      </div>
      <div className="wsf-display -ml-1 mt-4 text-[112px] leading-[0.8] text-accent">{pad2(count)}</div>
      <div className="wsf-display mt-3 text-[30px]">{night ? "out tonight." : "out right now."}</div>
      <div className="wsf-serif text-[32px] text-accent">{accent}</div>
    </section>
  );
}

// ── Open incidents ─────────────────────────────────────────────────────────

interface IncidentsCardProps {
  items: AlertItem[];
  /** The incident the dome is showing, if it is up. */
  activeId: string | null;
  now: Date | null;
  onOpen: (item: AlertItem) => void;
}

/** Everything unresolved, most pressing first. Clicking one brings the dome up for it. */
export function IncidentsCard({ items, activeId, now, onOpen }: IncidentsCardProps) {
  return (
    <Receipt
      className="wsf-in pointer-events-auto flex min-h-0 flex-col"
      style={delay(460)}
      strip={
        <>
          <span>Open · {items.length}</span>
          <span>Click to act</span>
        </>
      }
    >
      <div className="min-h-0 overflow-y-auto">
        {items.map((item) => {
          const tone: TagTone = item.urgent ? "danger" : (STATUS_TAG[item.incident.status] ?? STATUS_TAG.open).tone;
          const active = item.incident.id === activeId;
          return (
            <button
              key={item.incident.id}
              type="button"
              aria-current={active}
              onClick={() => onOpen(item)}
              className={cn("wsf-row", active && "is-selected")}
            >
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[15px] font-medium tracking-[-0.011em] text-fg">{item.title}</span>
                <span className="mt-0.5 block truncate text-[13px] text-dim">
                  {item.who}
                  {now && ` · ${timeAgo(item.incident.created_at, now.getTime())}`}
                </span>
              </span>
              <Tag tone={tone}>{statusLabel(item)}</Tag>
            </button>
          );
        })}
      </div>
    </Receipt>
  );
}

// ── Toast ──────────────────────────────────────────────────────────────────

const TOAST_MS = 6000;

export function Toast({ message, onDone }: { message: string; onDone: () => void }) {
  useEffect(() => {
    const id = setTimeout(onDone, TOAST_MS);
    return () => clearTimeout(id);
  }, [message, onDone]);

  return (
    <div className="pointer-events-none absolute left-1/2 top-[92px] z-[25] w-max max-w-[560px] -translate-x-1/2">
      <div role="status" className="wsf-in pointer-events-auto rounded-[26px] bg-inverse px-5 py-3 text-center text-[15px] font-medium leading-snug text-on-inverse">
        {message}
      </div>
    </div>
  );
}

// ── Splash ─────────────────────────────────────────────────────────────────

/** Shown while the dashboard works out whether it has a backend: the guardian
    sleeps, then wakes as the screen opens. */
export function Splash({ leaving }: { leaving: boolean }) {
  return (
    <div className={cn("wsf-splash", leaving && "is-leaving")} aria-hidden={leaving}>
      <div className="flex flex-col items-center text-center">
        <GuardianOrb size={132} mood={leaving ? "calm" : "asleep"} bodyColor={WSF.ground2} />
        <div className="wsf-display mt-6 text-[104px]">
          <Reveal text="wsf" delay={150} />
        </div>
        <div className="wsf-serif text-[44px] text-accent">
          <Reveal text="command." delay={300} />
        </div>
        <div className="wsf-in wsf-eyebrow mt-7 text-dim" style={delay(750)}>
          Checking the line
        </div>
      </div>
    </div>
  );
}
