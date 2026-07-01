import 'backend_event.dart';

enum UserTaskKind { subtitleGeneration, audioAnalysis }

enum UserTaskState { working, success, warning, error, cancelled, unknown }

class UserTaskStatus {
  const UserTaskStatus({
    required this.kind,
    required this.state,
    required this.rawStatus,
    required this.progress,
    this.targetId,
  });

  factory UserTaskStatus.transcription(TranscriptionJobChangedEvent event) =>
      UserTaskStatus(
        kind: UserTaskKind.subtitleGeneration,
        state: _stateFromRawStatus(event.status),
        rawStatus: event.status,
        progress: event.phaseProgress,
        targetId: event.mediaId,
      );

  factory UserTaskStatus.audioAnalysis(PhoneticAnalysisJobChangedEvent event) =>
      UserTaskStatus(
        kind: UserTaskKind.audioAnalysis,
        state: _stateFromRawStatus(event.status),
        rawStatus: event.status,
        progress: event.phaseProgress,
        targetId: event.trackId,
      );

  final UserTaskKind kind;
  final UserTaskState state;
  final String rawStatus;
  final int progress;
  final String? targetId;

  bool get active => state == UserTaskState.working;

  String get titleKey => switch (kind) {
    UserTaskKind.subtitleGeneration => 'taskSubtitleGeneration',
    UserTaskKind.audioAnalysis => 'taskAudioAnalysis',
  };

  String get stateKey => switch (state) {
    UserTaskState.working => 'taskStateWorking',
    UserTaskState.success => 'taskStateSuccess',
    UserTaskState.warning => 'taskStateWarning',
    UserTaskState.error => 'taskStateError',
    UserTaskState.cancelled => 'taskStateCancelled',
    UserTaskState.unknown => 'taskStateUnknown',
  };
}

UserTaskState _stateFromRawStatus(String status) {
  final value = status.toLowerCase();
  return switch (value) {
    'completed' ||
    'complete' ||
    'succeeded' ||
    'success' => UserTaskState.success,
    'failed' || 'error' => UserTaskState.error,
    'cancelled' || 'canceled' => UserTaskState.cancelled,
    'interrupted' => UserTaskState.warning,
    'queued' ||
    'pending' ||
    'running' ||
    'extracting' ||
    'recognizing' ||
    'recognizing_phones' ||
    'aligning' ||
    'analyzing' => UserTaskState.working,
    _ => UserTaskState.unknown,
  };
}
