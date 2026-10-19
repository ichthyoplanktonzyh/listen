import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/cold_start_marking_view_model.dart';
import 'package:llplayer_next/data/repositories/cold_start_marking_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/theme/typography.dart';
import 'package:llplayer_next/widgets/panels/cold_start_marking_sheet.dart';

LocalApi _api() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'token',
  transport: (method, path, body) async {
    if (path.contains('cold-start-words')) {
      return (
        statusCode: 200,
        body:
            '[{"display_form":"company","normalized_form":"company",'
            '"occurrence_count":3}]',
      );
    }
    return (statusCode: 404, body: 'unexpected $method $path');
  },
);

Widget _host(LocalApi api) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ColdStartMarkingSheet(
      viewModel: ColdStartMarkingViewModel(
        LocalColdStartMarkingRepository(api),
        trackId: 'track-1',
        language: 'en',
      ),
      onDone: () {},
    ),
  ),
);

void main() {
  testWidgets('the sheet measures itself from the token layer', (tester) async {
    await tester.pumpWidget(_host(_api()));
    await tester.pumpAndSettle();

    expect(find.text('company'), findsOneWidget);

    // Column cap: this sheet is a column of decisions (one word, three
    // verdicts), so it takes the form cap rather than the 400 it hard-coded.
    // `maxHeight` stays a literal — a viewport budget is not a column measure.
    final box = tester.widget<ConstrainedBox>(
      find
          .ancestor(
            of: find.byType(Padding),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(box.constraints.maxWidth, ListenBreakpoints.formColumnMax);

    // Container inset: a dialog body is the `card` role.
    expect(
      tester
          .widget<Padding>(
            find
                .descendant(
                  of: find.byType(ConstrainedBox),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding,
      ListenPadding.card,
    );

    // Glyph: the dismiss action is a control, not chrome.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.close)).size,
      ListenIconSize.control,
    );

    // Typography slot: the word under judgement is the one hero size on this
    // sheet. It used to read `headlineMedium`, which is 28px at w400 — a size
    // the ladder never chose.
    expect(
      tester.widget<Text>(find.text('company')).style?.fontSize,
      ListenType.hero.fontSize,
    );
  });
}
