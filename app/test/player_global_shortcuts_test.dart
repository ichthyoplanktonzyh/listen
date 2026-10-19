import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/widgets/player/player_global_shortcuts.dart';

void main() {
  testWidgets('player shortcuts handle keys when text input is not focused', (
    tester,
  ) async {
    var hideSubtitleCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerGlobalShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyH): () {
              hideSubtitleCalls += 1;
            },
          },
          child: const Focus(
            autofocus: true,
            child: Scaffold(body: Center(child: Text('player'))),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);

    expect(hideSubtitleCalls, 1);
  });

  testWidgets('player shortcuts yield to focused text input', (tester) async {
    var hideSubtitleCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerGlobalShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyH): () {
              hideSubtitleCalls += 1;
            },
          },
          child: const Focus(
            autofocus: true,
            child: Scaffold(
              body: Center(child: SizedBox(width: 240, child: TextField())),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);

    expect(hideSubtitleCalls, 0);
  });
}
