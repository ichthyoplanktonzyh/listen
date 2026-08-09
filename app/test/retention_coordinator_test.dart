import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/media_session_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/media_session_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/data/repositories/subtitle_analysis_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/managed_asset_store.dart';
import 'package:llplayer_next/services/media_import_file_service.dart';

/// Retention end to end through the session coordinator: opening local media
/// is Temporary Material (retain false) and keeps playing when Core fails;
/// Keep copies into the managed store and re-registers the managed path with
/// retain true; a failed registration rolls back only a copy this operation
/// created (never a pre-existing deduplication target); reference-in-place
/// retains without copying; unretain changes membership only.
void main() {
  test(
    'opening local media registers Temporary Material (retain false)',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final harness = _harness(adapter: adapter, repository: repository);

      await harness.session.openMediaPath('/media/original.mp3');

      expect(repository.registered, hasLength(1));
      expect(repository.registered.single.path, '/media/original.mp3');
      expect(repository.registered.single.retain, isFalse);
      // Playback happened and the session is marked temporary.
      expect(adapter.opened, ['/media/original.mp3']);
      expect(harness.player.mediaRetained, isFalse);
      expect(
        harness.player.status,
        _en('statusPlayingFile').replaceAll('{name}', 'original.mp3'),
      );
    },
  );

  test('playback still works when Core registration fails on open', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository()..failRegistration = true;
    final harness = _harness(adapter: adapter, repository: repository);

    await harness.session.openMediaPath('/media/original.mp3');

    expect(adapter.opened, ['/media/original.mp3']);
    expect(adapter.played, isTrue);
    // The failure is named on the status line, never the exception text.
    expect(harness.player.status, _en('statusPlayingCoreUnavailable'));
    expect(harness.player.statusFailure, isNotNull);
    expect(harness.player.status, isNot(contains('core refused')));
  });

  test('an already-retained media reopens without losing membership', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository()
      ..alreadyRetained.add('/media/kept.mp3');
    final harness = _harness(adapter: adapter, repository: repository);

    await harness.session.openMediaPath('/media/kept.mp3');

    // Core 3.1 fingerprint identity: re-registering a kept path keeps its
    // membership even though the open itself passes retain false.
    expect(repository.registered.single.retain, isFalse);
    expect(harness.player.mediaRetained, isTrue);
  });

  test('Keep copies into the managed store and rebinds the session', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original Title',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);

    await harness.session.keepCurrentMedia();

    // Copied once, registered at the managed path with retain true and the
    // original title, and the session now points at the managed copy.
    expect(store.copies, ['/media/original.mp3']);
    expect(repository.registered, hasLength(1));
    expect(repository.registered.single.path, store.copyPath);
    expect(repository.registered.single.retain, isTrue);
    expect(repository.registered.single.title, 'Original Title');
    expect(repository.registered.single.kind, 'audio');
    expect(repository.retained, isEmpty);
    expect(harness.player.mediaPath, store.copyPath);
    expect(harness.player.mediaTitle, 'Original Title');
    expect(harness.player.mediaId, 'media-1');
    expect(harness.player.mediaRetained, isTrue);
    expect(harness.player.status, _en('statusMediaKept'));
    expect(harness.player.statusIsError, isFalse);
    // The recent-media path follows the session to the managed copy.
    expect(harness.settings.lastRecordedPath, store.copyPath);
    expect(harness.player.retentionInFlight, isFalse);
  });

  test(
    'a failed Core registration rolls back only a newly created copy',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository()..failRegistration = true;
      final store = _FakeManagedStore()..createdNew = true;
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
      );
      harness.player.setMedia(
        id: 'media-1',
        path: '/media/original.mp3',
        title: 'Original',
        fingerprint: 'fp',
      );
      harness.player.setMediaRetained(false);

      await harness.session.keepCurrentMedia();

      // The copy this operation created is removed; the media stays temporary.
      expect(store.deleted, [store.copyPath]);
      expect(repository.retained, isEmpty);
      expect(harness.player.mediaRetained, isFalse);
      expect(harness.player.mediaPath, '/media/original.mp3');
      expect(harness.player.status, _en('statusKeepFailed'));
      expect(harness.player.statusIsError, isTrue);
      expect(harness.player.statusFailure, isNotNull);
      expect(harness.player.status, isNot(contains('core refused')));
    },
  );

  test(
    'a failed Core registration never removes a pre-existing dedupe target',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository()..failRegistration = true;
      final store = _FakeManagedStore()..createdNew = false;
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
      );
      harness.player.setMedia(
        id: 'media-1',
        path: '/media/original.mp3',
        title: 'Original',
        fingerprint: 'fp',
      );
      harness.player.setMediaRetained(false);

      await harness.session.keepCurrentMedia();

      // The deduplication target was already in the store; nothing is deleted.
      expect(store.deleted, isEmpty);
      expect(repository.retained, isEmpty);
      expect(harness.player.mediaRetained, isFalse);
      expect(harness.player.status, _en('statusKeepFailed'));
    },
  );

  test(
    'an unavailable managed store reports honestly and changes nothing',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final store = _FakeManagedStore()..unavailable = true;
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
      );
      harness.player.setMedia(
        id: 'media-1',
        path: '/media/original.mp3',
        title: 'Original',
        fingerprint: 'fp',
      );
      harness.player.setMediaRetained(false);

      await harness.session.keepCurrentMedia();

      expect(store.copies, isEmpty);
      expect(repository.registered, isEmpty);
      expect(repository.retained, isEmpty);
      expect(harness.player.mediaRetained, isFalse);
      expect(harness.player.status, _en('statusManagedStoreUnavailable'));
      expect(harness.player.statusIsError, isTrue);
      expect(harness.player.status, isNot(contains('ManagedStoreUnavailable')));
    },
  );

  test('a local managed-copy failure never leaks filesystem details', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore()..copyFails = true;
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);

    await harness.session.keepCurrentMedia();

    expect(repository.retained, isEmpty);
    expect(harness.player.mediaRetained, isFalse);
    expect(harness.player.status, _en('statusKeepFailed'));
    expect(harness.player.status, isNot(contains('ManagedStoreCopyFailed')));
    expect(harness.player.statusFailure, isNull);
  });

  test('reference in place retains without copying', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);

    await harness.session.referenceCurrentMediaInPlace();

    expect(repository.retained, ['media-1']);
    expect(store.copies, isEmpty);
    expect(harness.player.mediaPath, '/media/original.mp3');
    expect(harness.player.mediaRetained, isTrue);
    expect(harness.player.status, _en('statusMediaKeptInPlace'));
  });

  test('unretain changes membership only — no file, store or learning state '
      'is touched', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: store.copyPath,
      title: 'Kept',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(true);

    await harness.session.unretainCurrentMedia();

    expect(repository.unretained, ['media-1']);
    expect(harness.player.mediaRetained, isFalse);
    expect(harness.player.mediaPath, store.copyPath);
    expect(store.deleted, isEmpty);
    // Learning/session identity is untouched.
    expect(harness.player.mediaId, 'media-1');
    expect(harness.player.status, _en('statusMediaUnkept'));
  });

  test('an unretain failure is named and keeps membership', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository()..failUnretain = true;
    final store = _FakeManagedStore();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/store/copy.mp3',
      title: 'Kept',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(true);

    await harness.session.unretainCurrentMedia();

    expect(harness.player.mediaRetained, isTrue);
    expect(harness.player.status, _en('statusUnkeepFailed'));
    expect(harness.player.statusIsError, isTrue);
    expect(harness.player.status, isNot(contains('refused')));
  });

  test('retention operations refuse re-entry while in flight', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);
    harness.player.setRetentionInFlight(true);

    await harness.session.keepCurrentMedia();

    expect(store.copies, isEmpty);
    expect(repository.registered, isEmpty);
    expect(harness.player.mediaRetained, isFalse);
  });

  test('retention needs an open media', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final harness = _harness(adapter: adapter, repository: repository);

    await harness.session.keepCurrentMedia();
    expect(harness.player.status, _en('statusOpenMediaFirst'));

    await harness.session.referenceCurrentMediaInPlace();
    expect(harness.player.status, _en('statusOpenMediaFirst'));
  });
}

String _en(String key) => const AppLocalizations(Locale('en')).text(key);

({
  _FakeAdapter adapter,
  PlayerController player,
  SubtitleController subtitle,
  _RecordingSettings settings,
  MediaSessionCoordinator session,
})
_harness({
  required _FakeAdapter adapter,
  required _FakeSessionRepository repository,
  _FakeManagedStore? store,
}) {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final settings = _RecordingSettings();
  final speech = SpeechEnhancementWorkflowController();
  final resourceActions =
      ResourceActionsCoordinator(
        player: player,
        subtitle: subtitle,
        speechEnhancement: speech,
        repository: _FakeResourceRepository(),
      )..bind(
        isMounted: () => true,
        text: (key) => _en(key),
        reloadSpeechEnhancements: (_) async {},
        activatePrimaryTrack: (_, {required nextStatus}) async {},
        reloadLearningEntries: () async {},
      );
  final session =
      MediaSessionCoordinator(
        adapter: adapter,
        player: player,
        subtitle: subtitle,
        learning: LearningController(),
        settings: settings,
        speechEnhancement: speech,
        resourceActions: resourceActions,
        repository: repository,
        subtitleAnalysis: _FakeSubtitleAnalysisRepository(),
        managedStore: store ?? _FakeManagedStore(),
        importFiles: _FixedImportFiles(),
      )..bind(
        isMounted: () => true,
        text: (key) => _en(key),
        confirmLLTimelineMismatch:
            ({
              required String resourceFingerprint,
              required String currentFingerprint,
            }) async => true,
        onMediaSwitched: () {},
        reloadLearningEntries: () async {},
        loadPhraseCandidates: (_) async {},
      );
  return (
    adapter: adapter,
    player: player,
    subtitle: subtitle,
    settings: settings,
    session: session,
  );
}

/// An adapter that plays nothing, so the coordinator's open path runs in a
/// plain Dart test. [DesktopPlayerAdapter] is a plain class, so a subclass
/// with real `open`/`play`/`seek` overrides is the seam.
class _FakeAdapter extends DesktopPlayerAdapter {
  final opened = <String>[];
  bool played = false;

  @override
  Future<void> open(String path, {bool play = true}) async {
    opened.add(path);
  }

  @override
  Future<void> play() async {
    played = true;
  }

  @override
  Future<void> seek(Duration position) async {}
}

class _FakeSessionRepository implements MediaSessionRepository {
  bool failRegistration = false;
  bool failUnretain = false;
  final alreadyRetained = <String>{};
  final registered =
      <({String path, bool retain, String? title, String? kind})>[];
  final retained = <String>[];
  final unretained = <String>[];

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'refused by fake core');

  @override
  Future<MediaItem> registerMedia(
    String path, {
    required bool retain,
    String? title,
    String? kind,
  }) async {
    registered.add((path: path, retain: retain, title: title, kind: kind));
    if (failRegistration) throw StateError('core refused');
    return MediaItem(
      id: 'media-1',
      path: path,
      fingerprint: 'fp',
      title: title ?? 'T',
      kind: kind ?? 'audio',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 1,
      // Core 3.1 fingerprint identity keeps existing membership on a
      // re-registration, even one that passes retain false.
      retainedAtMs: retain || alreadyRetained.contains(path) ? 1 : null,
    );
  }

  @override
  Future<MediaItem> retainMedia(String mediaId) async {
    retained.add(mediaId);
    return MediaItem(
      id: mediaId,
      path: '/media/original.mp3',
      fingerprint: 'fp',
      title: 'T',
      kind: 'audio',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 2,
      retainedAtMs: 2,
    );
  }

  @override
  Future<MediaItem> unretainMedia(String mediaId) async {
    if (failUnretain) throw StateError('refused');
    unretained.add(mediaId);
    return MediaItem(
      id: mediaId,
      path: '/media/original.mp3',
      fingerprint: 'fp',
      title: 'T',
      kind: 'audio',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 2,
    );
  }

  @override
  Future<void> saveProgress(String mediaId, Duration position) async {}

  @override
  Future<Duration?> readProgress(String mediaId) async => null;

  @override
  Future<SubtitleTrack> importSubtitle(String mediaId, String path) async =>
      throw UnimplementedError();

  @override
  Future<SubtitleTrack> importTimeline({
    required String mediaId,
    required Map<String, dynamic> document,
    required bool allowMismatch,
  }) async => throw UnimplementedError();
}

class _FakeManagedStore implements ManagedAssetStoreService {
  String copyPath = '/store/copy-0.mp3';
  bool createdNew = true;
  bool unavailable = false;
  bool copyFails = false;
  final copies = <String>[];
  final deleted = <String>[];

  @override
  Future<ManagedAssetCopy> copyIntoStore({required String sourcePath}) async {
    if (unavailable) throw const ManagedStoreUnavailable();
    if (copyFails) throw const ManagedStoreCopyFailed();
    copies.add(sourcePath);
    return ManagedAssetCopy(
      path: copyPath,
      createdNew: createdNew,
      mediaKind: 'audio',
    );
  }

  @override
  Future<void> deleteStoreCopy(String path) async {
    deleted.add(path);
  }
}

class _RecordingSettings extends SettingsController {
  String? lastRecordedPath;

  @override
  void recordRecentMedia({
    required String path,
    required String title,
    required int positionMs,
    required int durationMs,
    required int subtitleCount,
  }) {
    lastRecordedPath = path;
  }
}

class _FakeResourceRepository implements ResourceRepository {
  @override
  bool get isAvailable => false;
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'unavailable');
  @override
  Future<ContentDifficultyProfile> contentFit(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId) async => [];
  @override
  Future<List<WordTiming>> wordTimings(String trackId) async => [];
  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(
    String trackId,
  ) async => [];
  @override
  Future<void> archiveSubtitle(String trackId) async {}
  @override
  Future<void> restoreSubtitle(String trackId) async {}
  @override
  Future<void> deleteSubtitle(String trackId) async {}
  @override
  Future<String> exportSubtitleSrt(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<void> updateTrackLanguage(String trackId, String language) async {}
  @override
  Future<void> activateWordTimeline(String timelineId) async {}
  @override
  Future<void> activatePhoneTimeline(String timelineId) async {}
  @override
  Future<void> archivePhoneTimeline(String timelineId) async {}
  @override
  Future<void> deletePhoneTimeline(String timelineId) async {}
}

class _FakeSubtitleAnalysisRepository implements SubtitleAnalysisRepository {
  @override
  bool get isAvailable => false;
  @override
  Future<bool> syntaxReady() async => false;
  @override
  Future<void> analyzeTrackSyntax(String trackId) async {}
  @override
  Future<PronunciationAnalysis> analyzePronunciation(String sentenceId) async =>
      throw UnimplementedError();
  @override
  Future<String> startPhoneticAnalysis({
    required String trackId,
    required String? sentenceId,
    required String preferredModelId,
  }) async => throw UnimplementedError();
}

/// Lets openMediaPath find a concrete media path without a picker.
class _FixedImportFiles implements MediaImportFileService {
  @override
  Future<String?> pickMedia() async => null;
  @override
  Future<String?> pickSubtitle() async => null;
  @override
  Future<String?> pickContentPackage() async => null;
  @override
  Future<TimelineFileDocument?> pickTimeline() async => null;
  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;
  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async => null;
}
