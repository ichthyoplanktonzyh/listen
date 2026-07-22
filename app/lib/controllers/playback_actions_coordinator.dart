import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../models/timeline.dart';
import '../models/types.dart';
import '../player_adapter.dart';
import '../services/api_service.dart';
import 'occurrence_media_resolver.dart';
import 'player_controller.dart';
import 'subtitle_controller.dart';

/// A chunk resolved against its owning cue and partition, used by the
/// chunk-navigation playback actions.
class ChunkRef {
  const ChunkRef(this.cue, this.chunk, this.partition);

  final Cue cue;
  final DisplayChunk chunk;
  final SentenceChunkPartition partition;

  Duration get start => chunk.start;
}

/// Owns playback-centric actions: chunk navigation/looping, source-loop
/// ranges, playing a vocabulary occurrence from its source media (resolving
/// the media by fingerprint), phonetic finding feedback, vocabulary
/// export/import, and archiving the current media record. Context-free;
/// dialogs stay with the host.
class PlaybackActionsCoordinator {
  PlaybackActionsCoordinator({
    required this.adapter,
    required this.player,
    required this.subtitle,
  });

  final DesktopPlayerAdapter adapter;
  final PlayerController player;
  final SubtitleController subtitle;

  late LocalApi? Function() getApi;
  late bool Function() isMounted;
  String Function(String key)? text;

  String _t(String key) => text?.call(key) ?? key;
  late Future<void> Function() reloadLearningEntries;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    String Function(String key)? text,
    required Future<void> Function() reloadLearningEntries,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
    this.text = text;
    this.reloadLearningEntries = reloadLearningEntries;
  }

  // ── Chunk navigation ──

  ChunkRef? currentChunkRef() {
    final cue = subtitle.currentPrimaryCue;
    if (cue == null) return null;
    final partition = subtitle.chunkPartitionsBySentence[cue.id];
    if (partition == null || partition.chunks.isEmpty) return null;
    final index =
        subtitle.currentChunkIndex ??
        currentChunkAtPosition(
          partition,
          player.position,
          offset: subtitle.primarySubtitleOffset,
        );
    if (index == null) return null;
    for (final chunk in partition.chunks) {
      if (chunk.index == index) return ChunkRef(cue, chunk, partition);
    }
    return null;
  }

  ChunkRef? chunkRefAt(Cue cue, int chunkIndex) {
    final partition = subtitle.chunkPartitionsBySentence[cue.id];
    if (partition == null || partition.chunks.isEmpty) return null;
    if (chunkIndex < 0 || chunkIndex >= partition.chunks.length) return null;
    return ChunkRef(cue, partition.chunks[chunkIndex], partition);
  }

  Future<void> seekChunk(DisplayChunk chunk) async {
    final start = mediaTime(chunk.start);
    await adapter.seek(start);
    player.setPosition(start);
  }

  Future<void> seekAdjacentChunk(int delta) async {
    final current = currentChunkRef();
    final cue = current?.cue ?? subtitle.currentPrimaryCue;
    if (cue == null) return;
    final localIndex = current == null
        ? 0
        : current.partition.chunks.indexWhere(
            (chunk) => chunk.index == current.chunk.index,
          );
    var target = chunkRefAt(cue, localIndex + delta);
    if (target == null && delta < 0) {
      final previousCue = subtitle.primaryCursor.previous(cue);
      final previousPartition = previousCue == null
          ? null
          : subtitle.chunkPartitionsBySentence[previousCue.id];
      if (previousCue != null &&
          previousPartition != null &&
          previousPartition.chunks.isNotEmpty) {
        target = ChunkRef(
          previousCue,
          previousPartition.chunks.last,
          previousPartition,
        );
      }
    }
    if (target == null && delta > 0) {
      final nextCue = subtitle.primaryCursor.next(cue);
      target = nextCue == null ? null : chunkRefAt(nextCue, 0);
    }
    if (target == null) return;
    await seekChunk(target.chunk);
  }

  Future<void> loopCurrentChunk() async {
    final current = currentChunkRef();
    if (current == null) return;
    final start = mediaTime(current.chunk.start);
    final end = mediaTime(current.chunk.end);
    if (end <= start) return;
    player.setSourceLoop(start, end, label: 'loopChunk');
    subtitle.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> loopExpandedChunk() async {
    final current = currentChunkRef();
    if (current == null) return;
    final localIndex = current.partition.chunks.indexWhere(
      (chunk) => chunk.index == current.chunk.index,
    );
    final next =
        localIndex >= 0 && localIndex + 1 < current.partition.chunks.length
        ? current.partition.chunks[localIndex + 1]
        : null;
    final start = mediaTime(current.chunk.start);
    final end = mediaTime(next?.end ?? current.cue.end);
    if (end <= start) return;
    player.setSourceLoop(start, end, label: 'expandChunk');
    subtitle.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  /// Subtitle time shifted by the primary offset, clamped at zero.
  Duration mediaTime(Duration subtitleTime) {
    final value = subtitleTime + subtitle.primarySubtitleOffset;
    return value.isNegative ? Duration.zero : value;
  }

  int mediaTimeMs(Duration subtitleTime) =>
      mediaTime(subtitleTime).inMilliseconds;

  /// The chunk under the playback cursor for the current primary cue, used to
  /// seed chunk-based practice.
  DisplayChunk? currentPracticeChunk() {
    final cue = subtitle.currentPrimaryCue;
    if (cue == null) return null;
    final current = currentChunkRef();
    if (current?.cue.id == cue.id) return current!.chunk;
    final partition = subtitle.chunkPartitionsBySentence[cue.id];
    if (partition == null || partition.chunks.isEmpty) return null;
    final currentIndex = subtitle.currentChunkIndex;
    if (currentIndex != null) {
      for (final chunk in partition.chunks) {
        if (chunk.index == currentIndex) return chunk;
      }
    }
    return partition.chunks.first;
  }

  List<DisplayChunk> currentPracticeChunks() {
    final cue = subtitle.currentPrimaryCue;
    if (cue == null) return const [];
    return subtitle.chunkPartitionsBySentence[cue.id]?.chunks ?? const [];
  }

  // ── Source-loop ranges ──

  /// [label] is the transient status text (may carry dynamic detail such as a
  /// phoneme or hotspot name). [labelKey] is a localization key naming the loop
  /// scenario for the persistent source-loop chip; it defaults to the generic
  /// `loopRange` when a caller has no more specific category.
  Future<void> loopRange(
    int startMs,
    int endMs,
    String label, {
    String labelKey = 'loopRange',
  }) async {
    final start = Duration(milliseconds: startMs);
    final end = Duration(milliseconds: endMs);
    if (start >= end) return;
    player.setSourceLoop(start, end, label: labelKey);
    subtitle.setLoopCue(false);
    if (isMounted()) player.setStatus(label);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> pauseReviewRange() async {
    await adapter.pause();
    if (player.sourceLoopLabel == 'loopReview') {
      player.setSourceLoop(null, null);
    }
  }

  // ── Occurrence playback ──

  /// Resolves a durable occurrence snapshot without changing the primary
  /// player. Slice playback and any later occurrence consumer must use this
  /// one path for linked-media lookup and user-assisted file recovery.
  Future<OccurrenceMediaResolution> resolveOccurrenceMedia(
    Map<String, dynamic> occurrence, {
    bool filterMediaExtensions = false,
  }) async {
    final api = getApi();
    if (api == null) {
      return const UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.coreUnavailable,
      );
    }
    return OccurrenceMediaResolver(
      readMedia: api.readMedia,
      fingerprintFile: api.fingerprintFile,
      registerMedia: (path) async {
        await api.registerMedia(path);
      },
      pickFile: (groups) => openFile(acceptedTypeGroups: groups),
    ).resolve(
      occurrence,
      currentMediaFingerprint: player.mediaFingerprint,
      currentMediaPath: player.mediaPath,
      filterMediaExtensions: filterMediaExtensions,
    );
  }

  // ── Feedback / vocabulary / media record ──

  Future<void> savePhoneticFindingFeedback(
    PhoneticFinding finding,
    String value,
  ) async {
    final service = getApi();
    if (service == null) return;
    try {
      await service.updatePhoneticFindingFeedback(
        findingId: finding.id,
        value: value,
      );
      if (isMounted()) {
        player.setStatus(_t('statusAudioFindingFeedbackSaved').replaceAll('{value}', value));
      }
    } catch (error) {
      if (isMounted()) {
        player.setStatus('${_t('statusAudioFindingFeedbackFailed')}: $error', error: true);
      }
    }
  }

  Future<void> exportVocabulary() async {
    final service = getApi();
    if (service == null) return;
    final location = await getSaveLocation(
      suggestedName: 'listen-vocabulary-v1.json',
    );
    if (location == null) return;
    final bundle = await service.exportVocabulary();
    await File(
      location.path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(bundle));
    player.setStatus(_t('statusVocabularyExported'));
  }

  Future<void> importVocabulary() async {
    final service = getApi();
    if (service == null) return;
    const group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final bundle =
        jsonDecode(await File(file.path).readAsString())
            as Map<String, dynamic>;
    await service.importVocabulary(bundle);
    await reloadLearningEntries();
    player.setStatus(_t('statusVocabularyImported'));
  }

  Future<void> archiveCurrentMedia() async {
    final service = getApi();
    if (service == null || player.mediaId == null) return;
    await service.setMediaAvailability(player.mediaId!, 'archived');
    player.setStatus(_t('statusMediaArchived'));
  }
}
