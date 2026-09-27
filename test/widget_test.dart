import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/screens/map_screen.dart';
import 'package:maple_crossing/components/overlay.dart';

void main() {
  testWidgets('Pitched map pulses the road with a full-screen overlay', (
    tester,
  ) async {
    late MapLibreMap map;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          mapBuilder: (value) {
            map = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(map.options.initPitch, 55);
    expect(map.options.initCenter!.lat, closeTo(42.325242, 0.01));
    final initialWidth = (map.layers.first as PolylineLayer).width;
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      (map.layers.first as PolylineLayer).width,
      greaterThan(initialWidth),
    );
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Dismiss build notice'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss build notice'));
    await tester.pump();
    expect(
      find.textContaining('This application is not a finished build.'),
      findsNothing,
    );
    expect(
      tester.getSize(find.byType(MapOverlay)),
      tester.getSize(find.byType(Scaffold)),
    );
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(
                  of: find.byType(MapOverlay),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );
    expect(map.children, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Replacing a road updates the themed geometry and camera target',
    (tester) async {
      late MapLibreMap map;
      Widget screen(LineString road) => MaterialApp(
        home: MapScreen(
          road: road,
          mapBuilder: (value) {
            map = value;
            return const SizedBox.expand();
          },
        ),
      );
      final first = LineString(
        coordinates: [Position(-83, 42), Position(-82.9, 42.1)],
      );
      final second = LineString(
        coordinates: [Position(-79.4, 43.6), Position(-79.3, 43.7)],
      );
      await tester.pumpWidget(screen(first));
      expect(map.options.initCenter!.lng, closeTo(-82.95, 0.00001));
      await tester.pumpWidget(screen(second));
      expect(map.options.initCenter!.lng, closeTo(-79.35, 0.00001));
      expect(map.layers.length, 3);
      expect((map.layers.last as PolylineLayer).width, 13);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
