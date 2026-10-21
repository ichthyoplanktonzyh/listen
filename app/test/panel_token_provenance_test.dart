import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/data/repositories/listening_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/listening_inbox_panel.dart';

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
}
