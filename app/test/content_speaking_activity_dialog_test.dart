import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/content_activity.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/widgets/flows/content_speaking_activity_dialog.dart';

void main() {
  testWidgets('content speaking chooser keeps conversation beside practices', (
    tester,
  ) async {
    ContentSpeakingActivity? selected;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showContentSpeakingActivityDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('content-activity-retelling')), findsOne);
    expect(find.byKey(const ValueKey('content-activity-shadowing')), findsOne);
    expect(
      find.byKey(const ValueKey('content-activity-conversation')),
      findsOne,
    );

    // S2 token provenance: three named choices are a column of decisions, so
    // the chooser takes `formColumnMax` rather than the 440 it hard-coded.
    expect(
      tester
          .widget<ConstrainedBox>(
            find
                .ancestor(
                  of: find.byKey(
                    const ValueKey('content-activity-conversation'),
                  ),
                  matching: find.byType(ConstrainedBox),
                )
                .first,
          )
          .constraints
          .maxWidth,
      ListenBreakpoints.formColumnMax,
    );

    await tester.tap(
      find.byKey(const ValueKey('content-activity-conversation')),
    );
    await tester.pumpAndSettle();
    expect(selected, ContentSpeakingActivity.conversation);
  });
}
