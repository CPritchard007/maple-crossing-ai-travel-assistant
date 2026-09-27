import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/services/road_closure_service.dart';

void main() {
  test(
    'closures render red tubes and points, refresh removes reopened roads',
    () async {
      var closed = true;
      final service = RoadClosureService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/road-closures');
          return http.Response(
            jsonEncode({
              'fetchedAt': DateTime.now().toUtc().toIso8601String(),
              'closures': closed
                  ? [
                      {
                        'status': 'hazard',
                        'geometry': {
                          'type': 'LineString',
                          'coordinates': [
                            [-83.05, 42.33],
                            [-83.06, 42.34],
                          ],
                        },
                      },
                      {
                        'status': 'hazard',
                        'geometry': {
                          'type': 'Point',
                          'coordinates': [-82.95, 42.3],
                        },
                      },
                    ]
                  : [],
            }),
            200,
          );
        }),
      );
      await service.refresh();
      expect(service.layers.length, 5);
      expect((service.layers[2] as PolylineLayer).color, Colors.red);
      expect(
        (service.layers[2] as PolylineLayer).list.single.coordinates.first.lng,
        -83.05,
      );
      expect(
        (service.layersAt(1).last as CircleLayer).color.toARGB32(),
        Colors.red.toARGB32(),
      );
      closed = false;
      await service.refresh();
      expect(service.layers, isEmpty);
      expect(service.label, contains('0 reported'));
      service.dispose();
    },
  );

  test(
    'missing key, stale data and invalid geometry never imply clear roads',
    () async {
      var response = http.Response('{"code":"not_configured"}', 503);
      final service = RoadClosureService(
        client: MockClient((_) async => response),
      );
      await service.refresh();
      expect(service.label, contains('not configured'));
      expect(service.layers, isEmpty);
      response = http.Response(
        jsonEncode({'fetchedAt': '2000-01-01T00:00:00Z', 'closures': []}),
        200,
      );
      await service.refresh();
      expect(service.label, contains('unavailable'));
      response = http.Response(
        jsonEncode({
          'fetchedAt': DateTime.now().toIso8601String(),
          'closures': [
            {
              'status': 'hazard',
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [-83, 420],
                  [-83, 42],
                ],
              },
            },
          ],
        }),
        200,
      );
      await service.refresh();
      expect(service.label, contains('unavailable'));
      expect(service.layers, isEmpty);
      service.dispose();
    },
  );
}
