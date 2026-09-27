import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maple_crossing/components/border_popups.dart';
import 'package:maple_crossing/services/border_crossing_service.dart';

void main() {
  testWidgets('Popup shows name, actual direction and missing wait time', (
    tester,
  ) async {
    final entrance = BorderEntrance(
      name: 'Detroit–Windsor Tunnel',
      crossingId: 'tunnel',
      position: Position(-83.035, 42.315),
      destinationCountry: 'CA',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 210,
              height: 122,
              child: BorderPopup(entrance: entrance),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Detroit–Windsor Tunnel'), findsOneWidget);
    expect(find.text('Canada → US'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Unknown side and duration never invent a direction or wait', () {
    final unknown = BorderEntrance(
      name: 'Crossing',
      crossingId: 'x',
      position: Position(0, 0),
    );
    expect(unknown.direction, 'US ↔ Canada');
    expect(unknown.durationLabel, 'Wait time unavailable');
    final known = BorderEntrance(
      name: 'Crossing',
      crossingId: 'x',
      position: Position(0, 0),
      destinationCountry: 'US',
      waitMinutes: 12,
    );
    expect(known.direction, 'US → Canada');
    expect(known.durationLabel, '12 min wait');
  });
}
