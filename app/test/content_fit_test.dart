import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/panels/content_fit_card.dart';

void main() {
  test(
    'decodes fit dimensions and explainability without inventing missing data',
    () {
      final profile = ContentDifficultyProfile.fromJson(_profileJson);

      expect(profile.meaning.fit, 'comprehensible');
      expect(profile.sound.fit, 'challenging');
      expect(
        profile.meaning.decisiveSignals.single.kind,
        'unknown_meaning_density',
      );
      expect(profile.sound.signals.single.contribution, 0.35);
      expect(profile.featureSnapshot!.value('speech_rate'), 2.2);
      expect(profile.featureSnapshot!.value('unknown'), isNull);
      expect(profile.featureCoverage!.missingFeatures, [
        'unknown_phrase_density',
      ]);
      expect(profile.usageCalibrated, isTrue);
      expect(profile.isIntensiveListeningTarget, isTrue);
      expect(profile.toJson(), _profileJson);
    },
  );

  testWidgets(
    'fit card presents meaning and sound and explains decisive evidence',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ContentFitCard(
                profile: ContentDifficultyProfile.fromJson(_profileJson),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Meaning'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Manageable'), findsOneWidget);
      expect(find.text('Challenging'), findsOneWidget);
      expect(find.textContaining('focused listening'), findsOneWidget);

      await tester.tap(find.byKey(const Key('content-fit-details')));
      await tester.pumpAndSettle();
      expect(find.text('Why this fit?'), findsOneWidget);
      expect(find.text('Unknown-word density'), findsOneWidget);
      expect(find.text('Speech rate'), findsOneWidget);
      expect(find.text('Not available: Unknown expressions'), findsOneWidget);
    },
  );
}

const _profileJson = <String, dynamic>{
  'subject_kind': 'subtitle_track',
  'subject_id': 'track-1',
  'language': 'en',
  'meaning': {
    'fit': 'comprehensible',
    'signals': [
      {'kind': 'unknown_meaning_density', 'value': 0.78, 'decisive': true},
    ],
    'score': 0.74,
  },
  'sound': {
    'fit': 'challenging',
    'signals': [
      {
        'kind': 'speech_rate_wpm',
        'value': 2.2,
        'decisive': true,
        'contribution': 0.35,
      },
    ],
    'score': 0.62,
  },
  'assessed_token_ratio': 0.72,
  'evidence_grade': 'usage_calibrated',
  'algorithm_version': 'v2',
  'computed_at_ms': 10,
  'input_fingerprint': 'fp-1',
  'feature_snapshot': {'speech_rate': 2.2},
  'feature_coverage': {
    'total_features': 2,
    'available_features': 1,
    'coverage_ratio': 0.5,
    'missing_features': ['unknown_phrase_density'],
  },
};
