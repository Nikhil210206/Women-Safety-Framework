import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories/profile_repository.dart';
import 'screens/home_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_emergency_contact_screen.dart';
import 'screens/onboarding_personal_info_screen.dart';
import 'screens/splash_screen.dart';
import 'services/demo_mode.dart';
import 'services/location_service.dart';
import 'theme/wsf.dart';
import 'ui/guardian_orb.dart';
import 'ui/kit.dart';

const bool _kBypassAuth = bool.fromEnvironment('BYPASS_AUTH');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
  if (mapboxToken.isNotEmpty) {
    MapboxOptions.setAccessToken(mapboxToken);
  }

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  runApp(const WsfApp());
}

class WsfApp extends StatelessWidget {
  const WsfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WSF',
      debugShowCheckedModeBanner: false,
      theme: Wsf.theme(),
      home: const _Root(),
    );
  }
}

/// Plays the startup animation over the app. The app itself is mounted
/// underneath once the splash is fully opaque, so it is laid out and ready by
/// the time the exit wipe opens onto it.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _appMounted = false;
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          if (_appMounted) const AuthShell() else const ColoredBox(color: Wsf.ink),
          if (!_splashDone)
            SplashScreen(
              onReady: () => setState(() => _appMounted = true),
              onDone: () => setState(() => _splashDone = true),
            ),
        ],
      );
}

// An unreachable server can hold a request open for a minute or more; the
// loading screen gives up on the profile check after this long.
const Duration _kProfileCheckTimeout = Duration(seconds: 8);

// ── Onboarding routing state ──────────────────────────────────────────────────

enum _OnboardingStep {
  checking,          // async profile check in progress
  needsPersonalInfo, // Step 1 not done
  needsEmergencyContact, // Step 1 done, Step 2 not done
  complete,          // both steps done → HomeScreen
}

// ── AuthShell ─────────────────────────────────────────────────────────────────

class AuthShell extends StatefulWidget {
  const AuthShell({super.key});

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  StreamSubscription<AuthState>? _authSub;

  Session? _session;
  _OnboardingStep _step = _OnboardingStep.checking;

  // The intro story opens the app for anyone who has not finished setting up:
  // on every launch while signed out or part-way through setup, and again
  // after signing out. Nothing is remembered between launches.
  bool _introSeen = false;

  void _finishIntro() => setState(() => _introSeen = true);

  /// Demo build: the "session" is the in-memory [DemoSession], not Supabase.
  void _onDemoChanged() {
    if (!mounted) return;
    final demo = DemoSession.instance;
    if (demo.signedIn) {
      setState(() => _step = _OnboardingStep.checking);
      _checkOnboardingStatus(DemoSession.userId);
    } else {
      setState(() {
        _step = _OnboardingStep.complete;
        _introSeen = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (kDemoMode) {
      DemoSession.instance.addListener(_onDemoChanged);
      _step = _OnboardingStep.complete; // state irrelevant until signed in
      return;
    }
    _session = Supabase.instance.client.auth.currentSession;

    // If the app was opened with an existing session, kick off the check now.
    if (_session != null) {
      _checkOnboardingStatus(_session!.user.id);
    } else {
      _step = _OnboardingStep.complete; // state irrelevant when not signed in
    }

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;

      if (data.session == null && _session != null) {
        // Session ended — clear live-location beacon and stop tracking.
        LocationService().clearLocation();
        setState(() {
          _session = null;
          _step = _OnboardingStep.complete; // reset; LoginScreen doesn't use it
          _introSeen = false;
        });
        return;
      }

      if (data.session != null && data.session!.user.id != _session?.user.id) {
        // New sign-in (or token refresh for a different user) — re-check profile.
        setState(() {
          _session = data.session;
          _step = _OnboardingStep.checking;
        });
        _checkOnboardingStatus(data.session!.user.id);
        return;
      }

      setState(() => _session = data.session);
    });
  }

  Future<void> _checkOnboardingStatus(String userId) async {
    try {
      // registration_complete is the single official gate. If it's set, the
      // user is fully onboarded — go straight to Home.
      final registrationDone = await ProfileRepository.instance
          .isRegistrationComplete(userId)
          .timeout(_kProfileCheckTimeout);

      if (!mounted) return;

      if (registrationDone) {
        setState(() => _step = _OnboardingStep.complete);
        return;
      }

      // Not complete — figure out which step to resume from. Personal info
      // (age) is Step 1; the emergency contact is Step 2.
      final personalDone = await ProfileRepository.instance
          .isPersonalInfoComplete(userId)
          .timeout(_kProfileCheckTimeout);

      if (!mounted) return;

      setState(() => _step = personalDone
          ? _OnboardingStep.needsEmergencyContact
          : _OnboardingStep.needsPersonalInfo);
    } catch (_) {
      // Network failure or timeout during check — let the user through rather
      // than blocking them on a loading spinner indefinitely.
      if (mounted) setState(() => _step = _OnboardingStep.complete);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    DemoSession.instance.removeListener(_onDemoChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dev-only UI preview: flutter run --dart-define=BYPASS_AUTH=true
    if (_kBypassAuth) return const HomeScreen();

    final (String name, Widget screen) = _route();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      switchInCurve: Wsf.expoOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.965, end: 1.0).animate(anim), child: child),
      ),
      child: KeyedSubtree(key: ValueKey(name), child: screen),
    );
  }

  (String, Widget) _route() {
    final signedIn = kDemoMode ? DemoSession.instance.signedIn : _session != null;
    final settingUp = _step == _OnboardingStep.needsPersonalInfo ||
        _step == _OnboardingStep.needsEmergencyContact;

    // Intro first, then on to wherever they left off (login or a setup step).
    if (!_introSeen && (!signedIn || settingUp)) {
      return ('intro', IntroScreen(onDone: _finishIntro));
    }

    // Not signed in.
    if (!signedIn) return ('login', const LoginScreen());

    // Signed in — route based on onboarding state.
    switch (_step) {
      case _OnboardingStep.checking:
        return ('loading', const _LoadingShell());

      case _OnboardingStep.needsPersonalInfo:
        return (
          'personal',
          OnboardingPersonalInfoScreen(
            onComplete: () {
              final userId = kDemoMode ? DemoSession.userId : _session?.user.id;
              if (userId == null) return;
              setState(() => _step = _OnboardingStep.checking);
              _checkOnboardingStatus(userId);
            },
          ),
        );

      case _OnboardingStep.needsEmergencyContact:
        return (
          'contact',
          OnboardingEmergencyContactScreen(
            onComplete: () => setState(() => _step = _OnboardingStep.complete),
          ),
        );

      case _OnboardingStep.complete:
        return ('home', const HomeScreen());
    }
  }
}

// ── Thin loading screen shown while the profile check runs ───────────────────

class _LoadingShell extends StatelessWidget {
  const _LoadingShell();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GuardianOrb(size: 120, mood: OrbMood.listening, interactive: false),
            SizedBox(height: 12),
            Eyebrow('one sec'),
          ],
        ),
      ),
    );
  }
}
