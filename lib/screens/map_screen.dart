import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:latlong2/latlong.dart';

import '../components/overlay.dart';
import '../components/location_arrow.dart';
import '../components/action_command_form.dart';
import '../components/support_button.dart';
import '../components/build_notice.dart';
import '../components/border_popups.dart';
import '../data/lauzon_road.dart';
import '../services/road_highlight_service.dart';
import '../services/road_closure_service.dart';
import '../services/action_service.dart';
import '../services/user_location_service.dart';
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
    this.actions,
    this.locateUser,
  });

  /// Road to highlight. Defaults to the bundled Lauzon Road segment.
  final LineString? road;
  final ActionService? actions;

  @visibleForTesting
  final Future<LatLng?> Function()? locateUser;
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

  late void Function() _detachActions;
  final _styleReady = Completer<void>();
  GeoAction? _geoAction;
  final _location = UserLocationService();
  final _closures = RoadClosureService();
  LatLng? _userPosition;
  bool _returningHome = false;
  Future<LatLng?>? _initialLocation;

  Future<void> _locateAtStartup() async {
    final position = await _initialLocation;
    if (!mounted || position == null) return;
    setState(() => _userPosition = position);
    if (!_actions.isRunning && _geoAction == null) await _positionRoad();
  }

  Future<void> _returnToUser() async {
    if (_initialLocation == null) return;
    final position = await (widget.locateUser?.call() ?? _location.locate());
    if (!mounted) return;
    final target = position ?? _userPosition;
    if (target == null) return;
    setState(() {
      _userPosition = target;
      _geoAction = null;
      _returningHome = true;
    });
    try {
      await _positionRoad();
    } finally {
      _returningHome = false;
    }
  }

  ActionService get _actions => widget.actions ?? actionService;

  Color _statusColor(GeoStatus status) => switch (status) {
    GeoStatus.recommendation => const Color(0xFF82D5B0),
    GeoStatus.hazard => Colors.red,
    GeoStatus.summary => const Color(0xFF64B5F6),
  };

  Future<void> _applyGeoAction(GeoAction action) async {
    if (widget.mapBuilder == null) await _styleReady.future;
    if (!mounted) throw StateError('Map was disposed.');
    setState(() => _geoAction = action);
    if (action.highlight == GeoHighlight.path) {
      _highlight.setColor(_statusColor(action.status));
      _highlight.setRoad(
        LineString(
          coordinates: [
            for (final p in action.coordinates)
              Position(p.longitude, p.latitude),
          ],
        ),
      );
    }
    await _positionGeoAction(action);
  }

  Completer<void>? _actionCameraIdle;

  Future<void> _positionGeoAction(GeoAction action) async {
    final controller = _mapController;
    if (controller == null || !mounted) return;
    final lats = action.coordinates.map((p) => p.latitude);
    final lngs = action.coordinates.map((p) => p.longitude);
    double minimum(double a, double b) => a < b ? a : b;
    double maximum(double a, double b) => a > b ? a : b;
    final idle = widget.mapBuilder == null ? Completer<void>() : null;
    _actionCameraIdle?.complete();
    _actionCameraIdle = idle;
    try {
      await controller.fitBounds(
        bounds: LngLatBounds(
          longitudeWest: (lngs.reduce(minimum) - 0.0001).clamp(-180, 180),
          longitudeEast: (lngs.reduce(maximum) + 0.0001).clamp(-180, 180),
          latitudeSouth: (lats.reduce(minimum) - 0.0001).clamp(-90, 90),
          latitudeNorth: (lats.reduce(maximum) + 0.0001).clamp(-90, 90),
        ),
        offset: Offset(0, -_viewportHeight * 0.20),
        webMaxZoom: action.highlight == GeoHighlight.none ? 15 : 17,
        pitch: widget.initialPitch,
        // A web maxDuration makes longer flights instant rather than capping them.
        webSpeed: 0.8,
        nativeDuration: const Duration(milliseconds: 1500),
      );
      if (idle != null) {
        await idle.future.timeout(const Duration(seconds: 30));
      }
    } finally {
      if (identical(_actionCameraIdle, idle)) _actionCameraIdle = null;
    }
    if (mounted) _scheduleViewportUpdate();
  }

  List<Marker> get _actionPoints {
    final action = _geoAction;
    if (action == null ||
        action.highlight == GeoHighlight.none ||
        action.highlight == GeoHighlight.path) {
      return [];
    }
    final p = action.coordinates.single;
    final size = action.highlight == GeoHighlight.destination ? 72.0 : 56.0;
    return [
      Marker(
        point: Position(p.longitude, p.latitude),
        size: Size.square(size),
        alignment: Alignment.bottomCenter,
        child: LocationArrow(color: _statusColor(action.status)),
      ),
    ];
  }

  LatLng get _center {
    final center = _highlight.center;
    return widget.initialCenter ??
        _userPosition ??
        LatLng(center.lat.toDouble(), center.lng.toDouble());
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actions != widget.actions) {
      _detachActions();
      _detachActions = _actions.attachMap(
        _applyGeoAction,
        onFinished: _returnToUser,
      );
    }
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
    _detachActions = _actions.attachMap(
      _applyGeoAction,
      onFinished: _returnToUser,
    );
    if (widget.mapBuilder == null || widget.locateUser != null) {
      _initialLocation =
          widget.locateUser?.call() ??
          _location.locate(requestPermission: true);
      unawaited(_locateAtStartup());
    }
    // Continuous source updates prevent MapLibre from reaching its first idle.
    if (widget.onReady != null) _highlight.pause();
    _loadBorders();
    if (widget.mapBuilder == null) _waits.start();
    _closures.addListener(_closuresChanged);
    if (widget.mapBuilder == null) _closures.start();
  }

  void _closuresChanged() {
    if (mounted) setState(() {});
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
    if (!_initialCameraReady && _initialLocation != null) {
      try {
        _userPosition = await _initialLocation!.timeout(
          const Duration(seconds: 15),
        );
      } on TimeoutException {
        // Start with the default view while permission is still pending.
      }
      if (!mounted) return;
    }
    if (_geoAction != null) {
      await _positionGeoAction(_geoAction!);
      return;
    }
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
      webMaxZoom: _userPosition != null ? 15 : widget.initialZoom,
      pitch: widget.initialPitch,
      webMaxDuration: _returningHome ? null : Duration.zero,
      nativeDuration: _returningHome
          ? const Duration(milliseconds: 1500)
          : Duration.zero,
    );
    _scheduleViewportUpdate();
    _initialCameraReady = true;
    _notifyReady();
    if (!_styleReady.isCompleted) _styleReady.complete();
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
    _detachActions();
    _actionCameraIdle?.complete();
    _actionCameraIdle = null;
    if (!_styleReady.isCompleted) _styleReady.complete();
    _viewportTimer?.cancel();
    _viewportGeohashes.dispose();
    _highlight.dispose();
    _waits.dispose();
    _closures.dispose();
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
            if (event is MapEventCameraIdle) {
              _actionCameraIdle?.complete();
              _actionCameraIdle = null;
            }
            if (event is MapEventIdle) {
              _mapIdle = true;
              _notifyReady();
            }
            if (event is MapEventMoveCamera || event is MapEventCameraIdle) {
              _scheduleViewportUpdate();
            }
          },
          layers: [
            ..._closures.layersAt(_highlight.pulse),
            if (_userPosition != null)
              CircleLayer(
                points: [
                  Point(
                    coordinates: Position(
                      _userPosition!.longitude,
                      _userPosition!.latitude,
                    ),
                  ),
                ],
                radius: 8,
                color: const Color(0xFF448AFF),
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            if ((_geoAction == null && widget.road != null) ||
                _geoAction?.highlight == GeoHighlight.path)
              ..._highlight.layers,
            ..._borderConnections,
            ..._borderLayers,
          ],
          children: [
            if (_actionPoints.isNotEmpty) WidgetLayer(markers: _actionPoints),
            ListenableBuilder(
              listenable: _waits,
              builder: (context, _) =>
                  BorderPopups(entrances: _borderEntrances, waits: _waits),
            ),
          ],
        );
        return Scaffold(
          drawer: Drawer(
            backgroundColor: const Color(0xFF182024),
            child: SafeArea(
              child: Builder(
                builder: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Close menu',
                            icon: const Icon(
                              Icons.menu,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => Scaffold.of(context).closeDrawer(),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'Maple Crossing',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white24),
                    ListTile(
                      leading: const Icon(
                        Icons.map_outlined,
                        color: Colors.white,
                      ),
                      title: const Text(
                        'Map',
                        style: TextStyle(color: Colors.white),
                      ),
                      selected: true,
                      onTap: () => Scaffold.of(context).closeDrawer(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: ActionCommandForm(actions: _actions),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        _closures.label,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: SupportButton(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              widget.mapBuilder?.call(map) ?? map,
              Positioned.fill(child: MapOverlay(actions: _actions)),
              const BuildNotice(),
              const Positioned(
                bottom: 4,
                right: 8,
                child: SafeArea(
                  child: Text(
                    'Closures: © TomTom · Waits: Transit Barometer · Checkpoints: © OpenStreetMap contributors · Crossing inventory: Wikipedia (CC BY-SA) · OpenFreeMap · © OpenMapTiles',
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
