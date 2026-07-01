import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/backend_event.dart';
import 'package:llplayer_next/models/task_status.dart';

void main() {
  test('transcription task maps backend progress to user status', () {
    final task = UserTaskStatus.transcription(
      const TranscriptionJobChangedEvent(
        status: 'running',
        phaseProgress: 42,
        mediaId: 'media-1',
      ),
    );

    expect(task.kind, UserTaskKind.subtitleGeneration);
    expect(task.state, UserTaskState.working);
    expect(task.progress, 42);
    expect(task.targetId, 'media-1');
  });

  test('audio analysis terminal states map to user task categories', () {
    final completed = UserTaskStatus.audioAnalysis(
      const PhoneticAnalysisJobChangedEvent(
        status: 'completed',
        phaseProgress: 100,
        trackId: 'track-1',
      ),
    );
    final failed = UserTaskStatus.audioAnalysis(
      const PhoneticAnalysisJobChangedEvent(
        status: 'failed',
        phaseProgress: 37,
        trackId: 'track-1',
      ),
    );
    final interrupted = UserTaskStatus.audioAnalysis(
      const PhoneticAnalysisJobChangedEvent(
        status: 'interrupted',
        phaseProgress: 66,
        trackId: 'track-1',
      ),
    );

    expect(completed.state, UserTaskState.success);
    expect(failed.state, UserTaskState.error);
    expect(interrupted.state, UserTaskState.warning);
  });
}
