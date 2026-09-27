import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'border_crossing_service.dart';

/// Transit Barometer passenger waits, following BORDER_WAIT_TIMES_HANDOFF.md.
class BorderWaitService extends ChangeNotifier {
  BorderWaitService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const slugs = {
    'road-061': 'windsor-and-detroit-tunnel',
    'road-062': 'ambassador-bridge',
    'road-063': 'gordie-howe-international-bridge',
  };
  Map<String, dynamic> _records = {};
  bool failed = false;
  bool _disposed = false;
  bool _fetching = false;
  DateTime? updatedAt;
  Timer? _timer;

  void start() {
    if (_timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _fetching) return;
    _fetching = true;
    try {
      // A cache-busting URL avoids stale browser caches without CORS preflight.
      final uri = Uri.https('transitbarometer.com', '/api/border.json', {
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('Feed HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['crossings'] is! List) {
        throw const FormatException('Missing crossings');
      }
      final next = <String, dynamic>{};
      for (final row in data['crossings'] as List) {
        if (row is Map<String, dynamic> && row['slug'] is String) {
          next[row['slug'] as String] = row;
        }
      }
      if (_disposed) return;
      _records = next;
      updatedAt =
          DateTime.tryParse('${data['generated_at_utc']}') ??
          DateTime.tryParse('${data['generated_at']}');
      failed = false;
    } catch (_) {
      if (!_disposed) failed = true; // Retain the last successful reading.
    } finally {
      _fetching = false;
      if (!_disposed) notifyListeners();
    }
  }

  WaitReading reading(BorderEntrance entrance) {
    final slug = slugs[entrance.crossingId];
    final key = switch (entrance.destinationCountry) {
      'CA' => 'into_canada',
      'US' => 'into_us',
      _ => null,
    };
    final row = _records[slug];
    final direction = row is Map && key != null ? row[key] : null;
    final age = updatedAt == null
        ? null
        : DateTime.now().difference(updatedAt!);
    return WaitReading.fromDirection(
      direction,
      stale: failed || (age != null && age > const Duration(minutes: 15)),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}

class WaitReading {
  const WaitReading(this.label, {this.updated = '', this.stale = false});
  final String label;
  final String updated;
  final bool stale;

  factory WaitReading.fromDirection(dynamic direction, {bool stale = false}) {
    if (direction is! Map || direction['cars'] is! Map) {
      return WaitReading('—', stale: stale);
    }
    final cars = direction['cars'] as Map;
    String text(dynamic value) => value is String ? value.trim() : '';
    final kind = text(cars['kind']);
    final carText = text(cars['text']);
    final status = [
      kind,
      text(direction['status']),
      carText,
      'Open',
    ].firstWhere((s) => s.isNotEmpty);
    final closed = [
      kind,
      carText,
      text(direction['status']),
    ].any((s) => s.toLowerCase().contains('closed'));
    final minutes = cars['minutes'];
    final valid = minutes is num && minutes.isFinite;
    final label = closed
        ? 'Closed'
        : ['n/a', 'unknown'].contains(status.toLowerCase())
        ? 'N/A'
        : !valid
        ? '—'
        : minutes <= 0
        ? 'No delay'
        : '$minutes min';
    return WaitReading(
      label,
      updated: text(direction['updated']),
      stale: stale,
    );
  }
}
