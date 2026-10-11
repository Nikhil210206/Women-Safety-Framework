import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';

/// First-launch story. Five full-bleed colour blocks you scrub through by
/// hand; the guardian is one continuous object that travels, resizes and
/// changes mood with the scroll position.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _Tone {
  const _Tone({
    required this.bg,
    required this.fg,
    required this.dim,
    required this.accent,
    required this.dither,
  });
  final Color bg, fg, dim, accent, dither;

  static _Tone lerp(_Tone a, _Tone b, double t) => _Tone(
        bg: Color.lerp(a.bg, b.bg, t)!,
        fg: Color.lerp(a.fg, b.fg, t)!,
        dim: Color.lerp(a.dim, b.dim, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        dither: Color.lerp(a.dither, b.dither, t)!,
      );
}

class _Stop {
  const _Stop(this.align, this.size, this.mood);
  final Alignment align;

  /// Orb diameter as a fraction of screen width.
  final double size;
  final OrbMood mood;
}

class _Copy {
  const _Copy(this.eyebrow, this.lead, this.accent, this.body);
  final String eyebrow, lead, accent, body;
}

const _tones = [
  _Tone(bg: Wsf.ink, fg: Wsf.bone, dim: Wsf.boneDim, accent: Wsf.volt, dither: Wsf.volt),
  _Tone(bg: Wsf.volt, fg: Wsf.ink, dim: Color(0xFF465212), accent: Wsf.pine, dither: Color(0x99283600)),
  _Tone(bg: Wsf.bone, fg: Wsf.ink, dim: Color(0xFF5E6152), accent: Wsf.pine, dither: Color(0x55005840)),
  _Tone(bg: Wsf.pine, fg: Wsf.bone, dim: Color(0xFFA9C9BD), accent: Wsf.volt, dither: Color(0xAA41D58C)),
  _Tone(bg: Wsf.ink, fg: Wsf.bone, dim: Wsf.boneDim, accent: Wsf.volt, dither: Wsf.volt),
];

const _stops = [
  _Stop(Alignment(0, -0.40), 0.64, OrbMood.calm),
  _Stop(Alignment(0, -0.50), 0.42, OrbMood.listening),
  _Stop(Alignment(-0.66, -0.67), 0.25, OrbMood.curious),
  _Stop(Alignment(0.66, -0.67), 0.25, OrbMood.alert),
  _Stop(Alignment(0, -0.38), 0.40, OrbMood.happy),
];

/// Height of the closing arch as a fraction of the screen.
const double _archHeight = 0.62;

const _copy = [
  _Copy(
    '00 · hello',
    'walk home.',
    "we've got you.",
    'wsf is a guardian that rides along on every walk: listening, routing and ready to call for help.',
  ),
  _Copy(
    '01 · it listens',
    'ears on.',
    'always.',
    'an on-device model listens for screams, shouting and breaking glass. the audio never leaves your phone.',
  ),
  _Copy(
    '02 · it routes',
    'skip the',
    'sketchy bits.',
    'every route is scored against live risk zones, so the way home bends around trouble.',
  ),
  _Copy(
    '03 · it calls',
    'one tap.',
    'everyone knows.',
    'sos alerts the response desk with your live location and readies a text to your person. go quiet mid-walk and it checks on you.',
  ),
];

class _IntroScreenState extends State<IntroScreen> with TickerProviderStateMixin {
  final PageController _pc = PageController();
  final GlobalKey<GuardianOrbState> _orbKey = GlobalKey();
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat();

  int _current = 0;
  bool _poked = false;

  static const int _last = 4;

  double get _page => _pc.hasClients && _pc.position.haveDimensions ? (_pc.page ?? 0) : 0;

  @override
  void dispose() {
    _pc.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _next() {
    if (_current >= _last) return widget.onDone();
    _pc.nextPage(duration: const Duration(milliseconds: 900), curve: Wsf.expoInOut);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (_current == 1 || _current == 2) ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _pc,
          builder: (context, _) {
            final page = _page.clamp(0.0, _last.toDouble());
            final i = page.floor().clamp(0, _last - 1);
            final f = page - i;
            final tone = _Tone.lerp(_tones[i], _tones[i + 1], f);
            final a = _stops[i], b = _stops[i + 1];
            final ef = Curves.easeInOut.transform(f);
            final orbSize = size.width * ui.lerpDouble(a.size, b.size, ef)!;
            // On the last page the orb perches on the crown of the arch,
            // wherever that lands on this screen.
            final perchY = size.height * (1 - _archHeight) - size.width * _stops[_last].size * 0.38;
            final perch = Alignment(0, perchY / (size.height / 2) - 1);
            final orbAlign = Alignment.lerp(a.align, i + 1 == _last ? perch : b.align, ef)!;
            final orbRect = Rect.fromCenter(
              center: orbAlign.alongSize(size),
              width: orbSize,
              height: orbSize,
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: tone.bg),
                DitherField(
                  color: tone.dither,
                  interactive: false,
                  cell: 9,
                  base: 0.02,
                  intensity: 0.8,
                  waves: [
                    DitherWave(
                      origin: Offset((orbAlign.x + 1) / 2, (orbAlign.y + 1) / 2),
                      wavelength: 110,
                      speed: 0.25,
                      amplitude: 0.7,
                      reach: 560,
                    ),
                  ],
                  mask: DitherMasks.fadeDown(0.6),
                ),

                // Per-page art, parallaxed against the scroll.
                _art(
                  1,
                  page,
                  size,
                  _ListenArt(
                    loop: _loop,
                    color: tone.fg,
                    orbCenterY: _stops[1].align.alongSize(size).dy,
                    orbSize: size.width * _stops[1].size,
                  ),
                ),
                _art(2, page, size, _RouteArt(loop: _loop, active: _current == 2)),
                _art(3, page, size, _SosArt(loop: _loop, active: _current == 3)),
                _arch(page, size),

                Positioned.fromRect(
                  rect: orbRect,
                  child: GuardianOrb(
                    key: _orbKey,
                    size: orbSize,
                    mood: _stops[page.round()].mood,
                    interactive: false,
                    // A volt halo only belongs on the dark pages.
                    glow: page.round() != 1 && page.round() != 2,
                    look: switch (page.round()) {
                      2 => const Offset(0.8, 0.5),
                      3 => const Offset(-0.7, 0.6),
                      _ => null,
                    },
                  ),
                ),

                // Poke hint on the first page.
                Positioned(
                  left: 0,
                  right: 0,
                  top: orbRect.bottom + 6,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: Wsf.base,
                      opacity: (_poked || page > 0.15) ? 0 : 1,
                      child: Center(child: Eyebrow('psst. poke it', color: tone.dim)),
                    ),
                  ),
                ),

                // The pages own horizontal drags; taps that land on the orb
                // are forwarded to it.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) {
                    if ((d.localPosition - orbRect.center).distance < orbSize * 0.45) {
                      _orbKey.currentState?.poke();
                      if (!_poked) setState(() => _poked = true);
                    }
                  },
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _last + 1,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (p) {
                      HapticFeedback.selectionClick();
                      setState(() => _current = p);
                    },
                    itemBuilder: (_, p) => p == _last
                        ? const SizedBox.expand()
                        : _TextPage(
                            copy: _copy[p],
                            tone: _tones[p],
                            play: _current == p,
                            shift: (p - page) * 70,
                          ),
                  ),
                ),

                // Top bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Wsf.gutter, 10, 12, 0),
                      child: Row(
                        children: [
                          Wordmark(size: 24, color: tone.fg, dot: tone.accent),
                          const Spacer(),
                          AnimatedOpacity(
                            duration: Wsf.base,
                            opacity: _current == _last ? 0 : 1,
                            child: GhostButton(
                              label: 'skip',
                              color: tone.dim,
                              onTap: _current == _last ? null : widget.onDone,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom controls
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Wsf.gutter, 0, Wsf.gutter, 6),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        switchInCurve: Wsf.expoOut,
                        transitionBuilder: (c, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(anim),
                            child: c,
                          ),
                        ),
                        child: _current == _last
                            ? Column(
                                key: const ValueKey('cta'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PillButton(
                                    label: "let's go",
                                    bg: Wsf.ink,
                                    fg: Wsf.volt,
                                    onTap: widget.onDone,
                                  ),
                                  const SizedBox(height: 14),
                                  const Eyebrow('set-up takes about a minute', color: Color(0xFF465212)),
                                ],
                              )
                            : Row(
                                key: const ValueKey('rail'),
                                children: [
                                  Eyebrow('0${_current + 1}/05', color: tone.dim, size: 12),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: StepRail(
                                      total: _last + 1,
                                      current: _current,
                                      on: tone.fg,
                                      off: tone.fg.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  DiscButton(
                                    icon: Icons.arrow_forward_rounded,
                                    size: 62,
                                    bg: tone.fg,
                                    fg: tone.bg,
                                    border: null,
                                    onTap: _next,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Positions page [index]'s art in the top 58% and slides it faster than
  /// the text for a parallax split.
  Widget _art(int index, double page, Size size, Widget child) {
    final delta = index - page;
    if (delta.abs() >= 1) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: size.height * 0.58,
      child: IgnorePointer(
        child: Opacity(
          opacity: (1 - delta.abs() * 1.5).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(delta * size.width * 1.15, 0),
            child: Transform.scale(scale: 1 - delta.abs() * 0.12, child: child),
          ),
        ),
      ),
    );
  }

  /// The closing arch rises from the bottom as the last page arrives.
  Widget _arch(double page, Size size) {
    final t = (page - (_last - 1)).clamp(0.0, 1.0);
    if (t <= 0) return const SizedBox.shrink();
    final h = size.height * _archHeight;
    final e = Wsf.expoOut.transform(t);
    return Positioned(
      left: 0,
      right: 0,
      bottom: -h * (1 - e),
      height: h,
      child: IgnorePointer(
        child: ClipPath(
          clipper: const ArchClipper(rise: 0.42),
          child: ColoredBox(
            color: Wsf.volt,
            child: Padding(
              padding: EdgeInsets.fromLTRB(Wsf.gutter, size.width * 0.36, Wsf.gutter, 0),
              child: Column(
                children: [
                  Headline(
                    'ready when',
                    'you are.',
                    size: 58,
                    color: Wsf.ink,
                    accentColor: Wsf.pine,
                    alignment: Alignment.center,
                    play: _current == _last,
                    delay: const Duration(milliseconds: 250),
                  ),
                  const SizedBox(height: 22),
                  FadeSlide(
                    play: _current == _last,
                    delay: const Duration(milliseconds: 700),
                    child: const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        Tag('it listens', bg: Wsf.ink, outlined: true),
                        Tag('it routes', bg: Wsf.ink, outlined: true),
                        Tag('it calls', bg: Wsf.ink, outlined: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextPage extends StatelessWidget {
  const _TextPage({required this.copy, required this.tone, required this.play, required this.shift});
  final _Copy copy;
  final _Tone tone;
  final bool play;
  final double shift;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final headline = (w * 0.158).clamp(48.0, 72.0);
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Wsf.gutter, 0, Wsf.gutter, 104),
        child: Transform.translate(
          offset: Offset(shift, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeSlide(play: play, child: Eyebrow(copy.eyebrow, color: tone.dim, size: 12)),
              const SizedBox(height: 14),
              Headline(
                copy.lead,
                copy.accent,
                size: headline,
                color: tone.fg,
                accentColor: tone.accent,
                play: play,
                delay: const Duration(milliseconds: 80),
              ),
              const SizedBox(height: 18),
              FadeSlide(
                play: play,
                delay: const Duration(milliseconds: 380),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 330),
                  child: Text(copy.body, style: Wsf.body(size: 16.5, color: tone.dim, height: 1.42)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 01 · listening: level bars either side of the orb ────────────────────────

class _ListenArt extends StatelessWidget {
  const _ListenArt({required this.loop, required this.color, required this.orbCenterY, required this.orbSize});
  final Animation<double> loop;
  final Color color;
  final double orbCenterY;
  final double orbSize;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: orbCenterY - 75,
            height: 150,
            child: CustomPaint(painter: _BarsPainter(loop, color, orbSize)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: orbCenterY + orbSize / 2 + 14,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tag('scream · 92%', bg: Wsf.ink, fg: Wsf.volt, icon: Icons.graphic_eq_rounded),
                SizedBox(width: 8),
                Tag('on-device', bg: Wsf.ink, outlined: true),
              ],
            ),
          ),
        ],
      );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.loop, this.color, this.gap) : super(repaint: loop);
  final Animation<double> loop;
  final Color color;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final t = loop.value * math.pi * 2;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7;
    const n = 6;
    const pitch = 15.0;
    final mid = size.height / 2;
    for (var side = -1; side <= 1; side += 2) {
      for (var i = 0; i < n; i++) {
        final x = size.width / 2 + side * (gap / 2 + 4 + i * pitch);
        final fall = 1 - i / n;
        final h =
            8 + 62 * fall * (0.5 + 0.5 * math.sin(t * 3 + i * 0.9 + side)) * (0.6 + 0.4 * math.sin(t * 5 + i * 1.7));
        canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color || old.gap != gap;
}

// ── 02 · routing: a map card whose route bends around two zones ──────────────

class _RouteArt extends StatelessWidget {
  const _RouteArt({required this.loop, required this.active});
  final Animation<double> loop;
  final bool active;

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Wsf.gutter, 92, Wsf.gutter, 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Wsf.ink,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Wsf.ink, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(painter: _MiniMapPainter(loop)),
                ),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: FadeSlide(
                  play: active,
                  delay: const Duration(milliseconds: 500),
                  child: const Tag('safest · 12 min', icon: Icons.shield_rounded),
                ),
              ),
              Positioned(
                right: 14,
                top: 14,
                child: FadeSlide(
                  play: active,
                  delay: const Duration(milliseconds: 650),
                  child: const Tag('avoids 2 zones', bg: Wsf.coral, fg: Wsf.coralDeep),
                ),
              ),
            ],
          ),
        ),
      );
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter(this.loop) : super(repaint: loop);
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Streets
    final street = Paint()
      ..color = Wsf.ink4
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final fx in [0.2, 0.46, 0.74]) {
      canvas.drawLine(Offset(w * fx, -10), Offset(w * (fx + 0.08), h + 10), street);
    }
    for (final fy in [0.26, 0.56, 0.84]) {
      canvas.drawLine(Offset(-10, h * fy), Offset(w + 10, h * (fy - 0.07)), street);
    }

    // Zones: dithered coral, pulsing.
    final pulse = 0.5 + 0.5 * math.sin(loop.value * math.pi * 4);
    void zone(Offset c, double r) {
      const cell = 6.0;
      final dots = Paint()
        ..color = Wsf.coral
        ..strokeCap = StrokeCap.round;
      final n = (r / cell).ceil();
      for (var j = -n; j <= n; j++) {
        for (var i = -n; i <= n; i++) {
          final p = Offset((i + 0.5) * cell, (j + 0.5) * cell);
          final d = p.distance / r;
          if (d > 1) continue;
          final level = ditherLevel((1 - d) * (0.55 + 0.35 * pulse) + 0.12, i + n, j + n);
          if (level == 0) continue;
          dots.strokeWidth = cell * (0.22 + level * 0.14);
          canvas.drawPoints(ui.PointMode.points, [c + p], dots);
        }
      }
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Wsf.coral.withValues(alpha: 0.55 + 0.4 * pulse),
      );
    }

    zone(Offset(w * 0.36, h * 0.4), w * 0.15);
    zone(Offset(w * 0.68, h * 0.63), w * 0.12);

    // The safe route swerves past both.
    final start = Offset(w * 0.1, h * 0.86);
    final end = Offset(w * 0.9, h * 0.2);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(w * 0.12, h * 0.52, w * 0.2, h * 0.16, w * 0.5, h * 0.2)
      ..cubicTo(w * 0.62, h * 0.22, w * 0.5, h * 0.44, w * 0.56, h * 0.46)
      ..cubicTo(w * 0.72, h * 0.5, w * 0.92, h * 0.5, end.dx, end.dy);

    final metric = route.computeMetrics().first;
    final progress = Curves.easeInOut.transform((loop.value / 0.5).clamp(0.0, 1.0));
    final fade = loop.value > 0.9 ? 1 - (loop.value - 0.9) / 0.1 : 1.0;
    final drawn = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = Wsf.volt.withValues(alpha: 0.18 * fade),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Wsf.volt.withValues(alpha: fade),
    );

    canvas.drawCircle(start, 9, Paint()..color = Wsf.bone);
    canvas.drawCircle(start, 4, Paint()..color = Wsf.ink);
    final head = metric.getTangentForOffset(metric.length * progress)?.position ?? end;
    canvas.drawCircle(head, 7, Paint()..color = Wsf.volt.withValues(alpha: fade));
    canvas.drawCircle(
      end,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Wsf.volt,
    );
    canvas.drawCircle(end, 3.5, Paint()..color = Wsf.volt);
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) => false;
}

// ── 03 · SOS: a coral button sending rings to three contacts ─────────────────

class _SosArt extends StatelessWidget {
  const _SosArt({required this.loop, required this.active});
  final Animation<double> loop;
  final bool active;

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: const Alignment(0, 0.28),
              child: SizedBox.square(
                dimension: 300,
                child: CustomPaint(painter: _RingsPainter(loop)),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.28),
              child: Container(
                width: 124,
                height: 124,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Wsf.coral,
                  shape: BoxShape.circle,
                  border: Border.all(color: Wsf.ink, width: 3),
                ),
                child: Text('SOS', style: Wsf.display(42, color: Wsf.ink, height: 1)),
              ),
            ),
            _chip(const Alignment(-0.84, -0.14), 'mom', 420),
            _chip(const Alignment(0.86, 0.5), 'response desk', 560),
            _chip(const Alignment(-0.7, 0.88), 'live location', 700),
          ],
        ),
      );

  Widget _chip(Alignment at, String text, int delayMs) => Align(
        alignment: at,
        child: FadeSlide(
          play: active,
          delay: Duration(milliseconds: delayMs),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
            decoration: BoxDecoration(
              color: Wsf.bone,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Wsf.ink, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Wsf.volt, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 15, color: Wsf.ink),
                ),
                const SizedBox(width: 8),
                Text(text, style: Wsf.body(size: 14.5, color: Wsf.ink, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.loop) : super(repaint: loop);
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var k = 0; k < 3; k++) {
      final v = (loop.value * 2 + k / 3) % 1;
      canvas.drawCircle(
        c,
        62 + v * 88,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Wsf.coral.withValues(alpha: (1 - v) * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => false;
}
