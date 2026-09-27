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
      expect(steps, hasLength(3));
      expect(steps[0].geo!.highlight, GeoHighlight.none);
      expect(steps[1].geo!.highlight, GeoHighlight.path);
      expect(steps[2].geo, isNull);
      expect(steps.every((step) => step.speech.isNotEmpty), isTrue);
      expect(find.text('Actions completed.'), findsOneWidget);
    },
  );
}
