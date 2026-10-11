// Design gallery: every WSF screen and component, runnable without the map,
// the microphone or a backend. Useful for reviewing UI on any device, including
// a browser:
//
//   flutter run -t lib/dev/gallery.dart
//   flutter build web -t lib/dev/gallery.dart
//
// On the web, jump straight to an entry with its route, e.g. `/#/intro`.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/alerts.dart';
import '../screens/chat_overlay.dart';
import '../screens/intro_screen.dart';
import '../screens/login_screen.dart';
import '../screens/onboarding_emergency_contact_screen.dart';
import '../screens/onboarding_personal_info_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/splash_screen.dart';
import '../theme/wsf.dart';
import '../ui/dither.dart';
import '../ui/guardian_orb.dart';
import '../ui/home_chrome.dart';
import '../ui/kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Wsf.warmFonts();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Services read dotenv in their constructors; an empty env is enough here.
    dotenv.testLoad(fileInput: '');
  }
  // Screens reach for Supabase.instance; give them an inert client.
  await Supabase.initialize(url: 'https://gallery.invalid', anonKey: 'gallery');
  runApp(const GalleryApp());
}

typedef _Entry = ({String id, String label, WidgetBuilder builder});

final List<_Entry> _entries = [
  (id: 'splash', label: 'startup animation', builder: (_) => const _SplashLoop()),
  (id: 'intro', label: 'intro story', builder: (c) => IntroScreen(onDone: () => Navigator.maybePop(c))),
  (id: 'login', label: 'login', builder: (_) => const LoginScreen()),
  (id: 'setup', label: 'set-up · about you', builder: (c) => OnboardingPersonalInfoScreen(onComplete: () => Navigator.maybePop(c))),
  (id: 'person', label: 'set-up · your person', builder: (c) => OnboardingEmergencyContactScreen(onComplete: () => Navigator.maybePop(c))),
  (id: 'done', label: 'set-up · done', builder: (c) => SetupDoneScreen(firstName: 'Ananya', contactName: 'Mom', onContinue: () => Navigator.maybePop(c))),
  (id: 'home', label: 'home chrome', builder: (_) => const _HomeMock()),
  (id: 'sos', label: 'alert · sos countdown', builder: (_) => const SosCountdownDialog()),
  (id: 'drift', label: 'alert · off route', builder: (_) => const DriftSosOverlay()),
  (id: 'audio', label: 'alert · threat heard', builder: (_) => const AudioThreatOverlay(label: 'Screaming', confidence: 0.92)),
  (id: 'chat', label: 'chat', builder: (_) => const _ChatMock()),
  (id: 'profile', label: 'profile', builder: (_) => const ProfileScreen()),
  (id: 'orb', label: 'guardian moods', builder: (_) => const _OrbMoods()),
  (id: 'kit', label: 'components', builder: (_) => const _KitPage()),
];

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WSF gallery',
        debugShowCheckedModeBanner: false,
        theme: Wsf.theme(),
        // On the web, `/#/intro` opens that entry directly.
        onGenerateRoute: (settings) {
          final id = (settings.name ?? '/').replaceAll('/', '');
          final entry = _entries.where((e) => e.id == id).firstOrNull;
          return MaterialPageRoute(
            settings: settings,
            builder: entry?.builder ?? (_) => const _Menu(),
          );
        },
      );
}

class _Menu extends StatelessWidget {
  const _Menu();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Wsf.gutter),
            children: [
              const Wordmark(size: 40),
              const SizedBox(height: 6),
              const Eyebrow('design gallery'),
              const SizedBox(height: 28),
              for (final (i, e) in _entries.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PillButton(
                    label: e.label,
                    bg: i == 0 ? Wsf.volt : Wsf.ink3,
                    fg: i == 0 ? Wsf.voltDeep : Wsf.bone,
                    onTap: () => Navigator.pushNamed(context, '/${e.id}'),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Replays the splash over a stand-in app so the exit wipe has something to
/// open onto.
class _SplashLoop extends StatefulWidget {
  const _SplashLoop();

  @override
  State<_SplashLoop> createState() => _SplashLoopState();
}

class _SplashLoopState extends State<_SplashLoop> {
  int _run = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            body: Center(
              child: PillButton(
                expand: false,
                label: 'replay',
                icon: Icons.replay_rounded,
                onTap: () => setState(() {
                  _run++;
                  _done = false;
                }),
              ),
            ),
          ),
          if (!_done)
            SplashScreen(key: ValueKey(_run), onReady: () {}, onDone: () => setState(() => _done = true)),
        ],
      );
}

class _OrbMoods extends StatelessWidget {
  const _OrbMoods();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in OrbMood.values)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GuardianOrb(size: 132, mood: m),
                    const SizedBox(height: 6),
                    Eyebrow(m.name),
                  ],
                ),
            ],
          ),
        ),
      );
}

class _KitPage extends StatefulWidget {
  const _KitPage();

  @override
  State<_KitPage> createState() => _KitPageState();
}

class _KitPageState extends State<_KitPage> {
  String? _blood = 'O+';
  bool _right = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            DitherField(color: Wsf.volt, intensity: 0.5, mask: DitherMasks.fadeDown(0.5)),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(Wsf.gutter),
                children: [
                  const Eyebrow('01 · type'),
                  const SizedBox(height: 12),
                  const Headline('walk home.', "we've got you."),
                  const SizedBox(height: 28),
                  const Eyebrow('02 · actions'),
                  const SizedBox(height: 12),
                  PillButton(label: 'start walking', onTap: () {}),
                  const SizedBox(height: 10),
                  PillButton(label: 'send code', bg: Wsf.bone, fg: Wsf.ink, onTap: () {}),
                  const SizedBox(height: 10),
                  PillButton(label: 'send sos now', bg: Wsf.coral, fg: Wsf.coralDeep, onTap: () {}),
                  const SizedBox(height: 28),
                  const Eyebrow('03 · inputs'),
                  const SizedBox(height: 12),
                  WsfField(label: 'full name', controller: _text, hint: 'what do we call you?'),
                  const SizedBox(height: 16),
                  ChoiceChips<String>(
                    options: const ['A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−'],
                    value: _blood,
                    columns: 4,
                    big: true,
                    onChanged: (v) => setState(() => _blood = v),
                  ),
                  const SizedBox(height: 16),
                  SegmentedPill(
                    left: 'new here',
                    right: 'been here',
                    isRight: _right,
                    onChanged: (v) => setState(() => _right = v),
                  ),
                  const SizedBox(height: 28),
                  const Eyebrow('04 · surfaces'),
                  const SizedBox(height: 12),
                  ReceiptCard(
                    label: 'your zone',
                    trailing: const Tag('live'),
                    child: Text('calm right now', style: Wsf.display(30)),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tag('safe route'),
                      Tag('caution', bg: Wsf.amber, fg: Wsf.amberDeep),
                      Tag('high risk', bg: Wsf.coral, fg: Wsf.coralDeep),
                      Tag('on-device', bg: Wsf.bone, outlined: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// The home screen's chrome over a stand-in map. Tap the guardian to cycle
/// through calm, caution and danger.
class _HomeMock extends StatefulWidget {
  const _HomeMock();

  @override
  State<_HomeMock> createState() => _HomeMockState();
}

class _HomeMockState extends State<_HomeMock> {
  ZoneState _zone = ZoneState.calm;
  bool _heat = true;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _FakeMapPainter()),
          Positioned(
            top: top + 10,
            left: 12,
            right: 12,
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                color: Wsf.ink,
                borderRadius: BorderRadius.circular(31),
                border: Border.all(color: Wsf.line, width: 2),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(color: Wsf.volt, shape: BoxShape.circle),
                    child: const Icon(Icons.search_rounded, color: Wsf.voltDeep, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('where to?', style: Wsf.body(size: 17, color: Wsf.bone, weight: FontWeight.w500)),
                  ),
                  const Eyebrow('safest route'),
                  const SizedBox(width: 18),
                ],
              ),
            ),
          ),
          Positioned(
            top: top + 86,
            right: 12,
            child: MapDock(
              actions: [
                DockAction(icon: Icons.blur_on_rounded, active: _heat, onTap: () => setState(() => _heat = !_heat)),
                DockAction(icon: Icons.chat_bubble_rounded, onTap: () {}),
                DockAction(icon: Icons.campaign_rounded, onTap: () {}),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 330,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Wsf.expoOut,
                  color: _zone.bg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetHandle(color: _zone.dim.withValues(alpha: 0.5)),
                      StatusHeader(
                        zone: _zone,
                        listening: true,
                        onOrbTap: () => setState(
                          () => _zone = ZoneState.values[(_zone.index + 1) % ZoneState.values.length],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                          decoration: const BoxDecoration(
                            color: Wsf.ink,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Eyebrow('nearby · safe spots'),
                              const SizedBox(height: 12),
                              SafeSpotTile(
                                icon: Icons.local_police_rounded,
                                title: 'Narsingi Police Station',
                                distanceKm: 0.4,
                                address: 'Narsingi Main Rd, Hyderabad',
                                onTap: () {},
                              ),
                              SafeSpotTile(
                                icon: Icons.local_hospital_rounded,
                                title: 'Continental Hospitals',
                                distanceKm: 1.2,
                                address: 'Financial District, Hyderabad',
                                onTap: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavDock(index: 0, onHome: () {}, onSos: () => Navigator.pushNamed(context, '/sos'), onProfile: () {}),
    );
  }
}

class _FakeMapPainter extends CustomPainter {
  const _FakeMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0D0F0B));
    final road = Paint()
      ..color = const Color(0xFF1E211A)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (var i = -2; i < 9; i++) {
      canvas.drawLine(Offset(i * 70.0, 0), Offset(i * 70.0 + 160, size.height), road);
      canvas.drawLine(Offset(0, i * 110.0 + 40), Offset(size.width, i * 110.0 - 30), road);
    }
    void zone(Offset c, double r, Color color) {
      const cell = 6.0;
      final dots = Paint()
        ..color = color
        ..strokeCap = StrokeCap.round;
      final n = (r / cell).ceil();
      for (var j = -n; j <= n; j++) {
        for (var i = -n; i <= n; i++) {
          final p = Offset((i + 0.5) * cell, (j + 0.5) * cell);
          if (p.distance > r) continue;
          final level = ditherLevel(0.7, i + n, j + n);
          dots.strokeWidth = cell * (0.2 + level * 0.14);
          canvas.drawCircle(c + p, dots.strokeWidth / 2, dots);
        }
      }
      canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: 0.13));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = color,
      );
    }

    zone(Offset(size.width * 0.3, size.height * 0.3), 74, Wsf.coral);
    zone(Offset(size.width * 0.72, size.height * 0.44), 58, Wsf.amber);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.5), 22, Paint()..color = Wsf.volt.withValues(alpha: 0.25));
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.5), 8, Paint()..color = Wsf.volt);
  }

  @override
  bool shouldRepaint(_FakeMapPainter old) => false;
}

class _ChatMock extends StatelessWidget {
  const _ChatMock();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _FakeMapPainter()),
            Align(alignment: Alignment.bottomCenter, child: ChatOverlay(lat: 17.3422, lng: 78.3663)),
          ],
        ),
      );
}
