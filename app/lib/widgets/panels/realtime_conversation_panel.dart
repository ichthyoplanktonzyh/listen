import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../localization.dart';
import '../../models/realtime_conversation.dart';
import '../../services/api_service.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/listen_loading.dart';

String realtimeHistoryTitle(RealtimeConversationSessionView session) {
  final preview = session.conversationPreview?.trim();
  if (preview?.isNotEmpty == true) return preview!;
  if (session.turnCount == 0) return 'No conversation captured';
  return session.surfaceKind == 'open_chat'
      ? 'Free conversation'
      : 'Topic conversation';
}

class RealtimeConversationPanel extends StatefulWidget {
  const RealtimeConversationPanel({
    super.key,
    required this.controller,
    required this.api,
    required this.launch,
    required this.acquireAudioFocus,
    required this.onClose,
    this.onManageVoices,
  });
  final RealtimeConversationController controller;
  final LocalApi api;
  final RealtimeConversationLaunch launch;
  final Future<void> Function() acquireAudioFocus;
  final VoidCallback onClose;

  /// Opens the settings domain where realtime voices are configured (#87).
  /// The lobby only *chooses* a voice; when none exists the learner still
  /// needs a way out of the dead end, and this route covers the app bar.
  /// Null keeps the panel usable in tests and in hosts without settings.
  final Future<void> Function()? onManageVoices;

  @override
  State<RealtimeConversationPanel> createState() =>
      _RealtimeConversationPanelState();
}

class _RealtimeConversationPanelState extends State<RealtimeConversationPanel> {
  final ScrollController _scrollController = ScrollController();
  int _timelineSignature = 0;
  bool _closePromptOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_followLiveTimeline);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadProfiles(widget.api);
      widget.controller.loadHistory(widget.api);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_followLiveTimeline);
    _scrollController.dispose();
    super.dispose();
  }

  void _followLiveTimeline() {
    final state = widget.controller.state;
    final signature = Object.hashAll([
      for (final item in state.items)
        Object.hash(item.sequence, item.status, item.displayText),
    ]);
    if (signature == _timelineSignature) return;
    _timelineSignature = signature;
    final shouldFollow =
        !_scrollController.hasClients ||
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 120;
    if (!shouldFollow || state.phase != RealtimeConversationPhase.live) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final canClose = state.canConfigure;
      return PopScope(
        canPop: canClose,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && state.canCancel) _requestClose();
        },
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              ListTile(
                leading: IconButton(
                  onPressed: canClose || state.canCancel ? _requestClose : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: const Text('Realtime speech conversation'),
                subtitle: const Text(
                  'Provider captions are live guidance. Only the local Whisper transcript becomes learner output.',
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.launch.mode == RealtimeConversationMode.free
                              ? 'Free conversation'
                              : 'Selected topic',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: ListenSpacing.gap6),
                        Text(
                          widget.launch.anchor?.text ??
                              'Start without sending media or subtitle context.',
                        ),
                        const SizedBox(height: ListenSpacing.gap16),
                        _LobbyVoiceChoice(
                          profiles: state.profiles,
                          selectedProfileId: state.selectedProfileId,
                          enabled: state.canConfigure,
                          onSelected: widget.controller.selectProfile,
                          onManageVoices: widget.onManageVoices == null
                              ? null
                              : _manageVoices,
                        ),
                        const SizedBox(height: ListenSpacing.gap24),
                        if (state.phase == RealtimeConversationPhase.live) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Chip(
                              key: const ValueKey('realtime-activity'),
                              avatar: Icon(
                                _activityIcon(state.activity),
                                size: 18,
                              ),
                              label: Text(_activityLabel(state.activity)),
                            ),
                          ),
                          const SizedBox(height: ListenSpacing.gap12),
                        ],
                        if (state.error != null)
                          _notice(context, state.error!, true),
                        if (state.items.isEmpty &&
                            state.phase == RealtimeConversationPhase.live)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'Listening… Start speaking when ready.',
                            ),
                          ),
                        for (final item in state.items) ...[
                          _ConversationTurnCard(item: item),
                          const SizedBox(height: ListenSpacing.gap12),
                        ],
                        if (state.postProcessingCount > 0)
                          Text(
                            '${state.postProcessingCount} learner turn(s) are being transcribed locally.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (state.postProcessingCount > 0)
                          const SizedBox(height: ListenSpacing.gap16),
                        Wrap(
                          spacing: 12,
                          children: [
                            if (state.canConfigure)
                              FilledButton.icon(
                                key: const ValueKey('realtime-start'),
                                onPressed: state.selectedProfileId == null
                                    ? null
                                    : () => widget.controller.start(
                                        widget.api,
                                        widget.launch,
                                        acquireAudioFocus:
                                            widget.acquireAudioFocus,
                                      ),
                                icon: const Icon(Icons.mic),
                                label: const Text('Start conversation'),
                              ),
                            if (state.phase == RealtimeConversationPhase.live)
                              FilledButton.icon(
                                key: const ValueKey('realtime-finish'),
                                onPressed: widget.controller.finish,
                                icon: const Icon(Icons.stop),
                                label: const Text(
                                  'Finish and transcribe locally',
                                ),
                              ),
                            if (state.canCancel)
                              TextButton(
                                key: const ValueKey('realtime-cancel'),
                                onPressed: _cancelAndClose,
                                child: const Text('Cancel and discard'),
                              ),
                            if (state.isWorking)
                              const Padding(
                                padding: EdgeInsets.all(8),
                                child: ListenLoading(),
                              ),
                          ],
                        ),
                        if (state.canConfigure) ...[
                          const SizedBox(height: ListenSpacing.gap32),
                          const Divider(),
                          const SizedBox(height: ListenSpacing.gap12),
                          Text(
                            'Conversation history',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: ListenSpacing.gap8),
                          if (state.historyError != null)
                            _notice(context, state.historyError!, true),
                          if (state.historyLoading)
                            const LinearProgressIndicator(),
                          if (!state.historyLoading &&
                              state.historySessions.isEmpty)
                            const Text(
                              'Completed conversations will appear here.',
                            ),
                          if (state.selectedHistorySessionId != null) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed:
                                    widget.controller.closeHistorySession,
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('All conversations'),
                              ),
                            ),
                            for (final item in state.historyItems) ...[
                              _ConversationTurnCard(item: item),
                              const SizedBox(height: ListenSpacing.gap12),
                            ],
                          ] else
                            for (final session in state.historySessions)
                              _HistorySessionTile(
                                session: session,
                                onTap: () => widget.controller
                                    .openHistorySession(widget.api, session.id),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _requestClose() async {
    final state = widget.controller.state;
    if (state.canConfigure) {
      widget.onClose();
      return;
    }
    if (!state.canCancel || _closePromptOpen) return;
    _closePromptOpen = true;
    bool? discard;
    try {
      discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this conversation?'),
          content: const Text(
            'The active conversation and unfinished local transcription will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep talking'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard and close'),
            ),
          ],
        ),
      );
    } finally {
      _closePromptOpen = false;
    }
    if (discard == true) await _cancelAndClose();
  }

  Future<void> _cancelAndClose() async {
    await widget.controller.cancel();
    if (mounted) widget.onClose();
  }

  String _activityLabel(RealtimeConversationActivity activity) =>
      switch (activity) {
        RealtimeConversationActivity.learnerSpeaking => 'You are speaking',
        RealtimeConversationActivity.thinking => 'Thinking',
        RealtimeConversationActivity.assistantSpeaking =>
          'Assistant is speaking',
        RealtimeConversationActivity.listening => 'Listening',
        RealtimeConversationActivity.inactive => 'Preparing',
      };

  IconData _activityIcon(RealtimeConversationActivity activity) =>
      switch (activity) {
        RealtimeConversationActivity.learnerSpeaking => Icons.mic,
        RealtimeConversationActivity.thinking => Icons.more_horiz,
        RealtimeConversationActivity.assistantSpeaking => Icons.volume_up,
        RealtimeConversationActivity.listening => Icons.hearing,
        RealtimeConversationActivity.inactive => Icons.hourglass_top,
      };

  Widget _notice(BuildContext context, String text, bool error) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: ListenRadii.controlBorder,
    ),
    child: Text(text),
  );

  /// Hands off to the settings domain and re-reads the voices on return, so a
  /// voice added there is selectable without leaving the conversation.
  Future<void> _manageVoices() async {
    await widget.onManageVoices!();
    if (!mounted) return;
    await widget.controller.loadProfiles(widget.api);
  }
}

/// The lobby's entire provider surface (#87 / S10): pick which voice speaks
/// with you. Everything else (endpoint, workspace, region, API key) lives in
/// Settings › Realtime voice.
///
/// Kept as its own widget so S6 can lift the lobby into the stage shell
/// without re-deriving this control from the panel's build method.
class _LobbyVoiceChoice extends StatelessWidget {
  const _LobbyVoiceChoice({
    required this.profiles,
    required this.selectedProfileId,
    required this.enabled,
    required this.onSelected,
    required this.onManageVoices,
  });

  final List<RealtimeProviderProfileView> profiles;
  final String? selectedProfileId;
  final bool enabled;
  final ValueChanged<String> onSelected;
  final Future<void> Function()? onManageVoices;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (profiles.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.text('realtimeNoVoiceInLobby')),
          if (onManageVoices != null) ...[
            const SizedBox(height: ListenSpacing.gap8),
            OutlinedButton.icon(
              key: const ValueKey('realtime-manage-voices'),
              onPressed: () => unawaited(onManageVoices!()),
              icon: const Icon(Icons.settings_outlined),
              label: Text(l.text('realtimeManageVoices')),
            ),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('realtime-voice-choice'),
            initialValue: selectedProfileId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l.text('realtimeChooseVoice'),
              border: const OutlineInputBorder(),
            ),
            items: profiles
                .map(
                  (profile) => DropdownMenuItem(
                    value: profile.id,
                    child: Text(
                      '${profile.displayName} · ${profile.voice}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: enabled
                ? (value) {
                    if (value != null) onSelected(value);
                  }
                : null,
          ),
        ),
        if (onManageVoices != null) ...[
          const SizedBox(width: ListenSpacing.gap12),
          TextButton.icon(
            key: const ValueKey('realtime-manage-voices'),
            onPressed: () => unawaited(onManageVoices!()),
            icon: const Icon(Icons.settings_outlined),
            label: Text(l.text('realtimeManageVoices')),
          ),
        ],
      ],
    );
  }
}


class _HistorySessionTile extends StatelessWidget {
  const _HistorySessionTile({required this.session, required this.onTap});

  final RealtimeConversationSessionView session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final started = DateTime.fromMillisecondsSinceEpoch(
      session.startedAtMs,
    ).toLocal();
    final minute = started.minute.toString().padLeft(2, '0');
    final title = realtimeHistoryTitle(session);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        session.surfaceKind == 'open_chat'
            ? Icons.forum_outlined
            : Icons.topic_outlined,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${started.year}-${started.month.toString().padLeft(2, '0')}-'
        '${started.day.toString().padLeft(2, '0')} '
        '${started.hour.toString().padLeft(2, '0')}:$minute'
        ' · ${session.status}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ConversationTurnCard extends StatelessWidget {
  const _ConversationTurnCard({required this.item});

  final RealtimeConversationItem item;

  @override
  Widget build(BuildContext context) {
    final learner = item.role == 'learner';
    final colorScheme = Theme.of(context).colorScheme;
    final text = item.displayText.isEmpty
        ? (learner ? 'Listening…' : 'Responding…')
        : item.displayText;
    return Align(
      alignment: learner ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: learner
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: ListenRadii.panelBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  learner ? 'You' : 'Assistant',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: ListenSpacing.gap4),
                SelectableText(text),
                const SizedBox(height: ListenSpacing.gap6),
                Text(
                  learner
                      ? switch (item.status) {
                          'finalized' =>
                            'Local Whisper transcript · learner output',
                          'failed' => 'Local transcription unavailable',
                          'local_transcription_pending' =>
                            'Transcribing locally…',
                          _ => 'Live provider caption · guidance only',
                        }
                      : switch (item.status) {
                          'finalized' => 'Assistant response',
                          'failed' => 'Assistant history could not be saved',
                          _ => 'Assistant responding…',
                        },
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (item.error != null) ...[
                  const SizedBox(height: ListenSpacing.gap4),
                  Text(item.error!, style: TextStyle(color: colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
