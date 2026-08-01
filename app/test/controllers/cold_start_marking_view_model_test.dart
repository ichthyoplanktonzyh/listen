import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/cold_start_marking_view_model.dart';
import 'package:llplayer_next/data/repositories/cold_start_marking_repository.dart';
import 'package:llplayer_next/models/types.dart';

const _first = ColdStartWordCandidate(
  displayForm: 'first',
  normalizedForm: 'first',
  occurrenceCount: 2,
);
const _second = ColdStartWordCandidate(
  displayForm: 'second',
  normalizedForm: 'second',
  occurrenceCount: 1,
);

class _Repository implements ColdStartMarkingRepository {
  final loads = <Completer<List<ColdStartWordCandidate>>>[];
  final savedStatuses = <String>[];
  bool failSave = false;

  @override
  Future<List<ColdStartWordCandidate>> loadCandidates(String trackId) {
    final completer = Completer<List<ColdStartWordCandidate>>();
    loads.add(completer);
    return completer.future;
  }

  @override
  Future<void> saveMark({
    required ColdStartWordCandidate candidate,
    required String status,
    required String language,
  }) async {
    savedStatuses.add('$language:${candidate.displayForm}:$status');
    if (failSave) throw StateError('save failed');
  }
}

void main() {
  group('ColdStartMarkingViewModel', () {
    test('a stale load cannot replace the latest candidate list', () async {
      final repository = _Repository();
      final viewModel = ColdStartMarkingViewModel(
        repository,
        trackId: 'track',
        language: 'en',
      );

      final firstLoad = viewModel.load();
      final secondLoad = viewModel.load();
      repository.loads[1].complete([_second]);
      await secondLoad;
      repository.loads[0].complete([_first]);
      await firstLoad;

      expect(viewModel.state.current, same(_second));
      viewModel.dispose();
    });

    test(
      'saves through the repository and advances after a failed save',
      () async {
        final repository = _Repository();
        final viewModel = ColdStartMarkingViewModel(
          repository,
          trackId: 'track',
          language: 'en',
        );
        final load = viewModel.load();
        repository.loads.single.complete([_first, _second]);
        await load;

        repository.failSave = true;
        await viewModel.mark('known_recognized');

        expect(repository.savedStatuses, ['en:first:known_recognized']);
        expect(viewModel.state.current, same(_second));
        expect(viewModel.state.saveFailed, isTrue);
        expect(viewModel.state.submitting, isFalse);
        viewModel.dispose();
      },
    );

    test(
      'marks the flow finished after the final candidate is skipped',
      () async {
        final repository = _Repository();
        final viewModel = ColdStartMarkingViewModel(
          repository,
          trackId: 'track',
          language: 'en',
        );
        final load = viewModel.load();
        repository.loads.single.complete([_first]);
        await load;

        viewModel.skip();

        expect(viewModel.state.finished, isTrue);
        viewModel.dispose();
      },
    );
  });
}
