import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/learning_workflow_controller.dart';
import 'package:llplayer_next/data/repositories/learning_repository.dart';
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
  group('LearningWorkflowController.openWord', () {
    test('switches to the word learning panel before lookups finish', () async {
      final learning = LearningController()..selectSidePanel(0);
      final firstResponse = Completer<ApiResponse>();
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) {
          if (method == 'PUT' && path == '/v1/lexical-entries') {
            return firstResponse.future;
          }
          if (path.startsWith('/v1/dictionary?')) {
            return Future.value((
              statusCode: 200,
              body: '{"query":"hello","normalized_lemma":"hello","results":[]}',
            ));
          }
          if (path.startsWith('/v1/pronunciation/lookup?')) {
            return Future.value((
              statusCode: 200,
              body: '{"text":"Hello","normalized":"hello","variants":[]}',
            ));
          }
          if (path == '/v1/languages/en/profile') {
            return Future.value((
              statusCode: 200,
              body: '{"language_code":"en","capabilities":{}}',
            ));
          }
          return Future.value((
            statusCode: 404,
            body: 'unexpected $method $path',
          ));
        },
      );
      final controller = LearningWorkflowController(
        repository: LocalLearningRepository(() => api),
      );
      const token = SubtitleToken(
        index: 0,
        kind: 'word',
        text: 'Hello',
        normalized: 'hello',
      );
      final cue = _cue('A');

      final future = controller.openWord(
        token: token,
        cue: cue,
        language: 'en',
        learning: learning,
        isMounted: () => true,
      );

      expect(learning.sidePanel, 2);
      expect(learning.selectedToken, token);
      expect(learning.selectedCue, cue);
      expect(learning.selectedLexicalDetails, isNull);

      firstResponse.complete((
        statusCode: 200,
        body:
            '{"entry":{"id":"lexical-1","normalized_form":"hello","display_form":"Hello","kind":"word","language":"en"},"history":[],"occurrences":[]}',
      ));
      await future;

      expect(learning.sidePanel, 2);
      expect(learning.selectedLexicalDetails?.entry.normalizedForm, 'hello');
    });

    test('keeps word details visible when optional lookups fail', () async {
      final learning = LearningController()..selectSidePanel(0);
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (method == 'PUT' && path == '/v1/lexical-entries') {
            return (
              statusCode: 200,
              body:
                  '{"entry":{"id":"lexical-1","normalized_form":"hello","display_form":"Hello","kind":"word","language":"en"},"history":[],"occurrences":[]}',
            );
          }
          return (statusCode: 503, body: 'optional service unavailable');
        },
      );
      final controller = LearningWorkflowController(
        repository: LocalLearningRepository(() => api),
      );
      const token = SubtitleToken(
        index: 0,
        kind: 'word',
        text: 'Hello',
        normalized: 'hello',
      );

      await controller.openWord(
        token: token,
        cue: _cue('A'),
        language: 'en',
        learning: learning,
        isMounted: () => true,
      );

      expect(learning.sidePanel, 2);
      expect(learning.selectedLexicalDetails?.entry.normalizedForm, 'hello');
      expect(learning.selectedDictionary, isNull);
      expect(learning.selectedPronunciation, isNull);
    });

    test('falls back to cached word entry when details lookup fails', () async {
      final learning = LearningController()
        ..setWordEntries(const {
          'hello': LexicalEntry(
            id: 'lexical-1',
            normalizedForm: 'hello',
            displayForm: 'Hello',
            kind: 'word',
            language: 'en',
            status: 'known_not_recognized',
          ),
        });
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async =>
            (statusCode: 503, body: 'lookup unavailable'),
      );
      final controller = LearningWorkflowController(
        repository: LocalLearningRepository(() => api),
      );
      const token = SubtitleToken(
        index: 0,
        kind: 'word',
        text: 'Hello',
        normalized: 'hello',
      );

      await controller.openWord(
        token: token,
        cue: _cue('A'),
        language: 'en',
        learning: learning,
        isMounted: () => true,
      );

      expect(learning.sidePanel, 2);
      expect(learning.selectedLexicalDetails?.entry.id, 'lexical-1');
      expect(
        learning.selectedLexicalDetails?.entry.status,
        'known_not_recognized',
      );
    });

    test(
      'shows cached word entry before full details lookup completes',
      () async {
        final learning = LearningController()
          ..setWordEntries(const {
            'hello': LexicalEntry(
              id: 'lexical-1',
              normalizedForm: 'hello',
              displayForm: 'Hello',
              kind: 'word',
              language: 'en',
            ),
          });
        final detailsResponse = Completer<ApiResponse>();
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) {
            if (method == 'GET' && path == '/v1/lexical-entries/lexical-1') {
              return detailsResponse.future;
            }
            return Future.value((
              statusCode: 503,
              body: 'optional unavailable',
            ));
          },
        );
        final controller = LearningWorkflowController(
          repository: LocalLearningRepository(() => api),
        );
        const token = SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'Hello',
          normalized: 'hello',
        );

        final future = controller.openWord(
          token: token,
          cue: _cue('A'),
          language: 'en',
          learning: learning,
          isMounted: () => true,
        );

        expect(learning.sidePanel, 2);
        expect(learning.selectedLexicalDetails?.entry.id, 'lexical-1');

        detailsResponse.complete((
          statusCode: 200,
          body:
              '{"entry":{"id":"lexical-1","normalized_form":"hello","display_form":"Hello","kind":"word","language":"en","status":"known_recognized"},"history":[],"occurrences":[]}',
        ));
        await future;

        expect(
          learning.selectedLexicalDetails?.entry.status,
          'known_recognized',
        );
      },
    );
  });

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

    test(
      'discards a stale diagnosis when a newer request supersedes it',
      () async {
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
      },
    );

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
      final controller = LearningWorkflowController(
        repository: LocalLearningRepository(() => api),
      );

      await controller.loadPhraseCandidates(
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
        cue: _cue('A'),
        learning: learning,
        isMounted: () => true,
        currentCueId: () => 'A',
      );

      expect(learning.phraseCandidates, isEmpty);
    });
  });
}
