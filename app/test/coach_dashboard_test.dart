import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/coach_dashboard_controller.dart';
import 'package:llplayer_next/data/repositories/coach_dashboard_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/coach_dashboard.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/coach/coach_dashboard_screen.dart';

void main() {
  testWidgets(
    'dashboard routes listening suggestions and confirms graduation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = _CoachRepository();
      final controller = CoachDashboardController(repository);
      addTearDown(controller.dispose);
      var openedReview = 0;
      var openedContentHome = 0;
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
          home: CoachDashboardScreen(
            controller: controller,
            language: 'en',
            onOpenReview: () => openedReview++,
            onOpenHunting: () {},
            onOpenContentHome: () => openedContentHome++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('coach-dashboard-listening-only')),
        findsOneWidget,
      );
      expect(find.text('Listening activity'), findsOneWidget);
      expect(find.text('Listening review attempts'), findsOneWidget);
      expect(find.text('Writing'), findsNothing);
      expect(find.text('Listening material'), findsOneWidget);

      await tester.tap(find.text('Show source records'));
      await tester.pumpAndSettle();
      expect(repository.evidenceRequests, 1);
      expect(find.text('Successful · review'), findsOneWidget);

      await tester.tap(find.byKey(const Key('load-fit-calibration')));
      await tester.pumpAndSettle();
      expect(find.text('No eligible listening samples yet.'), findsOneWidget);

      await tester.tap(find.text('Review words due for practice'));
      expect(openedReview, 1);
      await tester.tap(find.text('Continue listening'));
      expect(openedContentHome, 1);

      await tester.tap(find.byKey(const Key('coach-intent-media-1')));
      await tester.pumpAndSettle();
      expect(repository.intentUpdates.single, ('media-1', 'pin_intensive'));

      await tester.tap(find.byKey(const Key('coach-graduate-media-1')));
      await tester.pumpAndSettle();
      expect(find.text('Graduate this listening material?'), findsOneWidget);
      expect(repository.graduatedMediaIds, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.graduatedMediaIds, isEmpty);

      await tester.tap(find.byKey(const Key('coach-graduate-media-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mark completed'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.graduatedMediaIds, ['media-1']);
    },
  );
}

class _CoachRepository implements CoachDashboardRepository {
  final graduatedMediaIds = <String>[];
  final intentUpdates = <(String, String?)>[];
  var evidenceRequests = 0;

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');

  @override
  Future<CoachDashboard> loadDashboard({
    required int days,
  }) async => _dashboard;

  @override
  Future<List<CoachEvidenceItem>> loadEvidence({
    required String metric,
    required int days,
    required int limit,
    required int offset,
  }) async {
    evidenceRequests++;
    return const [
      CoachEvidenceItem(
        id: 'evidence-1',
        occurredAtMs: 1,
        result: 'success',
        sourceKind: 'review',
        snapshot: 'listening source',
        sourceAvailable: true,
        unavailableReason: null,
      ),
    ];
  }

  @override
  Future<MediaLibraryEntry> graduateMaterial(String mediaId) async {
    graduatedMediaIds.add(mediaId);
    return _mediaEntry;
  }

  @override
  Future<MediaLibraryEntry> setMaterialIntent(
    String mediaId,
    String? intent,
  ) async {
    intentUpdates.add((mediaId, intent));
    return _mediaEntry;
  }

  @override
  Future<List<ContentFitCalibrationSample>> calibrationSamples({
    String? language,
  }) async => const [];
}

final _dashboard = CoachDashboard.fromJson({
  'period_start_ms': 0,
  'period_end_ms': 604800000,
  'generated_at_ms': 1,
  'listening_metrics': [
    {
      'key': 'review_attempts',
      'value': 2,
      'source': 'review_attempts',
      'authority_layer': 'core',
    },
  ],
  'suggestions': [
    {
      'id': 'review-1',
      'kind': 'review_due',
      'title_key': 'coachSuggestionReview',
      'reason_key': 'coachSuggestionReviewReason',
      'destination': {'kind': 'review_queue'},
      'evidence_source': 'fsrs',
      'evidence_count': 1,
    },
    {
      'id': 'continue-1',
      'kind': 'continue_listening',
      'title_key': 'coachSuggestionContinue',
      'reason_key': 'coachSuggestionContinueReason',
      'destination': {'kind': 'content_home'},
      'evidence_source': 'listening_session',
      'evidence_count': 1,
    },
    {
      'id': 'writing-1',
      'kind': 'writing',
      'title_key': 'writing',
      'reason_key': 'writing',
      'destination': {'kind': 'writing'},
      'evidence_source': 'writing',
      'evidence_count': 1,
    },
  ],
  'starter_checklist': <String>[],
  'materials': [
    {
      'media_id': 'media-1',
      'title': 'Listening material',
      'report_count': 2,
      'first_report': 'got_the_gist',
      'latest_report': 'understood_all',
      'reports_understood_all': 1,
      'reports_got_the_gist': 1,
      'reports_unclear': 0,
      'practice_attempts': 3,
      'practice_correct': 2,
      'triage_intent': 'pin_extensive',
      'graduation_candidate': true,
      'recommended_intent': 'pin_intensive',
    },
  ],
});

const _mediaEntry = MediaLibraryEntry(
  media: MediaItem(
    id: 'media-1',
    path: '/media/1.mp3',
    fingerprint: 'fp-1',
    title: 'Listening material',
    kind: 'audio',
    durationMs: 1000,
    availability: 'available',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  primaryTrackId: null,
  triageIntent: 'graduated',
  fit: null,
);
