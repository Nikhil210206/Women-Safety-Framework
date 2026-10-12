"use client";

import React, { useEffect, useRef } from "react";
import { DOT_ALPHA, DOT_SIZE, ditherLevel } from "@/lib/dither";
import { WSF } from "@/lib/theme";

/**
 * The WSF guardian: an ink sphere lit by ordered-dither dots, with two eyes.
 * A canvas port of mobile-app/lib/ui/guardian_orb.dart, trimmed to the moods a
 * command screen needs. It blinks and glances around by itself, follows the
 * pointer, squishes when clicked, and changes expression with `mood`.
 */
export type OrbMood = "asleep" | "calm" | "caution" | "alert";

const EYES: Record<OrbMood, { w: number; h: number }> = {
  asleep: { w: 0.19, h: 0.035 },
  calm: { w: 0.15, h: 0.3 },
  caution: { w: 0.17, h: 0.38 },
  alert: { w: 0.27, h: 0.29 },
};

const MOOD_COLOR: Record<OrbMood, string> = {
  asleep: WSF.accent,
  calm: WSF.accent,
  caution: WSF.caution,
  alert: WSF.danger,
};

const MOOD_LABEL: Record<OrbMood, string> = {
  asleep: "Guardian, waking up",
  calm: "Guardian, calm",
  caution: "Guardian, watchful",
  alert: "Guardian, alarmed",
};

type Rgb = [number, number, number];
const toRgb = (hex: string): Rgb => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)) as Rgb;
const mixRgb = (a: Rgb, b: Rgb, t: number): Rgb => [0, 1, 2].map((i) => a[i] + (b[i] - a[i]) * t) as Rgb;
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
const easeInOut = (t: number) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);

interface OrbState {
  from: OrbMood;
  to: OrbMood;
  blend: number;
  colorFrom: Rgb;
  colorTo: Rgb;
  last: number;
  nextBlink: number;
  blinkStart: number;
  gaze: { x: number; y: number };
  wander: { x: number; y: number };
  nextWander: number;
  pointer: { x: number; y: number; at: number } | null;
  squishStart: number;
}

// How long the eyes keep following the pointer after it stops moving.
const POINTER_HOLD_S = 2.5;

function paint(ctx: CanvasRenderingContext2D, size: number, t: number, s: OrbState, body: string, eye: string) {
  const radius = size * 0.5 * 0.84;
  const blend = easeInOut(s.blend);
  const [r, g, b] = mixRgb(s.colorFrom, s.colorTo, blend);
  const amount = (m: OrbMood) => (s.from === m ? 1 - blend : 0) + (s.to === m ? blend : 0);
  const alert = amount("alert");
  const asleep = amount("asleep");

  // Click squish: a damped spring on the vertical axis.
  const sq = t - s.squishStart;
  const squish = sq < 1.2 ? 0.13 * Math.exp(-5.5 * sq) * Math.cos(17 * sq) : 0;

  ctx.clearRect(0, 0, size, size);
  ctx.save();
  ctx.translate(size / 2 + Math.sin(t * 46) * radius * 0.016 * alert, size / 2);
  ctx.scale(1 + squish, 1 - squish);

  const breathe = 0.018 * Math.sin(t * (1.5 - asleep * 0.7 + alert * 7.5));
  // Nearly a circle: the wobble is felt more than seen.
  const edge = (theta: number) => 1 + breathe + 0.008 * Math.sin(3 * theta + t * 1.3) + 0.006 * Math.sin(5 * theta - t * 1.1);

  ctx.fillStyle = body;
  ctx.beginPath();
  for (let i = 0; i <= 72; i++) {
    const th = (i / 72) * Math.PI * 2;
    const rr = radius * edge(th);
    ctx.lineTo(Math.cos(th) * rr, Math.sin(th) * rr);
  }
  ctx.closePath();
  ctx.fill();

  // Eye geometry first: the dots clear a socket around each eye.
  const spec = { w: lerp(EYES[s.from].w, EYES[s.to].w, blend), h: lerp(EYES[s.from].h, EYES[s.to].h, blend) };
  const bl = (t - s.blinkStart) / 0.16;
  const blink = bl >= 0 && bl <= 1 ? Math.sin(bl * Math.PI) : 0;
  const open = 1 - blink * (1 - asleep);
  const eyeY = -0.07 + s.gaze.y * 0.13;
  const eyeLX = -0.215 + s.gaze.x * 0.17;
  const eyeRX = 0.215 + s.gaze.x * 0.17;
  const socketX = spec.w / 2 + 0.07;
  const socketY = spec.h / 2 + 0.07;

  // The light drifts a little so the shading never sits still.
  let lx = -0.52 + 0.14 * Math.sin(t * 0.6) + s.gaze.x * 0.1;
  let ly = -0.6 + 0.1 * Math.cos(t * 0.5) + s.gaze.y * 0.08;
  let lz = 0.62;
  const ln = Math.hypot(lx, ly, lz);
  lx /= ln;
  ly /= ln;
  lz /= ln;
  const pulse = 1 - alert * 0.32 * (0.5 + 0.5 * Math.sin(t * 10));

  const cell = Math.min(10, Math.max(2.6, size / 26));
  const half = Math.ceil((radius * 1.08) / cell);
  const dots: number[][] = [[], [], [], []];

  for (let j = -half; j <= half; j++) {
    const py = (j + 0.5) * cell;
    const ny0 = py / radius;
    for (let i = -half; i <= half; i++) {
      const px = (i + 0.5) * cell;
      const nx0 = px / radius;
      const d = Math.hypot(nx0, ny0);
      const e = edge(Math.atan2(ny0, nx0));
      if (d > e) continue;

      const nx = nx0 / e;
      const ny = ny0 / e;
      const nz = Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny));
      let lum = 0.09 + 0.98 * Math.max(0, nx * lx + ny * ly + nz * lz);
      // Rim light keeps the far edge of the sphere drawn in.
      const rim = 1 - nz;
      lum += 0.42 * rim * rim * Math.sqrt(rim);
      lum *= pulse;

      const ey = (ny0 - eyeY) / socketY;
      const exl = (nx0 - eyeLX) / socketX;
      const exr = (nx0 - eyeRX) / socketX;
      lum *= smooth(1.0, 1.75, Math.sqrt(Math.min(exl * exl, exr * exr) + ey * ey));

      const level = ditherLevel(lum, i + half, j + half);
      if (level > 0) dots[level].push(px, py);
    }
  }

  for (let level = 1; level <= 3; level++) {
    const list = dots[level];
    const dotR = (cell * DOT_SIZE[level]) / 2;
    ctx.fillStyle = `rgba(${r | 0}, ${g | 0}, ${b | 0}, ${DOT_ALPHA[level]})`;
    ctx.beginPath();
    for (let k = 0; k < list.length; k += 2) {
      ctx.moveTo(list[k] + dotR, list[k + 1]);
      ctx.arc(list[k], list[k + 1], dotR, 0, Math.PI * 2);
    }
    ctx.fill();
  }

  ctx.fillStyle = eye;
  for (const ex of [eyeLX, eyeRX]) {
    const ew = spec.w * radius;
    const eh = Math.max(spec.h * radius * open, radius * 0.03);
    ctx.beginPath();
    ctx.roundRect(ex * radius - ew / 2, eyeY * radius - eh / 2, ew, eh, Math.min(ew, eh) / 2);
    ctx.fill();
  }

  ctx.restore();
}

interface GuardianOrbProps {
  size?: number;
  mood?: OrbMood;
  /** The sphere itself. Keep it dark so the eyes read on any surface colour. */
  bodyColor?: string;
  eyeColor?: string;
  className?: string;
}

export function GuardianOrb({ size = 64, mood = "calm", bodyColor = WSF.ground, eyeColor = WSF.text, className }: GuardianOrbProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stateRef = useRef<OrbState | null>(null);
  if (!stateRef.current) {
    stateRef.current = {
      from: mood,
      to: mood,
      blend: 1,
      colorFrom: toRgb(MOOD_COLOR[mood]),
      colorTo: toRgb(MOOD_COLOR[mood]),
      last: 0,
      nextBlink: 1.4,
      blinkStart: -10,
      gaze: { x: 0, y: 0 },
      wander: { x: 0, y: 0 },
      nextWander: 1,
      pointer: null,
      squishStart: -10,
    };
  }

  const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    const s = stateRef.current!;

    const dpr = Math.min(3, window.devicePixelRatio || 1);
    canvas.width = Math.round(size * dpr);
    canvas.height = Math.round(size * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    // Reduced motion: one still frame, no loop.
    if (reducedMotion()) {
      paint(ctx, size, 0, s, bodyColor, eyeColor);
      return;
    }

    const onPointer = (e: PointerEvent) => {
      const box = canvas.getBoundingClientRect();
      const vx = (e.clientX - (box.left + box.width / 2)) / 260;
      const vy = (e.clientY - (box.top + box.height / 2)) / 260;
      const len = Math.hypot(vx, vy);
      s.pointer = { x: len > 1 ? vx / len : vx, y: len > 1 ? vy / len : vy, at: s.last };
    };
    window.addEventListener("pointermove", onPointer, { passive: true });

    // Resume from the last painted time so a re-run never rewinds the clock.
    const start = performance.now() - s.last * 1000;
    let frame = 0;
    const tick = (now: number) => {
      const t = (now - start) / 1000;
      const dt = Math.min(0.05, Math.max(0, t - s.last));
      s.last = t;

      if (s.blend < 1) s.blend = Math.min(1, s.blend + dt / 0.36);

      if (t > s.nextBlink) {
        s.blinkStart = t;
        // Now and then, blink twice.
        s.nextBlink = t + (Math.random() < 0.18 ? 0.34 : 2.2 + Math.random() * 3.2);
      }
      if (t > s.nextWander) {
        s.wander = Math.random() < 0.4 ? { x: 0, y: 0 } : { x: Math.random() * 1.5 - 0.75, y: Math.random() * 0.9 - 0.45 };
        s.nextWander = t + 1.1 + Math.random() * 2.2;
      }
      const target = s.pointer && t - s.pointer.at < POINTER_HOLD_S ? s.pointer : s.wander;
      const k = Math.min(1, dt * 9);
      s.gaze = { x: s.gaze.x + (target.x - s.gaze.x) * k, y: s.gaze.y + (target.y - s.gaze.y) * k };

      paint(ctx, size, t, s, bodyColor, eyeColor);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("pointermove", onPointer);
    };
  }, [size, bodyColor, eyeColor]);

  // Mood change: blend eyes and colour from wherever they are now.
  useEffect(() => {
    const s = stateRef.current!;
    if (s.to === mood) return;
    s.colorFrom = mixRgb(s.colorFrom, s.colorTo, easeInOut(s.blend));
    s.colorTo = toRgb(MOOD_COLOR[mood]);
    s.from = s.blend > 0.5 ? s.to : s.from;
    s.to = mood;
    s.blend = 0;

    if (reducedMotion()) {
      // No loop to blend it: snap, and repaint the still frame.
      s.from = mood;
      s.colorFrom = s.colorTo;
      s.blend = 1;
      const ctx = canvasRef.current?.getContext("2d");
      if (ctx) paint(ctx, size, 0, s, bodyColor, eyeColor);
    }
  }, [mood, size, bodyColor, eyeColor]);

  return (
    <canvas
      ref={canvasRef}
      role="img"
      aria-label={MOOD_LABEL[mood]}
      className={className}
      style={{ width: size, height: size }}
      onClick={() => {
        stateRef.current!.squishStart = stateRef.current!.last;
      }}
    />
  );
}
