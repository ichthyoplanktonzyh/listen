import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/coach_dashboard_controller.dart';
import 'package:llplayer_next/data/repositories/coach_dashboard_repository.dart';
import 'package:llplayer_next/models/coach_dashboard.dart';

const _dashboard = CoachDashboard(
  channels: [],
  suggestions: [],
  starterChecklist: [],
  materials: [],
  periodStartMs: 1,
  periodEndMs: 2,
  generatedAtMs: 2,
  features: [],
);
const _newDashboard = CoachDashboard(
  channels: [],
  suggestions: [],
  starterChecklist: [],
  materials: [],
  periodStartMs: 1,
  periodEndMs: 3,
  generatedAtMs: 3,
  features: [],
);

CoachEvidenceItem _item(String id) => CoachEvidenceItem(
  id: id,
  occurredAtMs: 1,
  result: 'correct',
  sourceKind: 'practice_attempt',
  snapshot: id,
  sourceAvailable: true,
);

class _Repository implements CoachDashboardRepository {
  final evidenceRequests = <({int limit, int offset})>[];
  final evidenceResponses = <Future<List<CoachEvidenceItem>>>[];
  final dashboardResponses = <Future<CoachDashboard>>[];
  Future<CoachDashboard> dashboardResponse = Future.value(_dashboard);
  Object? evidenceFailure;
  Object? materialFailure;

  @override
  Future<void> graduateMaterial(String mediaId) async {
    if (materialFailure case final failure?) throw failure;
  }

  @override
  Future<CoachDashboard> loadDashboard({
    required int days,
    required String language,
  }) => dashboardResponses.isEmpty
      ? dashboardResponse
      : dashboardResponses.removeAt(0);

  @override
  Future<List<CoachEvidenceItem>> loadEvidence({
    required String metric,
    required int days,
    required int limit,
    required int offset,
  }) {
    evidenceRequests.add((limit: limit, offset: offset));
    if (evidenceFailure case final failure?) return Future.error(failure);
    return evidenceResponses.removeAt(0);
  }

  @override
  Future<void> setMaterialIntent(String mediaId, String? intent) async {
    if (materialFailure case final failure?) throw failure;
  }
}

void main() {
  group('CoachDashboardController dashboard', () {
    test('a stale dashboard response cannot replace a newer refresh', () async {
      final first = Completer<CoachDashboard>();
      final second = Completer<CoachDashboard>();
      final repository = _Repository()
        ..dashboardResponses.addAll([first.future, second.future]);
      final controller = CoachDashboardController(repository);
      addTearDown(controller.dispose);

      final firstLoad = controller.load();
      final secondLoad = controller.load();
      second.complete(_newDashboard);
      await secondLoad;
      first.complete(_dashboard);
      await firstLoad;

      expect(controller.state.dashboard, same(_newDashboard));
    });
  });

  group('CoachDashboardController evidence', () {
    test(
      'appends pages with the current offset and marks the final page',
      () async {
        final repository = _Repository()
          ..evidenceResponses.addAll([
            Future.value([_item('one'), _item('two')]),
            Future.value([_item('three')]),
          ]);
        final controller = CoachDashboardController(repository);
        addTearDown(controller.dispose);
        await controller.load();

        await controller.loadEvidencePage('practice_attempts', pageSize: 2);
        await controller.loadEvidencePage('practice_attempts', pageSize: 2);

        expect(repository.evidenceRequests, [
          (limit: 2, offset: 0),
          (limit: 2, offset: 2),
        ]);
        final feed = controller.state.evidence['practice_attempts']!;
        expect(feed.items.map((item) => item.id), ['one', 'two', 'three']);
        expect(feed.exhausted, isTrue);
        expect(() => feed.items.add(_item('four')), throwsUnsupportedError);
      },
    );

    test('publishes a named failure while preserving prior items', () async {
      final repository = _Repository()
        ..evidenceResponses.add(Future.value([_item('one'), _item('two')]));
      final controller = CoachDashboardController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.loadEvidencePage('practice_attempts', pageSize: 2);
      repository.evidenceFailure = StateError('private transport detail');

      await controller.loadEvidencePage('practice_attempts', pageSize: 2);

      final feed = controller.state.evidence['practice_attempts']!;
      expect(feed.items.map((item) => item.id), ['one', 'two']);
      expect(feed.failure?.messageKey, 'coachEvidenceFailed');
      expect(feed.loading, isFalse);
    });

    test('dashboard refresh invalidates an in-flight evidence page', () async {
      final page = Completer<List<CoachEvidenceItem>>();
      final repository = _Repository()..evidenceResponses.add(page.future);
      final controller = CoachDashboardController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final evidence = controller.loadEvidencePage('practice_attempts');
      await controller.load();
      page.complete([_item('stale')]);
      await evidence;

      final feed = controller.state.evidence['practice_attempts']!;
      expect(feed.items, isEmpty);
      expect(feed.loading, isFalse);
    });

    test('dispose invalidates an in-flight evidence completion', () async {
      final page = Completer<List<CoachEvidenceItem>>();
      final repository = _Repository()..evidenceResponses.add(page.future);
      final controller = CoachDashboardController(repository);
      await controller.load();
      final evidence = controller.loadEvidencePage('practice_attempts');

      controller.dispose();
      page.complete([_item('late')]);

      await expectLater(evidence, completes);
    });
  });

  group('CoachDashboardController material actions', () {
    test(
      'reports a failed material write without discarding dashboard',
      () async {
        final repository = _Repository()
          ..materialFailure = StateError('write failed');
        final controller = CoachDashboardController(repository);
        addTearDown(controller.dispose);
        await controller.load();

        final changed = await controller.graduateMaterial('media');

        expect(changed, isFalse);
        expect(controller.state.dashboard, same(_dashboard));
        expect(
          controller.state.materialFailure?.messageKey,
          'coachMaterialActionFailed',
        );
      },
    );
  });
}
