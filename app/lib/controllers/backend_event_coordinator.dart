import 'dart:async';

import '../models/backend_event.dart';
import '../models/task_status.dart';
import '../models/types.dart';

class BackendEventCoordinator {
  const BackendEventCoordinator({
    required this.currentMediaId,
    required this.currentPrimaryTrackId,
    required this.loadWordEntries,
    required this.loadTimelineResource,
    required this.readSubtitle,
    required this.loadGeneratedTrack,
    required this.loadSpeechEnhancements,
    required this.setStatus,
    required this.setTaskStatus,
    required this.updateWordEntry,
  });

  final String? Function() currentMediaId;
  final String? Function() currentPrimaryTrackId;
  final Future<void> Function() loadWordEntries;
  final Future<void> Function(String trackId) loadTimelineResource;
  final Future<Map<String, dynamic>> Function(String trackId) readSubtitle;
  final Future<void> Function(Map<String, dynamic> track, bool secondary)
  loadGeneratedTrack;
  final Future<void> Function(String trackId) loadSpeechEnhancements;
  final void Function(String status) setStatus;
  final void Function(UserTaskStatus status) setTaskStatus;
  final void Function(String normalizedForm, LexicalEntry entry)
  updateWordEntry;

  void handle(Map<String, dynamic> raw) {
    final event = BackendEvent.fromJson(raw);
    if (event is ServiceStartedEvent) {
      unawaited(loadWordEntries());
      final trackId = currentPrimaryTrackId();
      if (trackId != null) unawaited(loadTimelineResource(trackId));
      return;
    }
    if (event is TranscriptionJobChangedEvent) {
      _handleTranscriptionJob(event);
      return;
    }
    if (event is WordTimingsCompletedEvent) {
      _handleWordTimingsCompleted(event);
      return;
    }
    if (event is SoundLineCompletedEvent) {
      _handleSoundLineCompleted(event);
      return;
    }
    if (event is PhoneticAnalysisJobChangedEvent) {
      _handlePhoneticAnalysisJob(event);
      return;
    }
    if (event is LexicalEntryChangedEvent) {
      updateWordEntry(event.normalizedForm, event.entry);
    }
  }

  void _handleTranscriptionJob(TranscriptionJobChangedEvent event) {
    if (event.mediaId != currentMediaId()) return;
    setTaskStatus(UserTaskStatus.transcription(event));
    if (event.status == 'completed' && event.generatedTrackId != null) {
      unawaited(
        readSubtitle(event.generatedTrackId!).then(
          (track) =>
              loadGeneratedTrack(track, event.destination == 'secondary'),
        ),
      );
      return;
    }
    setStatus('ASR ${event.status} · ${event.phaseProgress}%');
  }

  // Text line: whisper word timings are ready. Refresh resources so the core
  // experience (word seeking, chunks, phonetics) picks them up.
  void _handleWordTimingsCompleted(WordTimingsCompletedEvent event) {
    if (event.trackId != currentPrimaryTrackId()) return;
    unawaited(loadSpeechEnhancements(event.trackId));
  }

  // Sound line: the independent listening-structure workflow finished. Refresh
  // so the C (this-audio) view picks up pause/acoustic evidence.
  void _handleSoundLineCompleted(SoundLineCompletedEvent event) {
    if (event.trackId != currentPrimaryTrackId()) return;
    unawaited(loadSpeechEnhancements(event.trackId));
    setStatus('Sound line ready');
  }

  void _handlePhoneticAnalysisJob(PhoneticAnalysisJobChangedEvent event) {
    if (event.trackId != currentPrimaryTrackId()) return;
    setTaskStatus(UserTaskStatus.audioAnalysis(event));
    if (event.status == 'completed' && event.trackId != null) {
      unawaited(loadSpeechEnhancements(event.trackId!));
    }
    setStatus('Audio analysis ${event.status} · ${event.phaseProgress}%');
  }
}
