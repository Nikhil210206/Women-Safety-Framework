import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 4×4 Bayer matrix, row-major. Thresholds are `(value + 0.5) / 16`.
const List<int> kBayer4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/// Quantises [v] (0..1) to 0..3 using the ordered-dither threshold at (x, y).
int ditherLevel(double v, int x, int y) {
  if (v <= 0) return 0;
  if (v > 1) v = 1;
  return (v * 3 + (kBayer4[((y & 3) << 2) | (x & 3)] + 0.5) / 16).floor();
}

/// Three reusable point buffers, one per dither tone. Dots are drawn with
/// [Canvas.drawRawPoints], which keeps thousands of dots at one draw call each.
class DotBuffers {
  Float32List _a = Float32List(0), _b = Float32List(0), _c = Float32List(0);
  int na = 0, nb = 0, nc = 0;

  void reset(int maxDots) {
    if (_a.length < maxDots * 2) {
      _a = Float32List(maxDots * 2);
      _b = Float32List(maxDots * 2);
      _c = Float32List(maxDots * 2);
    }
    na = nb = nc = 0;
  }

  void add(int level, double x, double y) {
    switch (level) {
      case 1:
        _a[na++] = x;
        _a[na++] = y;
      case 2:
        _b[nb++] = x;
        _b[nb++] = y;
      default:
        _c[nc++] = x;
        _c[nc++] = y;
    }
  }

  void draw(Canvas canvas, Color color, double cell, {double scale = 1}) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    void pass(Float32List buf, int n, double size, double alpha) {
      if (n == 0) return;
      paint
        ..strokeWidth = cell * size * scale
        ..color = color.withValues(alpha: color.a * alpha);
      canvas.drawRawPoints(ui.PointMode.points, Float32List.sublistView(buf, 0, n), paint);
    }

    pass(_a, na, 0.28, 0.38);
    pass(_b, nb, 0.44, 0.68);
    pass(_c, nc, 0.60, 1.0);
  }
}

/// A source of travelling rings in a [DitherField].
class DitherWave {
  const DitherWave({
    required this.origin,
    this.wavelength = 90,
    this.speed = 0.22,
    this.amplitude = 0.7,
    this.reach = 520,
  });

  /// Position in field space, each axis 0..1 (values outside are fine).
  final Offset origin;
  final double wavelength;
  final double speed;
  final double amplitude;
  final double reach;
}

/// Extra multiplier per dot, given its normalised position. Used to keep the
/// field out from under text.
typedef DitherMask = double Function(double nx, double ny);

abstract final class DitherMasks {
  /// Full strength at the top, gone by [end] of the height.
  static DitherMask fadeDown([double end = 0.75]) =>
      (nx, ny) => (1 - ny / end).clamp(0.0, 1.0);

  /// Full strength at the bottom, gone by [end] measured from the bottom.
  static DitherMask fadeUp([double end = 0.75]) =>
      (nx, ny) => (1 - (1 - ny) / end).clamp(0.0, 1.0);
}

/// Animated ordered-dither dot field: wave sources, a touch glow and tap
/// ripples, drawn as three tones of dot.
class DitherField extends StatefulWidget {
  const DitherField({
    super.key,
    required this.color,
    this.waves = const [DitherWave(origin: Offset(0.5, 0.2))],
    this.cell = 8,
    this.base = 0.04,
    this.intensity = 1,
    this.mask,
    this.interactive = true,
  });

  final Color color;
  final List<DitherWave> waves;
  final double cell;
  final double base;
  final double intensity;
  final DitherMask? mask;
  final bool interactive;

  @override
  State<DitherField> createState() => DitherFieldState();
}

class _Ripple {
  _Ripple(this.at, this.born);
  final Offset at;
  final double born;
}

class DitherFieldState extends State<DitherField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final DotBuffers _dots = DotBuffers();
  final List<_Ripple> _ripples = [];
  Offset _touchPos = Offset.zero;
  bool _touching = false;
  double _touchStrength = 0;
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      final dt = t - _lastT;
      _lastT = t;
      if (!_touching) _touchStrength = math.max(0, _touchStrength - dt * 1.6);
      _ripples.removeWhere((r) => t - r.born > 1.8);
      _time.value = t;
    })
      ..start();
  }

  /// Sends a ring outward from [local] (field coordinates).
  void ripple(Offset local) => _ripples.add(_Ripple(local, _lastT));

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(painter: _FieldPainter(this), size: Size.infinite),
    );
    if (!widget.interactive) return IgnorePointer(child: paint);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _touchPos = e.localPosition;
        _touching = true;
        _touchStrength = 1;
        ripple(e.localPosition);
      },
      onPointerMove: (e) => _touchPos = e.localPosition,
      onPointerUp: (_) => _touching = false,
      onPointerCancel: (_) => _touching = false,
      child: paint,
    );
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.s) : super(repaint: s._time);
  final DitherFieldState s;

  @override
  void paint(Canvas canvas, Size size) {
    final w = s.widget;
    final cell = w.cell;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    if (cols <= 0 || rows <= 0) return;
    s._dots.reset(cols * rows);

    final t = s._time.value;
    final waves = w.waves;
    final n = waves.length;
    final ox = List<double>.generate(n, (i) => waves[i].origin.dx * size.width);
    final oy = List<double>.generate(n, (i) => waves[i].origin.dy * size.height);
    final touchStrength = s._touchStrength;
    final lastTouch = s._touchPos;
    final mask = w.mask;
    const tau = math.pi * 2;

    for (var y = 0; y < rows; y++) {
      final cy = (y + 0.5) * cell;
      final ny = cy / size.height;
      for (var x = 0; x < cols; x++) {
        final cx = (x + 0.5) * cell;
        var v = w.base;

        for (var i = 0; i < n; i++) {
          final wave = waves[i];
          final dx = cx - ox[i], dy = cy - oy[i];
          final d = math.sqrt(dx * dx + dy * dy);
          final fall = 1 - d / wave.reach;
          if (fall <= 0) continue;
          v += wave.amplitude *
              fall *
              fall *
              (0.5 + 0.5 * math.sin(d / wave.wavelength * tau - t * wave.speed * tau));
        }

        for (final r in s._ripples) {
          final age = t - r.born;
          final dx = cx - r.at.dx, dy = cy - r.at.dy;
          final d = math.sqrt(dx * dx + dy * dy);
          final band = (d - age * 460) / 30;
          v += 0.95 * math.exp(-band * band) * (1 - age / 1.8);
        }

        if (touchStrength > 0) {
          final dx = cx - lastTouch.dx, dy = cy - lastTouch.dy;
          final g = 1 - math.sqrt(dx * dx + dy * dy) / 150;
          if (g > 0) v += touchStrength * g * g * 0.9;
        }

        if (mask != null) v *= mask(cx / size.width, ny);
        v *= w.intensity;

        final level = ditherLevel(v, x, y);
        if (level > 0) s._dots.add(level, cx, cy);
      }
    }
    s._dots.draw(canvas, w.color, cell);
  }

  @override
  bool shouldRepaint(_FieldPainter old) => true;
}
