import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre/maplibre.dart';

import 'road_highlight_service.dart';

/// Persistent hazards are separate from the narration's temporary highlights.
class RoadClosureService extends ChangeNotifier {
  RoadClosureService({http.Client? client, this.baseUrl})
    : _client = client ?? http.Client();
  final http.Client _client;
  final Uri? baseUrl;
  Timer? _timer;
  bool _disposed = false;
  bool _fetching = false;
  List<Map<String, dynamic>> _closures = [];
  String label = 'Road closures: loading';
  DateTime? fetchedAt;

  Uri get _origin {
    const configured = String.fromEnvironment('BACKEND_URL');
    return baseUrl ??
        (configured.isNotEmpty
            ? Uri.parse(configured)
            : kReleaseMode && kIsWeb
            ? Uri.base
            : Uri.parse('http://localhost:3000'));
  }

  void start() {
    if (_timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _fetching) return;
    _fetching = true;
    try {
      final response = await _client
          .get(_origin.resolve('/api/road-closures'))
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        label = data['code'] == 'not_configured'
            ? 'Road closures: not configured'
            : 'Road closures: unavailable';
        _closures = [];
        fetchedAt = null;
      } else {
        final fetched = DateTime.parse(data['fetchedAt'] as String);
        if (DateTime.now().difference(fetched) > const Duration(minutes: 2)) {
          throw const FormatException('Expired closure feed');
        }
        final rows = (data['closures'] as List).cast<Map<String, dynamic>>();
        // Validate geometry before it reaches the map renderer.
        for (final row in rows) {
          final geometry = row['geometry'] as Map;
          final type = geometry['type'];
          if (row['status'] != 'hazard' ||
              !['Point', 'LineString'].contains(type)) {
            throw const FormatException('Invalid closure');
          }
          final coordinates = geometry['coordinates'] as List;
          final points = type == 'Point' ? [coordinates] : coordinates;
          if (points.isEmpty || (type == 'LineString' && points.length < 2)) {
            throw const FormatException('Empty geometry');
          }
          for (final point in points) {
            if (point is! List ||
                point.length != 2 ||
                point.any((v) => v is! num || !v.isFinite) ||
                (point[0] as num).abs() > 180 ||
                (point[1] as num).abs() > 90) {
              throw const FormatException('Invalid coordinate');
            }
          }
        }
        _closures = rows;
        fetchedAt = fetched;
        label = 'Road closures: ${rows.length} reported · TomTom';
      }
    } catch (_) {
      _closures = [];
      fetchedAt = null;
      label = 'Road closures: unavailable';
    } finally {
      _fetching = false;
      if (!_disposed) notifyListeners();
    }
  }

  List<Layer> get layers => layersAt(0.5);

  /// Shares the map's neon animation without creating one ticker per closure.
  List<Layer> layersAt(double pulse) {
    if (fetchedAt == null ||
        DateTime.now().difference(fetchedAt!) > const Duration(minutes: 2)) {
      return const [];
    }
    final roads = <LineString>[];
    final points = <Point>[];
    for (final row in _closures) {
      final end = DateTime.tryParse('${row['endTime']}');
      if (end != null && !end.isAfter(DateTime.now())) continue;
      final geometry = row['geometry'] as Map;
      final coordinates = geometry['coordinates'] as List;
      Position position(dynamic p) =>
          Position((p[0] as num).toDouble(), (p[1] as num).toDouble());
      if (geometry['type'] == 'LineString') {
        roads.add(LineString(coordinates: coordinates.map(position).toList()));
      } else {
        points.add(Point(coordinates: position(coordinates)));
      }
    }
    return [
      if (roads.isNotEmpty) ...[
        NeonRoadLayer(
          polylines: roads,
          color: Colors.red.withValues(alpha: .18 + pulse * .08),
          width: 34,
          blur: 24,
        ),
        NeonRoadLayer(
          polylines: roads,
          color: Colors.red.withValues(alpha: .48 + pulse * .14),
          width: 17,
          blur: 10,
        ),
        NeonRoadLayer(polylines: roads, color: Colors.red, width: 7, blur: 2),
        NeonRoadLayer(
          polylines: roads,
          color: Color.lerp(Colors.red, Colors.white, .82 + pulse * .08)!,
          width: 3,
          blur: 1,
        ),
      ],
      if (points.isNotEmpty)
        CircleLayer(
          points: points,
          radius: 12,
          color: Colors.red.withValues(alpha: .7 + pulse * .3),
          strokeColor: Colors.white,
          strokeWidth: 2,
        ),
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}
