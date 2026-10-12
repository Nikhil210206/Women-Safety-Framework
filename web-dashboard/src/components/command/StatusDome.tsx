"use client";

import React from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { GuardianOrb, type OrbMood } from "./GuardianOrb";
import { PillButton, Reveal } from "./kit";

/**
 * The arch at the bottom edge, with the guardian riding on it.
 *
 * At rest it is a low cap that says how things stand. It rises into the full
 * dome only when there is something to act on (a new alert, or an incident the
 * operator picked), shows that one thing with its actions, and settles back.
 */
export type DomeTone = "boot" | "calm" | "watch" | "alert";

/** What the cap says while the dome is down. */
export interface DomeStanding {
  tone: DomeTone;
  lead: string;
  note?: string;
}

/** What the raised dome shows. */
export type DomeSheet =
  | { kind: "calm"; lead: string; accent: string }
  | {
      kind: "incident";
      id: string;
      /** High severity and not yet acknowledged. */
      urgent: boolean;
      /** Still waiting for someone to acknowledge it. */
      open: boolean;
      eyebrow: string;
      headline: string;
      detail: string;
      /** Other unacknowledged alerts queued behind this one. */
      waiting: number;
    };

interface StatusDomeProps {
  standing: DomeStanding;
  /** Null while the dome is down. */
  sheet: DomeSheet | null;
  onRaise: () => void;
  onLower: () => void;
  onAcknowledge: (id: string) => void;
  onResolve: (id: string) => void;
  onShow: () => void;
  onNext: () => void;
}

const MOOD: Record<DomeTone, OrbMood> = {
  boot: "asleep",
  calm: "calm",
  watch: "caution",
  alert: "alert",
};

const delay = (ms: number) => ({ "--d": `${ms}ms` }) as React.CSSProperties;

export function StatusDome({ standing, sheet, onRaise, onLower, onAcknowledge, onResolve, onShow, onNext }: StatusDomeProps) {
  // Raised, the dome takes the colour of what it shows; at rest, of how things stand.
  const tone: DomeTone = !sheet ? standing.tone : sheet.kind === "calm" ? "calm" : sheet.urgent ? "alert" : "watch";

  return (
    <section
      className={cn("wsf-dome", sheet ? "is-raised" : "is-cap", `is-${tone}`, sheet?.kind === "calm" && "is-short")}
      aria-live={tone === "alert" ? "assertive" : "polite"}
    >
      <div className="wsf-dome__orb">
        <GuardianOrb size={64} mood={MOOD[tone]} />
      </div>

      {!sheet && (
        <button type="button" className="wsf-dome__cap" onClick={onRaise} aria-label={`${standing.lead} ${standing.note ?? ""} Open.`}>
          <span className="wsf-display text-[19px]">{standing.lead}</span>
          {standing.note && <span className="wsf-eyebrow">{standing.note}</span>}
        </button>
      )}

      {sheet && (
        <>
          <button type="button" className="wsf-dome__lower" onClick={onLower} aria-label="Hide" title="Hide (Esc)">
            <ChevronDown size={18} strokeWidth={2.4} aria-hidden />
          </button>

          {/* Remounts with its content, so the headline rises again instead of swapping in place */}
          <div key={sheet.kind === "incident" ? `${sheet.id}-${sheet.open}` : "calm"} className="wsf-dome__body">
            {sheet.kind === "calm" ? (
              <>
                <div className="wsf-display wsf-dome__lead">
                  <Reveal text={sheet.lead} delay={300} />
                </div>
                <div className="wsf-serif wsf-dome__accent">
                  <Reveal text={sheet.accent} delay={480} />
                </div>
              </>
            ) : (
              <>
                <div className="wsf-eyebrow">{sheet.eyebrow}</div>
                <h2 className="wsf-display wsf-display--plain wsf-dome__headline">
                  <Reveal text={sheet.headline} delay={300} />
                </h2>
                <p className="wsf-dome__detail">{sheet.detail}</p>
                <div className="wsf-in mt-4 flex justify-center gap-2.5" style={delay(620)}>
                  {sheet.open ? (
                    <PillButton onClick={() => onAcknowledge(sheet.id)}>Acknowledge</PillButton>
                  ) : (
                    <PillButton onClick={() => onResolve(sheet.id)}>Mark resolved</PillButton>
                  )}
                  <PillButton variant="ghost" onClick={onShow}>
                    Show on map
                  </PillButton>
                  {sheet.waiting > 0 && (
                    <PillButton variant="ghost" onClick={onNext}>
                      Next ({sheet.waiting})
                    </PillButton>
                  )}
                </div>
              </>
            )}
          </div>
        </>
      )}
    </section>
  );
}
