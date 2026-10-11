import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';

/// Number of questions across both set-up screens (4 about you, 2 about your
/// person). Drives the shared progress rail.
const int kSetupSteps = 6;

/// One question of the set-up conversation: progress rail, the guardian, a
/// two-part headline, one input, one button.
class SetupStep extends StatelessWidget {
  const SetupStep({
    super.key,
    required this.step,
    required this.eyebrow,
    required this.lead,
    required this.accent,
    required this.child,
    required this.onNext,
    this.hint,
    this.onBack,
    this.cta = 'next',
    this.loading = false,
    this.mood = OrbMood.curious,
    this.look,
  });

  /// Zero-based position in the overall flow.
  final int step;
  final String eyebrow;
  final String lead;
  final String accent;
  final String? hint;
  final Widget child;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final String cta;
  final bool loading;
  final OrbMood mood;
  final Offset? look;

  @override
  Widget build(BuildContext context) {
    final number = (step + 1).toString().padLeft(2, '0');
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DitherField(
            color: Wsf.volt,
            interactive: false,
            cell: 9,
            base: 0.015,
            intensity: 0.7,
            waves: const [
              DitherWave(origin: Offset(0.86, 0.14), wavelength: 95, speed: 0.22, amplitude: 0.7, reach: 420),
            ],
            mask: DitherMasks.fadeDown(0.42),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Wsf.gutter, 14, Wsf.gutter, 0),
                  child: Row(
                    children: [
                      AnimatedSize(
                        duration: Wsf.base,
                        curve: Wsf.expoOut,
                        child: onBack == null
                            ? const SizedBox(height: 44)
                            : Padding(
                                padding: const EdgeInsets.only(right: 14),
                                child: DiscButton(
                                  icon: Icons.arrow_back_rounded,
                                  size: 44,
                                  bg: Wsf.ink3,
                                  onTap: onBack,
                                ),
                              ),
                      ),
                      const Expanded(child: SizedBox()),
                      Eyebrow('$number/0$kSetupSteps', size: 12),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Wsf.gutter, 14, Wsf.gutter, 0),
                  child: StepRail(total: kSetupSteps, current: step),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(Wsf.gutter, 8, Wsf.gutter, 16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 520),
                      switchInCurve: Wsf.expoOut,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, if (current != null) current],
                      ),
                      transitionBuilder: (c, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(anim),
                          child: c,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(step),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: GuardianOrb(size: 108, mood: mood, look: look),
                          ),
                          Eyebrow(eyebrow),
                          const SizedBox(height: 12),
                          Headline(lead, accent, size: 54),
                          if (hint != null) ...[
                            const SizedBox(height: 14),
                            FadeSlide(
                              delay: const Duration(milliseconds: 320),
                              child: Text(hint!, style: Wsf.body()),
                            ),
                          ],
                          const SizedBox(height: 28),
                          FadeSlide(delay: const Duration(milliseconds: 220), child: child),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Wsf.gutter, 6, Wsf.gutter, 14),
                  child: PillButton(label: cta, loading: loading, onTap: onNext),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Oversized single-line answer field: the answer is the headline.
class BigAnswerField extends StatelessWidget {
  const BigAnswerField({
    super.key,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.fontSize = 34,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final double fontSize;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    UnderlineInputBorder line(Color c) => UnderlineInputBorder(borderSide: BorderSide(color: c, width: 3));
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      maxLines: maxLines,
      minLines: 1,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      keyboardAppearance: Brightness.dark,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorWidth: 3,
      cursorRadius: const Radius.circular(2),
      style: Wsf.display(fontSize, height: 1.1),
      decoration: InputDecoration(
        filled: false,
        hintText: hint,
        hintStyle: Wsf.display(fontSize, color: Wsf.ink4, height: 1.1),
        contentPadding: const EdgeInsets.only(bottom: 12, top: 4),
        border: line(Wsf.line),
        enabledBorder: line(Wsf.line),
        focusedBorder: line(Wsf.volt),
      ),
    );
  }
}

/// Horizontal number wheel. The centred number is the value.
class NumberWheel extends StatefulWidget {
  const NumberWheel({
    super.key,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final int min;
  final int max;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<NumberWheel> {
  late final PageController _pc =
      PageController(viewportFraction: 0.36, initialPage: widget.value - widget.min);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 170,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Tick marks under the wheel.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 31; i++)
                    Container(
                      width: 2,
                      height: i == 15 ? 26 : (i % 5 == 0 ? 14 : 8),
                      decoration: BoxDecoration(
                        color: i == 15 ? Wsf.volt : Wsf.ink4,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                ],
              ),
            ),
            Positioned.fill(
              bottom: 30,
              child: PageView.builder(
                controller: _pc,
                itemCount: widget.max - widget.min + 1,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  widget.onChanged(widget.min + i);
                },
                itemBuilder: (_, i) => AnimatedBuilder(
                  animation: _pc,
                  builder: (_, __) {
                    final page = _pc.hasClients && _pc.position.haveDimensions
                        ? _pc.page ?? _pc.initialPage.toDouble()
                        : _pc.initialPage.toDouble();
                    final d = (page - i).abs().clamp(0.0, 1.0);
                    // The numeral is wider than its slot; let it overflow
                    // rather than wrap onto a second line.
                    return OverflowBox(
                      minWidth: 0,
                      maxWidth: double.infinity,
                      child: Transform.scale(
                        scale: 1 - d * 0.55,
                        child: Text(
                          '${widget.min + i}',
                          maxLines: 1,
                          softWrap: false,
                          style: Wsf.display(
                            120,
                            height: 1,
                            color: Color.lerp(Wsf.volt, Wsf.ink4, d)!,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
}
