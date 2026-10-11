import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fieldKey = GlobalKey<DitherFieldState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  bool _isRegister = true; // true = Register, false = Login
  bool _isOtpSent = false;
  bool _isSubmitting = false;

  // Brief emotional beats for the guardian (an error flinch, a success grin).
  OrbMood? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    for (final f in [_nameFocus, _phoneFocus, _otpFocus]) {
      f.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  /// E.164: if input starts with `+`, keep country code + digits; else default +91.
  String? _formatPhoneE164(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('+')) {
      final rest = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      if (rest.length < 8) return null;
      return '+$rest';
    }

    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length == 11 && digits.startsWith('91')) return '+$digits';
    if (digits.length == 10) return '+91$digits';
    if (digits.length >= 10) return '+91${digits.substring(digits.length - 10)}';
    return null;
  }

  void _flashMood(OrbMood mood, [int ms = 1400]) {
    _flashTimer?.cancel();
    setState(() => _flash = mood);
    _flashTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _flashMood(OrbMood.alert);
    wsfToast(context, message, icon: Icons.error_outline_rounded);
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) {
      _flashMood(OrbMood.alert, 900);
      return;
    }

    final formatted = _formatPhoneE164(_phoneController.text);
    if (formatted == null) {
      _showError('That number does not look right.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: formatted,
        data: _isRegister ? {'full_name': _nameController.text.trim()} : null,
      );
      if (!mounted) return;
      setState(() {
        _isOtpSent = true;
        _isSubmitting = false;
      });
      _otpFocus.requestFocus();
    } on AuthException catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
      _showError(e.message);
    } catch (_) {
      if (mounted) setState(() => _isSubmitting = false);
      _showError('Could not send the code. Try again.');
    }
  }

  Future<void> _verifyOtp() async {
    final formatted = _formatPhoneE164(_phoneController.text);
    if (formatted == null) {
      _showError('That number does not look right.');
      return;
    }
    final token = _otpController.text.trim();
    if (token.isEmpty) {
      _showError('Enter the code from your texts.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: formatted,
        token: token,
        type: OtpType.sms,
      );

      if (_isRegister) {
        final enteredName = _nameController.text.trim();
        // Force-update metadata and profile with the typed name.
        if (enteredName.isNotEmpty) {
          try {
            await Supabase.instance.client.auth.updateUser(
              UserAttributes(data: {'full_name': enteredName}),
            );
          } catch (_) {}
        }
        final uid = Supabase.instance.client.auth.currentUser?.id;
        final phone = Supabase.instance.client.auth.currentUser?.phone;
        if (uid != null) {
          try {
            await Supabase.instance.client.from('profiles').upsert({
              'id': uid,
              'full_name': enteredName.isNotEmpty ? enteredName : null,
              'phone': phone,
            }, onConflict: 'id');
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (Supabase.instance.client.auth.currentUser == null) {
        _showError('That code did not work.');
      } else {
        HapticFeedback.mediumImpact();
        _flashMood(OrbMood.happy, 4000);
      }
      // AuthShell handles navigation via onAuthStateChange.
    } on AuthException catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
      _showError(e.message);
    } catch (_) {
      if (mounted) setState(() => _isSubmitting = false);
      _showError('Could not check that code.');
    }
  }

  void _resetPhoneStep() {
    setState(() {
      _isOtpSent = false;
      _otpController.clear();
    });
    _phoneFocus.requestFocus();
  }

  void _setMode(bool login) {
    setState(() {
      _isRegister = !login;
      _isOtpSent = false;
      _nameController.clear();
      _phoneController.clear();
      _otpController.clear();
    });
  }

  OrbMood get _mood {
    if (_flash != null) return _flash!;
    if (_isSubmitting) return OrbMood.listening;
    if (_isOtpSent) return OrbMood.shy; // it looks away while you type the code
    if (_nameFocus.hasFocus || _phoneFocus.hasFocus) return OrbMood.curious;
    return OrbMood.calm;
  }

  @override
  Widget build(BuildContext context) {
    final typing = _nameFocus.hasFocus || _phoneFocus.hasFocus;
    final (lead, accent) = _isOtpSent
        ? ('check your', 'texts.')
        : _isRegister
            ? ('hey,', 'you made it.')
            : ('welcome', 'back.');

    return Scaffold(
      body: Listener(
        // Any touch sends a ring through the dots behind the form.
        onPointerDown: (e) => _fieldKey.currentState?.ripple(e.localPosition),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DitherField(
              key: _fieldKey,
              color: Wsf.volt,
              interactive: false,
              cell: 9,
              base: 0.02,
              waves: const [
                DitherWave(origin: Offset(0.5, 0.16), wavelength: 105, speed: 0.24, amplitude: 0.7, reach: 520),
              ],
              mask: DitherMasks.fadeDown(0.5),
            ),
            SafeArea(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(Wsf.gutter, 10, Wsf.gutter, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: Wordmark(size: 24)),
                      const SizedBox(height: 6),
                      Center(
                        child: GuardianOrb(
                          size: 148,
                          mood: _mood,
                          look: typing ? const Offset(0, 0.9) : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Eyebrow(_isOtpSent ? 'step 2 of 2 · the code' : 'step 1 of 2 · your number'),
                      const SizedBox(height: 12),
                      Headline(lead, accent, key: ValueKey('$_isRegister$_isOtpSent'), size: 56),
                      const SizedBox(height: 26),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 520),
                        curve: Wsf.expoOut,
                        alignment: Alignment.topCenter,
                        child: _isOtpSent ? _otpStep() : _numberStep(),
                      ),

                      const SizedBox(height: 26),
                      PillButton(
                        label: _isOtpSent ? 'let me in' : 'text me a code',
                        loading: _isSubmitting,
                        onTap: _isOtpSent ? _verifyOtp : _sendOtp,
                      ),
                      const SizedBox(height: 6),
                      if (_isOtpSent)
                        Center(
                          child: GhostButton(
                            label: 'wrong number? change it',
                            onTap: _isSubmitting ? null : _resetPhoneStep,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: const Center(
                            child: Eyebrow('your number is only used to sign you in', color: Wsf.boneFaint),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberStep() => Column(
        key: const ValueKey('number'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedPill(
            left: 'new here',
            right: 'been here',
            isRight: !_isRegister,
            onChanged: _isSubmitting ? null : _setMode,
          ),
          const SizedBox(height: 22),
          if (_isRegister) ...[
            WsfField(
              label: 'your name',
              controller: _nameController,
              focusNode: _nameFocus,
              hint: 'what do we call you?',
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: (v) => (v == null || v.trim().isEmpty) ? 'WE NEED A NAME' : null,
            ),
            const SizedBox(height: 18),
          ],
          WsfField(
            label: 'phone number',
            controller: _phoneController,
            focusNode: _phoneFocus,
            hint: '98765 43210',
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
            // +91 is assumed unless the number is typed with its own code.
            prefix: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _phoneController,
              builder: (_, v, __) => v.text.trimLeft().startsWith('+')
                  ? const Icon(Icons.public_rounded, size: 18, color: Wsf.volt)
                  : Text('+91', style: Wsf.mono(size: 14, color: Wsf.volt)),
            ),
            onSubmitted: (_) => _sendOtp(),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'WE NEED A NUMBER';
              if (_formatPhoneE164(v) == null) return 'THAT NUMBER LOOKS OFF';
              return null;
            },
          ),
        ],
      );

  Widget _otpStep() => Column(
        key: const ValueKey('otp'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              text: 'we texted a code to ',
              children: [
                TextSpan(
                  text: _formatPhoneE164(_phoneController.text) ?? _phoneController.text,
                  style: Wsf.body(color: Wsf.bone, weight: FontWeight.w600),
                ),
                const TextSpan(text: '. the guardian is not peeking.'),
              ],
            ),
            style: Wsf.body(),
          ),
          const SizedBox(height: 20),
          OtpBoxes(
            controller: _otpController,
            focusNode: _otpFocus,
            enabled: !_isSubmitting,
            onCompleted: (_) => _verifyOtp(),
          ),
        ],
      );
}

/// Six code boxes fed by one invisible text field, so paste and SMS autofill
/// behave like a normal input.
class OtpBoxes extends StatefulWidget {
  const OtpBoxes({
    super.key,
    required this.controller,
    required this.focusNode,
    this.length = 6,
    this.enabled = true,
    this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool enabled;
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final focused = widget.focusNode.hasFocus;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.focusNode.requestFocus(),
      child: Stack(
        children: [
          // The real input: present, focusable, invisible.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                autofocus: true,
                keyboardType: TextInputType.number,
                keyboardAppearance: Brightness.dark,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                showCursor: false,
                enableInteractiveSelection: false,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  if (v.length == widget.length) widget.onCompleted?.call(v);
                },
              ),
            ),
          ),
          IgnorePointer(
            child: Row(
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _OtpCell(
                      char: i < text.length ? text[i] : null,
                      active: focused && i == text.length.clamp(0, widget.length - 1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpCell extends StatelessWidget {
  const _OtpCell({required this.char, required this.active});
  final String? char;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final filled = char != null;
    return AnimatedContainer(
      duration: Wsf.base,
      curve: Wsf.backOut,
      height: 68,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? Wsf.volt : Wsf.ink3,
        borderRadius: BorderRadius.circular(filled ? 34 : 18),
        border: Border.all(color: active || filled ? Wsf.volt : Wsf.line, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Wsf.backOut,
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: filled
            ? Text(char!, key: ValueKey(char), style: Wsf.display(30, color: Wsf.voltDeep, height: 1))
            : active
                ? const _Caret()
                : const SizedBox.shrink(),
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
          width: 3,
          height: 26,
          decoration: BoxDecoration(color: Wsf.volt, borderRadius: BorderRadius.circular(2)),
        ),
      );
}
