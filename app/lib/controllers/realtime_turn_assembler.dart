import '../models/realtime_conversation.dart';

/// Provider-neutral, in-memory assembly of one ordered conversation timeline.
///
/// Local sequence owns identity and ordering. Provider item ids are retained
/// only as live-session correlation keys and may be absent.
class RealtimeTurnAssembler {
  final List<RealtimeConversationItem> _items = [];
  final Map<String, int> _providerItemSequences = {};
  int _nextSequence = 1;
  int? activeLearnerSequence;
  int? activeAssistantSequence;

  List<RealtimeConversationItem> get items => List.unmodifiable(_items);

  void reset() {
    _items.clear();
    _providerItemSequences.clear();
    _nextSequence = 1;
    activeLearnerSequence = null;
    activeAssistantSequence = null;
  }

  int? startLearner({required int startedAtMs, String? providerItemId}) {
    if (activeLearnerSequence != null) {
      correlate(activeLearnerSequence!, providerItemId);
      return null;
    }
    final sequence = _nextSequence++;
    activeLearnerSequence = sequence;
    _append(
      RealtimeConversationItem(
        sequence: sequence,
        role: 'learner',
        status: 'streaming',
        startedAtMs: startedAtMs,
        providerItemId: providerItemId,
      ),
    );
    correlate(sequence, providerItemId);
    return sequence;
  }

  int? closeLearnerCorrelation(String? providerItemId) {
    final sequence = activeLearnerSequence;
    if (sequence == null) return null;
    correlate(sequence, providerItemId);
    activeLearnerSequence = null;
    return sequence;
  }

  void correlateActiveLearner(String? providerItemId) {
    final sequence = activeLearnerSequence;
    if (sequence != null) correlate(sequence, providerItemId);
  }

  void updateLearnerProviderText(String? providerItemId, String text) {
    final sequence = _sequenceFor(
      providerItemId,
      role: 'learner',
      fallback: activeLearnerSequence,
    );
    if (sequence == null) return;
    correlate(sequence, providerItemId);
    replace(sequence, (item) => item.copyWith(providerText: text));
  }

  int updateAssistantText(
    String? providerItemId,
    String text, {
    required bool append,
    required int startedAtMs,
  }) {
    final correlated = providerItemId == null
        ? null
        : _providerItemSequences[providerItemId];
    if (correlated != null && _isTerminal(item(correlated).status)) {
      return correlated;
    }
    var sequence = _sequenceFor(
      providerItemId,
      role: 'assistant',
      fallback: activeAssistantSequence,
    );
    if (sequence == null) {
      sequence = _nextSequence++;
      activeAssistantSequence = sequence;
      _append(
        RealtimeConversationItem(
          sequence: sequence,
          role: 'assistant',
          status: 'streaming',
          startedAtMs: startedAtMs,
          providerItemId: providerItemId,
        ),
      );
    }
    correlate(sequence, providerItemId);
    replace(
      sequence,
      (item) =>
          item.copyWith(providerText: append ? item.providerText + text : text),
    );
    return sequence;
  }

  int? finalizeAssistant(String? providerItemId, String text, int endedAtMs) {
    final existing = _sequenceFor(
      providerItemId,
      role: 'assistant',
      fallback: activeAssistantSequence,
    );
    if (existing != null && _isTerminal(item(existing).status)) return null;
    final sequence = updateAssistantText(
      providerItemId,
      text,
      append: false,
      startedAtMs: endedAtMs,
    );
    replace(
      sequence,
      (item) => item.copyWith(status: 'finalized', endedAtMs: endedAtMs),
    );
    if (activeAssistantSequence == sequence) activeAssistantSequence = null;
    return sequence;
  }

  int? interruptAssistant(int endedAtMs) {
    final sequence = activeAssistantSequence;
    if (sequence == null) return null;
    final current = item(sequence);
    if (current.status != 'streaming') {
      activeAssistantSequence = null;
      return null;
    }
    replace(
      sequence,
      (item) => item.copyWith(status: 'interrupted', endedAtMs: endedAtMs),
    );
    activeAssistantSequence = null;
    return sequence;
  }

  void correlate(int sequence, String? providerItemId) {
    if (providerItemId == null) return;
    _providerItemSequences[providerItemId] = sequence;
    replace(sequence, (item) => item.copyWith(providerItemId: providerItemId));
  }

  void replace(
    int sequence,
    RealtimeConversationItem Function(RealtimeConversationItem) update,
  ) {
    final index = _items.indexWhere((item) => item.sequence == sequence);
    if (index < 0) return;
    _items[index] = update(_items[index]);
  }

  RealtimeConversationItem item(int sequence) =>
      _items.firstWhere((item) => item.sequence == sequence);

  int? _sequenceFor(
    String? providerItemId, {
    required String role,
    int? fallback,
  }) {
    final correlated = providerItemId == null
        ? null
        : _providerItemSequences[providerItemId];
    if (correlated != null && item(correlated).role == role) return correlated;
    if (fallback != null && item(fallback).role == role) return fallback;
    for (final item in _items.reversed) {
      if (item.role == role &&
          item.status != 'finalized' &&
          item.status != 'interrupted' &&
          item.status != 'failed') {
        return item.sequence;
      }
    }
    return null;
  }

  void _append(RealtimeConversationItem item) {
    _items.add(item);
    _items.sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  bool _isTerminal(String status) =>
      status == 'finalized' || status == 'interrupted' || status == 'failed';
}
