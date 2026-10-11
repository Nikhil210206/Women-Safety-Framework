import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// WSF design tokens — "Night volt".
///
/// Ink base, volt lime as the single loud colour, bone for surfaces that need
/// to feel like paper, coral reserved for danger and amber for caution.
abstract final class Wsf {
  // ── Palette ────────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF0B0C0A);
  static const Color ink2 = Color(0xFF12140F);
  static const Color ink3 = Color(0xFF1A1D15);
  static const Color ink4 = Color(0xFF262A1E);
  static const Color line = Color(0xFF2E3324);

  static const Color bone = Color(0xFFF3F1E7);
  static const Color boneDim = Color(0xFFA3A694);
  static const Color boneFaint = Color(0xFF6B6E5F);

  static const Color volt = Color(0xFFD4FF3A);
  static const Color voltDeep = Color(0xFF1A2400);

  static const Color pine = Color(0xFF00503A);
  static const Color pineDeep = Color(0xFF003527);
  static const Color mint = Color(0xFF41D58C);

  static const Color coral = Color(0xFFFF5A3C);
  static const Color coralDeep = Color(0xFF2E0A03);
  static const Color amber = Color(0xFFFFB627);
  static const Color amberDeep = Color(0xFF2E1F00);

  // ── Motion ─────────────────────────────────────────────────────────────────
  /// The house easing: fast out of the gate, long settle.
  static const Curve expoOut = Cubic(0.16, 1, 0.3, 1);
  static const Curve expoInOut = Cubic(0.87, 0, 0.13, 1);
  static const Curve backOut = Cubic(0.34, 1.56, 0.64, 1);

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 420);
  static const Duration slow = Duration(milliseconds: 900);

  // ── Shape ──────────────────────────────────────────────────────────────────
  static const double rCard = 24;
  static const double rField = 18;
  static const double gutter = 24;

  // ── Type ───────────────────────────────────────────────────────────────────
  /// Heavy grotesk for headlines, numerals and the wordmark. Always lowercase
  /// in copy, tight tracking, tight leading.
  static TextStyle display(double size, {Color color = bone, double height = 0.92}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: height,
        letterSpacing: -0.045 * size,
        color: color,
      );

  /// Italic serif used for the accent half of a headline.
  static TextStyle serif(double size, {Color color = volt, double height = 0.98}) =>
      GoogleFonts.instrumentSerif(
        fontSize: size,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        height: height,
        letterSpacing: -0.02 * size,
        color: color,
      );

  static TextStyle body({
    double size = 16,
    Color color = boneDim,
    FontWeight weight = FontWeight.w400,
    double height = 1.4,
  }) =>
      GoogleFonts.geist(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: -0.011 * size,
        color: color,
      );

  /// Mono eyebrow / label. Callers pass already-uppercased strings.
  static TextStyle mono({
    double size = 11,
    Color color = boneDim,
    FontWeight weight = FontWeight.w500,
  }) =>
      GoogleFonts.geistMono(
        fontSize: size,
        fontWeight: weight,
        height: 1.2,
        letterSpacing: 0.08 * size,
        color: color,
      );

  /// Touches every font file once so [GoogleFonts.pendingFonts] can await them.
  static void warmFonts() {
    display(16);
    serif(16);
    body();
    body(weight: FontWeight.w500);
    body(weight: FontWeight.w600);
    mono();
  }

  // ── Theme ──────────────────────────────────────────────────────────────────
  static ThemeData theme() {
    OutlineInputBorder border(Color c, [double w = 2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(rField),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: volt,
        onPrimary: voltDeep,
        secondary: bone,
        onSecondary: ink,
        surface: ink,
        onSurface: bone,
        error: coral,
        onError: ink,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: volt,
        selectionColor: volt.withValues(alpha: 0.3),
        selectionHandleColor: volt,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: ink,
        foregroundColor: bone,
        titleTextStyle: body(size: 17, color: bone, weight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bone,
        contentTextStyle: body(size: 14, color: ink, weight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ink3,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rCard)),
        titleTextStyle: display(26),
        contentTextStyle: body(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: volt),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ink3,
        hintStyle: body(color: boneFaint),
        labelStyle: body(size: 14),
        errorStyle: mono(color: coral),
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        disabledBorder: border(Colors.transparent),
        focusedBorder: border(volt),
        errorBorder: border(coral),
        focusedErrorBorder: border(coral),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      ),
      textTheme: TextTheme(
        displayLarge: display(48),
        titleLarge: display(26),
        bodyLarge: body(color: bone),
        bodyMedium: body(size: 14),
        labelLarge: body(color: bone, weight: FontWeight.w600),
      ),
    );
  }
}
