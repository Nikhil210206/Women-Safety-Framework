"use client";

import React, { useState } from "react";
import { ArrowRight } from "lucide-react";
import { cn } from "@/lib/utils";

/* Shared primitives of the WSF command screen: tag, pill button, chip, receipt
   card and the per-character headline reveal. Styles live in app/globals.css. */

const TAG_TONE = {
  danger: "wsf-tag--danger",
  "danger-outline": "wsf-tag--danger-outline",
  caution: "wsf-tag--caution",
  clear: "wsf-tag--clear",
  line: "wsf-tag--line",
} as const;

export type TagTone = keyof typeof TAG_TONE;

export function Tag({ tone = "line", className, children }: { tone?: TagTone; className?: string; children: React.ReactNode }) {
  return <span className={cn("wsf-tag", TAG_TONE[tone], className)}>{children}</span>;
}

interface PillButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "ghost";
}

export function PillButton({ variant = "primary", className, onClick, children, ...rest }: PillButtonProps) {
  // Counts presses so the roll animation can be replayed by remounting.
  const [fired, setFired] = useState(0);
  return (
    <button
      type="button"
      {...rest}
      className={cn("wsf-pill", variant === "ghost" && "wsf-pill--ghost", fired > 0 && "is-fired", className)}
      onClick={(e) => {
        setFired((n) => n + 1);
        onClick?.(e);
      }}
    >
      <span className="wsf-pill__label" key={fired}>
        <span>{children}</span>
        <span aria-hidden>{children}</span>
      </span>
      {variant === "primary" && (
        <span className="wsf-pill__disc" aria-hidden>
          <ArrowRight key={fired} size={17} strokeWidth={2.2} />
        </span>
      )}
    </button>
  );
}

export function Chip({ on, onToggle, children }: { on: boolean; onToggle: () => void; children: React.ReactNode }) {
  return (
    <button type="button" aria-pressed={on} onClick={onToggle} className={cn("wsf-chip", on && "is-on")}>
      {children}
    </button>
  );
}

/** A card with a 2px rule and a mono header strip. `strip` is the strip's content. */
export function Receipt({
  strip,
  className,
  style,
  children,
}: {
  strip: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
  children: React.ReactNode;
}) {
  return (
    <section className={cn("wsf-receipt", className)} style={style}>
      <header className="wsf-receipt__strip wsf-eyebrow">{strip}</header>
      {children}
    </section>
  );
}

const CHAR_STAGGER_MS = 22;

/** Headline text whose characters rise from under their own line, 22ms apart. */
export function Reveal({ text, delay = 0 }: { text: string; delay?: number }) {
  let index = 0;
  return (
    <>
      <span className="sr-only">{text}</span>
      <span aria-hidden>
        {text.split(" ").map((word, w) => (
          <React.Fragment key={w}>
            {w > 0 && " "}
            <span className="wsf-reveal__word">
              {Array.from(word).map((char, c) => (
                <span key={c} className="wsf-reveal__char" style={{ animationDelay: `${delay + index++ * CHAR_STAGGER_MS}ms` }}>
                  {char}
                </span>
              ))}
            </span>
          </React.Fragment>
        ))}
      </span>
    </>
  );
}
