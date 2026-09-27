import 'package:flutter/material.dart';
import 'package:maple_crossing/components/location_arrow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:latlong2/latlong.dart';
import 'package:maple_crossing/screens/map_screen.dart';
import 'package:maple_crossing/services/action_service.dart';

class _Style implements StyleController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Camera implements MapController {
  LngLatBounds? bounds;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fitBounds) {
      bounds = invocation.namedArguments[#bounds] as LngLatBounds;
      return Future<void>.value();
    }
    if (invocation.memberName == #getVisibleRegion) {
      return Future.value(bounds!);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets('unavailable user location preserves action camera behavior', (
    tester,
  ) async {
    late MapLibreMap map;
    final camera = _Camera();
    final actions = ActionService(speak: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          actions: actions,
          locateUser: () async => null,
          mapBuilder: (value) {
            map = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    map.onMapCreated!(camera);
    await tester.runAsync(() async {
      map.onStyleLoaded!(_Style());
      await Future<void>.delayed(Duration.zero);
      await actions.execute('Visit ((geo lat="42.1" lng="-82.7")) Done');
    });
    await tester.pump();
    expect(camera.bounds!.longitudeWest, closeTo(-82.7, 0.001));
    expect(camera.bounds!.latitudeSouth, closeTo(42.1, 0.001));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starts at user location and returns after a narrated action', (
    tester,
  ) async {
    late MapLibreMap map;
    final camera = _Camera();
    final actions = ActionService(speak: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          actions: actions,
          locateUser: () async => const LatLng(42.35, -83.05),
          mapBuilder: (value) {
            map = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    map.onMapCreated!(camera);
    await tester.runAsync(() async {
      map.onStyleLoaded!(_Style());
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(camera.bounds!.longitudeWest, closeTo(-83.05, 0.00001));
    await tester.runAsync(
      () => actions.execute('Visit ((geo lat="42.1" lng="-82.7")) Done'),
    );
    await tester.pump();
    expect(camera.bounds!.longitudeWest, closeTo(-83.05, 0.00001));
    expect(camera.bounds!.latitudeSouth, closeTo(42.35, 0.00001));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all highlight statuses and intents render and replace correctly', (
    tester,
  ) async {
    late MapLibreMap map;
    final camera = _Camera();
    final actions = ActionService(speak: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          actions: actions,
          mapBuilder: (value) {
            map = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    map.onMapCreated!(camera);
    final colors = {
      'recommendation': const Color(0xFF82D5B0),
      'hazard': Colors.red,
      'summary': const Color(0xFF64B5F6),
    };
    for (final status in colors.keys) {
      for (final intent in ['waypoint', 'reroute', 'terminate']) {
        for (final kind in ['point', 'destination', 'path']) {
          final geometry = kind == 'path'
              ? 'path="42.326792,-82.9397677;42.3236127,-82.9378624"'
              : 'lat="42.326792" lng="-82.9397677"';
          await tester.runAsync(
            () => actions.execute(
              '((highlight $geometry highlight="$kind" type="$status" action="$intent"))',
            ),
          );
          await tester.pump();
          expect(camera.bounds!.longitudeWest, closeTo(-82.9398677, 0.000001));
          if (kind == 'path') {
            final road = map.layers.first as PolylineLayer;
            expect(road.list.single.coordinates, hasLength(2));
            // Pulse layers deliberately vary opacity while retaining the status hue.
            expect(
              road.color.withValues(alpha: 1).toARGB32(),
              colors[status]!.toARGB32(),
            );
          } else {
            final marker = map.children
                .whereType<WidgetLayer>()
                .single
                .markers
                .single;
            expect((marker.child as LocationArrow).color, colors[status]);
            expect(marker.alignment, Alignment.bottomCenter);
            expect(marker.point.lng, -82.9397677);
            expect(marker.point.lat, 42.326792);
            expect(marker.size.width, kind == 'destination' ? 72 : 56);
          }
          final count = map.layers.length + map.children.length;
          await tester.runAsync(
            () => actions.execute('((geo lat="42.3149" lng="-83.0364"))'),
          );
          await tester.pump();
          expect(camera.bounds!.longitudeWest, closeTo(-83.0365, 0.000001));
          expect(map.layers.length + map.children.length, lessThan(count));
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('feed updates road geometry, status color and destination marker', (
    tester,
  ) async {
    late MapLibreMap map;
    final camera = _Camera();
    final actions = ActionService(speak: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          actions: actions,
          mapBuilder: (value) {
            map = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    map.onMapCreated!(camera);
    await tester.runAsync(
      () => actions.execute(
        'Road warning ((geo type="hazard" action="reroute" highlight="path" path="42.3,-83.0;42.4,-82.9"))',
      ),
    );
    await tester.pump();
    expect(camera.bounds!.longitudeWest, closeTo(-83.0001, 0.000001));
    expect(camera.bounds!.latitudeNorth, closeTo(42.4001, 0.000001));
    final layer = map.layers.first as PolylineLayer;
    expect(layer.list.single.coordinates.first.lng, -83.0);
    expect(layer.list.single.coordinates.first.lat, 42.3);
    await tester.runAsync(
      () => actions.execute(
        'Arrived ((geo lat="42.2" lng="-82.8" type="summary" action="terminate" highlight="destination"))',
      ),
    );
    await tester.pump();
    expect(camera.bounds!.longitudeEast, closeTo(-82.7999, 0.000001));
    final marker = map.children.whereType<WidgetLayer>().single.markers.single;
    expect(find.text('Arrived'), findsOneWidget);
    expect(find.text('One Moment Please...'), findsNothing);
    expect(marker.size.width, 72);
    expect((marker.child as LocationArrow).color, const Color(0xFF64B5F6));
    final highlightedLayerCount = map.children.length;
    await tester.runAsync(
      () => actions.execute('((geo lat="42.1" lng="-82.7"))'),
    );
    await tester.pump();
    expect(camera.bounds!.longitudeEast, closeTo(-82.6999, 0.000001));
    expect(map.children.length, highlightedLayerCount - 1);
    expect(find.text('Arrived'), findsOneWidget);
    await tester.runAsync(
      () => actions.execute('((highlight lat="42.1" lng="-82.7"))'),
    );
    await tester.pump();
    expect(
      (map.children.whereType<WidgetLayer>().single.markers.single).size.width,
      56,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
