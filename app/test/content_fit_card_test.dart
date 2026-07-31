import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/content_fit_card.dart';

ContentDifficultyProfile _profile({
  String meaningFit = 'comprehensible',
  String soundFit = 'challenging',
  double assessedTokenRatio = 0.95,
  String evidenceGrade = 'initial_estimate',
}) => ContentDifficultyProfile.fromJson({
  'subject_kind': 'media',
  'subject_id': 'media-1',
  'language': 'en',
  'meaning': {
    'fit': meaningFit,
    'signals': [
      {'kind': 'unknown_meaning_density', 'value': 0.03, 'decisive': true},
      {'kind': 'unassessed_density', 'value': 0.02, 'decisive': true},
    ],
  },
  'sound': {
    'fit': soundFit,
    'signals': [
      {'kind': 'known_not_recognized_density', 'value': 0.06, 'decisive': true},
      {'kind': 'speech_rate_wpm', 'value': 152.0, 'decisive': false},
    ],
  },
  'assessed_token_ratio': assessedTokenRatio,
  'evidence_grade': evidenceGrade,
  'algorithm_version': 'content-fit-v2',
  'computed_at_ms': 1700000000000,
  'input_fingerprint': 'fp',
});

Widget _host(
  ContentDifficultyProfile profile, {
  VoidCallback? onStartColdStart,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ContentFitCard(profile: profile, onStartColdStart: onStartColdStart),
  ),
);

void main() {
  // The discipline gates prove no *literal* survives in the source; this
  // proves the values that replaced them are the tokens and not a coincidence,
  // which is the half a source scan cannot see.
  testWidgets('card inset and header glyph come from the token layer', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_profile()));

    final padding = tester.widget<Padding>(
      find
          .ancestor(
            of: find.byIcon(Icons.tune_outlined),
            matching: find.byType(Padding),
          )
          .last,
    );
    expect(padding.padding, ListenPadding.card);

    final icon = tester.widget<Icon>(find.byIcon(Icons.tune_outlined));
    expect(icon.size, ListenIconSize.control);
  });

  testWidgets('renders both dimension bands and the golden-target note', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_profile()));
    expect(find.text('Difficulty'), findsOneWidget);
    expect(find.text('Comfortable'), findsOneWidget);
    expect(find.text('Challenging'), findsOneWidget);
    // meaning comprehensible x sound challenging = intensive target
    expect(
      find.textContaining('good intensive listening material'),
      findsOneWidget,
    );
    expect(find.text('Initial estimate'), findsOneWidget);
  });

  testWidgets('hides the golden-target note when sound is easy', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_profile(soundFit: 'too_easy')));
    expect(
      find.textContaining('good intensive listening material'),
      findsNothing,
    );
  });

  testWidgets('shows the honest-degradation notice on a thin profile', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_profile(assessedTokenRatio: 0.2)));
    expect(find.textContaining('conservative guess'), findsOneWidget);
    // Bands stay visible: fit is never hidden, only reframed.
    expect(find.text('Comfortable'), findsOneWidget);
  });

  testWidgets('detail dialog explains the bands from signals', (tester) async {
    await tester.pumpWidget(_host(_profile()));
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Why this rating'), findsOneWidget);
    expect(find.text('Known but not yet caught by ear'), findsOneWidget);
    expect(find.text('6.0%'), findsOneWidget);
    expect(find.text('Speech rate'), findsOneWidget);
    expect(find.text('152'), findsOneWidget);
    // decisive markers appear only for band-driving signals
    expect(find.text('Drove the rating'), findsNWidgets(3));
  });

  testWidgets(
    'quick marking button appears only on degraded profile with callback',
    (tester) async {
      // No callback: button absent even on degraded profile.
      await tester.pumpWidget(_host(_profile(assessedTokenRatio: 0.2)));
      expect(find.text('Quick marking'), findsNothing);

      // With callback on sufficient profile: button absent.
      await tester.pumpWidget(
        _host(_profile(assessedTokenRatio: 0.95), onStartColdStart: () {}),
      );
      expect(find.text('Quick marking'), findsNothing);

      // With callback on degraded profile: button present.
      var tapped = false;
      await tester.pumpWidget(
        _host(
          _profile(assessedTokenRatio: 0.2),
          onStartColdStart: () => tapped = true,
        ),
      );
      expect(find.text('Quick marking'), findsOneWidget);
      await tester.tap(find.text('Quick marking'));
      expect(tapped, isTrue);
    },
  );

  testWidgets('calibrated grade replaces the initial-estimate label', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_profile(evidenceGrade: 'usage_calibrated')));
    expect(find.text('Calibrated by your usage'), findsOneWidget);
    expect(find.text('Initial estimate'), findsNothing);
  });
}
