import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wsf.dart';

/// One line of a [SplitReveal]. Lines never wrap; they scale down to fit.
class RevealLine {
  const RevealLine(this.text, this.style);
  final String text;
  final TextStyle style;
}

/// Headline reveal: every character rises out from under its own line with a
/// short stagger and a long expo settle.
class SplitReveal extends StatefulWidget {
  const SplitReveal({
    super.key,
    required this.lines,
    this.play = true,
    this.delay = Duration.zero,
    this.stagger = const Duration(milliseconds: 22),
    this.charDuration = const Duration(milliseconds: 950),
    this.alignment = Alignment.centerLeft,
  });

  final List<RevealLine> lines;

  /// Flip to true to play, false to reset to hidden.
  final bool play;
  final Duration delay;
  final Duration stagger;
  final Duration charDuration;
  final Alignment alignment;

  @override
  State<SplitReveal> createState() => _SplitRevealState();
}

class _SplitRevealState extends State<SplitReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  int get _chars => widget.lines.fold(0, (n, l) => n + l.text.characters.length);
  int get _totalMs =>
      widget.delay.inMilliseconds + widget.stagger.inMilliseconds * _chars + widget.charDuration.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _c.duration = Duration(milliseconds: _totalMs);
    if (widget.play) _c.forward();
  }

  @override
  void didUpdateWidget(SplitReveal old) {
    super.didUpdateWidget(old);
    _c.duration = Duration(milliseconds: _totalMs);
    if (widget.play && !old.play) {
      _c.forward(from: 0);
    } else if (!widget.play && old.play) {
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalMs.toDouble();
    var index = 0;
    final cross = widget.alignment.x < 0
        ? CrossAxisAlignment.start
        : widget.alignment.x > 0
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: [
        for (final line in widget.lines)
          _Line(
            line: line,
            alignment: widget.alignment,
            children: [
              for (final ch in line.text.characters)
                () {
                  final start = (widget.delay.inMilliseconds + widget.stagger.inMilliseconds * index++) / total;
                  final end = (start + widget.charDuration.inMilliseconds / total).clamp(0.0, 1.0);
                  final curve = Interval(start, end, curve: Wsf.expoOut);
                  final size = line.style.fontSize ?? 16;
                  final rise = size * ((line.style.height ?? 1) + 0.4);
                  return AnimatedBuilder(
                    animation: _c,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(0, (1 - curve.transform(_c.value)) * rise),
                      child: child,
                    ),
                    child: Text(ch, style: line.style),
                  );
                }(),
            ],
          ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line, required this.children, required this.alignment});
  final RevealLine line;
  final List<Widget> children;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final size = line.style.fontSize ?? 16;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: ClipRect(
        clipper: _LineClipper(top: size * 0.25, bottom: size * 0.16, side: size * 0.2),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Clips to the line box, loosened so ascenders, descenders and italic
/// overhang are not shaved off by the tight display leading.
class _LineClipper extends CustomClipper<Rect> {
  const _LineClipper({required this.top, required this.bottom, required this.side});
  final double top, bottom, side;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-side, -top, size.width + side, size.height + bottom);

  @override
  bool shouldReclip(_LineClipper old) => old.top != top || old.bottom != bottom || old.side != side;
}

/// Fades and lifts a child into place after [delay]. For everything that is
/// not a headline.
class FadeSlide extends StatefulWidget {
  const FadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 700),
    this.offset = const Offset(0, 22),
    this.play = true,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final bool play;

  @override
  State<FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<FadeSlide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Wsf.expoOut);

  @override
  void initState() {
    super.initState();
    if (widget.play) _start();
  }

  void _start() {
    Future.delayed(widget.delay, () {
      if (mounted && widget.play) _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(FadeSlide old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) {
      _start();
    } else if (!widget.play && old.play) {
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, child) => Opacity(
          opacity: _a.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: widget.offset * (1 - _a.value), child: child),
        ),
        child: widget.child,
      );
}

/// Shrinks slightly while held, springs back on release.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: _down ? const Duration(milliseconds: 90) : const Duration(milliseconds: 420),
          curve: _down ? Curves.easeOut : Wsf.backOut,
          child: widget.child,
        ),
      );
}

/// Route that opens the next screen through a growing circle.
class CircleRevealRoute<T> extends PageRouteBuilder<T> {
  CircleRevealRoute({required Widget page, this.origin = const Alignment(0, 0.7)})
      : super(
          transitionDuration: const Duration(milliseconds: 850),
          reverseTransitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) {
            final a = CurvedAnimation(parent: anim, curve: Wsf.expoInOut, reverseCurve: Curves.easeIn);
            return AnimatedBuilder(
              animation: a,
              builder: (_, c) => ClipPath(clipper: CircleClipper(a.value, origin), child: c),
              child: child,
            );
          },
        );

  final Alignment origin;
}

class CircleClipper extends CustomClipper<Path> {
  const CircleClipper(this.t, this.origin);
  final double t;
  final Alignment origin;

  @override
  Path getClip(Size size) {
    final c = origin.alongSize(size);
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((p) => (p - c).distance).reduce((a, b) => a > b ? a : b);
    return Path()..addOval(Rect.fromCircle(center: c, radius: far * t));
  }

  @override
  bool shouldReclip(CircleClipper old) => old.t != t || old.origin != origin;
}
