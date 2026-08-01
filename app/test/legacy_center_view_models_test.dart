import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_assets_view_models.dart';
import 'package:llplayer_next/controllers/phonetic_analysis_view_model.dart';
import 'package:llplayer_next/controllers/transcription_view_models.dart';
import 'package:llplayer_next/data/repositories/learning_assets_repository.dart';
import 'package:llplayer_next/data/repositories/phonetic_analysis_repository.dart';
import 'package:llplayer_next/data/repositories/transcription_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/runtime_resources.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';

void main() {
  test(
    'learning assets ignores a stale query and exposes immutable values',
    () async {
      final repository = _LearningRepository();
      final viewModel = LearningAssetsViewModel(repository, language: 'en');

      final first = viewModel.load();
      final second = viewModel.setKind('word');
      repository.second.complete([_details('current')]);
      await second;
      repository.first.complete([_details('stale')]);
      await first;

      expect(viewModel.state.values.single.entry.id, 'current');
      expect(
        () => viewModel.state.values.add(_details('mutation')),
        throwsUnsupportedError,
      );
      viewModel.dispose();
    },
  );

  test('phonetic commands refresh immutable state', () async {
    final repository = _PhoneticRepository();
    final viewModel = PhoneticAnalysisViewModel(repository);
    await viewModel.refresh();
    await viewModel.cancelJob('job-1');

    expect(repository.cancelled, 'job-1');
    expect(
      () => viewModel.state.jobs.add(_phoneticJob),
      throwsUnsupportedError,
    );
    viewModel.dispose();
  });

  test('transcription refresh publishes immutable snapshots', () async {
    final viewModel = TranscriptionCenterViewModel(
      _TranscriptionRepository(),
      loadTrack: (_, _) async {},
    );
    await viewModel.refresh();

    expect(viewModel.state.jobs, isEmpty);
    expect(
      () => viewModel.state.jobs.add(_transcriptionJob),
      throwsUnsupportedError,
    );
    viewModel.dispose();
  });
}

LexicalEntryDetails _details(String id) => LexicalEntryDetails(
  entry: LexicalEntry(
    id: id,
    normalizedForm: id,
    displayForm: id,
    kind: 'word',
    language: 'en',
  ),
  occurrences: const [],
);

final class _LearningRepository implements LearningAssetsRepository {
  final first = Completer<List<LexicalEntryDetails>>();
  final second = Completer<List<LexicalEntryDetails>>();
  int calls = 0;

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');

  @override
  Future<List<LexicalEntryDetails>> lexicalEntries({
    required String language,
    required String kind,
    String? status,
    required String search,
  }) => ++calls == 1 ? first.future : second.future;
  @override
  Future<LexicalEntryDetails> upsertLexicalEntry(Map<String, dynamic> value) =>
      throw UnimplementedError();
  @override
  Future<List<LearningResourceDescriptor>> learningResources() async => [];
  @override
  Future<void> installLearningResource(String id) async {}
  @override
  Future<void> removeLearningResource(String id) async {}
  @override
  Future<String> openSubtitlesMovieHash(String mediaPath) =>
      throw UnimplementedError();
  @override
  Future<List<OpenSubtitleCandidate>> searchOpenSubtitles({
    required String apiKey,
    String? query,
    String? moviehash,
  }) => throw UnimplementedError();
  @override
  Future<String> downloadOpenSubtitle({
    required String apiKey,
    required int fileId,
  }) => throw UnimplementedError();
}

const _phoneticJob = PhoneticJobView(
  id: 'job-1',
  trackId: 'track-1',
  scope: 'track',
  providerId: 'provider',
  runtimeId: 'runtime',
  runtimeVersion: '1',
  modelRevision: '1',
  status: 'completed',
  phaseProgress: 100,
  createdAtMs: 1,
);

final class _PhoneticRepository implements PhoneticAnalysisRepository {
  String? cancelled;
  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');
  @override
  Future<List<PhoneticProviderView>> providers() async => [];
  @override
  Future<List<PhoneticModelView>> models() async => [];
  @override
  Future<List<PhoneticJobView>> jobs() async => [_phoneticJob];
  @override
  Future<void> installModel(String id) async {}
  @override
  Future<void> cancelJob(String id) async => cancelled = id;
  @override
  Future<void> retryJob(String id) async {}
  @override
  Future<void> deleteJob(String id) async {}
  @override
  Future<void> clearTerminalJobs() async {}
}

const _transcriptionJob = TranscriptionJobView(
  id: 'job-1',
  mediaId: 'media-1',
  mediaTitle: 'Media',
  modelId: 'model',
  destination: 'primary',
  status: 'completed',
  phaseProgress: 100,
  createdAtMs: 1,
);

final class _TranscriptionRepository implements TranscriptionRepository {
  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');
  @override
  Future<List<TranscriptionProviderView>> providers() async => [];
  @override
  Future<List<TranscriptionModelView>> models() async => [];
  @override
  Future<List<TranscriptionJobView>> jobs() async => [];
  @override
  Future<void> createJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    required bool force,
  }) async {}
  @override
  Future<void> registerCustomModel(String path) async {}
  @override
  Future<void> installModel(String id) async {}
  @override
  Future<void> cancelModelInstall(String id) async {}
  @override
  Future<void> deleteModel(String id) async {}
  @override
  Future<void> cancelJob(String id) async {}
  @override
  Future<void> retryJob(String id) async {}
  @override
  Future<SubtitleTrack> readSubtitle(String id) => throw UnimplementedError();
  @override
  Future<String> exportSubtitleSrt(String id) => throw UnimplementedError();
  @override
  Future<void> archiveJob(String id) async {}
}
