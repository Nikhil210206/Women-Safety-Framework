import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../theme/wsf.dart';
import '../ui/dither.dart';

/// Draws risk zones on the map as style layers instead of flat annotations:
/// a faint wash, an ordered-dither dot fill, a blurred glow and a crisp edge.
/// The dots and glow breathe using native paint transitions, so the pulse
/// costs one style call per beat rather than one per frame.
///
/// Zones (polygons from `dynamic_zones`) and heat (circles from
/// `heatmap_zones`) live in separate sources so either can be swapped alone.
class ZoneLayers {
  ZoneLayers(this._map);

  final MapboxMap _map;
  Timer? _pulse;
  bool _beat = false;
  bool _attached = false;
  bool _hasDots = false;
  String _zones = _empty;
  String _heat = _empty;

  static const String _empty = '{"type":"FeatureCollection","features":[]}';
  static const String _zoneSrc = 'wsf-zones';
  static const String _heatSrc = 'wsf-heat';
  static const String _dotsRed = 'wsf-dots-red';
  static const String _dotsAmber = 'wsf-dots-amber';

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static List<Object> get _toneColor =>
      ['match', ['get', 'tone'], 'amber', _hex(Wsf.amber), _hex(Wsf.coral)];
  static const List<Object> _tonePattern = [
    'match', ['get', 'tone'], 'amber', _dotsAmber, _dotsRed, //
  ];

  /// Adds images, sources and layers to the current style. Call again after
  /// every style load; a style swap drops everything added at runtime.
  Future<void> attach() async {
    _attached = false;
    final style = _map.style;

    // The dot texture is a nicety. If the images cannot be registered, zones
    // still draw with their wash, glow and edge.
    var dots = true;
    try {
      await style.addStyleImage(_dotsRed, 3, await _dotTile(Wsf.coral), false, [], [], null);
      await style.addStyleImage(_dotsAmber, 3, await _dotTile(Wsf.amber), false, [], [], null);
    } catch (e) {
      dots = false;
      // ignore: avoid_print
      print('[ZoneLayers] dot pattern unavailable: $e');
    }

    try {
      for (final (id, data) in [(_heatSrc, _heat), (_zoneSrc, _zones)]) {
        if (!await style.styleSourceExists(id)) {
          await style.addSource(GeoJsonSource(id: id, data: data));
        }
      }

      // Heat: softer, sits underneath.
      await _add(dots
          ? FillLayer(
              id: 'wsf-heat-dots',
              sourceId: _heatSrc,
              fillPatternExpression: _tonePattern,
              fillOpacity: 0.42,
            )
          : FillLayer(
              id: 'wsf-heat-dots',
              sourceId: _heatSrc,
              fillColorExpression: _toneColor,
              fillOpacity: 0.16,
            ));
      await _add(LineLayer(
        id: 'wsf-heat-edge',
        sourceId: _heatSrc,
        lineColorExpression: _toneColor,
        lineWidth: 1.4,
        lineOpacity: 0.65,
        lineDasharray: [2, 2.5],
      ));

      // Zones: wash, dots, glow, edge.
      await _add(FillLayer(
        id: 'wsf-zones-wash',
        sourceId: _zoneSrc,
        fillColorExpression: _toneColor,
        fillOpacity: 0.13,
      ));
      if (dots) {
        await _add(FillLayer(
          id: 'wsf-zones-dots',
          sourceId: _zoneSrc,
          fillPatternExpression: _tonePattern,
          fillOpacity: 0.9,
        ));
      }
      await _add(LineLayer(
        id: 'wsf-zones-glow',
        sourceId: _zoneSrc,
        lineColorExpression: _toneColor,
        lineWidth: 16,
        lineBlur: 12,
        lineOpacity: 0.5,
        lineJoin: LineJoin.ROUND,
      ));
      await _add(LineLayer(
        id: 'wsf-zones-edge',
        sourceId: _zoneSrc,
        lineColorExpression: _toneColor,
        lineWidth: 2.2,
        lineJoin: LineJoin.ROUND,
      ));

      for (final (layer, prop) in [
        if (dots) ('wsf-zones-dots', 'fill-opacity-transition'),
        ('wsf-zones-glow', 'line-opacity-transition'),
        ('wsf-zones-glow', 'line-width-transition'),
      ]) {
        await _set(layer, prop, {'duration': _beatMs, 'delay': 0});
      }
      _hasDots = dots;

      _attached = true;
      _pulse?.cancel();
      _pulse = Timer.periodic(const Duration(milliseconds: _beatMs), (_) => _tick());
    } catch (e) {
      // ignore: avoid_print
      print('[ZoneLayers] attach failed: $e');
    }
  }

  static const int _beatMs = 1500;

  Future<void> _add(Layer layer) async {
    if (await _map.style.styleLayerExists(layer.id)) return;
    await _map.style.addLayer(layer);
  }

  Future<void> _set(String layer, String property, Object value) async {
    try {
      await _map.style.setStyleLayerProperty(layer, property, value);
    } catch (_) {
      // The style may be mid-swap; the next attach() restores everything.
    }
  }

  void _tick() {
    if (!_attached) return;
    _beat = !_beat;
    if (_hasDots) _set('wsf-zones-dots', 'fill-opacity', _beat ? 0.5 : 0.92);
    _set('wsf-zones-glow', 'line-opacity', _beat ? 0.18 : 0.55);
    _set('wsf-zones-glow', 'line-width', _beat ? 10.0 : 18.0);
  }

  /// Replaces the polygon zones. [rows] are `dynamic_zones` rows: each has a
  /// GeoJSON `boundary` (object or string) and a `risk_level`.
  Future<void> setZones(List<dynamic> rows) async {
    final features = <Map<String, dynamic>>[];
    for (final zone in rows) {
      final raw = zone['boundary'];
      if (raw == null) continue;
      final geometry = raw is String ? jsonDecode(raw) : raw;
      features.add({
        'type': 'Feature',
        'properties': {'tone': zone['risk_level'] == 'yellow' ? 'amber' : 'red'},
        'geometry': geometry,
      });
    }
    _zones = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await _push(_zoneSrc, _zones);
  }

  /// Replaces the heat circles. [rows] are `heatmap_zones` rows.
  Future<void> setHeat(List<Map<String, dynamic>> rows) async {
    final features = <Map<String, dynamic>>[];
    for (final zone in rows) {
      // Columns are latitude/longitude or center_lat/center_lng depending on
      // how the heatmap_zones table was created.
      final lat = ((zone['latitude'] ?? zone['center_lat']) as num).toDouble();
      final lng = ((zone['longitude'] ?? zone['center_lng']) as num).toDouble();
      final radius = (zone['radius_m'] as num).toDouble();
      features.add({
        'type': 'Feature',
        'properties': {'tone': zone['risk_level'] == 'high' ? 'red' : 'amber'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [circleRing(lat, lng, radius)],
        },
      });
    }
    _heat = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await _push(_heatSrc, _heat);
  }

  Future<void> _push(String source, String data) async {
    if (!_attached) return; // attach() will pick the data up
    try {
      await _map.style.setStyleSourceProperty(source, 'data', data);
    } catch (e) {
      // ignore: avoid_print
      print('[ZoneLayers] update failed for $source: $e');
    }
  }

  void dispose() => _pulse?.cancel();

  // ── Geometry helpers ───────────────────────────────────────────────────────

  /// A closed ring of [points] approximating a circle of [radiusM] metres.
  static List<List<double>> circleRing(double lat, double lng, double radiusM, {int points = 48}) {
    const earth = 6371000.0;
    return [
      for (var i = 0; i <= points; i++)
        () {
          final a = i / points * 2 * math.pi;
          final dLat = radiusM / earth * 180 / math.pi * math.sin(a);
          final dLng = radiusM / earth * 180 / math.pi * math.cos(a) / math.cos(lat * math.pi / 180);
          return [lng + dLng, lat + dLat];
        }(),
    ];
  }

  /// Made-up zones around a point, shaped like `dynamic_zones` rows. For
  /// reviewing the map styling when the database has nothing to show; never
  /// fed to geofencing.
  static List<Map<String, dynamic>> demoZones(double lat, double lng) {
    Map<String, dynamic> blob(double dLat, double dLng, double radiusM, String level, double phase) {
      const earth = 6371000.0;
      const n = 40;
      final cLat = lat + dLat, cLng = lng + dLng;
      final ring = [
        for (var i = 0; i <= n; i++)
          () {
            final a = i / n * 2 * math.pi;
            final r = radiusM * (1 + 0.22 * math.sin(3 * a + phase) + 0.12 * math.sin(5 * a - phase));
            return [
              cLng + r / earth * 180 / math.pi * math.cos(a) / math.cos(cLat * math.pi / 180),
              cLat + r / earth * 180 / math.pi * math.sin(a),
            ];
          }(),
      ];
      return {
        'risk_level': level,
        'boundary': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
      };
    }

    return [
      blob(0.0034, 0.0030, 260, 'red', 0.4),
      blob(-0.0040, -0.0036, 320, 'yellow', 1.9),
      blob(0.0010, -0.0062, 200, 'red', 3.1),
    ];
  }

  /// A repeating tile of dots sized by the 4×4 Bayer matrix: the dither
  /// texture, as a fill pattern.
  static Future<MbxImage> _dotTile(Color color) async {
    const scale = 3.0;
    const pitch = 5.0;
    const n = 4;
    final px = (pitch * n * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..color = color
      ..isAntiAlias = true;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final t = kBayer4[j * 4 + i] / 15;
        canvas.drawCircle(
          ui.Offset((i + 0.5) * pitch * scale, (j + 0.5) * pitch * scale),
          pitch * scale * (0.15 + 0.27 * (1 - t)),
          paint,
        );
      }
    }
    final image = await recorder.endRecording().toImage(px, px);
    // The plugin decodes this with UIImage / BitmapFactory, so it has to be
    // an encoded image rather than raw pixels.
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return MbxImage(width: px, height: px, data: bytes!.buffer.asUint8List());
  }
}
