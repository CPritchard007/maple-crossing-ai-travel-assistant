import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

/// Renders supplied road geometry with the shared neon-tube theme.
/// Coordinates use longitude, latitude order. Dispose with the owning widget.
class RoadHighlightService extends ChangeNotifier {
  RoadHighlightService({
    required TickerProvider vsync,
    required LineString road,
  }) {
    setRoad(road);
    _pulse = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1800),
    )..addListener(notifyListeners);
    _pulse.repeat(reverse: true);
  }

  late final AnimationController _pulse;
  late LineString _road;
  Color _color = Colors.red;

  void setColor(Color color) {
    _color = color;
    notifyListeners();
  }

  void pause() => _pulse.stop();
  void resume() => _pulse.repeat(reverse: true);

  /// Replace the highlighted road without restarting the animation.
  void setRoad(LineString road) {
    if (road.coordinates.length < 2 ||
        road.coordinates.any(
          (p) =>
              !p.lng.isFinite ||
              !p.lat.isFinite ||
              p.lng < -180 ||
              p.lng > 180 ||
              p.lat < -90 ||
              p.lat > 90,
        )) {
      throw ArgumentError(
        'A road requires at least two valid longitude/latitude coordinates.',
      );
    }
    _road = LineString(coordinates: List.unmodifiable(road.coordinates));
    notifyListeners();
  }

  Position get center {
    final points = _road.coordinates;
    final west = points.map((p) => p.lng).reduce((a, b) => a < b ? a : b);
    final east = points.map((p) => p.lng).reduce((a, b) => a > b ? a : b);
    final south = points.map((p) => p.lat).reduce((a, b) => a < b ? a : b);
    final north = points.map((p) => p.lat).reduce((a, b) => a > b ? a : b);
    return Position((west + east) / 2, (south + north) / 2);
  }

  double get pulse => Curves.easeInOut.transform(_pulse.value);

  List<PolylineLayer> get layers {
    return [
      // Wide, diffuse light spill, with a fixed footprint as brightness breathes.
      NeonRoadLayer(
        polylines: [_road],
        color: _color.withValues(alpha: 0.18 + pulse * 0.08),
        width: 34,
        blur: 24,
      ),
      NeonRoadLayer(
        polylines: [_road],
        color: _color.withValues(alpha: 0.48 + pulse * 0.14),
        width: 17,
        blur: 10,
      ),
      NeonRoadLayer(polylines: [_road], color: _color, width: 7, blur: 2),
      // A continuous near-white filament keeps the tube crisp and readable.
      NeonRoadLayer(
        polylines: [_road],
        color: Color.lerp(_color, Colors.white, 0.82 + pulse * 0.08)!,
        width: 3,
        blur: 1,
      ),
    ];
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
}

/// PolylineLayer 0.2.2 omits its blur property from the generated paint.
/// Apply it explicitly and round joins/caps so the road reads as a light tube.
class NeonRoadLayer extends PolylineLayer {
  const NeonRoadLayer({
    required super.polylines,
    required super.color,
    required super.width,
    required super.blur,
  });

  @override
  Map<String, Object> getPaint() => {...super.getPaint(), 'line-blur': blur};

  @override
  Map<String, Object> getLayout() => {
    'line-cap': 'round',
    'line-join': 'round',
  };
}
