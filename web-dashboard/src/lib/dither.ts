/** 4×4 Bayer matrix, row-major. Thresholds are `(value + 0.5) / 16`. */
export const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/** Dot diameter (in cells) and opacity for the three dither tones. */
export const DOT_SIZE = [0, 0.28, 0.44, 0.6];
export const DOT_ALPHA = [0, 0.38, 0.68, 1];

/** Quantises `v` (0..1) to 0..3 using the ordered-dither threshold at (x, y). */
export function ditherLevel(v: number, x: number, y: number): number {
  if (v <= 0) return 0;
  return Math.floor(Math.min(v, 1) * 3 + (BAYER4[((y & 3) << 2) | (x & 3)] + 0.5) / 16);
}
