import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_turn_assembler.dart';

void main() {
  test('uses local sequence while provider ids remain correlation only', () {
    final turns = RealtimeTurnAssembler();

    final learner = turns.startLearner(startedAtMs: 10, providerItemId: null);
    turns.correlateActiveLearner('provider-user');
    turns.updateLearnerProviderText('provider-user', 'provider caption');
    turns.closeLearnerCorrelation('provider-user');
    final assistant = turns.finalizeAssistant(
      'provider-assistant',
      'final arrived without a delta',
      20,
    );

    expect(learner, 1);
    expect(assistant, 2);
    expect(turns.items.map((item) => item.sequence), [1, 2]);
    expect(turns.items.first.providerItemId, 'provider-user');
    expect(turns.items.last.status, 'finalized');
  });

  test('deduplicates terminal events and closes interrupted assistant', () {
    final turns = RealtimeTurnAssembler();
    turns.updateAssistantText(
      'provider-assistant',
      'partial',
      append: true,
      startedAtMs: 10,
    );

    final interrupted = turns.interruptAssistant(20);
    final duplicate = turns.interruptAssistant(21);
    final lateFinal = turns.finalizeAssistant(
      'provider-assistant',
      'late provider final',
      22,
    );

    expect(interrupted, 1);
    expect(duplicate, isNull);
    expect(lateFinal, isNull);
    expect(turns.items.single.status, 'interrupted');
    expect(turns.items.single.providerText, 'partial');
  });
}
