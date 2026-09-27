import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maple_crossing/components/overlay.dart';
import 'package:maple_crossing/services/action_service.dart';
import 'package:maple_crossing/services/app_instance_service.dart';

void main() {
  testWidgets(
    'overlay listens directly and retains text for action-only steps',
    (tester) async {
      final actions = ActionService(
        speak: (_) async {},
        onMapAction: (_) async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapOverlay(actions: actions)),
        ),
      );
      await tester.runAsync(
        () =>
            actions.execute('Watch this crossing ((geo lat="42.3" lng="-83"))'),
      );
      await tester.pump();
      expect(find.text('Watch this crossing'), findsOneWidget);
      expect(find.text('One Moment Please...'), findsNothing);
      await tester.runAsync(
        () => actions.execute('((highlight lat="42.3" lng="-83"))'),
      );
      await tester.pump();
      expect(find.text('Watch this crossing'), findsOneWidget);
      await tester.runAsync(() => actions.execute('Updated notice'));
      await tester.pump();
      expect(find.text('Updated notice'), findsOneWidget);
      expect(find.text('Watch this crossing'), findsNothing);
    },
  );

  for (final success in [true, false]) {
    testWidgets('registration ends loading on success=$success', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      final service = AppInstanceService(
        client: MockClient((_) => response.future),
      );
      final initialization = service.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapOverlay(instanceService: service)),
        ),
      );
      expect(find.text('Initializing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      response.complete(
        http.Response(
          jsonEncode({'instanceId': service.instanceId}),
          success ? 200 : 400,
        ),
      );
      await tester.runAsync(() => initialization);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text(success ? 'Connected' : 'Connection unavailable'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  }
}
