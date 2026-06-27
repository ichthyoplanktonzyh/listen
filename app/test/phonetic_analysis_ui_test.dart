import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/phonetic_analysis_ui.dart';

Future<void> pumpAnalysisCenterFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('analysis center exposes model provenance and job actions', (
    tester,
  ) async {
    String? cancelled;
    String? retried;
    var jobs = <Map<String, dynamic>>[
      {
        'id': 'active-job',
        'scope': 'track',
        'status': 'recognizing_phones',
        'phase_progress': 50,
        'provider_id': 'fixture',
        'model_revision': 'v1',
        'error_message': null,
      },
      {
        'id': 'failed-job',
        'scope': 'sentence',
        'status': 'failed',
        'phase_progress': 25,
        'provider_id': 'fixture',
        'model_revision': 'v1',
        'error_message': 'research failure',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: PhoneticAnalysisCenter(
          loadProviders: () async => [
            {
              'display_name': 'Research fixture',
              'available': false,
              'experimental': true,
              'diagnostic': 'Disabled outside verification',
            },
          ],
          loadModels: () async => [
            {
              'display_name': 'Fixture model',
              'state': 'custom',
              'license': 'Research only',
              'revision': 'v1',
              'training_data_provenance': 'Synthetic',
              'application_verified': false,
              'distribution_allowed': false,
            },
          ],
          loadJobs: () async => jobs,
          cancelJob: (id) async {
            cancelled = id;
            jobs = [];
            return {'id': id, 'status': 'cancelled'};
          },
          retryJob: (id) async {
            retried = id;
            jobs = [];
            return {'id': id, 'status': 'queued'};
          },
        ),
      ),
    );
    await pumpAnalysisCenterFrame(tester);

    expect(find.textContaining('Research fixture'), findsOneWidget);
    expect(find.textContaining('Research only'), findsOneWidget);

    await tester.tap(find.text('Jobs'));
    await pumpAnalysisCenterFrame(tester);
    expect(find.text('track'), findsOneWidget);
    expect(find.text('Recognizing phones'), findsOneWidget);
    expect(find.textContaining('research failure'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await pumpAnalysisCenterFrame(tester);
    expect(cancelled, 'active-job');

    jobs = [
      {
        'id': 'failed-job',
        'scope': 'sentence',
        'status': 'failed',
        'phase_progress': 25,
        'provider_id': 'fixture',
        'model_revision': 'v1',
        'error_message': 'research failure',
      },
    ];
    await tester.tap(find.byIcon(Icons.refresh).first);
    await pumpAnalysisCenterFrame(tester);
    await tester.tap(find.text('Jobs'));
    await pumpAnalysisCenterFrame(tester);
    await tester.tap(find.byTooltip('Retry'));
    await pumpAnalysisCenterFrame(tester);
    expect(retried, 'failed-job');
  });
}
