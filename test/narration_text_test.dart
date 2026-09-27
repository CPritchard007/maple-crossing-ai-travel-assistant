import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maple_crossing/components/overlay.dart';

void main() {
  testWidgets('fixed size narration follows playback and resets for new text', (
    tester,
  ) async {
    final progress = ValueNotifier<double>(0);
    final longText = List.filled(100, 'Readable narration.').join(' ');
    Future<void> show(String text) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 140,
            child: NarrationText(text: text, progress: progress),
          ),
        ),
      ),
    );
    await show(longText);
    expect(tester.widget<Text>(find.text(longText)).style!.fontSize, 24);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, 0);
    progress.value = 0.5;
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    progress.value = 1;
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    await show('Short narration.');
    expect(scroll.position.pixels, 0);
    expect(
      tester.widget<Text>(find.text('Short narration.')).style!.fontSize,
      24,
    );
    await tester.pumpWidget(const SizedBox());
    progress.dispose();
  });
}
