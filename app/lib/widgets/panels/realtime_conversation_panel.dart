import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../localization.dart';
import '../../models/realtime_conversation.dart';
import '../../services/api_service.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/capability_viz.dart';
import '../common/listen_loading.dart';
import 'conversation_afterglow_caption.dart';
import 'conversation_stage_shell.dart';

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
    this.captionEnabled = false,
    this.onCaptionEnabledChanged,
  });
  final RealtimeConversationController controller;
  final LocalApi api;
  final RealtimeConversationLaunch launch;
  final Future<void> Function() acquireAudioFocus;
  final VoidCallback onClose;

  /// The remembered state of the lobby's caption switch (#85 · S8). Defaults
  /// to off — the owner-decided default; the host passes the persisted value.
  final bool captionEnabled;

  /// Persists a change to that switch. Null keeps the panel usable in tests
  /// and in hosts without settings: the switch still works for the session,
  /// it just is not remembered.
  final ValueChanged<bool>? onCaptionEnabledChanged;

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
  bool _closePromptOpen = false;

  /// Live copy of the lobby's caption switch, seeded from the remembered
  /// value so the panel keeps working when no host persists it.
  late bool _captionEnabled = widget.captionEnabled;

  /// The debrief is a room the learner leaves, not a phase the backend
  /// reports: once dismissed the shell falls back to the lobby without
  /// touching controller state. S9 (#86) owns what the room contains.
  bool _debriefDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadProfiles(widget.api);
      widget.controller.loadHistory(widget.api);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final segment = conversationStageSegmentOf(
        state,
        debriefDismissed: _debriefDismissed,
      );
      return PopScope(
        canPop: state.canConfigure,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && state.canCancel) _requestClose();
        },
        child: ConversationStageShell(
          segment: segment,
          child: switch (segment) {
            ConversationStageSegment.lobby => _lobby(context, state),
            ConversationStageSegment.stage => _stage(context, state),
            ConversationStageSegment.debrief => _debrief(context, state),
          },
        ),
      );
    },
  );

  /// 门厅: what the conversation will be about and who speaks with you —
  /// the only decision left before the lights go down (#87 moved provider
  /// configuration to settings).
  Widget _lobby(
    BuildContext context,
    RealtimeConversationState state,
  ) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(ListenSpacing.gap12),
          child: IconButton(
            key: const ValueKey('realtime-close'),
            tooltip: 'Leave conversation',
            onPressed: _requestClose,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
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
                    const SizedBox(height: ListenSpacing.gap12),
                    // 字幕默认关 (#85 · S8): the switch is here, in the lobby,
                    // and the choice is remembered. It only ever governs the
                    // other person's line — the learner's own words are not
                    // on the stage to switch on.
                    SwitchListTile.adaptive(
                      key: const ValueKey('realtime-caption-toggle'),
                      contentPadding: EdgeInsets.zero,
                      value: _captionEnabled,
                      onChanged: _setCaptionEnabled,
                      title: const Text('Show what the other person says'),
                      subtitle: const Text(
                        'One dim line on stage, gone a few seconds after they '
                        'finish. Off by default — listen first.',
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap8),
                    // Honest layering, stated before the lights go down:
                    // the provider's live captions never become learner
                    // output — only the local Whisper transcript does.
                    Text(
                      'Provider captions are live guidance. Your own words '
                      'never appear on stage: only the local Whisper '
                      'transcript becomes learner output, in the summary '
                      'afterwards.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap24),
                    if (state.error != null)
                      _notice(context, state.error!, true),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey('realtime-start'),
                        onPressed: state.selectedProfileId == null
                            ? null
                            : _startConversation,
                        icon: const Icon(Icons.mic),
                        label: const Text('Start conversation'),
                      ),
                    ),
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
                    if (state.historyLoading) const LinearProgressIndicator(),
                    if (!state.historyLoading && state.historySessions.isEmpty)
                      const Text('Completed conversations will appear here.'),
                    if (state.selectedHistorySessionId != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.controller.closeHistorySession,
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
                          onTap: () => widget.controller.openHistorySession(
                            widget.api,
                            session.id,
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// 舞台: the room with the lights off. There is no transcript here —
  /// 「你的话 live 中不上屏」 — and at most one line of 余音字幕 for the other
  /// person, only if the lobby switch is on. The shape in the middle is
  /// replaced by S7's 回声水面 (#84).
  Widget _stage(BuildContext context, RealtimeConversationState state) =>
      ConversationStageLayout(
        caption: _captionEnabled
            ? ConversationAfterglowCaption(
                line: conversationAfterglowLineOf(state),
              )
            : null,
        exitAffordance: IconButton(
          key: const ValueKey('realtime-close'),
          tooltip: 'Leave conversation',
          onPressed: _requestClose,
          icon: const Icon(Icons.close),
        ),
        visualization: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConversationEchoSurface(
              key: const ValueKey('conversation-echo-surface'),
              levels: conversationEchoLevelsOf(state.activity),
            ),
            const SizedBox(height: ListenSpacing.gap16),
            // The surface carries the state; this line stays as the screen
            // reader's and the label-reader's version of the same thing —
            // never the only place the state exists (D2).
            Text(
              key: const ValueKey('realtime-activity'),
              _activityLabel(state.activity),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            // D5: while the other voice is speaking, say out loud that cutting
            // in is allowed. The surface already shows your open channel; this
            // names it once, dimly, and disappears the moment it is your turn.
            if (state.activity ==
                RealtimeConversationActivity.assistantSpeaking) ...[
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                key: const ValueKey('realtime-interrupt-hint'),
                'Just speak to cut in',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: ListenSpacing.gap16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _notice(context, state.error!, true),
              ),
            ],
          ],
        ),
        controls: Wrap(
          alignment: WrapAlignment.center,
          spacing: ListenSpacing.gap12,
          runSpacing: ListenSpacing.gap8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (state.phase == RealtimeConversationPhase.live)
              FilledButton.icon(
                key: const ValueKey('realtime-finish'),
                onPressed: widget.controller.finish,
                icon: const Icon(Icons.stop),
                label: const Text('Finish and transcribe locally'),
              ),
            if (state.canCancel)
              TextButton(
                key: const ValueKey('realtime-cancel'),
                onPressed: _cancelAndClose,
                child: const Text('Cancel and discard'),
              ),
            if (state.isWorking) const ListenLoading(),
          ],
        ),
      );

  /// 结束页: the stage dims and the conversation becomes readable. S9 (#86)
  /// replaces this body with the three-part 回流; S6 only guarantees the room
  /// exists, is reachable, and can be left.
  Widget _debrief(BuildContext context, RealtimeConversationState state) =>
      SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(ListenSpacing.gap12),
              child: TextButton.icon(
                key: const ValueKey('realtime-debrief-back'),
                onPressed: () => setState(() => _debriefDismissed = true),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to conversations'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.error != null)
                          _notice(context, state.error!, true),
                        for (final item in state.items) ...[
                          _ConversationTurnCard(item: item),
                          const SizedBox(height: ListenSpacing.gap12),
                        ],
                        if (state.postProcessingCount > 0)
                          Text(
                            '${state.postProcessingCount} learner turn(s) are '
                            'being transcribed locally.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  void _setCaptionEnabled(bool value) {
    setState(() => _captionEnabled = value);
    widget.onCaptionEnabledChanged?.call(value);
  }

  void _startConversation() {
    setState(() => _debriefDismissed = false);
    widget.controller.start(
      widget.api,
      widget.launch,
      acquireAudioFocus: widget.acquireAudioFocus,
    );
  }

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
