import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';

/// Startup sequence. The guardian assembles out of dither dots asleep, wakes,
/// looks around, the wordmark rises, then a volt ring sweeps outward and opens
/// onto the app underneath.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onReady, required this.onDone});

  /// Called once the splash is fully opaque and about to hold for a beat —
  /// the moment to mount the real app beneath it.
  final VoidCallback onReady;

  /// Called when the exit wipe has finished and the splash can be removed.
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _appear =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _exit =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1050));

  OrbMood _mood = OrbMood.asleep;
  Offset? _look = Offset.zero;
  bool _type = false;
  bool _awake = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  Future<void> _run() async {
    // Fonts download on first launch. The orb needs none, so it performs
    // while they arrive; the wordmark waits for them (up to a limit).
    Wsf.warmFonts();
    final fonts = GoogleFonts.pendingFonts().timeout(const Duration(seconds: 3), onTimeout: () => const []);

    _appear.forward();
    await _wait(1150);
    if (!mounted) return;
    setState(() => _mood = OrbMood.calm);
    await _wait(520);
    if (!mounted) return;
    setState(() => _look = const Offset(-0.9, 0.05));
    await _wait(380);
    if (!mounted) return;
    setState(() => _look = const Offset(0.9, 0.05));
    await _wait(380);
    if (!mounted) return;
    setState(() => _look = const Offset(0, 0.25));

    await fonts.catchError((_) => const <void>[]);
    if (!mounted) return;
    setState(() {
      _type = true;
      _awake = true;
    });
    widget.onReady();

    await _wait(1250);
    if (!mounted) return;
    setState(() {
      _mood = OrbMood.happy;
      _look = null;
    });
    await _wait(620);
    if (!mounted) return;
    await _exit.forward();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _appear.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final orbSize = (size.width * 0.58).clamp(180.0, 280.0);
    const orbCenter = Alignment(0, -0.26);

    final content = Material(
      color: Wsf.ink,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _appear,
            builder: (_, __) => DitherField(
              color: Wsf.volt,
              interactive: false,
              cell: 9,
              base: 0,
              intensity: 0.95 * Curves.easeOut.transform(_appear.value),
              waves: const [
                DitherWave(origin: Offset(0.5, 0.37), wavelength: 120, speed: 0.28, amplitude: 0.75, reach: 620),
              ],
              // Keep the dots off the orb and off the type.
              mask: (nx, ny) {
                final dx = (nx - 0.5) * size.width, dy = (ny - 0.37) * size.height;
                final d = (dx * dx + dy * dy) / (orbSize * orbSize);
                final hole = (d - 0.42).clamp(0.0, 1.0);
                return hole * (1 - ((ny - 0.5) / 0.3).clamp(0.0, 1.0));
              },
            ),
          ),
          Align(
            alignment: orbCenter,
            child: AnimatedBuilder(
              animation: _appear,
              builder: (_, __) => GuardianOrb(
                size: orbSize,
                mood: _mood,
                look: _look,
                appear: Curves.easeOutCubic.transform(_appear.value),
                interactive: false,
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.42),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SplitReveal(
                      play: _type,
                      stagger: const Duration(milliseconds: 70),
                      lines: [RevealLine('wsf', Wsf.display(132, height: 0.86))],
                    ),
                    AnimatedScale(
                      scale: _type ? 1 : 0,
                      duration: const Duration(milliseconds: 700),
                      curve: const Interval(0.45, 1, curve: Wsf.backOut),
                      child: Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(left: 6, bottom: 18),
                        decoration: const BoxDecoration(color: Wsf.volt, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SplitReveal(
                  play: _type,
                  alignment: Alignment.center,
                  delay: const Duration(milliseconds: 260),
                  stagger: const Duration(milliseconds: 14),
                  lines: [RevealLine('your walk-home guardian', Wsf.serif(27))],
                ),
              ],
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.9),
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: Wsf.base,
                child: Eyebrow(
                  _awake ? 'women safety framework' : 'waking up',
                  key: ValueKey(_awake),
                  color: Wsf.boneFaint,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: _exit,
      builder: (_, child) {
        if (_exit.value == 0) return child!;
        final v = _exit.value;
        final outer = Wsf.expoInOut.transform((v / 0.72).clamp(0.0, 1.0));
        final inner = Wsf.expoInOut.transform(((v - 0.28) / 0.72).clamp(0.0, 1.0));
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(clipper: _HoleClipper(inner, orbCenter), child: child),
            IgnorePointer(
              child: CustomPaint(painter: _RingPainter(inner: inner, outer: outer, origin: orbCenter)),
            ),
          ],
        );
      },
      child: content,
    );
  }
}

double _farCorner(Size size, Offset c) => [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((p) => (p - c).distance).reduce((a, b) => a > b ? a : b);

/// Everything except a growing circle — the splash with a hole punched in it.
class _HoleClipper extends CustomClipper<Path> {
  const _HoleClipper(this.t, this.origin);
  final double t;
  final Alignment origin;

  @override
  Path getClip(Size size) {
    final c = origin.alongSize(size);
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: c, radius: _farCorner(size, c) * t));
  }

  @override
  bool shouldReclip(_HoleClipper old) => old.t != t;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.inner, required this.outer, required this.origin});
  final double inner, outer;
  final Alignment origin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = origin.alongSize(size);
    final far = _farCorner(size, c);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: far * outer))
        ..addOval(Rect.fromCircle(center: c, radius: far * inner)),
      Paint()..color = Wsf.volt,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.inner != inner || old.outer != outer;
}
