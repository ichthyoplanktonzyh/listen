import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_flow_view_models.dart';
import 'package:llplayer_next/data/repositories/external_vocabulary_repository.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/file_transfer_service.dart';

class _VocabularyRepository implements ExternalVocabularyRepository {
  List<Map<String, dynamic>>? entries;
  String? language;
  String? status;
  bool? overwrite;

  @override
  Future<ExternalVocabularyImportSummary> importEntries(
    List<Map<String, dynamic>> entries, {
    required String language,
    required String defaultStatus,
    required bool overwriteExisting,
  }) async {
    this.entries = entries;
    this.language = language;
    status = defaultStatus;
    overwrite = overwriteExisting;
    return const ExternalVocabularyImportSummary(
      created: 1,
      initialized: 0,
      skipped: 0,
      overwritten: 0,
      invalid: 0,
    );
  }
}

class _WordListFileService implements ExternalWordListFileService {
  _WordListFileService(this.result);

  final ExternalWordListReadResult? result;

  @override
  Future<ExternalWordListReadResult?> pickAndRead() async => result;

  @override
  Future<ExternalWordListReadResult> read(String path) async => result!;
}

void main() {
  test(
    'external vocabulary import owns selection, write, and refresh',
    () async {
      final repository = _VocabularyRepository();
      var refreshes = 0;
      final viewModel = ExternalVocabularyImportViewModel(
        repository,
        language: 'en',
        onImported: () async => refreshes++,
        fileService: _WordListFileService(
          ExternalWordListReadSuccess([
            {'word': 'listen'},
          ]),
        ),
      );

      expect(await viewModel.pick(), isTrue);
      expect(viewModel.state.entries.single['word'], 'listen');

      final summary = await viewModel.import(
        defaultStatus: 'known_recognized',
        overwriteExisting: true,
      );

      expect(summary.created, 1);
      expect(repository.language, 'en');
      expect(repository.status, 'known_recognized');
      expect(repository.overwrite, isTrue);
      expect(repository.entries?.single['word'], 'listen');
      expect(refreshes, 1);
      expect(viewModel.state.importing, isFalse);
    },
  );

  test(
    'external vocabulary import exposes parse failure without writing',
    () async {
      final repository = _VocabularyRepository();
      final viewModel = ExternalVocabularyImportViewModel(
        repository,
        language: 'en',
        onImported: () async {},
        fileService: _WordListFileService(
          const ExternalWordListFormatFailure('bad csv'),
        ),
      );

      expect(await viewModel.pick(), isTrue);
      expect(viewModel.state.formatFailure, 'bad csv');
      expect(repository.entries, isNull);
    },
  );

  test('external vocabulary import preserves picker cancellation', () async {
    final viewModel = ExternalVocabularyImportViewModel(
      _VocabularyRepository(),
      language: 'en',
      onImported: () async {},
      fileService: _WordListFileService(null),
    );

    expect(await viewModel.pick(), isFalse);
    expect(viewModel.state.entries, isEmpty);
  });
}
