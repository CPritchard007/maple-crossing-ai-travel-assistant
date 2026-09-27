import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre/maplibre.dart';
import 'package:latlong2/latlong.dart';

/// Loads the bundled snapshot once; no runtime network requests are needed.
class BorderCrossingService {
  static const visibleCrossingIds = {'road-061', 'road-062', 'road-063'};

  static const assetPath = 'assets/data/us_canada_border_crossings.json';

  Future<List<BorderEntrance>> loadEntrances({AssetBundle? bundle}) async {
    final data =
        jsonDecode(await (bundle ?? rootBundle).loadString(assetPath))
            as Map<String, dynamic>;
    final entrances = <BorderEntrance>[];
    for (final entry in data['crossings'] as List<dynamic>) {
      final record = entry as Map<String, dynamic>;
      if (!visibleCrossingIds.contains(record['id'])) continue;
      // Boundary coordinates are reference data, never entrance fallbacks.
      for (final entrance
          in record['entrances'] as List<dynamic>? ?? const []) {
        final lat = (entrance['latitude'] as num).toDouble();
        final lon = (entrance['longitude'] as num).toDouble();
        if (!lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180) {
          throw const FormatException('Invalid border entrance coordinates');
        }
        entrances.add(
          BorderEntrance(
            name: record['name'] as String? ?? 'Border crossing',
            crossingId: record['id'] as String? ?? '',
            position: Position(lon, lat),
            destinationCountry: entrance['destination_country'] as String?,
            waitMinutes: (entrance['wait_minutes'] as num?)?.toInt(),
            historical:
                record['status'] == 'historical_or_restricted_review_required',
          ),
        );
      }
    }
    return combineNearby(entrances);
  }

  /// Keep a real checkpoint as the anchor, shared by the circle and popup.
  /// Unknown sides use a conservative radius to avoid merging across the border.
  List<BorderEntrance> combineNearby(List<BorderEntrance> entrances) {
    const distance = Distance();
    final combined = <BorderEntrance>[];
    for (final entrance in entrances) {
      final radius = entrance.destinationCountry == null ? 60.0 : 350.0;
      final duplicate = combined.any(
        (other) =>
            other.crossingId == entrance.crossingId &&
            other.destinationCountry == entrance.destinationCountry &&
            other.historical == entrance.historical &&
            distance(
                  LatLng(
                    other.position.lat.toDouble(),
                    other.position.lng.toDouble(),
                  ),
                  LatLng(
                    entrance.position.lat.toDouble(),
                    entrance.position.lng.toDouble(),
                  ),
                ) <=
                radius,
      );
      if (!duplicate) combined.add(entrance);
    }
    return combined;
  }

  /// Long straight visual references through paired checkpoints, not road routes.
  List<PolylineLayer> connectionsFor(List<BorderEntrance> entrances) {
    final lines = <LineString>[];
    for (final id in visibleCrossingIds) {
      final us = entrances.where(
        (e) => e.crossingId == id && e.destinationCountry == 'US',
      );
      final canada = entrances.where(
        (e) => e.crossingId == id && e.destinationCountry == 'CA',
      );
      if (us.isEmpty || canada.isEmpty) continue;
      final a = us.first.position;
      final b = canada.first.position;
      lines.add(LineString(coordinates: [a, b]));
    }
    if (lines.isEmpty) return const [];
    return [
      ZoomWeightedConnectionLayer(
        polylines: lines,
        color: const Color(0xB371DDF4),
        width: 2,
        // Two dashed strokes, centered on either side of the 28 px circles.
        gapWidth: 26,
        dashArray: const [4, 3],
      ),
    ];
  }

  Future<List<CircleLayer>> loadLayers({AssetBundle? bundle}) async =>
      layersFor(await loadEntrances(bundle: bundle));

  List<CircleLayer> layersFor(List<BorderEntrance> entrances) {
    final regular = <Point>[];
    final historical = <Point>[];
    for (final entrance in entrances) {
      (entrance.historical ? historical : regular).add(
        Point(coordinates: entrance.position),
      );
    }
    return [
      MapAlignedCircleLayer(
        points: historical,
        radius: 10,
        color: const Color(0xFF8E969F),
        strokeWidth: 2,
        strokeColor: Colors.white,
      ),
      MapAlignedCircleLayer(
        points: regular,
        radius: 14,
        color: const Color(0xFF33DAFF),
        strokeWidth: 2,
        strokeColor: Colors.white,
      ),
    ];
  }
}

/// Keeps crossing markers on the ground plane when the camera is pitched.
class MapAlignedCircleLayer extends CircleLayer {
  const MapAlignedCircleLayer({
    required super.points,
    super.radius,
    super.color,
    super.strokeWidth,
    super.strokeColor,
  });

  @override
  Map<String, Object> getPaint() => {
    ...super.getPaint(),
    'circle-radius': _zoomSize(radius.toDouble()),
    'circle-stroke-width': _zoomSize(strokeWidth.toDouble()),
    'circle-pitch-alignment': 'map',
    'circle-pitch-scale': 'map',
  };
}

// Native camera expressions animate with zoom without rebuilding the layers.
List<Object> _zoomSize(double size, {double subtract = 0}) => [
  'interpolate',
  ['linear'],
  ['zoom'],
  8,
  size * 0.25 - subtract,
  11.5,
  size * 0.45 - subtract,
  15,
  size - subtract,
  19,
  size * 1.5 - subtract,
];

/// Keep the paired dashed lines aligned with the growing regular circles.
class ZoomWeightedConnectionLayer extends PolylineLayer {
  const ZoomWeightedConnectionLayer({
    required super.polylines,
    super.color,
    super.width,
    super.gapWidth,
    super.dashArray,
  });

  @override
  Map<String, Object> getPaint() => {
    ...super.getPaint(),
    'line-gap-width': _zoomSize(28, subtract: width.toDouble()),
  };
}

class BorderEntrance {
  const BorderEntrance({
    required this.name,
    required this.crossingId,
    required this.position,
    this.destinationCountry,
    this.waitMinutes,
    this.historical = false,
  });
  final String name;
  final String crossingId;
  final Position position;

  /// Inspection-site country in the source data, not the popup travel destination.
  final String? destinationCountry;
  final int? waitMinutes;
  final bool historical;

  /// Popups describe a trip starting on the marker's side of the border.
  String? get travelDestinationCountry => switch (destinationCountry) {
    'US' => 'CA',
    'CA' => 'US',
    _ => null,
  };

  String get direction => switch (travelDestinationCountry) {
    'CA' => 'US → Canada',
    'US' => 'Canada → US',
    _ => 'US ↔ Canada',
  };
  String get durationLabel => waitMinutes == null || waitMinutes! < 0
      ? 'Wait time unavailable'
      : '$waitMinutes min wait';
}
