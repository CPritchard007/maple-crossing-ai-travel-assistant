import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/services/border_crossing_service.dart';
import 'package:maple_crossing/services/border_wait_service.dart';

void main() {
  test('Normalizes closed, missing, unknown and zero waits from handoff', () {
    expect(WaitReading.fromDirection(null).label, '—');
    expect(
      WaitReading.fromDirection({
        'cars': {'minutes': '12'},
      }).label,
      '—',
    );
    expect(
      WaitReading.fromDirection({
        'cars': {'minutes': 0},
      }).label,
      'No delay',
    );
    expect(
      WaitReading.fromDirection({
        'cars': {'minutes': -1},
      }).label,
      'No delay',
    );
    expect(
      WaitReading.fromDirection({
        'cars': {'kind': 'unknown', 'minutes': 12},
      }).label,
      'N/A',
    );
    expect(
      WaitReading.fromDirection({
        'status': 'Closed',
        'cars': {'minutes': 12},
      }).label,
      'Closed',
    );
    expect(
      WaitReading.fromDirection({
        'cars': {'text': 'Temporarily closed'},
      }).label,
      'Closed',
    );
  });
  test(
    'Exact slug and direction mapping; refresh failure retains last reading',
    () async {
      var fail = false;
      final service = BorderWaitService(
        client: MockClient((request) async {
          if (fail) return http.Response('error', 503);
          return http.Response(
            jsonEncode({
              'crossings': [
                {
                  'slug': 'ambassador-bridge',
                  'into_us': {
                    'cars': {'minutes': 5},
                    'updated': 'At 9:00 am',
                  },
                  'into_canada': {
                    'cars': {'minutes': 15},
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      final us = BorderEntrance(
        name: 'Ambassador',
        crossingId: 'road-062',
        position: Position(-83, 42),
        destinationCountry: 'US',
      );
      final ca = BorderEntrance(
        name: 'Ambassador',
        crossingId: 'road-062',
        position: Position(-83, 42),
        destinationCountry: 'CA',
      );
      await service.refresh();
      expect(service.reading(us).label, '5 min');
      expect(service.reading(ca).label, '15 min');
      fail = true;
      await service.refresh();
      expect(service.reading(us).label, '5 min');
      expect(service.reading(us).stale, isTrue);
    },
  );
}
