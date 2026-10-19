import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/data/repositories/listening_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/listening_inbox_panel.dart';
import 'package:llplayer_next/widgets/panels/llm_feedback_assist.dart';
import 'package:llplayer_next/widgets/panels/llm_judgment_assist.dart';

/// Token provenance for the three panels that had no widget test of their own
/// before the S2 migration.
///
/// The four discipline gates read the source and can only prove that no bare
/// literal is left in it. They cannot tell `ListenIconSize.control` from any
/// other constant that happens to be in scope, and they say nothing about which
/// step a given glyph ended up on. These assertions close that half: they pump
/// the widget and read the value it actually renders.

Widget _host(Widget child) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

LocalApi _inboxApi() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'token',
  transport: (method, path, body) async {
    if (path.startsWith('/v1/listening-inbox/items')) {
      return (
        statusCode: 200,
        body:
            '[{"id":"inbox-1","target":{"kind":"sentence","sentence_id":"s1"},'
            '"anchors":[],"label":"a saved clip",'
            '"subtitle_snapshot":"who have had the most impact",'
            '"captured_at_ms":1,"status":"active","review_item_ids":[],'
            '"updated_at_ms":2,"playback_start_ms":1000,'
            '"playback_end_ms":4000}]',
      );
    }
    return (statusCode: 404, body: 'unexpected $method $path');
  },
);

void main() {
  testWidgets('the listening inbox row insets and leads with tokens', (
    tester,
  ) async {
    final api = _inboxApi();
    final controller = ExtensiveListeningController(
      repository: LocalListeningRepository(() => api),
    );
    await controller.refreshInbox();

    await tester.pumpWidget(
      _host(
        ListeningInboxPanel(
          controller: controller,
          onRefresh: () async {},
          onReplay: (_) async {},
          onProcess: (_, _) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('a saved clip'), findsOneWidget);

    // An inbox item is the repeating unit a user scans down, so it takes the
    // `row` role — not `card`, even though a `Card` draws it. At 16 the inset
    // would eat a tenth of the side panel's narrowest supported width.
    expect(
      tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.byIcon(Icons.bookmark_added_outlined),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding,
      ListenPadding.row,
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.bookmark_added_outlined)).size,
      ListenIconSize.control,
    );

    controller.dispose();
  });

  testWidgets('the feedback assist block pairs its glyphs with their text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const LlmFeedbackAssist(
          visible: true,
          feedback: 'Your second sentence changes tense halfway through.',
          busy: false,
          keyPrefix: 'writing-task',
          onRequest: _noop,
        ),
      ),
    );

    // The block sits under a divider, so its top inset is a gap, not a
    // container role: `gap12`, the step the off-ladder 14 rounds down to.
    expect(
      tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.byIcon(Icons.auto_awesome),
                  matching: find.byType(Padding),
                )
                .last,
          )
          .padding,
      const EdgeInsets.only(top: ListenSpacing.gap12),
    );

    // `inline`, not `control`: this glyph marks a section heading set in
    // `ListenType.body` (12px). An 18pt icon beside 12px text is the "icon
    // outweighs its label" drift the ladder exists to stop.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.auto_awesome)).size,
      ListenIconSize.inline,
    );
  });

  testWidgets('the judgment assist keeps its verdict rows dense', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LlmJudgmentAssist(
          visible: true,
          points: const [
            RubricPointView(
              pointId: 'p1',
              importance: 'required',
              statement: 'Names who the ban affected.',
            ),
          ],
          judgment: null,
          adjudications: const [],
          busy: false,
          keyPrefix: 'reading-task',
          onRequest: _noop,
          onCorrect: (_, _) {},
        ),
      ),
    );

    // With no judgment yet only the request button shows, and its label is
    // 14px, so its glyph is `control`.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.auto_awesome_outlined)).size,
      ListenIconSize.control,
    );
  });
}

void _noop() {}
