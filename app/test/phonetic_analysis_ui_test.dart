import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/phonetic_analysis_ui.dart';
import 'package:llplayer_next/models/runtime_resources.dart';
import 'package:llplayer_next/theme/icon_size.dart';

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
    var jobs = <PhoneticJobView>[
      phoneticJob(id: 'active-job', status: 'recognizing_phones', progress: 50),
      phoneticJob(
        id: 'failed-job',
        scope: 'sentence',
        status: 'failed',
        progress: 25,
        error: 'research failure',
      ),
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
            const PhoneticProviderView(
              id: 'fixture',
              displayName: 'Research fixture',
              runtimeId: 'fixture-runtime',
              runtimeVersion: 'v1',
              available: false,
              experimental: true,
              diagnostic: 'Disabled outside verification',
            ),
          ],
          loadModels: () async => [
            const PhoneticModelView(
              id: 'fixture-model',
              providerId: 'fixture',
              displayName: 'Fixture model',
              revision: 'v1',
              sizeBytes: 0,
              state: 'custom',
              installedBytes: 0,
              license: 'Research only',
              trainingDataProvenance: 'Synthetic',
              distributionAllowed: false,
              applicationVerified: false,
            ),
          ],
          loadJobs: () async => jobs,
          cancelJob: (id) async {
            cancelled = id;
            jobs = [];
            return phoneticJob(id: id, status: 'cancelled');
          },
          retryJob: (id) async {
            retried = id;
            jobs = [];
            return phoneticJob(id: id, status: 'queued');
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

    // S2 token provenance: the job list's status glyphs are `chrome`, and the
    // spinner that stands in for one while a job runs reads the same step — at
    // any other size the row would resize the moment the job settled.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error)).size,
      ListenIconSize.chrome,
    );
    final steps = <double>{
      ListenIconSize.inline,
      ListenIconSize.control,
      ListenIconSize.chrome,
      ListenIconSize.illustration,
    };
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      if (icon.size != null) expect(steps, contains(icon.size));
    }

    await tester.tap(find.byTooltip('Cancel'));
    await pumpAnalysisCenterFrame(tester);
    expect(cancelled, 'active-job');

    jobs = [
      phoneticJob(
        id: 'failed-job',
        scope: 'sentence',
        status: 'failed',
        progress: 25,
        error: 'research failure',
      ),
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

PhoneticJobView phoneticJob({
  required String id,
  required String status,
  String scope = 'track',
  int progress = 0,
  String? error,
}) => PhoneticJobView(
  id: id,
  trackId: 'track-1',
  scope: scope,
  providerId: 'fixture',
  runtimeId: 'fixture-runtime',
  runtimeVersion: 'v1',
  modelRevision: 'v1',
  status: status,
  phaseProgress: progress,
  createdAtMs: 1,
  errorMessage: error,
);
