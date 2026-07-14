import 'dart:async';

import '../models/backend_event.dart';
import '../models/task_status.dart';
import '../models/timeline.dart';
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
    required this.updateCapabilityProfile,
  });

  final String? Function() currentMediaId;
  final String? Function() currentPrimaryTrackId;
  final Future<void> Function() loadWordEntries;
  final Future<void> Function(String trackId) loadTimelineResource;
  final Future<SubtitleTrack> Function(String trackId) readSubtitle;
  final Future<void> Function(SubtitleTrack track, bool secondary)
  loadGeneratedTrack;
  final Future<void> Function(String trackId) loadSpeechEnhancements;
  final void Function(String status) setStatus;
  final void Function(UserTaskStatus status) setTaskStatus;
  final void Function(String normalizedForm, LexicalEntry entry)
  updateWordEntry;
  final void Function(String normalizedForm, LexicalCapabilityProfile profile)
  updateCapabilityProfile;

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
      final profile = event.details.capabilityProfile;
      if (profile != null) {
        updateCapabilityProfile(event.normalizedForm, profile);
      }
      return;
    }
    if (event is LexicalCapabilityChangedEvent) {
      _handleCapabilityChanged(event);
    }
  }

  void _handleTranscriptionJob(TranscriptionJobChangedEvent event) {
    if (event.mediaId != currentMediaId()) return;
    // Archiving republishes the completed job snapshot. It is metadata churn,
    // not a second completion, and its generated track may already be deleted.
    if (event.archivedAtMs != null) return;
    setTaskStatus(UserTaskStatus.transcription(event));
    if (event.status == 'completed' && event.generatedTrackId != null) {
      unawaited(_loadCompletedTranscription(event));
      return;
    }
    setStatus('ASR ${event.status} · ${event.phaseProgress}%');
  }

  Future<void> _loadCompletedTranscription(
    TranscriptionJobChangedEvent event,
  ) async {
    try {
      final track = await readSubtitle(event.generatedTrackId!);
      if (event.mediaId != currentMediaId()) return;
      await loadGeneratedTrack(track, event.destination == 'secondary');
    } catch (error) {
      setStatus('Generated subtitle unavailable: $error');
    }
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

  // The full profile update is handled by LexicalEntryChangedEvent (which
  // fires alongside this event).  This handler exists for future use.
  void _handleCapabilityChanged(LexicalCapabilityChangedEvent event) {}

  void _handlePhoneticAnalysisJob(PhoneticAnalysisJobChangedEvent event) {
    if (event.trackId != currentPrimaryTrackId()) return;
    setTaskStatus(UserTaskStatus.audioAnalysis(event));
    if (event.status == 'completed' && event.trackId != null) {
      unawaited(loadSpeechEnhancements(event.trackId!));
    }
    setStatus('Audio analysis ${event.status} · ${event.phaseProgress}%');
  }
}
