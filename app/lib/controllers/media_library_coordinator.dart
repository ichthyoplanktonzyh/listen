import 'dart:async';

import '../data/repositories/learning_material_repository.dart';
import '../data/repositories/media_library_repository.dart';
import '../models/personal_library.dart';
import '../models/saved_vocabulary_count.dart';
import '../models/types.dart';
import '../services/media_file_service.dart';
import 'extensive_listening_controller.dart';
import 'learning_controller.dart';
import 'player_controller.dart';
import 'settings_controller.dart';
import 'subtitle_controller.dart';

/// Owns the home media-library/triage actions plus the prefetched home
/// summary facts (saved vocabulary count, library entries). Extracted
/// verbatim from `_PlayerScreenState` (main.dart decomposition); media-session
/// operations arrive as injected callbacks so this stays testable in
/// isolation and never holds another coordinator.
class MediaLibraryCoordinator {
  MediaLibraryCoordinator({
    required this.player,
    required this.subtitle,
    required this.learning,
    required this.settings,
    required this.extensiveListening,
    required this.repository,
    required this.materialRepository,
    this.fileService = const LocalMediaFileService(),
  });

  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final SettingsController settings;
  final ExtensiveListeningController extensiveListening;
  final MediaLibraryRepository repository;
  final LearningMaterialRepository materialRepository;
  final MediaFileService fileService;

  late bool Function() isMounted;
  late String Function(String key) text;
  late void Function() requestRebuild;
  late Future<void> Function(String path) openMediaPath;
  late Future<void> Function() openMedia;

  /// Global learning totals prefetched for the no-media home surface so the
  /// readiness strip is not misleadingly empty at cold start.
  SavedVocabularyCount? savedVocabulary;
  List<MediaLibraryEntry>? mediaLibrary;

  /// The authoritative library: retained materials joined with their media
  /// rows, in material-listing order. [mediaLibrary] stays as the raw
  /// registered-media snapshot the current UI renders from.
  List<PersonalLibraryEntry>? personalLibrary;

  void bind({
    required bool Function() isMounted,
    required String Function(String key) text,
    required void Function() requestRebuild,
    required Future<void> Function(String path) openMediaPath,
    required Future<void> Function() openMedia,
  }) {
    this.isMounted = isMounted;
    this.text = text;
    this.requestRebuild = requestRebuild;
    this.openMediaPath = openMediaPath;
    this.openMedia = openMedia;
  }

  /// Persist the currently playing media so the no-media home can offer a real
  /// "continue" entry and honest readiness at the next launch.
  void recordRecentMedia() {
    final path = player.mediaPath;
    if (path == null || path.isEmpty) return;
    settings.recordRecentMedia(
      path: path,
      title: player.mediaTitle ?? fileService.basename(path),
      positionMs: player.position.inMilliseconds,
      durationMs: player.duration.inMilliseconds,
      subtitleCount: subtitle.subtitleResources.length,
    );
  }

  /// Prefetch global learning totals (vocabulary, listening inbox) so the home
  /// readiness strip reflects real state instead of cold-start zeros.
  Future<void> prefetchHomeSummary() async {
    // Passive prefetch (runs on connect, not on a user action): before the
    // core is up the home simply keeps its neutral placeholders.
    if (!repository.isAvailable) return;
    unawaited(extensiveListening.refreshInbox());
    unawaited(loadMediaLibrary());
    try {
      final count = await repository.savedVocabularyCount(
        language: settings.resolveLearningLanguage(
          subtitle.primaryTrack?.language,
        ),
      );
      if (isMounted()) {
        savedVocabulary = count;
        requestRebuild();
      }
    } catch (_) {
      // Leave the strip on its neutral placeholder when the count is
      // unavailable; the home must not fail because a summary query did.
    }
  }

  /// Generation of the most recently started [loadMediaLibrary]. Every call
  /// immediately bumps it — even a call that exits early because the material
  /// repository is unavailable — so an earlier in-flight load can never
  /// publish after a newer one has started.
  int _libraryLoadGeneration = 0;

  /// Media library facts for the home triage list. Failures leave the
  /// section on its previous state: the library is a suggestion surface,
  /// never a gate on playback or learning.
  ///
  /// Latest-request-wins: query results stay in locals until the whole load
  /// is known to be the newest generation, then both lists flip together in
  /// one atomic publish. A superseded request never writes state or rebuilds,
  /// regardless of whether it later succeeds or fails.
  Future<void> loadMediaLibrary() async {
    // Background summary refresh; a missing core keeps the previous list,
    // matching the failure policy documented above. Membership and ordering
    // come from the material repository, so it alone gates the load: the
    // registered-media query is only a best-effort join/path snapshot on top
    // of it.
    final generation = ++_libraryLoadGeneration;
    if (!materialRepository.isAvailable) return;
    try {
      final materials = await materialRepository.listLearningMaterials();
      // A newer load started while the material query was in flight: this
      // request is already superseded, before it even touches the media
      // snapshot.
      if (generation != _libraryLoadGeneration || !isMounted()) return;
      // Best-effort raw media snapshot. A skipped or failed media query keeps
      // whatever snapshot the section already had: the material rows still
      // publish, joined against that previous snapshot (or unresolved when
      // there is none yet).
      var snapshot = mediaLibrary;
      var refreshed = false;
      if (repository.isAvailable) {
        try {
          final entries = await repository.listMediaLibrary();
          snapshot = entries;
          refreshed = true;
        } catch (_) {
          // Keep whatever raw snapshot the section had.
        }
      }
      // Atomic publish: both next states are fully constructed in locals
      // before any field is written, so a projection failure can never leave
      // a "new mediaLibrary + old personalLibrary" partial state behind. Only
      // then do the fields flip, when this call is still the newest and the
      // surface is still mounted.
      if (generation != _libraryLoadGeneration || !isMounted()) return;
      final List<MediaLibraryEntry>? nextMediaLibrary = refreshed
          ? List.unmodifiable(snapshot!)
          : null;
      final List<PersonalLibraryEntry> nextPersonalLibrary = List.unmodifiable([
        for (final details in materials)
          PersonalLibraryEntry(
            details: details,
            mediaEntries: snapshot ?? const [],
          ),
      ]);
      if (nextMediaLibrary != null) {
        mediaLibrary = nextMediaLibrary;
      }
      personalLibrary = nextPersonalLibrary;
      requestRebuild();
    } catch (_) {
      // Material listing failed: keep the previous personalLibrary and
      // mediaLibrary; the home must not fail on a summary.
    }
  }

  /// Paths Core already holds, or null while that answer is unknown. Feeds the
  /// folder scan's cheap identification layer, which must not treat "the
  /// library has not loaded" as "nothing is registered".
  List<String>? get registeredMediaPaths =>
      mediaLibrary?.map((entry) => entry.media.path).toList(growable: false);

  /// Subset of [mediaLibrary] whose local media file still exists on disk.
  List<MediaLibraryEntry>? get offlineLibrary {
    final library = mediaLibrary;
    if (library == null) return null;
    return library
        .where((entry) => fileService.exists(entry.media.path))
        .toList(growable: false);
  }

  /// Opens a library row like any other media — triage never changes what
  /// opening a file does.
  Future<void> openLibraryEntry(MediaLibraryEntry entry) async {
    if (!fileService.exists(entry.media.path)) {
      player.setStatus(text('mediaFileMissing'));
      return;
    }
    await openMediaPath(entry.media.path);
  }

  /// One-click extensive listening: open the media, then start the ambient
  /// session with the loaded primary track.
  Future<void> startExtensiveFromLibrary(MediaLibraryEntry entry) async {
    if (!fileService.exists(entry.media.path)) {
      player.setStatus(text('mediaFileMissing'));
      return;
    }
    await openMediaPath(entry.media.path);
    if (!isMounted() || extensiveListening.active) return;
    final started = await extensiveListening.startSession(
      mediaId: player.mediaId,
      trackId: subtitle.primaryTrack?.id ?? entry.primaryTrackId,
    );
    if (started && isMounted()) {
      player.setStatus(text('statusExtensiveListeningStarted'));
    }
  }

  /// One-click intensive listening opens the material; a concrete current
  /// sentence is still required before the user chooses a practice type.
  Future<void> startIntensiveFromLibrary(MediaLibraryEntry entry) async {
    if (!fileService.exists(entry.media.path)) {
      player.setStatus(text('mediaFileMissing'));
      return;
    }
    await openMediaPath(entry.media.path);
    if (isMounted()) learning.selectTab(SidePanelTab.transcript);
  }

  Future<void> setLibraryTriageIntent(
    MediaLibraryEntry entry,
    String? intent,
  ) async {
    if (!repository.isAvailable) {
      // Unavailable State (CONTEXT.md): triage is a direct click on a library
      // row, so report the missing core instead of silently doing nothing.
      player.setStatus(text('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      final updated = await repository.setTriageIntent(entry.media.id, intent);
      if (!isMounted()) return;
      final library = mediaLibrary;
      if (library != null) {
        final index = library.indexWhere(
          (item) => item.media.id == updated.media.id,
        );
        if (index >= 0) {
          mediaLibrary = List.unmodifiable([
            ...library.take(index),
            updated,
            ...library.skip(index + 1),
          ]);
        }
      }
      // The authoritative projection delegates its triage facts to the joined
      // rows, so an intent change has to land there too or the two lists
      // drift apart.
      final personal = personalLibrary;
      if (personal != null) {
        var changed = false;
        final rows = <PersonalLibraryEntry>[];
        for (final row in personal) {
          final updatedRow = row.withMediaEntry(updated);
          if (updatedRow != row) changed = true;
          rows.add(updatedRow);
        }
        if (changed) personalLibrary = List.unmodifiable(rows);
      }
      requestRebuild();
    } catch (error) {
      player.setStatus(
        text('statusTriageIntentFailed'),
        error: true,
        failure: repository.failureDetail(error),
      );
    }
  }

  Future<void> toggleFamiliarSupply(bool enabled) async {
    await settings.update(
      settings.settings.copyWith(familiarMaterialSuggestions: enabled),
    );
  }

  /// Reopen the most recently played media from the home continue entry. The
  /// backend restores the exact saved position during [openMediaPath].
  Future<void> continueRecentMedia() async {
    final path = settings.lastMediaPath;
    if (path.isEmpty) {
      await openMedia();
      return;
    }
    if (!fileService.exists(path)) {
      player.setStatus(text('statusRecentMediaMissing'), error: true);
      await openMedia();
      return;
    }
    await openMediaPath(path);
  }
}
