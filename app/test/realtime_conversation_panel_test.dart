import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/realtime_conversation.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

void main() {
  test('new realtime profiles use Qwen full-duplex as the baseline', () {
    expect(qwenRealtimeBaselineModel, 'qwen3.5-omni-plus-realtime');
  });

  test('OpenAI realtime remains available as a reference provider', () {
    expect(openAiRealtimeBaselineModel, 'gpt-realtime-2.1');
  });

  test('history title comes from conversation turns, not media topic', () {
    final session = _session().withTurns([
      const RealtimeConversationItem(
        sequence: 1,
        role: 'learner',
        status: 'finalized',
        startedAtMs: 1,
        localText: 'What should schools do in an emergency?',
      ),
    ]);

    expect(
      realtimeHistoryTitle(session),
      'What should schools do in an emergency?',
    );
    expect(realtimeHistoryTitle(session), isNot('Media subtitle snapshot'));
  });

  test('failed zero-turn sessions do not masquerade as conversations', () {
    expect(
      realtimeHistoryTitle(_session().withTurns(const [])),
      'No conversation captured',
    );
  });
}

RealtimeConversationSessionView _session() =>
    const RealtimeConversationSessionView(
      id: 'session-1',
      profileId: 'profile-1',
      language: 'en',
      surfaceKind: 'topic_anchored',
      status: 'failed',
      startedAtMs: 1,
      topic: 'Media subtitle snapshot',
    );
