import 'package:flutter/foundation.dart';
import 'package:maplibre/maplibre.dart';

/// A geohash cover of the visible region's bounding box. With pitch/bearing,
/// this conservatively includes the screen corners, not just its center.
class ViewportGeohash {
  const ViewportGeohash({
    required this.bounds,
    required this.hashes,
    required this.precision,
  });

  final LngLatBounds bounds;
  final Set<String> hashes;
  final int precision;
}

/// Subscribe to [value], or call [cover] to query any geographic rectangle.
/// MapLibre independently requests/culls XYZ tiles for the same camera region;
/// geohashes are a spatial query index, not replacements for XYZ tile IDs.
class ViewportGeohashService extends ValueNotifier<ViewportGeohash?> {
  ViewportGeohashService() : super(null);

  static const _alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

  void update(LngLatBounds bounds) {
    if (value?.bounds == bounds) return;
    value = cover(bounds);
  }

  static String encode(double latitude, double longitude, {int precision = 5}) {
    if (precision < 1 ||
        precision > 8 ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      throw ArgumentError('Invalid coordinate or geohash precision');
    }
    var west = -180.0, east = 180.0, south = -90.0, north = 90.0;
    var character = 0;
    final result = StringBuffer();
    for (var bit = 0; bit < precision * 5; bit++) {
      character <<= 1;
      if (bit.isEven) {
        final middle = (west + east) / 2;
        if (longitude >= middle) {
          character |= 1;
          west = middle;
        } else {
          east = middle;
        }
      } else {
        final middle = (south + north) / 2;
        if (latitude >= middle) {
          character |= 1;
          south = middle;
        } else {
          north = middle;
        }
      }
      if (bit % 5 == 4) {
        result.write(_alphabet[character]);
        character = 0;
      }
    }
    return result.toString();
  }

  /// Precision automatically decreases for wide views to bound query size.
  /// Handles date-line crossings and longitudes from wrapped map worlds.
  static ViewportGeohash cover(
    LngLatBounds bounds, {
    int precision = 5,
    int maxCells = 256,
  }) {
    final south = bounds.latitudeSouth, north = bounds.latitudeNorth;
    final west = bounds.longitudeWest, east = bounds.longitudeEast;
    if (precision < 1 ||
        precision > 8 ||
        maxCells < 32 ||
        !south.isFinite ||
        !north.isFinite ||
        !west.isFinite ||
        !east.isFinite ||
        south < -90 ||
        north > 90 ||
        south > north) {
      throw ArgumentError('Invalid viewport bounds or cover limits');
    }
    final start = (west + 180) % 360 - 180;
    final rawWidth = east - west;
    final width = rawWidth.abs() >= 360 ? 360.0 : rawWidth % 360;
    final end = start + width;
    final intervals = width == 360
        ? [(-180.0, 180.0)]
        : end > 180
        ? [(start, 180.0), (-180.0, end - 360)]
        : [(start, end)];
    while (true) {
      final latitudeCells = 1 << (precision * 5 ~/ 2);
      final longitudeCells = 1 << ((precision * 5 + 1) ~/ 2);
      final dy = 180 / latitudeCells, dx = 360 / longitudeCells;
      final y0 = ((south + 90) / dy).floor().clamp(0, latitudeCells - 1);
      final y1 = ((north + 90) / dy).floor().clamp(0, latitudeCells - 1);
      final ranges = intervals
          .map(
            (range) => (
              ((range.$1 + 180) / dx).floor().clamp(0, longitudeCells - 1),
              ((range.$2 + 180) / dx).floor().clamp(0, longitudeCells - 1),
            ),
          )
          .toList();
      final count = ranges.fold<int>(
        0,
        (sum, r) => sum + (r.$2 - r.$1 + 1) * (y1 - y0 + 1),
      );
      if (count > maxCells && precision > 1) {
        precision--;
        continue;
      }
      final hashes = <String>{};
      for (final range in ranges) {
        for (var x = range.$1; x <= range.$2; x++) {
          for (var y = y0; y <= y1; y++) {
            hashes.add(
              encode(
                -90 + (y + .5) * dy,
                -180 + (x + .5) * dx,
                precision: precision,
              ),
            );
          }
        }
      }
      return ViewportGeohash(
        bounds: bounds,
        hashes: Set.unmodifiable(hashes),
        precision: precision,
      );
    }
  }
}
