import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/services/border_crossing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Dashed references connect only paired sides of the same crossing',
    () async {
      final service = BorderCrossingService();
      final entrances = await service.loadEntrances();
      final layers = service.connectionsFor(entrances);
      expect(layers.single.dashArray, [4, 3]);
      expect(layers.single.list.length, 2);
      expect(layers.single.gapWidth, 26);
      for (final line in layers.single.list) {
        expect(line.coordinates.length, 2);
      }
      for (final id in ['road-061', 'road-062']) {
        final pair = entrances.where((e) => e.crossingId == id).toList();
        expect(
          layers.single.list.any(
            (line) =>
                line.coordinates.contains(pair[0].position) &&
                line.coordinates.contains(pair[1].position),
          ),
          isTrue,
        );
      }
      expect(
        service.connectionsFor(
          entrances.where((e) => e.destinationCountry == 'CA').toList(),
        ),
        isEmpty,
      );
    },
  );

  test(
    'Combines nearby same-side circles but preserves other crossings and directions',
    () {
      BorderEntrance point(String id, String? side, double lat) =>
          BorderEntrance(
            name: id,
            crossingId: id,
            destinationCountry: side,
            position: Position(-83, lat),
          );
      final first = point('bridge', 'US', 42);
      final points = BorderCrossingService().combineNearby([
        first,
        point('bridge', 'US', 42.002),
        point('bridge', 'CA', 42.001),
        point('tunnel', 'US', 42.001),
        point('bridge', 'US', 42.01),
        point('unknown', null, 43),
        point('unknown', null, 43.0002),
        point('unknown', null, 43.002),
      ]);
      expect(points.length, 6);
      expect(points.first, same(first));
    },
  );

  test(
    'Uses entrance coordinates and never falls back to boundary locations',
    () async {
      final layers = await BorderCrossingService().loadLayers(
        bundle: _CrossingBundle(),
      );
      final points = layers.expand((layer) => layer.list).toList();
      expect(points.length, 2);
      expect(points.first.coordinates.lat, 42.3);
      expect(points.first.coordinates.lng, -83.0);
    },
  );

  test(
    'Only Windsor–Detroit crossings produce circles, retaining both sides',
    () async {
      final data =
          jsonDecode(
                await rootBundle.loadString(BorderCrossingService.assetPath),
              )
              as Map<String, dynamic>;
      final records = data['crossings'] as List<dynamic>;
      final layers = await BorderCrossingService().loadLayers();
      final entrances = records.expand((r) => r['entrances'] as List);
      expect(
        layers.expand((layer) => layer.list).length,
        lessThan(entrances.length),
      );
      final grouped = await BorderCrossingService().loadEntrances();
      for (final id in ['road-061', 'road-062']) {
        final points = grouped.where((e) => e.crossingId == id).toList();
        expect(points.length, 2);
        expect(points.map((e) => e.destinationCountry).toSet(), {'US', 'CA'});
      }
      expect(entrances, isNotEmpty);
      for (final name in ['Detroit–Windsor Tunnel', 'Ambassador Bridge']) {
        final crossing = records.firstWhere(
          (r) => (r['name'] as String).contains(name),
        );
        final points = crossing['entrances'] as List;
        expect(points.length, greaterThanOrEqualTo(2));
        expect(points.any((p) => p['latitude'] > crossing['latitude']), isTrue);
        expect(points.any((p) => p['latitude'] < crossing['latitude']), isTrue);
      }
      expect(records.length, 213);
      expect(records.map((r) => r['id']).toSet().length, records.length);
      expect(records.any((r) => r['latitude'] > 60), isTrue);
      expect(
        records.any(
          (r) => (r['name'] as String).contains('Detroit–Windsor Tunnel'),
        ),
        isTrue,
      );
      expect(layers.first.list, isEmpty);
      expect(grouped.map((e) => e.crossingId).toSet(), {
        'road-061',
        'road-062',
        'road-063',
      });
      expect(grouped.length, 5);
      expect(layers.last.list, isNotEmpty);
    },
  );
}

class _CrossingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'crossings': [
            {
              'id': 'road-001',
              'entrances': [
                {'latitude': 49, 'longitude': -120},
              ],
            },
            {'id': 'road-062', 'latitude': 0, 'longitude': 0, 'entrances': []},
            {'id': 'road-063', 'latitude': 1, 'longitude': 1},
            {
              'id': 'road-061',
              'latitude': 2,
              'longitude': 2,
              'entrances': [
                {'latitude': 42.3, 'longitude': -83.0},
                {'latitude': 42.4, 'longitude': -83.1},
              ],
            },
          ],
        }),
      ),
    ),
  );
}
