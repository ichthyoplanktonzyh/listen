import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/slice_playback_window.dart';

void main() {
  testWidgets('renders an invalid source range as an actionable window', (
    tester,
  ) async {
    final controller = SlicePlayerController();
    await controller.open(
      path: '/media/source.mp4',
      occurrence: const {'start_ms_snapshot': 5000, 'end_ms_snapshot': 2000},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SlicePlaybackWindow(
                controller: controller,
                onClose: controller.close,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Source clip'), findsOneWidget);
    expect(
      find.text('This source clip has an invalid time range'),
      findsOneWidget,
    );

    // S2 token provenance: the window's identity glyph is a `control` (it sits
    // beside a 13px title) and the error body insets at the `card` role, the
    // same inset the normal body uses — the two used to be 20 and 18.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.headphones_outlined)).size,
      ListenIconSize.control,
    );
    expect(
      tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.text('This source clip has an invalid time range'),
                  matching: find.byType(Padding),
                )
                .last,
          )
          .padding,
      ListenPadding.card,
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(controller.state.open, isFalse);
    controller.dispose();
  });
}
