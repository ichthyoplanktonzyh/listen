import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_assets_view_models.dart';
import 'package:llplayer_next/data/repositories/learning_assets_repository.dart';
import 'package:llplayer_next/models/runtime_resources.dart';
import 'package:llplayer_next/models/types.dart';

const _resourceA = LearningResourceDescriptor(
  id: 'a',
  displayName: 'A',
  version: '1',
  license: 'MIT',
  checksumSha256: 'a',
  sizeBytes: 1,
  state: 'available',
  installedBytes: 0,
);

const _resourceB = LearningResourceDescriptor(
  id: 'b',
  displayName: 'B',
  version: '1',
  license: 'MIT',
  checksumSha256: 'b',
  sizeBytes: 1,
  state: 'available',
  installedBytes: 0,
);

class _LearningAssetsRepository implements LearningAssetsRepository {
  final resourceLoads = <Completer<List<LearningResourceDescriptor>>>[];
  Completer<LexicalEntryDetails>? saveCompleter;
  Map<String, dynamic>? savedEntry;

  @override
  Future<List<LearningResourceDescriptor>> learningResources() {
    final completer = Completer<List<LearningResourceDescriptor>>();
    resourceLoads.add(completer);
    return completer.future;
  }

  @override
  Future<LexicalEntryDetails> upsertLexicalEntry(Map<String, dynamic> value) {
    savedEntry = value;
    return (saveCompleter = Completer<LexicalEntryDetails>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('learning resources drops an older load result', () async {
    final repository = _LearningAssetsRepository();
    final viewModel = LearningResourcesViewModel(repository);

    final first = viewModel.load();
    final second = viewModel.load();
    repository.resourceLoads[1].complete(const [_resourceB]);
    await second;
    repository.resourceLoads[0].complete(const [_resourceA]);
    await first;

    expect(viewModel.state.resources.single.id, 'b');
  });

  test(
    'phrase source is copied and completion after dispose is harmless',
    () async {
      final repository = _LearningAssetsRepository();
      final source = <String, dynamic>{'language': 'en', 'sentence_id': 'one'};
      final viewModel = PhraseCandidateViewModel(
        repository,
        candidate: const PhraseCandidate(
          canonicalForm: 'in fact',
          displayForm: 'in fact',
          tokenStart: 0,
          tokenEnd: 1,
        ),
        source: source,
      );
      source['sentence_id'] = 'mutated';

      final saving = viewModel.save();
      expect(
        (repository.savedEntry!['source']
            as Map<String, dynamic>)['sentence_id'],
        'one',
      );
      viewModel.dispose();
      repository.saveCompleter!.complete(
        const LexicalEntryDetails(
          entry: LexicalEntry(
            id: 'entry',
            normalizedForm: 'in fact',
            displayForm: 'in fact',
            kind: 'phrase',
            language: 'en',
          ),
        ),
      );

      await expectLater(saving, completes);
    },
  );
}
