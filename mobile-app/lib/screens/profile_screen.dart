import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/profile_repository.dart';
import '../services/location_service.dart';
import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/kit.dart';
import '../ui/motion.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController    = TextEditingController();
  final _ageController     = TextEditingController();
  final _addressController = TextEditingController();
  final _ecNameController  = TextEditingController();
  final _ecNumberController = TextEditingController();

  String? _bloodGroup;
  String? _ecRelationship;
  String? _phone;
  bool _loading = true;
  bool _saving  = false;
  bool _justSaved = false;

  static const List<String> _bloodGroups = [
    'A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−',
  ];

  static const List<String> _relationships = [
    'Mother', 'Father', 'Sister', 'Brother',
    'Spouse / Partner', 'Friend', 'Guardian', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _ecNameController.dispose();
    _ecNumberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      // Signed out (dev preview): show the empty form instead of loading forever.
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final profile = await ProfileRepository.instance.fetchProfile(userId);
      final ec      = await ProfileRepository.instance.fetchEmergencyContact(userId);

      if (!mounted) return;
      setState(() {
        _nameController.text    = profile?['full_name']   as String? ?? '';
        _ageController.text     = profile?['age'] != null ? '${profile!['age']}' : '';
        _addressController.text = profile?['home_address'] as String? ?? '';
        _bloodGroup             = profile?['blood_group']  as String?;
        _phone = Supabase.instance.client.auth.currentUser?.phone;

        if (ec != null) {
          _ecNameController.text   = ec['contact_name']   as String? ?? '';
          _ecNumberController.text = ec['contact_number'] as String? ?? '';
          _ecRelationship          = ec['relationship']   as String?;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _formatPhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('+')) {
      final digits = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      return digits.length >= 8 ? '+$digits' : null;
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+91$digits';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final ecFormatted = _formatPhone(_ecNumberController.text);
    if (ecFormatted == null) {
      _showSnack('Enter a valid emergency contact number.');
      return;
    }
    if (_bloodGroup == null || _ecRelationship == null) {
      _showSnack(_bloodGroup == null ? 'Pick your blood type.' : 'Pick how you know your contact.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ProfileRepository.instance.savePersonalInfo(
        userId:      userId,
        fullName:    _nameController.text.trim(),
        age:         int.parse(_ageController.text.trim()),
        bloodGroup:  _bloodGroup!,
        homeAddress: _addressController.text.trim(),
        phone:       _phone,
      );
      await ProfileRepository.instance.saveEmergencyContact(
        userId:          userId,
        contactName:     _ecNameController.text.trim(),
        contactNumber:   ecFormatted,
        relationship:    _ecRelationship!,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _justSaved = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _justSaved = false);
      });
      _showSnack('Profile saved.');
    } on PostgrestException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (_) {
      if (mounted) _showSnack('Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('sign out?'),
        content: const Text('The guardian stops watching until you sign back in.'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'stay',
                  icon: null,
                  height: 52,
                  bg: Wsf.ink4,
                  fg: Wsf.bone,
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  label: 'sign out',
                  icon: null,
                  height: 52,
                  bg: Wsf.coral,
                  fg: Wsf.coralDeep,
                  onTap: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocationService().clearLocation();
    await LocationService().dispose();
    await Supabase.instance.client.auth.signOut();
    // AuthShell swaps to the login screen underneath; clear this route off it.
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _showSnack(String msg) => wsfToast(context, msg);

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DitherField(
            color: Wsf.volt,
            interactive: false,
            cell: 9,
            base: 0.02,
            intensity: 0.75,
            waves: const [
              DitherWave(origin: Offset(0.5, 0.12), wavelength: 100, speed: 0.22, amplitude: 0.7, reach: 460),
            ],
            mask: DitherMasks.fadeDown(0.4),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      DiscButton(
                        icon: Icons.arrow_back_rounded,
                        size: 44,
                        bg: Wsf.ink3,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      if (!_loading)
                        PillButton(
                          label: 'save',
                          expand: false,
                          height: 44,
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onTap: _saving ? null : _save,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: GuardianOrb(size: 120, mood: OrbMood.listening, interactive: false),
                        )
                      : Form(
                          key: _formKey,
                          child: ListView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            children: [
                              Center(
                                child: GuardianOrb(
                                  size: 132,
                                  mood: _justSaved ? OrbMood.happy : OrbMood.calm,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Eyebrow('you'),
                                    const SizedBox(height: 10),
                                    Headline(
                                      name.isEmpty ? 'your profile' : name.split(' ').first.toLowerCase(),
                                      name.contains(' ')
                                          ? name.substring(name.indexOf(' ') + 1).toLowerCase()
                                          : null,
                                      size: 54,
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (_phone != null && _phone!.isNotEmpty)
                                          Tag(_phone!, bg: Wsf.bone, outlined: true, icon: Icons.phone_rounded),
                                        if (_bloodGroup != null)
                                          Tag(_bloodGroup!, bg: Wsf.coral, fg: Wsf.coralDeep, icon: Icons.water_drop_rounded),
                                        if (_ageController.text.isNotEmpty) Tag('${_ageController.text} yrs'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 26),
                              FadeSlide(
                                delay: const Duration(milliseconds: 120),
                                child: ReceiptCard(
                                  label: '01 · about you',
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      WsfField(
                                        label: 'full name',
                                        controller: _nameController,
                                        hint: 'your full name',
                                        textCapitalization: TextCapitalization.words,
                                        onChanged: (_) => setState(() {}),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty) ? 'REQUIRED' : null,
                                      ),
                                      const SizedBox(height: 18),
                                      WsfField(
                                        label: 'age',
                                        controller: _ageController,
                                        hint: '24',
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        onChanged: (_) => setState(() {}),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) return 'REQUIRED';
                                          final n = int.tryParse(v.trim());
                                          if (n == null || n < 1 || n > 120) {
                                            return 'ENTER AN AGE FROM 1 TO 120';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 18),
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4, bottom: 10),
                                        child: Eyebrow('blood type'),
                                      ),
                                      ChoiceChips<String>(
                                        options: _bloodGroups,
                                        value: _bloodGroup,
                                        columns: 4,
                                        height: 54,
                                        onChanged: (v) => setState(() => _bloodGroup = v),
                                      ),
                                      const SizedBox(height: 18),
                                      WsfField(
                                        label: 'home address',
                                        controller: _addressController,
                                        hint: 'street, area, city',
                                        maxLines: 3,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty) ? 'REQUIRED' : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              FadeSlide(
                                delay: const Duration(milliseconds: 220),
                                child: ReceiptCard(
                                  label: '02 · your person',
                                  trailing: const Tag('gets the sos', bg: Wsf.coral, fg: Wsf.coralDeep),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      WsfField(
                                        label: 'their name',
                                        controller: _ecNameController,
                                        hint: 'someone you trust',
                                        textCapitalization: TextCapitalization.words,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty) ? 'REQUIRED' : null,
                                      ),
                                      const SizedBox(height: 18),
                                      WsfField(
                                        label: 'their number',
                                        controller: _ecNumberController,
                                        hint: '98765 43210',
                                        keyboardType: TextInputType.phone,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
                                        ],
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) return 'REQUIRED';
                                          if (_formatPhone(v) == null) {
                                            return 'THAT NUMBER LOOKS OFF';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 18),
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4, bottom: 10),
                                        child: Eyebrow('they are your'),
                                      ),
                                      ChoiceChips<String>(
                                        options: _relationships,
                                        value: _ecRelationship,
                                        height: 46,
                                        labelOf: (r) => r.toLowerCase(),
                                        onChanged: (v) => setState(() => _ecRelationship = v),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              PillButton(
                                label: 'sign out',
                                bg: Wsf.ink3,
                                fg: Wsf.coral,
                                icon: Icons.logout_rounded,
                                onTap: _signOut,
                              ),
                              const SizedBox(height: 18),
                              const Center(child: Eyebrow('wsf · women safety framework', color: Wsf.boneFaint)),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
