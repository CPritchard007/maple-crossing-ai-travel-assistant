import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:latlong2/latlong.dart';

import '../components/overlay.dart';
import '../components/border_popups.dart';
import '../data/lauzon_road.dart';
import '../services/road_highlight_service.dart';
import '../services/border_crossing_service.dart';
import '../services/border_wait_service.dart';
import '../services/viewport_geohash_service.dart';

/// A pitched map with a pulsing road highlight.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.initialCenter,
    this.onViewportChanged,
    this.onReady,
    this.road,
    this.initialZoom = 11.5,
    this.initialPitch = 55,
    this.mapBuilder,
  });

  /// Road to highlight. Defaults to the bundled Lauzon Road segment.
  final LineString? road;
  final VoidCallback? onReady;

  /// Use this to query data for the current screen's geohash cells.
  final ValueChanged<ViewportGeohash>? onViewportChanged;

  /// Optional camera override; otherwise centers on the selected road.
  final LatLng? initialCenter;
  final double initialZoom;

  final double initialPitch;

  /// Allows tests to replace the native map surface.
  @visibleForTesting
  final Widget Function(MapLibreMap map)? mapBuilder;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  late final RoadHighlightService _highlight = RoadHighlightService(
    vsync: this,
    road: widget.road ?? lauzonRoad,
  );

  LatLng get _center {
    final center = _highlight.center;
    return widget.initialCenter ??
        LatLng(center.lat.toDouble(), center.lng.toDouble());
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.road != widget.road) {
      _highlight.setRoad(widget.road ?? lauzonRoad);
    }
    if (oldWidget.road != widget.road ||
        oldWidget.initialCenter != widget.initialCenter) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _positionRoad());
    }
  }

  final _waits = BorderWaitService();
  List<BorderEntrance> _borderEntrances = const [];
  List<PolylineLayer> _borderConnections = const [];
  List<CircleLayer> _borderLayers = const [];
  bool _initialCameraReady = false;
  bool _mapIdle = false;
  bool _bordersLoaded = false;
  bool _readySent = false;

  void _notifyReady() {
    if (_readySent || !_initialCameraReady || !_mapIdle || !_bordersLoaded) {
      return;
    }
    _readySent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReady?.call();
      _highlight.resume();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void initState() {
    super.initState();
    // Continuous source updates prevent MapLibre from reaching its first idle.
    if (widget.onReady != null) _highlight.pause();
    _loadBorders();
    if (widget.mapBuilder == null) _waits.start();
  }

  Future<void> _loadBorders() async {
    try {
      final service = BorderCrossingService();
      final entrances = await service.loadEntrances();
      if (mounted) {
        setState(() {
          _borderEntrances = entrances;
          _borderLayers = service.layersFor(entrances);
          _borderConnections = service.connectionsFor(entrances);
        });
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'border crossings',
        ),
      );
    } finally {
      if (mounted) {
        _bordersLoaded = true;
        _notifyReady();
      }
    }
  }

  MapController? _mapController;
  final _viewportGeohashes = ViewportGeohashService();
  Timer? _viewportTimer;
  int _viewportRequest = 0;

  void _scheduleViewportUpdate() {
    _viewportTimer?.cancel();
    final request = ++_viewportRequest;
    _viewportTimer = Timer(const Duration(milliseconds: 150), () async {
      final controller = _mapController;
      if (controller == null || !mounted) return;
      final bounds = await controller.getVisibleRegion();
      if (!mounted || request != _viewportRequest) return;
      _viewportGeohashes.update(bounds);
      widget.onViewportChanged?.call(_viewportGeohashes.value!);
    });
  }

  double _viewportHeight = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final height = MediaQuery.sizeOf(context).height;
    if (_viewportHeight != height) {
      _viewportHeight = height;
      WidgetsBinding.instance.addPostFrameCallback((_) => _positionRoad());
    }
  }

  Future<void> _positionRoad() async {
    final controller = _mapController;
    if (controller == null || !mounted) return;
    if (!_readySent) _mapIdle = false;
    final center = _center;
    await controller.fitBounds(
      bounds: LngLatBounds(
        longitudeWest: center.longitude - 0.000001,
        longitudeEast: center.longitude + 0.000001,
        latitudeSouth: center.latitude - 0.000001,
        latitudeNorth: center.latitude + 0.000001,
      ),
      // Move from the midpoint (50%) to one quarter (25%) of the viewport.
      offset: Offset(0, -_viewportHeight * 0.25),
      webMaxZoom: widget.initialZoom,
      pitch: widget.initialPitch,
      webMaxDuration: Duration.zero,
      nativeDuration: Duration.zero,
    );
    _scheduleViewportUpdate();
    _initialCameraReady = true;
    _notifyReady();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload preserves State and does not rerun initState.
    _loadBorders();
    WidgetsBinding.instance.addPostFrameCallback((_) => _positionRoad());
  }

  @override
  void dispose() {
    _viewportTimer?.cancel();
    _viewportGeohashes.dispose();
    _highlight.dispose();
    _waits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _highlight,
      builder: (context, child) {
        final map = MapLibreMap(
          options: MapOptions(
            initStyle: 'https://tiles.openfreemap.org/styles/dark',
            initCenter: Position(_center.longitude, _center.latitude),
            initZoom: widget.initialZoom,
            initPitch: widget.initialPitch,
            minZoom: 2,
            maxZoom: 19,
            maxPitch: 60,
          ),
          onMapCreated: (controller) => _mapController = controller,
          onStyleLoaded: (_) => _positionRoad(),
          onEvent: (event) {
            if (event is MapEventIdle) {
              _mapIdle = true;
              _notifyReady();
            }
            if (event is MapEventMoveCamera || event is MapEventCameraIdle) {
              _scheduleViewportUpdate();
            }
          },
          layers: [
            ..._highlight.layers,
            ..._borderConnections,
            ..._borderLayers,
          ],
          children: [
            ListenableBuilder(
              listenable: _waits,
              builder: (context, _) =>
                  BorderPopups(entrances: _borderEntrances, waits: _waits),
            ),
          ],
        );
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              widget.mapBuilder?.call(map) ?? map,
              const Positioned.fill(child: IgnorePointer(child: MapOverlay())),
              const Positioned(
                bottom: 4,
                right: 8,
                child: SafeArea(
                  child: Text(
                    'Waits: Transit Barometer · Checkpoints: © OpenStreetMap contributors · Crossing inventory: Wikipedia (CC BY-SA) · OpenFreeMap · © OpenMapTiles',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFFDFE5E7),
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
