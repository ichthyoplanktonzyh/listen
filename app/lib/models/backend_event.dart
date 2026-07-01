import 'types.dart';

class BackendEvent {
  const BackendEvent();

  factory BackendEvent.fromJson(Map<String, dynamic> json) {
    final name = json['event'];
    final payload = json['payload'];
    return switch (name) {
      'service-started' => const ServiceStartedEvent(),
      'transcription-job-changed' when payload is Map<String, dynamic> =>
        TranscriptionJobChangedEvent.fromJson(payload),
      'word-timings-completed' when payload is Map<String, dynamic> =>
        WordTimingsCompletedEvent.fromJson(payload),
      'sound-line-completed' when payload is Map<String, dynamic> =>
        SoundLineCompletedEvent.fromJson(payload),
      'phonetic-analysis-job-changed' when payload is Map<String, dynamic> =>
        PhoneticAnalysisJobChangedEvent.fromJson(payload),
      'lexical-entry-changed' when payload is Map<String, dynamic> =>
        LexicalEntryChangedEvent.fromJson(payload),
      _ => UnknownBackendEvent(
        name: name is String ? name : 'unknown',
        payload: payload,
      ),
    };
  }
}

class ServiceStartedEvent extends BackendEvent {
  const ServiceStartedEvent();
}

class UnknownBackendEvent extends BackendEvent {
  const UnknownBackendEvent({required this.name, this.payload});

  final String name;
  final Object? payload;
}

class WordTimingsCompletedEvent extends BackendEvent {
  const WordTimingsCompletedEvent({
    required this.trackId,
    required this.count,
    this.line,
    this.timelineId,
  });

  factory WordTimingsCompletedEvent.fromJson(Map<String, dynamic> json) =>
      WordTimingsCompletedEvent(
        trackId: json['track_id'] as String? ?? '',
        count: json['count'] as int? ?? 0,
        line: json['line'] as String?,
        timelineId: json['timeline_id'] as String?,
      );

  final String trackId;
  final int count;
  final String? line;
  final String? timelineId;
}

/// Emitted when the independent sound-line workflow finishes enriching a track
/// with listening-structure (pause/acoustic) resources. Distinct from the
/// text-line `word-timings-completed` so the two workflows never conflate.
class SoundLineCompletedEvent extends BackendEvent {
  const SoundLineCompletedEvent({
    required this.trackId,
    this.timelineId,
    this.acousticCueCount = 0,
  });

  factory SoundLineCompletedEvent.fromJson(Map<String, dynamic> json) =>
      SoundLineCompletedEvent(
        trackId: json['track_id'] as String? ?? '',
        timelineId: json['timeline_id'] as String?,
        acousticCueCount: json['acoustic_cue_count'] as int? ?? 0,
      );

  final String trackId;
  final String? timelineId;
  final int acousticCueCount;
}

class TranscriptionJobChangedEvent extends BackendEvent {
  const TranscriptionJobChangedEvent({
    required this.status,
    required this.phaseProgress,
    this.mediaId,
    this.generatedTrackId,
    this.destination,
    this.archivedAtMs,
  });

  factory TranscriptionJobChangedEvent.fromJson(Map<String, dynamic> json) =>
      TranscriptionJobChangedEvent(
        status: json['status'] as String? ?? 'unknown',
        phaseProgress: json['phase_progress'] as int? ?? 0,
        mediaId: json['media_id'] as String?,
        generatedTrackId: json['generated_track_id'] as String?,
        destination: json['destination'] as String?,
        archivedAtMs: json['archived_at_ms'] as int?,
      );

  final String status;
  final int phaseProgress;
  final String? mediaId;
  final String? generatedTrackId;
  final String? destination;
  final int? archivedAtMs;
}

class PhoneticAnalysisJobChangedEvent extends BackendEvent {
  const PhoneticAnalysisJobChangedEvent({
    required this.status,
    required this.phaseProgress,
    this.trackId,
  });

  factory PhoneticAnalysisJobChangedEvent.fromJson(Map<String, dynamic> json) =>
      PhoneticAnalysisJobChangedEvent(
        status: json['status'] as String? ?? 'unknown',
        phaseProgress: json['phase_progress'] as int? ?? 0,
        trackId: json['track_id'] as String?,
      );

  final String status;
  final int phaseProgress;
  final String? trackId;
}

class LexicalEntryChangedEvent extends BackendEvent {
  const LexicalEntryChangedEvent({required this.details});

  factory LexicalEntryChangedEvent.fromJson(Map<String, dynamic> json) =>
      LexicalEntryChangedEvent(details: LexicalEntryDetails.fromJson(json));

  final LexicalEntryDetails details;

  LexicalEntry get entry => details.entry;

  String get normalizedForm => entry.normalizedForm;
}
