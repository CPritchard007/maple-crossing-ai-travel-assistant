import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maple_crossing/components/action_command_form.dart';
import 'package:maple_crossing/services/action_service.dart';

class _Actions extends ActionService {
  String? submitted;
  @override
  Future<void> execute(String feed) async {
    submitted = feed;
  }
}

void main() {
  testWidgets(
    'test button submits a complete narration, geo and highlight feed',
    (tester) async {
      final actions = _Actions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ActionCommandForm(actions: actions),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Test narration, geo & highlight'));
      await tester.pumpAndSettle();
      expect(actions.submitted, ActionCommandForm.testCase);
      final steps = actions.parse(actions.submitted!);
      expect(steps, hasLength(5));
      expect(steps[0].geo!.highlight, GeoHighlight.path);
      expect(steps[0].geo!.status, GeoStatus.hazard);
      expect(steps[1].geo!.highlight, GeoHighlight.path);
      expect(steps[2].geo!.highlight, GeoHighlight.destination);
      expect(steps[3].geo!.highlight, GeoHighlight.destination);
      expect(steps[4].geo, isNull);
      expect(steps.first.speech, isEmpty);
      expect(steps.skip(1).every((step) => step.speech.isNotEmpty), isTrue);
      expect(find.text('Actions completed.'), findsOneWidget);
    },
  );
}
