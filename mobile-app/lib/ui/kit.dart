import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wsf.dart';
import 'motion.dart';

/// Mono eyebrow, e.g. `01 · LISTENS`.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = Wsf.boneDim, this.size = 11});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Wsf.mono(color: color, size: size));
}

/// The wordmark: lowercase, tight, with a volt full stop.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22, this.color = Wsf.bone, this.dot = Wsf.volt});
  final double size;
  final Color color;
  final Color dot;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('wsf', style: Wsf.display(size, color: color, height: 1)),
          Container(
            width: size * 0.2,
            height: size * 0.2,
            margin: EdgeInsets.only(left: size * 0.05, bottom: size * 0.16),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ],
      );
}

/// Two-part headline: a heavy grotesk line and an italic serif accent line.
class Headline extends StatelessWidget {
  const Headline(
    this.lead,
    this.accent, {
    super.key,
    this.size = 52,
    this.color = Wsf.bone,
    this.accentColor = Wsf.volt,
    this.play = true,
    this.delay = Duration.zero,
    this.alignment = Alignment.centerLeft,
  });

  final String lead;
  final String? accent;
  final double size;
  final Color color;
  final Color accentColor;
  final bool play;
  final Duration delay;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => SplitReveal(
        play: play,
        delay: delay,
        alignment: alignment,
        lines: [
          for (final l in lead.split('\n')) RevealLine(l, Wsf.display(size, color: color)),
          if (accent != null)
            for (final l in accent!.split('\n'))
              RevealLine(l, Wsf.serif(size * 1.04, color: accentColor)),
        ],
      );
}

/// Small rounded label. Mono, uppercase.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.bg = Wsf.volt, this.fg = Wsf.voltDeep, this.icon, this.outlined = false});
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : bg,
          borderRadius: BorderRadius.circular(99),
          border: outlined ? Border.all(color: bg, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: outlined ? bg : fg),
              const SizedBox(width: 5),
            ],
            Text(text.toUpperCase(), style: Wsf.mono(size: 10.5, color: outlined ? bg : fg, weight: FontWeight.w600)),
          ],
        ),
      );
}

/// Primary action. The label rolls up and is replaced from below on tap, and
/// the arrow disc nudges forward.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.bg = Wsf.volt,
    this.fg = Wsf.voltDeep,
    this.icon = Icons.arrow_forward_rounded,
    this.loading = false,
    this.height = 62,
    this.expand = true,
    this.border,
  });

  final String label;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final bool loading;
  final double height;
  final bool expand;
  final Color? border;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> with SingleTickerProviderStateMixin {
  late final AnimationController _roll =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    final label = Wsf.body(size: 17, color: widget.fg, weight: FontWeight.w600);
    final disc = widget.height - 16;

    return Pressable(
      scale: 0.97,
      haptic: false,
      onTap: !enabled
          ? null
          : () {
              HapticFeedback.lightImpact();
              _roll.forward(from: 0);
              widget.onTap!();
            },
      child: AnimatedOpacity(
        duration: Wsf.fast,
        opacity: widget.onTap == null ? 0.4 : 1,
        child: Container(
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding: EdgeInsets.only(left: 26, right: widget.icon == null ? 26 : 8),
          decoration: BoxDecoration(
            color: widget.bg,
            borderRadius: BorderRadius.circular(99),
            border: widget.border == null ? null : Border.all(color: widget.border!, width: 2),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Flexible(
                fit: widget.expand ? FlexFit.tight : FlexFit.loose,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _roll,
                    builder: (_, __) {
                      final v = Wsf.expoOut.transform(_roll.value);
                      const h = 26.0;
                      return SizedBox(
                        height: h,
                        child: Stack(
                          children: [
                            Transform.translate(
                              offset: Offset(0, -h * v),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(widget.label, style: label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(0, h * (1 - v)),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Opacity(
                                  opacity: _roll.value == 0 ? 0 : 1,
                                  child: Text(widget.label, style: label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (widget.icon != null) ...[
                const SizedBox(width: 14),
                Container(
                  width: disc,
                  height: disc,
                  decoration: BoxDecoration(color: widget.fg, shape: BoxShape.circle),
                  child: widget.loading
                      ? Padding(
                          padding: EdgeInsets.all(disc * 0.3),
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: widget.bg),
                        )
                      : AnimatedBuilder(
                          animation: _roll,
                          builder: (_, child) {
                            // Out to the right, back in from the left.
                            final v = _roll.value;
                            final dx = v < 0.5 ? v * 2 * disc : (v - 1) * 2 * disc;
                            return ClipOval(child: Transform.translate(offset: Offset(dx, 0), child: child));
                          },
                          child: Center(child: Icon(widget.icon, color: widget.bg, size: 22)),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Text-only secondary action.
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onTap, this.color = Wsf.boneDim, this.icon});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 8)],
              Text(label, style: Wsf.body(size: 15, color: color, weight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

/// Round icon button used on the map and in headers.
class DiscButton extends StatelessWidget {
  const DiscButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 48,
    this.bg = Wsf.ink,
    this.fg = Wsf.bone,
    this.border = Wsf.line,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color bg;
  final Color fg;
  final Color? border;
  final bool loading;

  @override
  Widget build(BuildContext context) => Pressable(
        scale: 0.9,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Wsf.base,
          curve: Wsf.expoOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: border == null ? null : Border.all(color: border!, width: 1.5),
          ),
          child: loading
              ? Padding(
                  padding: EdgeInsets.all(size * 0.3),
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, color: fg, size: size * 0.44),
        ),
      );
}

/// The "receipt" card: a 2px rule around paper, with an optional mono header.
class ReceiptCard extends StatelessWidget {
  const ReceiptCard({
    super.key,
    required this.child,
    this.label,
    this.trailing,
    this.bg = Wsf.ink2,
    this.border = Wsf.line,
    this.labelColor = Wsf.boneDim,
    this.padding = const EdgeInsets.all(18),
    this.radius = Wsf.rCard,
  });

  final Widget child;
  final String? label;
  final Widget? trailing;
  final Color bg;
  final Color border;
  final Color labelColor;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (label != null)
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border, width: 2))),
                child: Row(
                  children: [
                    Expanded(child: Eyebrow(label!, color: labelColor)),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      );
}

/// Labelled text input.
class WsfField extends StatelessWidget {
  const WsfField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.focusNode,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction,
    this.prefix,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final FocusNode? focusNode;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final Widget? prefix;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Eyebrow(label),
          ),
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            maxLines: maxLines,
            autofocus: autofocus,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters,
            validator: validator,
            onChanged: onChanged,
            onFieldSubmitted: onSubmitted,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            keyboardAppearance: Brightness.dark,
            style: Wsf.body(size: 18, color: enabled ? Wsf.bone : Wsf.boneFaint, weight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: prefix == null
                  ? null
                  : Padding(padding: const EdgeInsets.only(left: 18, right: 10), child: prefix),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
        ],
      );
}

/// Wrap of single-choice chips. The picked one fills with volt and pops.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.columns,
    this.height = 60,
    this.big = false,
  });

  final List<T> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;

  /// Fixed column count for an even grid; null wraps to content width.
  final int? columns;
  final double height;
  final bool big;

  @override
  Widget build(BuildContext context) {
    Widget chip(T o) {
      final on = o == value;
      final text = labelOf?.call(o) ?? '$o';
      return Pressable(
        scale: 0.92,
        onTap: () => onChanged(o),
        child: AnimatedContainer(
          duration: Wsf.base,
          curve: Wsf.backOut,
          height: height,
          alignment: Alignment.center,
          // Grid cells are narrow; let the label use nearly all of the chip.
          padding: EdgeInsets.symmetric(horizontal: columns == null ? 20 : 8),
          decoration: BoxDecoration(
            color: on ? Wsf.volt : Wsf.ink3,
            borderRadius: BorderRadius.circular(on ? height / 2 : 18),
            border: Border.all(color: on ? Wsf.volt : Wsf.line, width: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: big
                  ? Wsf.display(26, color: on ? Wsf.voltDeep : Wsf.bone, height: 1)
                  : Wsf.body(size: 16, color: on ? Wsf.voltDeep : Wsf.bone, weight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    if (columns == null) {
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final o in options) chip(o)]);
    }
    return LayoutBuilder(builder: (_, c) {
      const gap = 10.0;
      final w = (c.maxWidth - gap * (columns! - 1)) / columns!;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final o in options) SizedBox(width: w, child: chip(o))],
      );
    });
  }
}

/// Two-option pill switch with a sliding thumb.
class SegmentedPill extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.left,
    required this.right,
    required this.isRight,
    required this.onChanged,
    this.height = 52,
    this.bg = Wsf.ink3,
    this.thumb = Wsf.bone,
    this.onThumb = Wsf.ink,
    this.offThumb = Wsf.boneDim,
    this.leftIcon,
    this.rightIcon,
  });

  final String left;
  final String right;
  final bool isRight;
  final ValueChanged<bool>? onChanged;
  final double height;
  final Color bg;
  final Color thumb;
  final Color onThumb;
  final Color offThumb;
  final IconData? leftIcon;
  final IconData? rightIcon;

  @override
  Widget build(BuildContext context) {
    Widget side(String text, IconData? icon, bool on, bool value) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChanged == null || on
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onChanged!(value);
                  },
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 17, color: on ? onThumb : offThumb),
                    const SizedBox(width: 7),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: Wsf.fast,
                    style: Wsf.body(size: 15, color: on ? onThumb : offThumb, weight: FontWeight.w600),
                    child: Text(text),
                  ),
                ],
              ),
            ),
          ),
        );

    return AnimatedOpacity(
      duration: Wsf.fast,
      opacity: onChanged == null ? 0.5 : 1,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 520),
              curve: Wsf.expoOut,
              alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: thumb, borderRadius: BorderRadius.circular(99)),
                ),
              ),
            ),
            Row(children: [side(left, leftIcon, !isRight, false), side(right, rightIcon, isRight, true)]),
          ],
        ),
      ),
    );
  }
}

/// Segmented progress rail for multi-step flows.
class StepRail extends StatelessWidget {
  const StepRail({super.key, required this.total, required this.current, this.on = Wsf.volt, this.off = Wsf.ink4});
  final int total;

  /// Zero-based index of the step in progress; earlier steps render filled.
  final int current;
  final Color on;
  final Color off;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              flex: i == current ? 3 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Wsf.expoOut,
                height: 6,
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
                decoration: BoxDecoration(
                  color: i <= current ? on : off,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      );
}

/// The arch: a dome-topped panel, used for closing calls to action.
class ArchClipper extends CustomClipper<Path> {
  const ArchClipper({this.rise = 0.36});

  /// Dome height as a fraction of the width.
  final double rise;

  @override
  Path getClip(Size size) {
    final h = size.width * rise;
    return Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(0, 0, size.width / 2, 0)
      ..quadraticBezierTo(size.width, 0, size.width, h)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(ArchClipper old) => old.rise != rise;
}

/// Shows a snackbar in the house style, replacing any that is up.
void wsfToast(BuildContext context, String message, {IconData? icon}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2400),
      content: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: Wsf.ink), const SizedBox(width: 10)],
          Expanded(child: Text(message)),
        ],
      ),
    ));
}
