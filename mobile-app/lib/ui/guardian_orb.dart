import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/wsf.dart';
import 'dither.dart';

/// What the guardian is feeling. Drives eye shape, colour and motion.
enum OrbMood {
  /// Eyes shut, slow breathing. Splash, before it wakes.
  asleep,

  /// Default. Blinks and looks around.
  calm,

  /// Wide-eyed and attentive: watching you type, watching a route.
  curious,

  /// Squinting, rings travelling outward. The audio sentinel is on.
  listening,

  /// Smiling eyes and a blush. Success moments.
  happy,

  /// Scrunched shut. Looks away while you type a code.
  shy,

  /// Amber and alert. Moderate-risk zone.
  caution,

  /// Coral, wide eyes, shaking. High-risk zone or SOS.
  alert,
}

enum _EyeStyle { capsule, smile, scrunch }

class _Eye {
  const _Eye(this.style, this.w, this.h);
  final _EyeStyle style;
  final double w, h; // in units of orb radius
}

const Map<OrbMood, _Eye> _eyes = {
  OrbMood.asleep: _Eye(_EyeStyle.capsule, 0.19, 0.035),
  OrbMood.calm: _Eye(_EyeStyle.capsule, 0.15, 0.30),
  OrbMood.curious: _Eye(_EyeStyle.capsule, 0.165, 0.36),
  OrbMood.listening: _Eye(_EyeStyle.capsule, 0.18, 0.12),
  OrbMood.happy: _Eye(_EyeStyle.smile, 0.20, 0.20),
  OrbMood.shy: _Eye(_EyeStyle.scrunch, 0.17, 0.17),
  OrbMood.caution: _Eye(_EyeStyle.capsule, 0.17, 0.38),
  OrbMood.alert: _Eye(_EyeStyle.capsule, 0.27, 0.29),
};

Color orbMoodColor(OrbMood mood) => switch (mood) {
      OrbMood.caution => Wsf.amber,
      OrbMood.alert => Wsf.coral,
      _ => Wsf.volt,
    };

/// The WSF guardian: an ink sphere lit by ordered-dither dots, with two eyes.
///
/// It blinks and glances around by itself, follows a finger dragged across it,
/// squishes when tapped, and changes expression with [mood].
class GuardianOrb extends StatefulWidget {
  const GuardianOrb({
    super.key,
    this.size = 200,
    this.mood = OrbMood.calm,
    this.color,
    this.bodyColor = Wsf.ink,
    this.eyeColor = Wsf.bone,
    this.appear = 1,
    this.look,
    this.glow = true,
    this.interactive = true,
    this.onTap,
  });

  final double size;
  final OrbMood mood;

  /// Dither colour. Defaults to the mood's colour.
  final Color? color;

  /// The sphere itself. Keep it dark so the eyes read on any page colour.
  final Color bodyColor;
  final Color eyeColor;

  /// 0 → nothing, 1 → fully assembled. Dots fill in from the centre outward.
  final double appear;

  /// Gaze override, each axis -1..1. Null lets the orb look around on its own.
  final Offset? look;
  final bool glow;
  final bool interactive;
  final VoidCallback? onTap;

  @override
  State<GuardianOrb> createState() => GuardianOrbState();
}

class GuardianOrbState extends State<GuardianOrb> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final DotBuffers _dots = DotBuffers();
  final math.Random _rng = math.Random();

  double _last = 0;

  // Blink
  double _nextBlink = 1.4;
  double _blinkStart = -10;

  // Gaze
  Offset _gaze = Offset.zero;
  Offset _wander = Offset.zero;
  double _nextWander = 1.0;
  Offset? _drag;

  // Mood blend
  late OrbMood _from = widget.mood;
  late OrbMood _to = widget.mood;
  double _blend = 1;
  late Color _colorFrom = _targetColor;
  late Color _colorTo = _targetColor;

  // Tap squish
  double _squishStart = -10;

  Color get _targetColor => widget.color ?? orbMoodColor(widget.mood);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(GuardianOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moodChanged = oldWidget.mood != widget.mood;
    if (moodChanged || oldWidget.color != widget.color) {
      _colorFrom = Color.lerp(_colorFrom, _colorTo, _blend)!;
      _colorTo = _targetColor;
      if (moodChanged) {
        _from = _blend > 0.5 ? _to : _from;
        _to = widget.mood;
      }
      _blend = 0;
    }
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = (t - _last).clamp(0.0, 0.05);
    _last = t;

    if (_blend < 1) _blend = math.min(1, _blend + dt / 0.36);

    if (t > _nextBlink) {
      _blinkStart = t;
      // Now and then, blink twice.
      _nextBlink = t + (_rng.nextDouble() < 0.18 ? 0.34 : 2.2 + _rng.nextDouble() * 3.2);
    }

    if (t > _nextWander) {
      _wander = _rng.nextDouble() < 0.4
          ? Offset.zero
          : Offset(_rng.nextDouble() * 1.5 - 0.75, _rng.nextDouble() * 0.9 - 0.45);
      _nextWander = t + 1.1 + _rng.nextDouble() * 2.2;
    }
    final target = _drag ?? widget.look ?? _wander;
    _gaze += (target - _gaze) * math.min(1, dt * 9);

    _time.value = t;
  }

  /// Squishes the orb as if it had been tapped. For callers that own the
  /// gesture themselves (the orb is drawn under another scrollable).
  void poke() {
    _squishStart = _last;
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  void _setDrag(Offset local) {
    final c = widget.size / 2;
    final v = Offset((local.dx - c) / c, (local.dy - c) / c);
    final len = v.distance;
    _drag = len > 1 ? v / len : v;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orb = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbPainter(this),
      ),
    );
    if (!widget.interactive) return IgnorePointer(child: orb);
    // A Listener (not a pan recogniser) tracks the finger, so the eyes follow a
    // drag without stealing it from a PageView or sheet underneath.
    return Listener(
      onPointerDown: (e) => _setDrag(e.localPosition),
      onPointerMove: (e) => _setDrag(e.localPosition),
      onPointerUp: (_) => _drag = null,
      onPointerCancel: (_) => _drag = null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: poke,
        child: orb,
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.s) : super(repaint: s._time);
  final GuardianOrbState s;

  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = s.widget;
    final t = s._time.value;
    final appear = w.appear.clamp(0.0, 1.0);
    if (appear <= 0) return;

    final c = size.center(Offset.zero);
    final radius = size.width * 0.5 * 0.84;
    final blend = Curves.easeInOut.transform(s._blend);
    final color = Color.lerp(s._colorFrom, s._colorTo, blend)!;

    double amount(OrbMood m) =>
        (s._from == m ? 1 - blend : 0) + (s._to == m ? blend : 0);
    final listening = amount(OrbMood.listening);
    final alert = amount(OrbMood.alert);
    final asleep = amount(OrbMood.asleep);
    final sweet = math.max(amount(OrbMood.happy), amount(OrbMood.shy));

    // Tap squish: a damped spring on the vertical axis.
    final sq = t - s._squishStart;
    final squish = sq < 1.2 ? 0.13 * math.exp(-5.5 * sq) * math.cos(17 * sq) : 0.0;
    final tapSmile = sq < 0.75;

    canvas.save();
    canvas.translate(c.dx + math.sin(t * 46) * radius * 0.016 * alert, c.dy);
    canvas.scale(1 + squish, 1 - squish);

    final breathe = 0.018 * math.sin(t * (1.5 - asleep * 0.7 + alert * 7.5));
    // Nearly a circle: the wobble is felt more than seen.
    double edge(double theta) =>
        1 + breathe + 0.008 * math.sin(3 * theta + t * 1.3) + 0.006 * math.sin(5 * theta - t * 1.1);

    if (w.glow) {
      final glowR = radius * 1.5;
      canvas.drawCircle(
        Offset.zero,
        glowR,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.20 * appear), color.withValues(alpha: 0)],
            stops: const [0.45, 1],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: glowR)),
      );
    }

    if (w.bodyColor.a > 0) {
      final body = Path();
      const steps = 72;
      for (var i = 0; i <= steps; i++) {
        final th = i / steps * math.pi * 2;
        final r = radius * edge(th) * (0.3 + 0.7 * Curves.easeOutCubic.transform(appear));
        final p = Offset(math.cos(th) * r, math.sin(th) * r);
        i == 0 ? body.moveTo(p.dx, p.dy) : body.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(body..close(), Paint()..color = w.bodyColor.withValues(alpha: w.bodyColor.a * appear));
    }

    // ── Eye geometry (needed before the dots, which clear a socket) ───────────
    final from = _eyes[s._from]!, to = _eyes[s._to]!;
    final sameStyle = from.style == to.style;
    final spec = sameStyle
        ? _Eye(to.style, lerpDouble(from.w, to.w, blend)!, lerpDouble(from.h, to.h, blend)!)
        : (blend < 0.5 ? from : to);
    // Changing eye shape hides the swap behind a blink.
    final swapOpen = sameStyle ? 1.0 : (2 * blend - 1).abs();

    final b = (t - s._blinkStart) / 0.16;
    final blink = (b >= 0 && b <= 1) ? math.sin(b * math.pi) : 0.0;
    final open = swapOpen * (1 - blink * (1 - asleep)) * _smooth(0.55, 1.0, appear);

    final gaze = s._gaze;
    final eyeShift = Offset(gaze.dx * 0.17, gaze.dy * 0.13);
    final eyeL = const Offset(-0.215, -0.07) + eyeShift;
    final eyeR = const Offset(0.215, -0.07) + eyeShift;
    // Dots clear out of an ellipse around each eye so the eyes always read.
    final (socketX, socketY, socketDy) = switch (spec.style) {
      _EyeStyle.capsule => (spec.w / 2 + 0.07, spec.h / 2 + 0.07, 0.0),
      _EyeStyle.smile => (0.17, 0.11, -0.02),
      _EyeStyle.scrunch => (0.15, 0.14, 0.0),
    };

    // ── Dots ─────────────────────────────────────────────────────────────────
    final cell = (size.width / 34).clamp(2.4, 10.0);
    final half = (radius * 1.08 / cell).ceil();
    s._dots.reset((half * 2 + 1) * (half * 2 + 1));

    // The light drifts a little so the shading never sits still.
    var lx = -0.52 + 0.14 * math.sin(t * 0.6) + gaze.dx * 0.10;
    var ly = -0.60 + 0.10 * math.cos(t * 0.5) + gaze.dy * 0.08;
    var lz = 0.62;
    final ln = math.sqrt(lx * lx + ly * ly + lz * lz);
    lx /= ln;
    ly /= ln;
    lz /= ln;
    final pulse = 1 - alert * 0.32 * (0.5 + 0.5 * math.sin(t * 10));

    for (var j = -half; j <= half; j++) {
      final py = (j + 0.5) * cell;
      final ny0 = py / radius;
      for (var i = -half; i <= half; i++) {
        final px = (i + 0.5) * cell;
        final nx0 = px / radius;
        final d = math.sqrt(nx0 * nx0 + ny0 * ny0);
        final e = edge(math.atan2(ny0, nx0));
        if (d > e) continue;

        if (appear < 1) {
          final hash = (((i * 73856093) ^ (j * 19349663)) & 0xFF) / 255;
          if (appear * 1.25 < d * 0.8 + hash * 0.4) continue;
        }

        final nx = nx0 / e, ny = ny0 / e;
        final nz = math.sqrt(math.max(0, 1 - nx * nx - ny * ny));
        var lum = 0.09 + 0.98 * math.max(0, nx * lx + ny * ly + nz * lz);
        // Rim light: keeps the far edge of the sphere drawn in.
        final rim = 1 - nz;
        lum += 0.42 * rim * rim * math.sqrt(rim);
        if (listening > 0) {
          lum += 0.42 * listening * math.max(0, math.sin(d * 17 - t * 7.5)) * (1 - d);
        }
        lum *= pulse;

        final ey = (ny0 - eyeL.dy - socketDy) / socketY;
        final exl = (nx0 - eyeL.dx) / socketX, exr = (nx0 - eyeR.dx) / socketX;
        final q = math.sqrt(math.min(exl * exl, exr * exr) + ey * ey);
        lum *= _smooth(1.0, 1.75, q);

        final level = ditherLevel(lum, i + half, j + half);
        if (level > 0) s._dots.add(level, px, py);
      }
    }
    s._dots.draw(canvas, color, cell);

    // ── Eyes ─────────────────────────────────────────────────────────────────
    final eyePaint = Paint()..color = w.eyeColor;
    final style = tapSmile && spec.style == _EyeStyle.capsule && asleep < 0.5 ? _EyeStyle.smile : spec.style;

    void drawEye(Offset at, double side) {
      final p = at * radius;
      switch (style) {
        case _EyeStyle.capsule:
          final ew = spec.w * radius;
          final eh = math.max(spec.h * radius * open, radius * 0.03);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: p, width: ew, height: eh),
              Radius.circular(ew / 2),
            ),
            eyePaint,
          );
        case _EyeStyle.smile:
          final r = radius * 0.115;
          final stroke = Paint()
            ..color = w.eyeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.075
            ..strokeCap = StrokeCap.round;
          canvas.save();
          canvas.translate(p.dx, p.dy + r * 0.5);
          canvas.scale(1, math.max(open, 0.12));
          canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: r), math.pi * 1.12, math.pi * 0.76, false, stroke);
          canvas.restore();
        case _EyeStyle.scrunch:
          final k = radius * 0.085;
          final stroke = Paint()
            ..color = w.eyeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.07
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          final o = math.max(open, 0.12);
          canvas.drawPath(
            Path()
              ..moveTo(p.dx - side * k, p.dy - k * o)
              ..lineTo(p.dx + side * k * 0.8, p.dy)
              ..lineTo(p.dx - side * k, p.dy + k * o),
            stroke,
          );
      }
    }

    if (open > 0.001 || asleep > 0) {
      drawEye(eyeL, 1);
      drawEye(eyeR, -1);
    }

    final blush = math.max(sweet, tapSmile ? 1.0 : 0.0) * appear;
    if (blush > 0.01) {
      final bp = Paint()..color = Wsf.coral.withValues(alpha: 0.55 * blush);
      canvas.drawCircle((eyeL + const Offset(-0.13, 0.22)) * radius, radius * 0.07, bp);
      canvas.drawCircle((eyeR + const Offset(0.13, 0.22)) * radius, radius * 0.07, bp);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
