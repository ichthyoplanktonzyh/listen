import 'package:flutter/foundation.dart';

import '../models/content_channel.dart';
import '../services/api_service.dart';
import 'reading_channel_coordinator.dart';
import 'speaking_actions_coordinator.dart';
import 'speaking_channel_coordinator.dart';
import 'writing_channel_coordinator.dart';

/// The single place that knows a learner can only be in one content channel at
/// a time. It reads the current channel off the three channel coordinators and
/// owns the teardown order when switching between them — logic that used to be
/// repeated in every branch of the composition root's `_selectContentChannel`.
///
/// Deliberately not a [ChangeNotifier]: it holds no state of its own.
/// [selected] is derived, and the coordinators it reads already notify.
class ContentChannelCoordinator {
  ContentChannelCoordinator({
    required this.reading,
    required this.speaking,
    required this.speakingActions,
    required this.writing,
  });

  final ReadingChannelCoordinator reading;
  final SpeakingChannelCoordinator speaking;
  final SpeakingActionsCoordinator speakingActions;
  final WritingChannelCoordinator writing;

  LocalApi? Function()? _getApi;
  bool Function()? _speakingAvailable;
  Future<void> Function(LocalApi api)? _openSpeaking;
  Future<void> Function()? _openWriting;

  /// Host seams. The two opens stay with the composition root because they
  /// need localized rubric templates; [speakingAvailable] keeps the platform
  /// gate out of this class.
  void bind({
    required LocalApi? Function() getApi,
    required bool Function() speakingAvailable,
    required Future<void> Function(LocalApi api) openSpeaking,
    required Future<void> Function() openWriting,
  }) {
    _getApi = getApi;
    _speakingAvailable = speakingAvailable;
    _openSpeaking = openSpeaking;
    _openWriting = openWriting;
  }

  /// Everything that can change [selected], as one handle. The composition
  /// root listens to this instead of the three channel coordinators, and does
  /// not see their internal page-state churn at all.
  late final Listenable selection = Listenable.merge([
    reading.openChanges,
    speakingActions,
    writing,
  ]);

  /// Precedence, not history: whichever channel currently owns the immersive
  /// stage. Listening is the resting state with nothing open on top.
  ContentChannel get selected => writing.isOpen
      ? ContentChannel.writing
      : speakingActions.isOpen
      ? ContentChannel.speaking
      : reading.isOpen
      ? ContentChannel.reading
      : ContentChannel.listening;

  /// Enters [channel], tearing down whatever the learner was in first.
  /// Re-selecting the current channel is meaningful for writing (it re-opens
  /// on the segment under the playhead), so this is not short-circuited.
  Future<void> select(ContentChannel channel) async {
    // Writing survives only a re-selection of itself; `openTask` handles its
    // own re-entry.
    if (channel != ContentChannel.writing && writing.isOpen) {
      await writing.close();
    }
    switch (channel) {
      case ContentChannel.listening:
        await _closeSpeaking();
        await reading.close();
      case ContentChannel.reading:
        await _closeSpeaking();
        await reading.open();
      case ContentChannel.speaking:
        final service = _getApi?.call();
        if (service == null || !(_speakingAvailable?.call() ?? false)) return;
        await _openSpeaking?.call(service);
      case ContentChannel.writing:
        await _openWriting?.call();
    }
  }

  Future<void> _closeSpeaking() async {
    speaking.closeL1Check();
    if (speakingActions.isOpen) await speakingActions.close(_getApi?.call());
  }
}
