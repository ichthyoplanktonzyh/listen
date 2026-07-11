import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/vocabulary/dictionary_inline_clip_player.dart';

void main() {
  testWidgets('renders source playback as document-flow content', (
    tester,
  ) async {
    final controller = SlicePlayerController();
    await controller.showError('Could not locate source media');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const Text('Entry detail before player'),
              DictionaryInlineClipPlayer(
                controller: controller,
                occurrence: const LexicalOccurrence(
                  mediaTitleSnapshot: 'Personal media',
                  mediaFingerprintSnapshot: 'fp',
                  sentenceTextSnapshot: 'Their lives changed overnight.',
                  startMsSnapshot: 1000,
                  endMsSnapshot: 3000,
                  encounterCount: 1,
                ),
                target: 'their',
                onClose: () {},
              ),
              const Text('Entry detail after player'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Entry detail before player'), findsOneWidget);
    expect(find.text('Entry detail after player'), findsOneWidget);
    expect(find.text('Could not locate source media'), findsOneWidget);
    expect(find.byType(Positioned), findsNothing);
    controller.dispose();
  });
}
