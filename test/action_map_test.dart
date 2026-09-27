import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/screens/map_screen.dart';
import 'package:maple_crossing/services/action_service.dart';

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
            final marker = map.layers.first as CircleLayer;
            expect(marker.color, colors[status]);
            expect(marker.radius, kind == 'destination' ? 30 : 20);
          }
          final count = map.layers.length;
          await tester.runAsync(
            () => actions.execute('((geo lat="42.3149" lng="-83.0364"))'),
          );
          await tester.pump();
          expect(camera.bounds!.longitudeWest, closeTo(-83.0365, 0.000001));
          expect(map.layers.length, lessThan(count));
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
    final marker = map.layers.first as CircleLayer;
    expect(find.text('Arrived'), findsOneWidget);
    expect(find.text('One Moment Please...'), findsNothing);
    expect(marker.radius, 30);
    expect(marker.color, const Color(0xFF64B5F6));
    final highlightedLayerCount = map.layers.length;
    await tester.runAsync(
      () => actions.execute('((geo lat="42.1" lng="-82.7"))'),
    );
    await tester.pump();
    expect(camera.bounds!.longitudeEast, closeTo(-82.6999, 0.000001));
    expect(map.layers.length, highlightedLayerCount - 1);
    expect(find.text('Arrived'), findsOneWidget);
    await tester.runAsync(
      () => actions.execute('((highlight lat="42.1" lng="-82.7"))'),
    );
    await tester.pump();
    expect((map.layers.first as CircleLayer).radius, 20);
    await tester.pumpWidget(const SizedBox());
  });
}
