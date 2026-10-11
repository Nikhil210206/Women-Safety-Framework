import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/profile_repository.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';
import 'setup_scaffold.dart';

/// Set-up, part one: four questions about the user, asked one at a time and
/// saved together at the end.
class OnboardingPersonalInfoScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingPersonalInfoScreen({super.key, required this.onComplete});

  @override
  State<OnboardingPersonalInfoScreen> createState() => _OnboardingPersonalInfoScreenState();
}

class _OnboardingPersonalInfoScreenState extends State<OnboardingPersonalInfoScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();

  int _step = 0;
  int _age = 21;
  String? _selectedBloodGroup;
  bool _isSaving = false;
  bool _flinch = false;

  static const List<String> _bloodGroups = [
    'A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−',
  ];

  @override
  void initState() {
    super.initState();
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final metaName = meta?['full_name'] as String?;
    if (metaName != null && metaName.isNotEmpty) {
      _nameController.text = metaName;
    }
    _nameController.addListener(_refresh);
    _addressController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  bool get _stepValid => switch (_step) {
        0 => _nameController.text.trim().isNotEmpty,
        1 => true,
        2 => _selectedBloodGroup != null,
        _ => _addressController.text.trim().isNotEmpty,
      };

  void _next() {
    if (!_stepValid) {
      HapticFeedback.heavyImpact();
      setState(() => _flinch = true);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _flinch = false);
      });
      _showError(switch (_step) {
        0 => 'We need something to call you.',
        2 => 'Pick a blood type to continue.',
        _ => 'Add where home is to continue.',
      });
      return;
    }
    FocusScope.of(context).unfocus();
    if (_step < 3) {
      setState(() => _step++);
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

    setState(() => _isSaving = true);
    try {
      await ProfileRepository.instance.savePersonalInfo(
        userId: userId,
        fullName: _nameController.text.trim(),
        age: _age,
        bloodGroup: _selectedBloodGroup!,
        homeAddress: _addressController.text.trim(),
        phone: Supabase.instance.client.auth.currentUser?.phone,
      );
      if (!mounted) return;
      widget.onComplete();
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
    final mood = _flinch
        ? OrbMood.alert
        : _isSaving
            ? OrbMood.listening
            : (_stepValid && _step != 1 ? OrbMood.happy : OrbMood.curious);
    final back = _step == 0 ? null : () => setState(() => _step--);

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: switch (_step) {
        0 => SetupStep(
            step: 0,
            eyebrow: 'about you',
            lead: 'what do we',
            accent: 'call you?',
            mood: mood,
            look: const Offset(-0.6, 0.8),
            onBack: back,
            onNext: _next,
            child: BigAnswerField(
              controller: _nameController,
              hint: 'your name',
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              onSubmitted: (_) => _next(),
            ),
          ),
        1 => SetupStep(
            step: 1,
            eyebrow: 'about you',
            lead: 'how old',
            accent: 'are you?',
            hint: 'swipe the number.',
            mood: mood,
            look: const Offset(-0.5, 0.9),
            onBack: back,
            onNext: _next,
            child: NumberWheel(
              min: 13,
              max: 99,
              value: _age,
              onChanged: (v) => setState(() => _age = v),
            ),
          ),
        2 => SetupStep(
            step: 2,
            eyebrow: 'about you',
            lead: 'your',
            accent: 'blood type?',
            hint: 'the first thing a responder looks for.',
            mood: mood,
            look: const Offset(-0.5, 0.9),
            onBack: back,
            onNext: _next,
            child: ChoiceChips<String>(
              options: _bloodGroups,
              value: _selectedBloodGroup,
              columns: 4,
              height: 72,
              big: true,
              onChanged: (v) => setState(() => _selectedBloodGroup = v),
            ),
          ),
        _ => SetupStep(
            step: 3,
            eyebrow: 'about you',
            lead: "where's",
            accent: 'home?',
            hint: 'so the guardian knows where safe is.',
            mood: mood,
            look: const Offset(-0.6, 0.8),
            cta: 'save and continue',
            loading: _isSaving,
            onBack: back,
            onNext: _next,
            child: BigAnswerField(
              controller: _addressController,
              hint: 'street, area, city',
              maxLines: 3,
              fontSize: 26,
              keyboardType: TextInputType.streetAddress,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.fullStreetAddress],
            ),
          ),
      },
    );
  }
}
