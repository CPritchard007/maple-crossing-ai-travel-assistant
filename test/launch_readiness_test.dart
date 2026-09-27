import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/screens/map_screen.dart';
import 'package:maple_crossing/services/border_crossing_service.dart';

class _MapController implements MapController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fitBounds) return Future<void>.value();
    if (invocation.memberName == #getVisibleRegion) {
      return Future.value(
        const LngLatBounds(
          longitudeWest: -84,
          longitudeEast: -82,
          latitudeSouth: 42,
          latitudeNorth: 43,
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _StyleController implements StyleController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Launch completes once, after camera positioning and map idle', (
    tester,
  ) async {
    rootBundle.evict(BorderCrossingService.assetPath);
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (_) async {
        return ByteData.sublistView(utf8.encode('{"crossings":[]}'));
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      ),
    );
    late MapLibreMap map;
    var readyCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          onReady: () => readyCalls++,
          mapBuilder: (value) {
            map = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pump();
    expect(readyCalls, 0);
    map.onMapCreated!(_MapController());
    map.onStyleLoaded!(_StyleController());
    await tester.pump();
    expect(readyCalls, 0);
    map.onEvent!(const MapEventIdle());
    await tester.pump();
    expect(readyCalls, 1);
    map.onEvent!(const MapEventIdle());
    await tester.pump();
    expect(readyCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
