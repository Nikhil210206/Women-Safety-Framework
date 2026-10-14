import 'package:flutter/foundation.dart';

/// Offline walkthrough of the whole app, with no Supabase account behind it:
///
///   flutter run --release -d <device> --dart-define=DEMO_MODE=true
///
/// Login accepts any input and skips the SMS code. The profile and emergency
/// contact are kept in memory by [DemoSession], so the whole flow is walkable
/// and every launch starts again from the intro.
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

class DemoSession extends ChangeNotifier {
  DemoSession._();
  static final DemoSession instance = DemoSession._();

  static const String userId = 'demo-user';

  bool _signedIn = false;
  String? name;
  String? phone;
  Map<String, dynamic>? profile;
  Map<String, dynamic>? contact;
  bool registrationComplete = false;

  bool get signedIn => _signedIn;

  void signIn({String? name, String? phone}) {
    this.name = (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    this.phone = phone;
    _signedIn = true;
    notifyListeners();
  }

  void signOut() {
    _signedIn = false;
    name = null;
    phone = null;
    profile = null;
    contact = null;
    registrationComplete = false;
    notifyListeners();
  }
}
