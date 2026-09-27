import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

/// Renders supplied road geometry with the shared pulsing red theme.
/// Coordinates use longitude, latitude order. Dispose with the owning widget.
class RoadHighlightService extends ChangeNotifier {
  RoadHighlightService({
    required TickerProvider vsync,
    required LineString road,
  }) {
    setRoad(road);
    _pulse = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1200),
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

  List<PolylineLayer> get layers {
    final pulse = Curves.easeInOut.transform(_pulse.value);
    return [
      PolylineLayer(
        polylines: [_road],
        color: _color.withValues(alpha: 0.10 + pulse * 0.18),
        width: (45 + pulse * 30).round(),
      ),
      PolylineLayer(
        polylines: [_road],
        color: _color.withValues(alpha: 0.25 + pulse * 0.30),
        width: (25 + pulse * 12).round(),
      ),
      PolylineLayer(
        polylines: [_road],
        color: Color.lerp(
          _color,
          Color.lerp(_color, Colors.white, 0.45)!,
          pulse,
        )!,
        width: 13,
      ),
    ];
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
}
