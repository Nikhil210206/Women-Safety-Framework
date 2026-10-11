import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';

// Emergency surfaces. The playful voice stops here: copy is short, literal
// and sentence-case, type is as large as the screen allows, and every screen
// has one obvious way out.

/// Full-bleed countdown stage shared by the three alerts: a colour block, a
/// dither field that rings once a second, and a giant number.
class _AlertStage extends StatelessWidget {
  const _AlertStage({
    required this.fieldKey,
    required this.bg,
    required this.dots,
    required this.children,
  });

  final GlobalKey<DitherFieldState> fieldKey;
  final Color bg;
  final Color dots;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: bg.computeLuminance() > 0.4 ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        child: Material(
          color: bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DitherField(
                key: fieldKey,
                color: dots,
                interactive: false,
                cell: 10,
                base: 0.05,
                waves: const [
                  DitherWave(origin: Offset(0.5, 0.44), wavelength: 120, speed: 0.5, amplitude: 0.55, reach: 700),
                ],
                // Legibility first: the dots thin out toward the centre
                // column, where the copy and the countdown sit.
                mask: (nx, ny) {
                  final edge = ((nx - 0.5).abs() * 2.6 - 0.25).clamp(0.0, 1.0);
                  return edge * edge;
                },
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Wsf.gutter, 16, Wsf.gutter, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The countdown numeral. Punches in on every change.
class _BigCount extends StatelessWidget {
  const _BigCount(this.value, {required this.color});
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 240,
        child: FittedBox(
          fit: BoxFit.contain,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(value),
            tween: Tween(begin: 1.28, end: 1),
            duration: const Duration(milliseconds: 620),
            curve: Wsf.expoOut,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Text('$value', style: Wsf.display(280, color: color, height: 0.9)),
          ),
        ),
      );
}

void _ring(GlobalKey<DitherFieldState> key, BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  key.currentState?.ripple(Offset(size.width / 2, size.height * 0.44));
}

// ── SOS countdown ────────────────────────────────────────────────────────────

/// Ten seconds to cancel before the SOS goes out. Pops `true` to send,
/// `false` if cancelled.
class SosCountdownDialog extends StatefulWidget {
  final String? triggerReason;
  const SosCountdownDialog({super.key, this.triggerReason});

  static void dismissIfActive() {
    _SosCountdownDialogState.activeInstance?._dismissForOverride();
  }

  @override
  State<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<SosCountdownDialog> {
  static _SosCountdownDialogState? activeInstance;
  final _field = GlobalKey<DitherFieldState>();
  int _countdown = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    activeInstance = this;
    HapticFeedback.heavyImpact();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      HapticFeedback.mediumImpact();
      _ring(_field, context);
      setState(() {
        if (_countdown > 1) {
          _countdown--;
        } else {
          _timer?.cancel();
          Navigator.of(context).pop(true);
        }
      });
    });
  }

  @override
  void dispose() {
    if (activeInstance == this) {
      activeInstance = null;
    }
    _timer?.cancel();
    super.dispose();
  }

  void _dismissForOverride() {
    _timer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  void _finish(bool send) {
    _timer?.cancel();
    Navigator.of(context).pop(send);
  }

  @override
  Widget build(BuildContext context) {
    final detected = widget.triggerReason != null;
    return PopScope(
      canPop: false,
      child: _AlertStage(
        fieldKey: _field,
        bg: Wsf.coral,
        dots: Wsf.coralDeep.withValues(alpha: 0.55),
        children: [
          Row(
            children: [
              Tag(
                detected ? 'danger detected' : 'emergency',
                bg: Wsf.ink,
                fg: Wsf.coral,
                icon: Icons.warning_amber_rounded,
              ),
              const Spacer(),
              const Eyebrow('sos', color: Wsf.coralDeep, size: 12),
            ],
          ),
          if (detected) ...[
            const SizedBox(height: 14),
            Text(
              widget.triggerReason!,
              style: Wsf.body(size: 16, color: Wsf.coralDeep, weight: FontWeight.w600),
            ),
          ],
          const Spacer(),
          Text('Sending SOS in', textAlign: TextAlign.center, style: Wsf.display(30, color: Wsf.ink, height: 1)),
          _BigCount(_countdown, color: Wsf.ink),
          Text(
            'An emergency text with your location opens when this reaches zero.',
            textAlign: TextAlign.center,
            style: Wsf.body(size: 15.5, color: Wsf.coralDeep, weight: FontWeight.w500),
          ),
          const Spacer(),
          PillButton(
            label: detected ? "I'm safe. Cancel" : 'Cancel',
            bg: Wsf.bone,
            fg: Wsf.ink,
            icon: Icons.close_rounded,
            height: 68,
            onTap: () => _finish(false),
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'Send SOS now',
            bg: Wsf.ink,
            fg: Wsf.coral,
            icon: Icons.sos_rounded,
            onTap: () => _finish(true),
          ),
        ],
      ),
    );
  }
}

// ── Route drift check-in ─────────────────────────────────────────────────────

/// Shown when a tracked trip strays from its route. Pops `true` if the user
/// confirms they are safe, `false` when the 15 seconds run out.
class DriftSosOverlay extends StatefulWidget {
  final String? dangerReason;
  const DriftSosOverlay({super.key, this.dangerReason});

  static void dismissIfActive() {
    _DriftSosOverlayState.activeInstance?._dismissForOverride();
  }

  @override
  State<DriftSosOverlay> createState() => _DriftSosOverlayState();
}

class _DriftSosOverlayState extends State<DriftSosOverlay> {
  static _DriftSosOverlayState? activeInstance;
  final _field = GlobalKey<DitherFieldState>();
  int _countdown = 15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    activeInstance = this;
    _triggerHaptics();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _triggerHaptics();
      _ring(_field, context);
      setState(() {
        if (_countdown > 1) {
          _countdown--;
        } else {
          _timer?.cancel();
          Navigator.of(context).pop(false);
        }
      });
    });
  }

  void _triggerHaptics() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), () {
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    if (activeInstance == this) {
      activeInstance = null;
    }
    _timer?.cancel();
    super.dispose();
  }

  void _dismissForOverride() {
    _timer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: _AlertStage(
          fieldKey: _field,
          bg: Wsf.ink,
          dots: Wsf.amber.withValues(alpha: 0.4),
          children: [
            const Row(
              children: [
                Tag('off route', bg: Wsf.amber, fg: Wsf.amberDeep, icon: Icons.alt_route_rounded),
                Spacer(),
                Eyebrow('check-in', size: 12),
              ],
            ),
            const SizedBox(height: 10),
            const Center(child: GuardianOrb(size: 120, mood: OrbMood.caution, interactive: false)),
            Text('Are you safe?', textAlign: TextAlign.center, style: Wsf.display(48, height: 1)),
            const SizedBox(height: 12),
            Text(
              widget.dangerReason ??
                  'You have left your route. If you do not answer, an SOS is sent for you.',
              textAlign: TextAlign.center,
              style: Wsf.body(size: 16),
            ),
            const Spacer(),
            _BigCount(_countdown, color: Wsf.amber),
            const Spacer(),
            PillButton(
              label: "I'm safe",
              bg: Wsf.bone,
              fg: Wsf.ink,
              icon: Icons.check_rounded,
              height: 72,
              onTap: () {
                _timer?.cancel();
                Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      );
}

// ── Audio threat ─────────────────────────────────────────────────────────────

/// Shown when the on-device model hears a danger sound. Pops `true` if the
/// user says they are safe; `false` (send SOS) on the button or after 15 s.
class AudioThreatOverlay extends StatefulWidget {
  final String label;
  final double confidence;
  const AudioThreatOverlay({
    super.key,
    required this.label,
    required this.confidence,
  });

  @override
  State<AudioThreatOverlay> createState() => _AudioThreatOverlayState();
}

class _AudioThreatOverlayState extends State<AudioThreatOverlay> {
  final _field = GlobalKey<DitherFieldState>();
  int _countdown = 15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _triggerHaptics();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _triggerHaptics();
      if (!mounted) return;
      _ring(_field, context);
      setState(() {
        if (_countdown > 1) {
          _countdown--;
        } else {
          _timer?.cancel();
          // Time's up → return false so caller triggers SOS
          Navigator.of(context).pop(false);
        }
      });
    });
  }

  void _triggerHaptics() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), () {
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: _AlertStage(
          fieldKey: _field,
          bg: Wsf.coral,
          dots: Wsf.coralDeep.withValues(alpha: 0.55),
          children: [
            Row(
              children: [
                const Tag('threat heard', bg: Wsf.ink, fg: Wsf.coral, icon: Icons.graphic_eq_rounded),
                const Spacer(),
                Eyebrow(
                  '${(widget.confidence * 100).toStringAsFixed(0)}% confidence',
                  color: Wsf.coralDeep,
                  size: 12,
                ),
              ],
            ),
            const SizedBox(height: 22),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(widget.label, style: Wsf.display(54, color: Wsf.ink, height: 0.95)),
            ),
            const SizedBox(height: 12),
            Text(
              'The response desk has been alerted. Answer, or an SOS is sent for you.',
              style: Wsf.body(size: 16, color: Wsf.coralDeep, weight: FontWeight.w500),
            ),
            const Spacer(),
            _BigCount(_countdown, color: Wsf.ink),
            const Spacer(),
            // I'M SAFE — dismisses without SOS
            PillButton(
              label: "I'm safe",
              bg: Wsf.bone,
              fg: Wsf.ink,
              icon: Icons.check_rounded,
              height: 68,
              onTap: () {
                _timer?.cancel();
                Navigator.of(context).pop(true);
              },
            ),
            const SizedBox(height: 10),
            // SEND SOS — immediately triggers SOS
            PillButton(
              label: 'Send SOS',
              bg: Wsf.ink,
              fg: Wsf.coral,
              icon: Icons.sos_rounded,
              onTap: () {
                _timer?.cancel();
                Navigator.of(context).pop(false);
              },
            ),
          ],
        ),
      );
}
