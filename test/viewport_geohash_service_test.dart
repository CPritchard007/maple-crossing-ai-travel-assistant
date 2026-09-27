import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/services/viewport_geohash_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('standard geohash reference coordinate', () {
    expect(ViewportGeohashService.encode(42.6, -5.6), 'ezs42');
  });
  test('cover includes all viewport corners and center', () {
    const b = LngLatBounds(
      longitudeWest: -83.12,
      longitudeEast: -82.9,
      latitudeSouth: 42.2,
      latitudeNorth: 42.4,
    );
    final cover = ViewportGeohashService.cover(b);
    for (final lat in [42.2, 42.3, 42.4]) {
      for (final lon in [-83.12, -83.01, -82.9]) {
        expect(
          cover.hashes,
          contains(
            ViewportGeohashService.encode(lat, lon, precision: cover.precision),
          ),
        );
      }
    }
    expect(cover.hashes.length, lessThanOrEqualTo(256));
  });
  test('date line and wrapped worlds have the same cover', () {
    LngLatBounds bounds(double east) => LngLatBounds(
      longitudeWest: 179,
      longitudeEast: east,
      latitudeSouth: 10,
      latitudeNorth: 11,
    );
    final cover = ViewportGeohashService.cover(bounds(-179));
    expect(cover.hashes, ViewportGeohashService.cover(bounds(181)).hashes);
    for (final lon in [179.5, -179.5]) {
      expect(
        cover.hashes,
        contains(
          ViewportGeohashService.encode(10.5, lon, precision: cover.precision),
        ),
      );
    }
  });
  test('world coverage coarsens without dropping cells', () {
    final cover = ViewportGeohashService.cover(
      const LngLatBounds(
        longitudeWest: -180,
        longitudeEast: 180,
        latitudeSouth: -90,
        latitudeNorth: 90,
      ),
    );
    expect(cover.precision, 1);
    expect(cover.hashes.length, 32);
  });
  test('invalid bounds are rejected', () {
    expect(
      () => ViewportGeohashService.cover(
        const LngLatBounds(
          longitudeWest: 0,
          longitudeEast: 1,
          latitudeSouth: 20,
          latitudeNorth: 10,
        ),
      ),
      throwsArgumentError,
    );
  });
}
