import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/backend_event.dart';
import 'package:llplayer_next/models/task_status.dart';

void main() {
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
