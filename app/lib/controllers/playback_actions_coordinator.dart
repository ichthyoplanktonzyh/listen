import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../models/timeline.dart';
import '../models/types.dart';
import '../player_adapter.dart';
import '../services/api_service.dart';
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
  late Future<void> Function() reloadLearningEntries;
  late Future<void> Function(String path) openMediaPath;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required Future<void> Function() reloadLearningEntries,
    required Future<void> Function(String path) openMediaPath,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
    this.reloadLearningEntries = reloadLearningEntries;
    this.openMediaPath = openMediaPath;
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

  // ── Source-loop ranges ──

  Future<void> loopRange(int startMs, int endMs, String label) async {
    final start = Duration(milliseconds: startMs);
    final end = Duration(milliseconds: endMs);
    if (start >= end) return;
    player.setSourceLoop(start, end, label: 'loopRange');
    subtitle.setLoopCue(false);
    if (isMounted()) player.setStatus(label);
    await adapter.seek(start);
    await adapter.play();
  }

  // ── Occurrence playback ──

  /// Plays a lexical occurrence from its source media. If the occurrence
  /// belongs to a different media file, resolves it via the linked media
  /// record or asks the user to locate the file, verifying its fingerprint
  /// before registering it.
  Future<void> playOccurrence(
    Map<String, dynamic> occurrence, {
    String? statusBeforeLoop,
    bool filterMediaExtensions = false,
  }) async {
    final api = getApi();
    if (api == null) return;
    final expectedFingerprint =
        occurrence['media_fingerprint_snapshot'] as String;
    if (expectedFingerprint != player.mediaFingerprint) {
      String? sourcePath;
      final linkedMediaId = occurrence['media_id'] as String?;
      if (linkedMediaId != null) {
        try {
          final linkedMedia = await api.readMedia(linkedMediaId);
          final linkedPath = linkedMedia['path'] as String;
          if (await File(linkedPath).exists()) sourcePath = linkedPath;
        } catch (_) {
          sourcePath = null;
        }
      }
      if (sourcePath == null) {
        final group = filterMediaExtensions
            ? const XTypeGroup(
                label: 'source media',
                extensions: [
                  'mp4',
                  'mkv',
                  'mov',
                  'webm',
                  'm4a',
                  'mp3',
                  'wav',
                  'flac',
                ],
              )
            : const XTypeGroup(label: 'source media');
        final file = await openFile(acceptedTypeGroups: [group]);
        if (file == null) return;
        if (await api.fingerprintFile(file.path) != expectedFingerprint) {
          player.setStatus(
            'Selected file does not match the source fingerprint',
          );
          return;
        }
        await api.registerMedia(file.path);
        sourcePath = file.path;
      }
      await openMediaPath(sourcePath);
    }
    final start = Duration(
      milliseconds: occurrence['start_ms_snapshot'] as int,
    );
    final end = Duration(milliseconds: occurrence['end_ms_snapshot'] as int);
    if (statusBeforeLoop != null) player.setStatus(statusBeforeLoop);
    player.setSourceLoop(start, end, label: 'loopOccurrence');
    subtitle.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
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
        player.setStatus('Audio finding feedback saved: $value');
      }
    } catch (error) {
      if (isMounted()) {
        player.setStatus('Could not save audio finding feedback: $error');
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
    player.setStatus('Exported vocabulary assets');
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
    player.setStatus('Imported vocabulary assets');
  }

  Future<void> archiveCurrentMedia() async {
    final service = getApi();
    if (service == null || player.mediaId == null) return;
    await service.setMediaAvailability(player.mediaId!, 'archived');
    player.setStatus(
      'Archived current media record; vocabulary assets preserved',
    );
  }
}
