import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/learning_workflow_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/api_service.dart';

Cue _cue(String id) => Cue(
  id: id,
  index: 0,
  start: Duration.zero,
  end: const Duration(seconds: 1),
  text: 'text',
  tokens: const [],
);

void main() {
  group('LearningWorkflowController.refreshDiagnosis (generation guard)', () {
    test('clears the diagnosis when there is no cue', () async {
      final controller = LearningWorkflowController();
      final applied = <Diagnosis?>[];

      await controller.refreshDiagnosis(
        cue: null,
        diagnose: (_) async => Diagnosis(),
        currentCueId: () => null,
        setDiagnosis: applied.add,
      );

      expect(applied, [null]);
    });

    test('applies the diagnosis for the current cue', () async {
      final controller = LearningWorkflowController();
      final applied = <Diagnosis?>[];
      final diagnosis = Diagnosis();

      await controller.refreshDiagnosis(
        cue: _cue('A'),
        diagnose: (_) async => diagnosis,
        currentCueId: () => 'A',
        setDiagnosis: applied.add,
      );

      expect(applied, hasLength(1));
      expect(identical(applied.single, diagnosis), isTrue);
    });

    test('discards a stale diagnosis when a newer request supersedes it', () async {
      final controller = LearningWorkflowController();
      final applied = <Diagnosis?>[];
      final completerA = Completer<Diagnosis>();
      final completerB = Completer<Diagnosis>();
      final diagnosisA = Diagnosis();
      final diagnosisB = Diagnosis();
      var current = 'A';

      // First request for cue A (generation 1) starts and suspends.
      final futureA = controller.refreshDiagnosis(
        cue: _cue('A'),
        diagnose: (_) => completerA.future,
        currentCueId: () => current,
        setDiagnosis: applied.add,
      );
      // A newer request for cue B (generation 2) supersedes it.
      current = 'B';
      final futureB = controller.refreshDiagnosis(
        cue: _cue('B'),
        diagnose: (_) => completerB.future,
        currentCueId: () => current,
        setDiagnosis: applied.add,
      );

      // B resolves first, then the stale A resolves.
      completerB.complete(diagnosisB);
      completerA.complete(diagnosisA);
      await Future.wait([futureA, futureB]);

      expect(applied, hasLength(1), reason: 'the stale result is dropped');
      expect(identical(applied.single, diagnosisB), isTrue);
    });

    test('discards the diagnosis if the cue is no longer current', () async {
      final controller = LearningWorkflowController();
      final applied = <Diagnosis?>[];
      final completer = Completer<Diagnosis>();
      var current = 'A';

      final future = controller.refreshDiagnosis(
        cue: _cue('A'),
        diagnose: (_) => completer.future,
        currentCueId: () => current,
        setDiagnosis: applied.add,
      );
      current = 'B'; // navigated away before the result arrives
      completer.complete(Diagnosis());
      await future;

      expect(applied, isEmpty);
    });

    test('maps a diagnose error to null for the current cue', () async {
      final controller = LearningWorkflowController();
      final applied = <Diagnosis?>[];

      await controller.refreshDiagnosis(
        cue: _cue('A'),
        diagnose: (_) async => throw Exception('boom'),
        currentCueId: () => 'A',
        setDiagnosis: applied.add,
      );

      expect(applied, [null]);
    });
  });

  group('LearningWorkflowController.loadPhraseCandidates (via A1 seam)', () {
    test('loads phrase candidates through the LocalApi transport seam', () async {
      final controller = LearningWorkflowController();
      final learning = LearningController();
      var seenPath = '';
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenPath = path;
          return (
            statusCode: 200,
            body:
                '[{"canonical_form":"give up","display_form":"give up","token_start":0,"token_end":1}]',
          );
        },
      );

      await controller.loadPhraseCandidates(
        api: api,
        cue: _cue('A'),
        learning: learning,
        isMounted: () => true,
        currentCueId: () => 'A',
      );

      expect(seenPath, '/v1/sentences/A/phrase-candidates');
      expect(learning.phraseCandidates, hasLength(1));
      expect(learning.phraseCandidates.single.canonicalForm, 'give up');
    });

    test('clears phrase candidates when there is no api', () async {
      final controller = LearningWorkflowController();
      final learning = LearningController()
        ..setPhraseCandidates(const [
          PhraseCandidate(
            canonicalForm: 'stale',
            displayForm: 'stale',
            tokenStart: 0,
            tokenEnd: 1,
          ),
        ]);

      await controller.loadPhraseCandidates(
        api: null,
        cue: _cue('A'),
        learning: learning,
        isMounted: () => true,
        currentCueId: () => 'A',
      );

      expect(learning.phraseCandidates, isEmpty);
    });
  });
}
