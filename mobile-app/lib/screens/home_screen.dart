import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
// 1. HIDE 'Size' from Mapbox to avoid conflict with Flutter's Size
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:permission_handler/permission_handler.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:mobile_app/theme/wsf.dart';
import 'package:mobile_app/ui/home_chrome.dart';
import 'package:mobile_app/ui/kit.dart';
import 'package:mobile_app/ui/motion.dart';
import 'package:mobile_app/services/zone_layers.dart';
import 'package:mobile_app/screens/alerts.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:mobile_app/services/api_service.dart';
import 'package:mobile_app/services/mapbox_service.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_app/services/audio_sentinel_service.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:mobile_app/services/geofence_service.dart';
import 'package:mobile_app/services/location_service.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io' show Platform;
import 'profile_screen.dart';
// AI integration — isolated service + overlay (do not modify api_service.dart)
import 'package:mobile_app/services/ai_api_service.dart';
import 'package:mobile_app/screens/chat_overlay.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:perfect_volume_control/perfect_volume_control.dart';

/// Draws sample risk zones when the database returns none, so the map styling
/// can be reviewed offline: flutter run --dart-define=DEMO_ZONES=true
const bool _kDemoZones = bool.fromEnvironment('DEMO_ZONES');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const EventChannel _volumeButtonChannel =
      EventChannel('wsf/hardware_buttons');
  MapboxMap? mapboxMap;
  PolylineAnnotationManager? _polylineManager;
  CircleAnnotationManager? _circleManager;
  ZoneLayers? _zoneLayers;
  bool _demoZonesShown = false;

  final ApiService _apiService = ApiService();
  final MapboxService _mapboxService = MapboxService();
  // AI deterrent
  final AiApiService _aiApiService = AiApiService();
  final AudioPlayer _deterrentPlayer = AudioPlayer();
  bool _isDeterrentLoading = false;

  // Audio Sentinel Service
  final AudioSentinelService _audioSentinel = AudioSentinelService();

  // Text Controllers
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  // Focus Nodes
  final FocusNode _startFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();
  Timer? _debounce;

  // Coordinates
  // _cameraLat/_cameraLng are ONLY used for the initial MapWidget cameraOptions.
  // They are intentionally never updated so that setState calls from location
  // updates do not cause MapWidget to reapply cameraOptions and jump the camera.
  static const double _cameraLat = 17.3422;
  static const double _cameraLng = 78.3663;

  double _startLat = 17.3422; // Lords default — updated by real GPS
  double _startLng = 78.3663;
  double? _destLat;
  double? _destLng;

  // Set true once the camera has auto-centered on the first valid GPS fix, so
  // we center exactly once and never fight the user panning the map afterwards.
  bool _hasCenteredOnUser = false;

  // Search Box API state
  List<Map<String, dynamic>> _suggestions = [];
  String _searchSessionToken = '';
  bool _isSearchLoading = false;

  // Destination preview state (pin placed, waiting for user to confirm route)
  bool _isPendingRoute = false;
  String _pendingDestName = '';
  Map<String, dynamic>? _pendingRouteData; // cached route result shown during preview
  bool _isRouteFetching = false; // guard: prevent concurrent _fetchAndDrawRoute calls
  DateTime? _lastAudioIncidentAt;   // cooldown: one incident per 30 s maximum
  String?   _activeAudioIncidentId; // id of the open audio incident (cleared on resolve)
  bool      _audioAlertShowing = false; // guard: prevent stacked overlays

  // State Variables
  bool _isRouteActive = false;
  bool _isTracking = false;
  bool _isInputExpanded = false;
  bool _isNightMode = true; // the app opens on the dark map
  bool _isRouteSafe = true;
  int _riskScore = 0;
  double _durationMin = 0;

  // Multi-factor risk engine fields
  String _riskLevel = 'low';       // 'low' | 'medium' | 'high'
  String _riskExplanation = '';
  int _highRiskSegmentCount = 0;

  List<Position> _currentRouteGeometry = [];
  String? _activeTripId;
  StreamSubscription? _volumeDownSubscription;
  final List<DateTime> _volumeDownPresses = [];
  bool _isImmediateSosDispatching = false;

  // ✅ NEW: Zone Logic Variables
  List<dynamic> _activeZones = [];
  List<Map<String, dynamic>> _safeHavens = [];

  // Heatmap
  bool _showHeatmap = false;
  List<Map<String, dynamic>> _heatmapZones = [];
  ZoneState _zone = ZoneState.calm;

  int _navIndex = 0;

  // Slide animations for bottom panel + nav bar when search is open
  late AnimationController _bottomSlideController;
  late Animation<Offset> _bottomSlideAnimation;
  final PanelController _panelController = PanelController();
  final ScrollController _sheetScroll = ScrollController();

  /// How far the home sheet is pulled up, 0..1. Drives the map chrome fade.
  final ValueNotifier<double> _sheetT = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _bottomSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bottomSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1),
    ).animate(CurvedAnimation(
      parent: _bottomSlideController,
      curve: Curves.easeInOut,
    ));
    _startController.text = "Current Location";
    _initAudioSentinel();
    _initVolumeDownOverride();
    _ensureProfile(); // upsert profile row so display is always fresh for this user
    _requestPermissions().then((_) => _initBackgroundTracking());
  }

  @override
  void dispose() {
    if (_activeTripId != null) {
      Supabase.instance.client
          .from('trips')
          .update({
            'status': 'completed',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _activeTripId!)
          .catchError((_) {});
    }
    _startController.dispose();
    _destinationController.dispose();
    _startFocus.dispose();
    _destinationFocus.dispose();
    _debounce?.cancel();
    _volumeDownSubscription?.cancel();
    _audioSentinel.stopListening();
    _deterrentPlayer.dispose();
    _zoneLayers?.dispose();
    _sheetScroll.dispose();
    _sheetT.dispose();
    _bottomSlideController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.microphone,
    ].request();
  }

  /// Upserts the profiles row from live auth metadata every time HomeScreen mounts.
  /// Ensures the display name/phone is always current for the logged-in user,
  /// and creates the row for users who signed up before the auth trigger existed.
  Future<void> _ensureProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final metaName = user.userMetadata?['full_name'] as String?;
    await Supabase.instance.client.from('profiles').upsert({
      'id': user.id,
      'full_name': metaName,
      'phone': user.phone,
    }, onConflict: 'id').catchError((_) {});
  }

  void _initAudioSentinel() async {
    await _audioSentinel.initialize();
    _audioSentinel.onDangerDetected = (event, confidence) async {
      print('=== AUDIO DANGER DETECTED ===');
      print('Label: $event');
      print('Confidence: $confidence');

      // Write incident to Supabase — once per 30 s max (sustained sounds re-trigger).
      final now = DateTime.now();
      final bool cooledDown = _lastAudioIncidentAt == null ||
          now.difference(_lastAudioIncidentAt!) > const Duration(seconds: 30);

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (cooledDown && userId != null) {
        _lastAudioIncidentAt = now;
        print('[AudioSentinel] Writing incident to Supabase...');
        try {
          final insertResult = await supabase.from('incidents').insert({
            'user_id':      userId,
            'source':       'audio',
            'severity':     'high',
            'status':       'open',
            'latitude':     _startLat,
            'longitude':    _startLng,
            'notes':        'Audio threat detected: $event (${(confidence * 100).toStringAsFixed(0)}% confidence)',
            'display_name': supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'SENTRA user',
          }).select('id').single();
          _activeAudioIncidentId = insertResult['id'] as String?;
          print('[AudioSentinel] Incident written OK (id: $_activeAudioIncidentId)');
        } catch (e) {
          print('[AudioSentinel] ❌ Incident write FAILED: $e');
        }
        // Show overlay only after a confirmed insert, and never stack them.
        if (mounted && ModalRoute.of(context)?.isCurrent == true && !_audioAlertShowing) {
          _showAudioAlert(event, confidence);
        }
      } else if (userId == null) {
        print('[AudioSentinel] ⚠️ No authenticated user — incident not written');
      } else {
        print('[AudioSentinel] Cooldown active — skipping duplicate');
      }
    };
    _audioSentinel.startListening();
    setState(() {});
  }

  void _showAudioAlert(String label, double confidence) async {
    _audioAlertShowing = true;
    final bool isSafe = await showGeneralDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierColor: const Color(0xF0CC0000),
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (ctx, anim1, anim2) =>
              AudioThreatOverlay(label: label, confidence: confidence),
        ) ??
        false;
    _audioAlertShowing = false;

    if (isSafe) {
      // User confirmed they're safe — resolve the incident so dashboard clears it.
      final incidentId = _activeAudioIncidentId;
      if (incidentId != null) {
        try {
          await Supabase.instance.client.from('incidents').update({
            'status':      'resolved',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', incidentId);
          print('[AudioSentinel] Incident $incidentId resolved');
        } catch (e) {
          print('[AudioSentinel] ❌ Resolve failed: $e');
        }
        if (mounted) setState(() => _activeAudioIncidentId = null);
      }
    } else {
      _handleSosSequence(
        triggerReason: 'Audio threat detected: ${label.toUpperCase()}',
      );
    }
  }

  void _initVolumeDownOverride() {
    if (!Platform.isAndroid) return;
    try {
      _volumeDownSubscription =
          _volumeButtonChannel.receiveBroadcastStream().listen(
        (_) => _onVolumeDownPressed(),
        onError: (error) {
          print('Volume button listener error: $error');
        },
      );
    } catch (e) {
      print('Hardware buttons error: $e');
    }
  }

  void _onVolumeDownPressed() {
    final now = DateTime.now();
    _volumeDownPresses.add(now);
    _volumeDownPresses.removeWhere(
      (pressedAt) => now.difference(pressedAt) > const Duration(seconds: 2),
    );

    if (_volumeDownPresses.length >= 3) {
      _volumeDownPresses.clear();
      _triggerImmediateSosBypass();
    }
  }

  // ✅ NEW: Geofence OS Tracking Engine
  void _initBackgroundTracking() async {
    final geofenceService = GeofenceService();

    geofenceService.onDangerZoneTrigger = (bg.GeofenceEvent event) {
      if (mounted) {
        setState(() {
          if (event.action == "ENTER") {
            String severity =
                event.extras != null && event.extras!['risk_level'] != null
                    ? event.extras!['risk_level']
                    : "red";

            _zone = (severity == "yellow" || severity == "MODERATE")
                ? ZoneState.caution
                : ZoneState.danger;
          } else if (event.action == "EXIT") {
            _zone = ZoneState.calm;
          }
        });
      }
    };

    geofenceService.onDriftAlert = () {
      if (mounted) {
        _showDriftOverlay();
      }
    };

    // LocationService is the SINGLE filtered source of position. It is the only
    // code path allowed to set _startLat/_startLng from GPS. Fixes arriving here
    // have already passed the accuracy (≤100 m) and jump (≤50 km) gates.
    LocationService().onLocationUpdate = (lat, lng, heading, speed) {
      if (!mounted) return;
      final bool isFirstFix = !_hasCenteredOnUser;
      setState(() {
        _startLat = lat;
        _startLng = lng;
      });
      // Center the camera exactly once, on the first valid fix.
      if (isFirstFix) {
        _hasCenteredOnUser = true;
        if (_demoZonesShown) _loadDangerZones();
        mapboxMap?.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(lng, lat)),
            zoom: 15.0,
          ),
          MapAnimationOptions(duration: 1000),
        );
      }
    };

    // Order matters: LocationService.initialize() calls ready()/start() on the
    // plugin, which must happen before GeofenceService adds geofences.
    await LocationService().initialize();
    await geofenceService.initialize();
    _loadSafeHavens();
  }

  _onMapCreated(MapboxMap mapboxMap) {
    this.mapboxMap = mapboxMap;

    // Disable scale bar and move all ornaments to bottom-left
    mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    mapboxMap.compass.updateSettings(CompassSettings(
      position: OrnamentPosition.BOTTOM_LEFT,
      marginBottom: 80,
      marginLeft: 8,
    ));
    mapboxMap.attribution.updateSettings(AttributionSettings(
      position: OrnamentPosition.BOTTOM_LEFT,
      marginBottom: 8,
      marginLeft: 8,
    ));
    mapboxMap.logo.updateSettings(LogoSettings(
      position: OrnamentPosition.BOTTOM_LEFT,
      marginBottom: 8,
      marginLeft: 96,
    ));

    // ✅ NEW: Enable the Blue Dot (Location Component)
    mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: Wsf.volt.toARGB32(),
        pulsingMaxRadius: 30.0,
      ),
    );

    _zoneLayers = ZoneLayers(mapboxMap);
    final hour = DateTime.now().hour;
    if (hour >= 20 || hour < 7) {
      setState(() => _showHeatmap = true);
    }
  }

  /// Runs on every style load. Layers added at runtime do not survive a style
  /// swap, so zones are re-attached and re-fed here. The annotation managers
  /// are created after the zone layers so routes and pins draw above zones.
  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = mapboxMap;
    if (map == null) return;
    if (_isNightMode) await _tintMap(map);
    await _zoneLayers?.attach();
    _polylineManager = await map.annotations.createPolylineAnnotationManager();
    _circleManager = await map.annotations.createCircleAnnotationManager();
    await _loadDangerZones();
    if (_showHeatmap) await _loadHeatmap();
  }

  /// Nudges the stock dark style toward the app's ink so the map and the
  /// chrome read as one surface. Best-effort: unknown layers are skipped.
  Future<void> _tintMap(MapboxMap map) async {
    Future<void> tint(String layer, String property, String hex) async {
      try {
        if (await map.style.styleLayerExists(layer)) {
          await map.style.setStyleLayerProperty(layer, property, hex);
        }
      } catch (_) {}
    }

    await tint('land', 'background-color', '#0d0f0b');
    await tint('water', 'fill-color', '#12201a');
    await tint('building', 'fill-color', '#151811');
  }

  // --- DANGER ZONES ---
  Future<void> _loadDangerZones() async {
    // Only use simulated time if you add temporal logic to get_active_zones
    int simulatedTime = _isNightMode ? 22 : 10;

    // In demo mode, draw the sample zones straight away rather than waiting
    // out a slow or failing fetch; real zones replace them if any arrive.
    if (_kDemoZones && _activeZones.isEmpty) {
      await _zoneLayers?.setZones(ZoneLayers.demoZones(_startLat, _startLng));
      if (mounted && !_demoZonesShown) setState(() => _demoZonesShown = true);
    }

    final zones = await _apiService.getDangerZones(
      simulatedHour: simulatedTime,
    );

    // Store raw zones for OS Geofencing
    _activeZones = zones;
    GeofenceService().setupPolygons(_activeZones);

    // With an empty database and DEMO_ZONES set, draw sample zones so the map
    // styling can be reviewed. They are display-only and never geofenced.
    final useDemo = zones.isEmpty && _kDemoZones;
    await _zoneLayers?.setZones(
      useDemo ? ZoneLayers.demoZones(_startLat, _startLng) : zones,
    );
    if (mounted && useDemo != _demoZonesShown) {
      setState(() => _demoZonesShown = useDemo);
    }
  }

  // --- AI DETERRENT ---

  /// Triggers the Sarvam Bulbul V3 audio deterrent.
  /// Adjustment #1: volume override BEFORE play, stop before play.
  /// Adjustment #2: instant state lock + haptic on press.
  /// Adjustment #3: synchronous cached GPS read — never hangs.
  Future<void> _triggerAiDeterrent() async {
    // #2 — Instant state lock prevents double-fire during API latency
    if (_isDeterrentLoading) return;
    HapticFeedback.vibrate(); // Immediate physical confirmation
    setState(() => _isDeterrentLoading = true);

    try {
      // #3 — Read cached location synchronously; never request a fresh GPS fix
      final cached = LocationService().getCurrentLocation();
      final double lat = cached?.lat ?? _startLat;
      final double lng = cached?.lng ?? _startLng;

      final data = await _aiApiService.triggerDeterrent(
        lat: lat,
        lng: lng,
        language: 'en-IN',
      );

      if (data == null || data.audioBase64.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deterrent unavailable. Stay alert.')),
          );
        }
        return;
      }

      // Decode Base64 → Uint8List in memory — no disk writes
      final bytes = base64Decode(data.audioBase64);

      // #1 — Await volume override COMPLETELY before play
      await PerfectVolumeControl.setVolume(1.0);
      // Stop any in-flight audio to prevent overlap
      await _deterrentPlayer.stop();
      // Play in-memory bytes via BytesSource
      await _deterrentPlayer.play(BytesSource(bytes));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data.script),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('[Deterrent] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deterrent failed. Triggering SOS.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeterrentLoading = false);
    }
  }

  void _openChatOverlay() {
    // #3 — Synchronous cached GPS read
    final cached = LocationService().getCurrentLocation();
    final double lat = cached?.lat ?? _startLat;
    final double lng = cached?.lng ?? _startLng;

    // #4 — isScrollControlled:true allows keyboard insets inside the sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatOverlay(lat: lat, lng: lng),
    );
  }

  // --- SOS LOGIC ---
  void _showDriftOverlay({String? dangerReason}) async {
    bool isSafe = await showGeneralDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withOpacity(0.95),
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, anim1, anim2) {
            return DriftSosOverlay(dangerReason: dangerReason);
          },
        ) ??
        false;

    if (!isSafe && _activeTripId != null) {
      // User didn't answer within 15 seconds!
      try {
        await Supabase.instance.client
            .from('trips')
            .update({'status': 'sos'}).eq('id', _activeTripId as String);
      } catch (e) {
        print("Failed to dispatch SOS to Db: $e");
      }
      _handleSosSequence(
          triggerReason: dangerReason ?? "No response after straying from expected route.");
    }
  }

  void _handleSosSequence({String? triggerReason}) async {
    // The countdown opens through a circle growing out of the SOS button.
    bool shouldSend = await Navigator.of(context).push<bool>(
          CircleRevealRoute(
            page: SosCountdownDialog(triggerReason: triggerReason),
            origin: const Alignment(0, 0.9),
          ),
        ) ??
        false;

    if (!mounted) return;
    if (shouldSend) {
      _launchSmsApp();
    } else {
      wsfToast(context, 'SOS cancelled.');
    }
  }

  Future<void> _launchSmsApp() async {
    const String emergencyNumber = "+919940903891";
    // ✅ Updated to send actual coordinates if available
    final String message =
        "SOS! I need help. My current location is: https://maps.google.com/?q=$_startLat,$_startLng";

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Opening SMS App..."),
        duration: Duration(seconds: 2),
      ),
    );

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: emergencyNumber,
      queryParameters: <String, String>{'body': message},
    );
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not launch SMS app."),
        ),
      );
    }
  }

  Future<void> _triggerImmediateSosBypass() async {
    if (_isImmediateSosDispatching) return;
    _isImmediateSosDispatching = true;

    GeofenceService().cancelDriftTimer();
    SosCountdownDialog.dismissIfActive();
    DriftSosOverlay.dismissIfActive();

    try {
      if (_activeTripId != null) {
        await Supabase.instance.client
            .from('trips')
            .update({'status': 'sos'}).eq('id', _activeTripId as String);
      } else {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          await Supabase.instance.client
              .from('trips')
              .update({'status': 'sos'})
              .eq('user_id', userId)
              .eq('status', 'active');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Emergency override activated. Security dispatched."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to dispatch emergency: $e")),
      );
    } finally {
      _isImmediateSosDispatching = false;
    }
  }

  // --- ROUTE LOGIC ---
  void _handleMapTap(MapContentGestureContext context) {
    final point = context.point;
    final double lat = point.coordinates.lat.toDouble();
    final double lng = point.coordinates.lng.toDouble();

    _bottomSlideController.forward();
    _panelController.hide();
    setState(() {
      _isInputExpanded = true;
      _destLat = lat;
      _destLng = lng;
      _destinationController.text =
          "${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}";
    });

    _fetchAndDrawRoute(lat, lng);
  }

  void _onSearchChanged(String query, bool isStart) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isSearchLoading = false;
      });
      return;
    }

    // Mint a new session token on the first keystroke of each search session.
    if (_searchSessionToken.isEmpty) {
      _searchSessionToken = 'session_${DateTime.now().millisecondsSinceEpoch}';
    }

    setState(() => _isSearchLoading = true);

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (query.trim().length < 2) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _isSearchLoading = false;
          });
        }
        return;
      }
      final results = await _mapboxService.searchPlaces(
        query,
        sessionToken: _searchSessionToken,
      );
      print(
          '[HomeScreen] Results count: ${results.length} for query: "$query"');
      if (mounted) {
        setState(() {
          _suggestions = results;
          _isSearchLoading = false;
        });
      }
    });
  }

  Future<void> _selectSuggestion(
      Map<String, dynamic> suggestion, bool isStart) async {
    final String mapboxId = suggestion['mapbox_id'] ?? '';
    final String displayName = suggestion['name'] ?? '';

    _startFocus.unfocus();
    _destinationFocus.unfocus();
    setState(() {
      _suggestions = [];
      _isSearchLoading = true;
      _isInputExpanded = false;
    });
    _bottomSlideController.reverse();
    _panelController.show();

    final place = await _mapboxService.retrievePlace(
      mapboxId,
      sessionToken: _searchSessionToken,
    );

    _searchSessionToken = '';

    if (!mounted) return;
    setState(() => _isSearchLoading = false);

    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Could not get location details. Try again.")),
      );
      return;
    }

    final double lat = place['lat'] as double;
    final double lng = place['lng'] as double;
    final String name = (place['name'] as String).isNotEmpty
        ? place['name'] as String
        : displayName;

    if (isStart) {
      setState(() {
        _startLat = lat;
        _startLng = lng;
        _startController.text = name;
      });
      return;
    }

    // Destination selected — place a red pin and fly camera before routing
    setState(() {
      _destLat = lat;
      _destLng = lng;
      _destinationController.text = name;
      _isPendingRoute = true;
      _pendingDestName = name;
    });

    // Drop destination pin (red-tinted)
    await _dropPin(lat, lng);

    // Fetch the real road-following route immediately so it's visible in preview
    await _fetchAndDrawRoute(lat, lng, isPreview: true);
  }

  Future<void> _fetchAndDrawRoute(double endLat, double endLng, {bool isPreview = false}) async {
    if (_isRouteFetching) {
      print('[Route] Skipping — fetch already in progress');
      return;
    }
    setState(() => _isRouteFetching = true);

    print('[Route] Origin: $_startLat, $_startLng');
    print('[Route] Destination: $endLat, $endLng');

    try {
    if (!mounted) return;  // finally still runs — _isRouteFetching cleared
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Finding the safest way..."),
        duration: Duration(seconds: 1),
      ),
    );
    await _polylineManager?.deleteAll();
    await _circleManager?.deleteAll();

    final result = await _apiService.getSafeRoute(
      _startLat,
      _startLng,
      endLat,
      endLng,
    );

    if (!mounted) return;

    if (result != null && result['status'] == 'success') {
      final route = result['recommended_route'];
      final String encodedPolyline = route['route_geometry'];
      final int safetyScore = (route['safety_score'] as num?)?.toInt() ?? 50;
      final double duration = (route['duration'] as num) / 60;
      final bool routeSafe = result['is_route_safe'] ?? true;

      // Multi-factor risk fields (new engine)
      final String riskLevel = result['risk_level'] as String? ?? route['risk_level'] as String? ?? 'low';
      final String explanation = result['explanation'] as String? ?? route['explanation'] as String? ?? '';
      final List highRiskSegs = result['high_risk_segments'] as List? ?? route['high_risk_segments'] as List? ?? [];

      PolylinePoints polylinePoints = PolylinePoints();
      List<PointLatLng> decodedPoints = polylinePoints.decodePolyline(encodedPolyline);
      List<Position> routeGeometry =
          decodedPoints.map((p) => Position(p.longitude, p.latitude)).toList();

      // Route colour follows the risk level. A wide blurred pass sits under
      // the crisp line so the route glows on the dark map.
      final int routeColor = riskLook(riskLevel).bg.toARGB32();
      _polylineManager?.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: routeGeometry),
          lineColor: routeColor,
          lineWidth: 16.0,
          lineOpacity: 0.28,
          lineBlur: 10.0,
          lineJoin: LineJoin.ROUND,
        ),
      );
      _polylineManager?.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: routeGeometry),
          lineColor: routeColor,
          lineWidth: 5.0,
          lineJoin: LineJoin.ROUND,
        ),
      );

      _dropPin(endLat, endLng);

      if (isPreview) {
        setState(() {
          _pendingRouteData = result;
          _currentRouteGeometry = routeGeometry;
          _isRouteSafe = routeSafe;
          _riskScore = 100 - safetyScore;
          _durationMin = duration;
          _riskLevel = riskLevel;
          _riskExplanation = explanation;
          _highRiskSegmentCount = highRiskSegs.length;
        });
      } else {
        setState(() {
          _isRouteActive = true;
          _isTracking = false;
          _isRouteSafe = routeSafe;
          _riskScore = 100 - safetyScore;
          _durationMin = duration;
          _currentRouteGeometry = routeGeometry;
          _riskLevel = riskLevel;
          _riskExplanation = explanation;
          _highRiskSegmentCount = highRiskSegs.length;
        });
      }

      // Fly camera to show the full route
      if (mapboxMap != null && routeGeometry.isNotEmpty) {
        final lngs = routeGeometry.map((p) => p.lng.toDouble());
        final lats = routeGeometry.map((p) => p.lat.toDouble());
        final minLng = lngs.reduce((a, b) => a < b ? a : b);
        final maxLng = lngs.reduce((a, b) => a > b ? a : b);
        final minLat = lats.reduce((a, b) => a < b ? a : b);
        final maxLat = lats.reduce((a, b) => a > b ? a : b);
        try {
          final camera = await mapboxMap!.cameraForCoordinateBounds(
            CoordinateBounds(
              southwest: Point(coordinates: Position(minLng - 0.005, minLat - 0.005)),
              northeast: Point(coordinates: Position(maxLng + 0.005, maxLat + 0.005)),
              infiniteBounds: false,
            ),
            MbxEdgeInsets(top: 80, left: 60, bottom: 160, right: 60),
            null, null, null, null,
          );
          await mapboxMap!.flyTo(camera, MapAnimationOptions(duration: 1000));
        } catch (_) {}
      }
    } else if (result != null && result['status'] == 'error') {
      final msg = result['message'] as String? ?? 'Routing failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Unable to calculate route: $msg")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Unable to calculate route. Please try a different destination."),
        ),
      );
    }
    } finally {
      if (mounted) setState(() => _isRouteFetching = false);
    }
  }

  void _toggleSimulationMode() {
    setState(() => _isNightMode = !_isNightMode);
    // _onStyleLoaded re-attaches the zone layers once the new style is in.
    mapboxMap?.loadStyleURI(_mapStyle);
  }

  String get _mapStyle => _isNightMode ? MapboxStyles.DARK : MapboxStyles.LIGHT;

  /// Marks a destination: a solid volt dot inside a soft halo.
  Future<void> _dropPin(double lat, double lng) async {
    await _circleManager?.deleteAll();
    final at = Point(coordinates: Position(lng, lat));
    await _circleManager?.createMulti([
      CircleAnnotationOptions(
        geometry: at,
        circleRadius: 17,
        circleColor: Wsf.volt.toARGB32(),
        circleOpacity: 0.25,
      ),
      CircleAnnotationOptions(
        geometry: at,
        circleRadius: 7,
        circleColor: Wsf.volt.toARGB32(),
        circleStrokeColor: Wsf.ink.toARGB32(),
        circleStrokeWidth: 3,
      ),
    ]);
  }

  Future<void> _loadSafeHavens() async {
    final token = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (token.isEmpty) return;

    const categories = ['police', 'hospital', 'pharmacy', 'fire_station'];
    final List<Map<String, dynamic>> results = [];

    for (final category in categories) {
      try {
        final url = Uri.parse(
          'https://api.mapbox.com/search/searchbox/v1/category/$category'
          '?access_token=$token'
          '&proximity=$_startLng,$_startLat'
          '&limit=2'
          '&language=en',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final features = data['features'] as List? ?? [];
          for (final f in features) {
            final coords = f['geometry']['coordinates'] as List;
            final props = f['properties'] as Map<String, dynamic>;
            final dist = _calculateDistance(
              _startLat, _startLng,
              coords[1].toDouble(), coords[0].toDouble(),
            );
            results.add({
              'name': props['name'] ?? category,
              'category': category,
              'distance': dist,
              'lat': coords[1].toDouble(),
              'lng': coords[0].toDouble(),
              'address': props['full_address'] ?? props['place_formatted'] ?? '',
            });
          }
        }
      } catch (e) {
        print('[SafeHavens] Failed to fetch $category: $e');
      }
    }

    results.sort((a, b) =>
        (a['distance'] as double).compareTo(b['distance'] as double));

    if (mounted) {
      setState(() {
        _safeHavens = results.take(4).toList();
      });
    }
  }

  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  void _selectDestinationFromSafeHaven(
      double lat, double lng, String name) {
    _circleManager?.deleteAll();
    _polylineManager?.deleteAll();
    setState(() {
      _destLat = lat;
      _destLng = lng;
      _destinationController.text = name;
      _isPendingRoute = true;
      _pendingDestName = name;
    });
    _fetchAndDrawRoute(lat, lng, isPreview: true);
  }

  // --- HEATMAP ---

  Future<void> _loadHeatmap() async {
    String city = 'hyderabad';
    if (_startLat >= 12.8 && _startLat <= 13.3 &&
        _startLng >= 80.0 && _startLng <= 80.4) {
      city = 'chennai';
    }
    print('Current location: $_startLat, $_startLng');
    print('Detected city: $city');
    final zones = await _apiService.getHeatmapZones(
      city: city,
      hour: DateTime.now().hour,
      showAll: true,
    );
    if (!mounted) return;
    setState(() => _heatmapZones = zones);
    await _renderHeatmap();
  }

  Future<void> _renderHeatmap() async {
    await _zoneLayers?.setHeat(_heatmapZones);
  }

  Future<void> _clearHeatmap() async {
    await _zoneLayers?.setHeat(const []);
    setState(() => _heatmapZones = []);
  }

  // --- TRIP ACTIONS ---

  Future<void> _cancelRoute() async {
    if (_activeTripId != null) {
      await Supabase.instance.client
          .from('trips')
          .update({
            'status': 'completed',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _activeTripId!);
      setState(() { _activeTripId = null; });
    }
    GeofenceService().stopTripTracker();
    setState(() {
      _isRouteActive = false;
      _isTracking = false;
      _isInputExpanded = false;
      _destinationController.clear();
      _polylineManager?.deleteAll();
      _circleManager?.deleteAll();
    });
  }

  Future<void> _toggleTrip() async {
    if (_isTracking) {
      // End Trip
      setState(() {
        _isTracking = false;
        _isRouteActive = false;
        _isInputExpanded = false;
        _destinationController.clear();
        _polylineManager?.deleteAll();
        _circleManager?.deleteAll();
      });
      if (_activeTripId != null) {
        print('Trip ended: $_activeTripId');
        await Supabase.instance.client
            .from('trips')
            .update({
              'status': 'completed',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _activeTripId!);
        setState(() { _activeTripId = null; });
      }
      GeofenceService().stopTripTracker();
      if (mounted) wsfToast(context, 'You made it. Trip ended.', icon: Icons.check_circle_rounded);
    } else {
      // Start Trip — trip row already created by Start Journey
      setState(() { _isTracking = true; });
      if (_activeTripId != null) {
        GeofenceService().startTripTracker(
            _activeTripId!, _currentRouteGeometry);
        wsfToast(context, 'Tracking on. Trip ${_activeTripId!.substring(0, 8)}',
            icon: Icons.shield_rounded);
      } else {
        wsfToast(context, 'Setting up your escorted trip...');
      }
    }
  }

  void _cancelPreview() {
    setState(() {
      _isPendingRoute = false;
      _pendingDestName = '';
      _pendingRouteData = null;
      _destLat = null;
      _destLng = null;
      _destinationController.clear();
    });
    _circleManager?.deleteAll();
    _polylineManager?.deleteAll();
  }

  Future<void> _startJourney() async {
    print('=== START JOURNEY TAPPED ===');
    final supabase = Supabase.instance.client;
    print('User ID: ${supabase.auth.currentUser?.id}');
    print('Start: $_startLat, $_startLng');
    print('Dest: $_destLat, $_destLng');
    print('Active trip before insert: $_activeTripId');
    if (_pendingRouteData != null) {
      // Route already drawn in preview — just activate it
      setState(() {
        _isPendingRoute = false;
        _pendingRouteData = null;
        _isRouteActive = true;
        _isTracking = false;
      });
    } else {
      // Fallback: fetch fresh if preview route wasn't cached
      setState(() => _isPendingRoute = false);
      _fetchAndDrawRoute(_destLat!, _destLng!);
    }
    if (supabase.auth.currentUser != null) {
      try {
        print('Attempting trips insert...');
        final tripResponse = await supabase
            .from('trips')
            .insert({
              'user_id': supabase.auth.currentUser!.id,
              'status': 'active',
              'start_location': 'SRID=4326;POINT($_startLng $_startLat)',
              'destination': 'SRID=4326;POINT($_destLng $_destLat)',
              'started_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();
        print('Trip insert success: $tripResponse');
        final String tripId = tripResponse['id'] as String;
        setState(() { _activeTripId = tripId; });
        print('Trip created: $tripId');
        GeofenceService().startTripTracker(tripId, _currentRouteGeometry);
      } catch (e) {
        print('Trip insert FAILED: $e');
        print('Trip insert error type: ${e.runtimeType}');
      }
    } else {
      print('Trip insert skipped — user not authenticated');
    }
  }

  void _closeSearch() {
    setState(() {
      _isInputExpanded = false;
      _suggestions = [];
      _isSearchLoading = false;
      _searchSessionToken = '';
    });
    _startFocus.unfocus();
    _destinationFocus.unfocus();
    _bottomSlideController.reverse();
    _panelController.show();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Wsf.ink,
      body: SlidingUpPanel(
        controller: _panelController,
        maxHeight: _isPendingRoute ? 0 : (_isRouteActive ? 440 : 540),
        minHeight: _isPendingRoute ? 0 : (_isRouteActive ? 256 : 176),
        parallaxEnabled: !_isPendingRoute,
        parallaxOffset: .5,
        color: Colors.transparent,
        boxShadow: const [],
        onPanelSlide: (t) => _sheetT.value = t,
        onPanelClosed: () {
          // Collapsed, the sheet shows only its first rows; start them at the top.
          if (_sheetScroll.hasClients) _sheetScroll.jumpTo(0);
        },
        panel: _isPendingRoute ? const SizedBox.shrink() : _buildBottomSheet(),
        body: Stack(
          children: [
            MapWidget(
              key: const ValueKey("mapWidget"),
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(_cameraLng, _cameraLat)),
                zoom: 15.0,
              ),
              styleUri: _mapStyle,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              onTapListener: _handleMapTap,
            ),
            // Scrim so the search pill reads over any part of the dark map.
            if (_isNightMode) Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset + 130,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Wsf.ink.withValues(alpha: 0.8), Wsf.ink.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
            _buildAnimatedSearchPanel(),
            if (_isPendingRoute) _buildDestinationPreviewCard(),
            // Map tools: heat layer, chat with the guardian, loud deterrent.
            Positioned(
              top: topInset + 86,
              right: 12,
              child: _chrome(IgnorePointer(
                ignoring: _isInputExpanded,
                child: AnimatedOpacity(
                  duration: Wsf.fast,
                  opacity: _isInputExpanded ? 0 : 1,
                  child: MapDock(
                    actions: [
                      DockAction(
                        icon: Icons.blur_on_rounded,
                        tooltip: 'Risk heat',
                        active: _showHeatmap,
                        onTap: () {
                          setState(() => _showHeatmap = !_showHeatmap);
                          if (_showHeatmap) {
                            _loadHeatmap();
                          } else {
                            _clearHeatmap();
                          }
                        },
                      ),
                      DockAction(
                        icon: Icons.chat_bubble_rounded,
                        tooltip: 'Ask the guardian',
                        onTap: _openChatOverlay,
                      ),
                      DockAction(
                        icon: Icons.campaign_rounded,
                        tooltip: 'Loud deterrent',
                        loading: _isDeterrentLoading,
                        onTap: _isDeterrentLoading ? null : _triggerAiDeterrent,
                      ),
                    ],
                  ),
                ),
              )),
            ),
            if (_demoZonesShown && !_isInputExpanded)
              Positioned(
                top: topInset + 90,
                left: 14,
                child: _chrome(const Tag('demo zones', bg: Wsf.amber, fg: Wsf.amberDeep)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildAnimatedSearchPanel() {
    final hasList = _isSearchLoading || _suggestions.isNotEmpty;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _chrome(SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () {
            if (!_isInputExpanded) {
              HapticFeedback.selectionClick();
              setState(() => _isInputExpanded = true);
              _bottomSlideController.forward();
              _panelController.hide();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 520),
            curve: Wsf.expoOut,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            height: _isInputExpanded
                ? 146 +
                    (hasList ? 12 : 0) +
                    (_isSearchLoading ? 52 : 0) +
                    (_suggestions.length * 62).toDouble()
                : 62,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Wsf.ink,
              borderRadius: BorderRadius.circular(31),
              border: Border.all(color: Wsf.line, width: 2),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: _isInputExpanded
                    ? _buildExpandedInputs()
                    : _buildCollapsedInput(),
              ),
            ),
          ),
        ),
      )),
    );
  }

  /// Map chrome (search, tools) fades away as the sheet is pulled up, so it
  /// never collides with the status bar while the map parallaxes under it.
  Widget _chrome(Widget child) => ValueListenableBuilder<double>(
        valueListenable: _sheetT,
        builder: (_, t, c) {
          final opacity = (1 - t * 2.4).clamp(0.0, 1.0);
          return IgnorePointer(
            ignoring: opacity < 0.5,
            child: Opacity(opacity: opacity, child: c),
          );
        },
        child: child,
      );

  Widget _buildCollapsedInput() {
    return SizedBox(
      key: const ValueKey("collapsed"),
      height: 58,
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
            child: Text(
              "where to?",
              style: Wsf.body(size: 17, color: Wsf.bone, weight: FontWeight.w500),
            ),
          ),
          const Eyebrow('safest route'),
          const SizedBox(width: 18),
        ],
      ),
    );
  }

  Widget _buildExpandedInputs() {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: c, width: 2),
        );
    InputDecoration deco(String hint, {required Widget prefix, Widget? suffix}) =>
        InputDecoration(
          filled: true,
          fillColor: Wsf.ink3,
          isDense: true,
          hintText: hint,
          hintStyle: Wsf.body(size: 15.5, color: Wsf.boneFaint),
          prefixIcon: SizedBox(width: 44, child: Center(child: prefix)),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 0),
          suffixIcon: suffix,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          border: border(Colors.transparent),
          enabledBorder: border(Colors.transparent),
          focusedBorder: border(Wsf.volt),
        );
    final fieldStyle = Wsf.body(size: 15.5, color: Wsf.bone, weight: FontWeight.w500);

    return Padding(
      key: const ValueKey("expanded"),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Back + origin field
          Row(
            children: [
              DiscButton(
                icon: Icons.arrow_back_rounded,
                size: 40,
                bg: Wsf.ink3,
                border: null,
                onTap: _closeSearch,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: TextField(
                    controller: _startController,
                    focusNode: _startFocus,
                    onChanged: (val) => _onSearchChanged(val, true),
                    keyboardAppearance: Brightness.dark,
                    style: fieldStyle,
                    decoration: deco(
                      "Current Location",
                      prefix: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: Wsf.volt, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Connector between the two stops
          Padding(
            padding: const EdgeInsets.only(left: 71),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 14, color: Wsf.line),
            ),
          ),

          // Destination field + pick-on-map
          Row(
            children: [
              const SizedBox(width: 50),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: TextField(
                    controller: _destinationController,
                    focusNode: _destinationFocus,
                    onChanged: (val) => _onSearchChanged(val, false),
                    autofocus: true,
                    keyboardAppearance: Brightness.dark,
                    style: fieldStyle.copyWith(overflow: TextOverflow.ellipsis),
                    decoration: deco(
                      "where to?",
                      prefix: const Icon(Icons.place_rounded, color: Wsf.coral, size: 20),
                      suffix: GestureDetector(
                        onTap: () {
                          setState(() => _isInputExpanded = false);
                          _startFocus.unfocus();
                          _destinationFocus.unfocus();
                          _bottomSlideController.reverse();
                          _panelController.show();
                          wsfToast(context, 'Tap the map to drop your destination.',
                              icon: Icons.touch_app_rounded);
                        },
                        child: const Icon(Icons.map_rounded, color: Wsf.boneDim, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_isSearchLoading || _suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 2, color: Wsf.line),
            _buildSuggestionsList(),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (_isSearchLoading) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Text("nothing found nearby", style: Wsf.body(size: 13, color: Wsf.boneFaint)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _suggestions.map((suggestion) {
        final String name = suggestion['name'] ?? '';
        final String subtitle = suggestion['place_formatted'] ?? '';
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final bool isStart = _startFocus.hasFocus;
            _selectSuggestion(suggestion, isStart);
          },
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(color: Wsf.ink3, shape: BoxShape.circle),
                  child: const Icon(Icons.place_outlined, size: 18, color: Wsf.volt),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Wsf.body(size: 15, color: Wsf.bone, weight: FontWeight.w600),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Wsf.body(size: 12.5, color: Wsf.boneFaint),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDestinationPreviewCard() {
    final look = riskLook(_riskLevel);
    final bool ready = _pendingRouteData != null;
    // The panel body is as tall as the screen, so it runs behind the nav dock;
    // lift the card clear of the dock and the raised SOS button.
    return Positioned(
      bottom: MediaQuery.paddingOf(context).bottom + 70 + 26,
      left: 12,
      right: 12,
      child: FadeSlide(
        child: ReceiptCard(
          label: 'destination',
          bg: Wsf.ink,
          trailing: _isRouteFetching
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : (ready ? Tag(look.label, bg: look.bg, fg: look.fg) : null),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pendingDestName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Wsf.display(26, height: 1.04),
              ),
              if (ready) ...[
                const SizedBox(height: 8),
                Text(
                  '${_durationMin.toStringAsFixed(0)} min walk'
                  '${_riskExplanation.isNotEmpty ? ' · $_riskExplanation' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Wsf.body(size: 14),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  PillButton(
                    label: 'cancel',
                    expand: false,
                    icon: null,
                    height: 56,
                    bg: Wsf.ink3,
                    fg: Wsf.bone,
                    onTap: _cancelPreview,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PillButton(
                      label: 'start journey',
                      height: 56,
                      loading: _isRouteFetching,
                      onTap: _isRouteFetching ? null : _startJourney,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A sheet with a coloured header block and a dark, rounded body under it.
  Widget _sheet({
    required Color top,
    required Widget header,
    required List<Widget> children,
  }) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Wsf.expoOut,
        color: top,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: Wsf.ink,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  controller: _sheetScroll,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    if (_isRouteActive) {
      final look = riskLook(_riskLevel);
      return _sheet(
        top: look.bg,
        header: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHandle(color: look.dim.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tag(look.label, bg: Wsf.ink, fg: look.bg),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _durationMin.toStringAsFixed(0),
                              style: Wsf.display(68, color: look.fg, height: 0.9),
                            ),
                            const SizedBox(width: 8),
                            Text('min walk', style: Wsf.serif(28, color: look.fg)),
                          ],
                        ),
                        if (_riskExplanation.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _riskExplanation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Wsf.body(size: 13, color: look.dim, weight: FontWeight.w500),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(color: Wsf.ink, shape: BoxShape.circle),
                    child: Icon(Icons.directions_walk_rounded, color: look.bg, size: 28),
                  ),
                ],
              ),
            ),
          ],
        ),
        children: [
          Row(
            children: [
              PillButton(
                label: 'cancel',
                expand: false,
                icon: null,
                bg: Wsf.ink3,
                fg: Wsf.bone,
                onTap: _cancelRoute,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  label: _isTracking ? 'end trip' : 'start trip',
                  bg: _isTracking ? Wsf.bone : Wsf.volt,
                  fg: _isTracking ? Wsf.ink : Wsf.voltDeep,
                  icon: _isTracking ? Icons.flag_rounded : Icons.arrow_forward_rounded,
                  onTap: _toggleTrip,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_highRiskSegmentCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Wsf.coralDeep,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Wsf.coral, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Wsf.coral, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$_highRiskSegmentCount high-risk segment${_highRiskSegmentCount > 1 ? 's' : ''} on this route",
                      style: Wsf.body(size: 14, color: Wsf.coral, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          ReceiptCard(
            label: 'route details',
            trailing: _isTracking ? const Tag('tracking', icon: Icons.shield_rounded) : null,
            child: Text(
              "This path avoids ${_riskScore > 0 ? 'detected high-crime zones' : 'all known danger zones'}.",
              style: Wsf.body(size: 14.5),
            ),
          ),
        ],
      );
    }

    // Idle: where you are standing, and where is safe nearby.
    return _sheet(
      top: _zone.bg,
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHandle(color: _zone.dim.withValues(alpha: 0.5)),
          StatusHeader(zone: _zone, listening: _audioSentinel.isListening),
        ],
      ),
      children: [
        const Eyebrow('nearby · safe spots'),
        const SizedBox(height: 12),
        if (_safeHavens.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text("looking for safe places near you...", style: Wsf.body(size: 14)),
          )
        else
          ..._safeHavens.map((h) => _buildSafePlaceTile(h)),
        const SizedBox(height: 14),
        const Eyebrow('test mode · map mood'),
        const SizedBox(height: 12),
        SegmentedPill(
          left: 'day',
          right: 'night',
          leftIcon: Icons.wb_sunny_rounded,
          rightIcon: Icons.nights_stay_rounded,
          isRight: _isNightMode,
          onChanged: (_) => _toggleSimulationMode(),
        ),
      ],
    );
  }

  Widget _buildNavBar() {
    return SlideTransition(
      position: _bottomSlideAnimation,
      child: NavDock(
        index: _navIndex,
        // Home doubles as "take me back to where I am".
        onHome: () {
          setState(() => _navIndex = 0);
          mapboxMap?.flyTo(
            CameraOptions(
              center: Point(coordinates: Position(_startLng, _startLat)),
              zoom: 15.0,
            ),
            MapAnimationOptions(duration: 800),
          );
        },
        onSos: () => _handleSosSequence(),
        onProfile: () async {
          setState(() => _navIndex = 2);
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
          if (mounted) setState(() => _navIndex = 0);
        },
      ),
    );
  }

  Widget _buildSafePlaceTile(Map<String, dynamic> haven) {
    final String title = haven['name'] as String;
    final double dist = haven['distance'] as double;
    final String address = (haven['address'] as String?) ?? '';
    final String category = (haven['category'] as String?) ?? '';

    IconData icon;
    switch (category) {
      case 'police':
        icon = Icons.local_police_rounded;
        break;
      case 'hospital':
        icon = Icons.local_hospital_rounded;
        break;
      case 'pharmacy':
        icon = Icons.local_pharmacy_rounded;
        break;
      case 'fire_station':
        icon = Icons.fire_truck_rounded;
        break;
      default:
        icon = Icons.store_rounded;
    }

    return SafeSpotTile(
      icon: icon,
      title: title,
      distanceKm: dist,
      address: address,
      onTap: () => _selectDestinationFromSafeHaven(
        haven['lat'] as double,
        haven['lng'] as double,
        title,
      ),
    );
  }
}
