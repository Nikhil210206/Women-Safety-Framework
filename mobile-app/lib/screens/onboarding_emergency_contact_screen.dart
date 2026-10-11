import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/profile_repository.dart';
import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';
import 'setup_scaffold.dart';

/// Set-up, part two: the user's emergency contact, then a send-off.
class OnboardingEmergencyContactScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingEmergencyContactScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingEmergencyContactScreen> createState() => _OnboardingEmergencyContactScreenState();
}

class _OnboardingEmergencyContactScreenState extends State<OnboardingEmergencyContactScreen> {
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();

  int _step = 0; // 0 = who, 1 = their number, 2 = all set
  String? _selectedRelationship;
  bool _isSaving = false;
  bool _flinch = false;

  static const List<String> _relationships = [
    'Mother',
    'Father',
    'Sister',
    'Brother',
    'Spouse / Partner',
    'Friend',
    'Guardian',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_refresh);
    _numberController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  /// E.164 normalisation — same logic as LoginScreen to stay consistent.
  String? _formatPhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('+')) {
      final digits = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      return digits.length >= 8 ? '+$digits' : null;
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+91$digits';
    return null;
  }

  bool get _stepValid => _step == 0
      ? _nameController.text.trim().isNotEmpty && _selectedRelationship != null
      : _formatPhone(_numberController.text) != null;

  void _next() {
    if (!_stepValid) {
      HapticFeedback.heavyImpact();
      setState(() => _flinch = true);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _flinch = false);
      });
      _showError(_step == 0
          ? (_nameController.text.trim().isEmpty ? 'Who should we reach out to?' : 'Pick how you know them.')
          : 'Enter a valid phone number.');
      return;
    }
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      setState(() => _step = 1);
    } else {
      _save();
    }
  }

  Future<void> _save() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _showError('Session expired. Please sign in again.');
      return;
    }

    final formatted = _formatPhone(_numberController.text);
    if (formatted == null) {
      _showError('Enter a valid phone number.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ProfileRepository.instance.saveEmergencyContact(
        userId: userId,
        contactName: _nameController.text.trim(),
        contactNumber: formatted,
        relationship: _selectedRelationship!,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _step = 2);
    } on PostgrestException catch (e) {
      if (mounted) _showError(e.message);
    } catch (_) {
      if (mounted) _showError('Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) => wsfToast(context, msg, icon: Icons.error_outline_rounded);

  @override
  Widget build(BuildContext context) {
    if (_step == 2) {
      final fullName =
          Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] as String? ?? '';
      return SetupDoneScreen(
        firstName: fullName.trim().split(' ').first,
        contactName: _nameController.text.trim().split(' ').first,
        onContinue: widget.onComplete,
      );
    }

    final mood = _flinch
        ? OrbMood.alert
        : _isSaving
            ? OrbMood.listening
            : (_stepValid ? OrbMood.happy : OrbMood.curious);

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == 1) setState(() => _step = 0);
      },
      child: _step == 0
          ? SetupStep(
              step: 4,
              eyebrow: 'your person',
              lead: "who's your",
              accent: 'person?',
              hint: 'the one we reach when you hit sos.',
              mood: mood,
              look: const Offset(-0.6, 0.8),
              onNext: _next,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BigAnswerField(
                    controller: _nameController,
                    hint: 'their name',
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 24),
                  const Eyebrow('they are your'),
                  const SizedBox(height: 12),
                  ChoiceChips<String>(
                    options: _relationships,
                    value: _selectedRelationship,
                    height: 48,
                    labelOf: (r) => r.toLowerCase(),
                    onChanged: (v) => setState(() => _selectedRelationship = v),
                  ),
                ],
              ),
            )
          : SetupStep(
              step: 5,
              eyebrow: 'your person',
              lead: 'and their',
              accent: 'number?',
              hint: '+91 is assumed unless you type another code.',
              mood: mood,
              look: const Offset(-0.6, 0.8),
              cta: 'finish set-up',
              loading: _isSaving,
              onBack: () => setState(() => _step = 0),
              onNext: _next,
              child: BigAnswerField(
                controller: _numberController,
                hint: '98765 43210',
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]'))],
                onSubmitted: (_) => _next(),
              ),
            ),
    );
  }
}

/// The send-off: a volt block, a delighted guardian, and a way in.
class SetupDoneScreen extends StatelessWidget {
  const SetupDoneScreen({
    super.key,
    required this.firstName,
    required this.contactName,
    required this.onContinue,
  });

  final String firstName;
  final String contactName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    const olive = Color(0xFF465212);
    final name = firstName.isEmpty ? 'you' : firstName.toLowerCase();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Wsf.volt,
        body: Stack(
          fit: StackFit.expand,
          children: [
            DitherField(
              color: const Color(0x99283600),
              cell: 9,
              base: 0.03,
              waves: const [
                DitherWave(origin: Offset(0.5, 0.3), wavelength: 90, speed: 0.4, amplitude: 0.8, reach: 620),
              ],
              mask: DitherMasks.fadeDown(0.7),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Wsf.gutter, 14, Wsf.gutter, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Wordmark(size: 24, color: Wsf.ink, dot: Wsf.pine),
                    ),
                    const Spacer(),
                    const Center(child: GuardianOrb(size: 220, mood: OrbMood.happy, glow: false)),
                    const Spacer(),
                    const FadeSlide(child: Eyebrow('06/06 · done', color: olive, size: 12)),
                    const SizedBox(height: 14),
                    Headline(
                      "you're set,",
                      '$name.',
                      size: 62,
                      color: Wsf.ink,
                      accentColor: Wsf.pine,
                      delay: const Duration(milliseconds: 120),
                    ),
                    const SizedBox(height: 16),
                    FadeSlide(
                      delay: const Duration(milliseconds: 500),
                      child: Text(
                        contactName.isEmpty
                            ? 'the guardian is awake and your person is on file.'
                            : 'the guardian is awake, and ${contactName.toLowerCase()} is the one we reach if you ever hit sos.',
                        style: Wsf.body(size: 16.5, color: olive),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeSlide(
                      delay: const Duration(milliseconds: 700),
                      child: PillButton(label: 'take me in', bg: Wsf.ink, fg: Wsf.volt, onTap: onContinue),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
