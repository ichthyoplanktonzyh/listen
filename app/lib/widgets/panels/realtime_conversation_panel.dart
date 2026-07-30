import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../localization.dart';
import '../../models/realtime_conversation.dart';
import '../../services/api_service.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/capability_viz.dart';
import '../common/listen_loading.dart';
import 'conversation_afterglow_caption.dart';
import 'conversation_debrief.dart';
import 'conversation_stage_shell.dart';
import 'conversation_turn_failure.dart';

/// How a past conversation names itself in the history list.
///
/// **When, how long, how many turns** — never the first thing that was said.
/// The list used to title each row with the session's opening utterance, which
/// in practice meant five of six rows read `Hello`: a title that carries no
/// distinguishing information at all. What a learner actually looks for is the
/// session they remember having, and they remember it by when it happened and
/// how long it ran (the shape Granola and Fathom's meeting lists settled on).
///
/// Everything in the line is a fact the session already carries. A session with
/// no end timestamp contributes no duration rather than a guessed one, and a
/// session whose turns could not be counted contributes no turn count. Status
/// is described, never printed: `completed` is the normal case and gets no
/// label at all, because a normal state does not need a badge.
String realtimeHistoryTitle(
  RealtimeConversationSessionView session,
  AppLocalizations l,
) {
  final started = DateTime.fromMillisecondsSinceEpoch(
    session.startedAtMs,
  ).toLocal();
  final when = l
      .text('realtimeHistoryWhen')
      .replaceAll('{month}', '${started.month}')
      .replaceAll('{day}', '${started.day}')
      .replaceAll(
        '{time}',
        '${started.hour.toString().padLeft(2, '0')}:'
            '${started.minute.toString().padLeft(2, '0')}',
      );
  final parts = <String>[when];
  if (session.turnCount == 0) {
    // Nothing was captured: duration and turn count would both be noise, and
    // the reason the row is empty is the only useful thing to say.
    parts.add(l.text('realtimeHistoryNothingCaptured'));
    return parts.join(' · ');
  }
  final duration = session.duration;
  if (duration != null) {
    parts.add(
      duration.inMinutes < 1
          ? l.text('realtimeHistoryUnderAMinute')
          : l
                .text('realtimeHistoryMinutes')
                .replaceAll('{count}', '${duration.inMinutes}'),
    );
  }
  final turnCount = session.turnCount;
  if (turnCount != null) {
    parts.add(
      l.text('realtimeHistoryTurns').replaceAll('{count}', '$turnCount'),
    );
  }
  final status = realtimeHistoryStatusText(session.status, l);
  if (status != null) parts.add(status);
  return parts.join(' · ');
}

/// The descriptive form of a session's status, or null when there is nothing
/// to say.
///
/// `completed` is the normal outcome and returns null: a label on the normal
/// state is decoration, and it would make the abnormal ones harder to spot. An
/// unrecognised status also returns null rather than leaking the raw enum —
/// `completed` / `failed` on screen is exactly the debug output the charter
/// rules out.
String? realtimeHistoryStatusText(String status, AppLocalizations l) =>
    switch (status) {
      'completed' => null,
      'failed' => l.text('realtimeHistoryEndedWithError'),
      'interrupted' => l.text('realtimeHistoryLeftPartway'),
      'active' => l.text('realtimeHistoryNeverFinished'),
      _ => null,
    };

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
    this.onOpenVocabulary,
    this.onSaveExpression,
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

  /// 词汇本 — where the words this conversation handed to the speaking channel
  /// now live (#86 · S9). The debrief's 回流 section links there so the
  /// read-out is a door, not a claim. Null keeps the panel usable in tests and
  /// in hosts without the learning routes.
  final Future<void> Function()? onOpenVocabulary;

  /// 我的表达 — opens the "save an expression" flow prefilled with [text].
  /// Used by the debrief's amber targets, whose turns never became learner
  /// output: what gets saved is the learner writing something down, not the
  /// portrait gaining evidence.
  final Future<void> Function(String text)? onSaveExpression;

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

  /// The lobby shows the last few conversations and nothing more, until the
  /// learner asks for the rest. The history used to occupy roughly 60% of the
  /// first screen, which put the past above the thing the page is for.
  bool _historyExpanded = false;

  /// How many past conversations the lobby shows before folding the rest
  /// behind 「全部对话」.
  static const _lobbyHistoryPreviewCount = 5;

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
          // The room is built from the shell's own context, not this one.
          // These three builders read `Theme.of` for their ink, and the outer
          // context is the *app* theme — under the light theme that put the
          // lobby's heading at `#1d2623` on the stage's `#141d1a` ground,
          // invisible. The shell's context is the only one where the dark
          // scheme is guaranteed.
          builder: (context) => switch (segment) {
            ConversationStageSegment.lobby => _lobby(context, state),
            ConversationStageSegment.stage => _stage(context, state),
            ConversationStageSegment.debrief => _debrief(context, state),
          },
        ),
      );
    },
  );

  /// 门厅: one job — get the learner talking within two seconds.
  ///
  /// What used to be here was a settings form (a title, a voice dropdown, a
  /// switch, three paragraphs of explanation, then a history list eating most
  /// of the screen), and the audit's verdict on the previous rebuild —
  /// 「进入对话第一眼看到的是表单」— still held. So the shape is inverted: one
  /// line saying you can start, one line naming the voice, one big button, and
  /// everything that is a *setting* folded away behind a row you only open
  /// when you want to change it.
  ///
  /// Nothing was deleted. The caption switch (#85 · S8) and the honest layering
  /// paragraph (provider captions are guidance; only the local Whisper
  /// transcript becomes learner output) both still exist, and both still say
  /// the same thing — they just no longer have to be read before every single
  /// conversation.
  Widget _lobby(BuildContext context, RealtimeConversationState state) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final anchor = widget.launch.anchor?.text.trim();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(ListenSpacing.gap12),
            child: IconButton(
              key: const ValueKey('realtime-close'),
              tooltip: l.text('realtimeLeaveConversation'),
              onPressed: _requestClose,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                ListenSpacing.gap24,
                0,
                ListenSpacing.gap24,
                ListenSpacing.gap32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ListenBreakpoints.formColumnMax,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: ListenSpacing.gap32),
                      Text(
                        l.text('realtimeLobbyReady'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: ListenSpacing.gap8),
                      _LobbyVoiceChoice(
                        profiles: state.profiles,
                        selectedProfileId: state.selectedProfileId,
                        enabled: state.canConfigure,
                        onSelected: widget.controller.selectProfile,
                        onManageVoices: widget.onManageVoices == null
                            ? null
                            : _manageVoices,
                      ),
                      if (anchor != null && anchor.isNotEmpty) ...[
                        const SizedBox(height: ListenSpacing.gap6),
                        Text(
                          l
                              .text('realtimeLobbyTopic')
                              .replaceAll('{topic}', anchor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: ListenSpacing.gap24),
                      if (state.error != null) ...[
                        ConversationNoticeBar(notice: state.error!),
                        const SizedBox(height: ListenSpacing.gap12),
                      ],
                      // The one action. Everything else on this screen is
                      // either a fold-away setting or the past.
                      FilledButton.icon(
                        key: const ValueKey('realtime-start'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        onPressed: state.selectedProfileId == null
                            ? null
                            : _startConversation,
                        icon: const Icon(Icons.mic),
                        label: Text(l.text('realtimeStartConversation')),
                      ),
                      const SizedBox(height: ListenSpacing.gap12),
                      _LobbyCaptionChoice(
                        enabled: _captionEnabled,
                        onChanged: _setCaptionEnabled,
                      ),
                      const SizedBox(height: ListenSpacing.gap32),
                      const Divider(),
                      const SizedBox(height: ListenSpacing.gap16),
                      ..._lobbyHistory(context, state, l),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 最近的对话 — the past, kept where the past belongs: under the action,
  /// short, and readable at a glance.
  List<Widget> _lobbyHistory(
    BuildContext context,
    RealtimeConversationState state,
    AppLocalizations l,
  ) {
    final theme = Theme.of(context);
    if (state.selectedHistorySessionId != null) {
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('realtime-history-back'),
            onPressed: widget.controller.closeHistorySession,
            icon: const Icon(Icons.arrow_back),
            label: Text(l.text('realtimeHistoryBack')),
          ),
        ),
        if (state.historyError != null)
          ConversationNoticeBar(notice: state.historyError!),
        if (state.historyLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: ListenSpacing.gap16),
            child: ListenLoading(),
          ),
        for (final item in state.historyItems) ...[
          _ConversationTurnCard(item: item),
          const SizedBox(height: ListenSpacing.gap12),
        ],
      ];
    }
    final sessions = state.historySessions;
    final visible = _historyExpanded
        ? sessions
        : sessions.take(_lobbyHistoryPreviewCount).toList(growable: false);
    return [
      Text(
        l.text('realtimeRecentConversations'),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: ListenSpacing.gap8),
      if (state.historyError != null)
        ConversationNoticeBar(notice: state.historyError!),
      if (state.historyLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: ListenSpacing.gap16),
          child: ListenLoading(),
        ),
      if (!state.historyLoading && sessions.isEmpty)
        Text(
          l.text('realtimeHistoryEmpty'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      for (final session in visible)
        _HistorySessionTile(
          session: session,
          onTap: () =>
              widget.controller.openHistorySession(widget.api, session.id),
        ),
      if (!_historyExpanded && sessions.length > _lobbyHistoryPreviewCount)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('realtime-history-show-all'),
            onPressed: () => setState(() => _historyExpanded = true),
            child: Text(l.text('realtimeHistoryShowAll')),
          ),
        ),
    ];
  }

  /// 舞台: the room with the lights off. There is no transcript here —
  /// 「你的话 live 中不上屏」 — and at most one line of 余音字幕 for the other
  /// person, only if the lobby switch is on. The shape in the middle is
  /// replaced by S7's 回声水面 (#84).
  Widget _stage(BuildContext context, RealtimeConversationState state) {
    final l = AppLocalizations.of(context);
    return ConversationStageLayout(
      caption: _captionEnabled
          ? ConversationAfterglowCaption(
              line: conversationAfterglowLineOf(state),
            )
          : null,
      exitAffordance: IconButton(
        key: const ValueKey('realtime-close'),
        tooltip: l.text('realtimeLeaveConversation'),
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
          // The label sits under the water rather than against it: a 16pt gap
          // read as a caption stuck to the shape. `gap32` is the top of the
          // spacing ladder and the nearest step to the ~48pt the design note
          // asked for — the ladder is the constraint, not a suggestion.
          const SizedBox(height: ListenSpacing.gap32),
          // The surface carries the state; this line stays as the screen
          // reader's and the label-reader's version of the same thing —
          // never the only place the state exists (D2).
          Text(
            key: const ValueKey('realtime-activity'),
            _activityLabel(state.activity, l),
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
              l.text('realtimeInterruptHint'),
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
              // The stage's column measure, same as the caption above it: two
              // caps 40pt apart on one surface is two measurements pretending
              // to be a design.
              constraints: const BoxConstraints(
                maxWidth: ListenBreakpoints.formColumnMax,
              ),
              child: ConversationNoticeBar(notice: state.error!),
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
          // 「唯一光源」(charter · 舞台态 2): a filled control here was the
          // second-brightest thing on the stage and it was competing with
          // the water. The teal belongs to the surface — the way out is an
          // outline, and the destructive way out stays text.
          if (state.phase == RealtimeConversationPhase.live)
            OutlinedButton.icon(
              key: const ValueKey('realtime-finish'),
              onPressed: widget.controller.finish,
              icon: const Icon(Icons.stop),
              label: Text(l.text('realtimeFinishAndTranscribe')),
            ),
          if (state.canCancel)
            TextButton(
              key: const ValueKey('realtime-cancel'),
              onPressed: _cancelAndClose,
              child: Text(l.text('realtimeCancelAndDiscard')),
            ),
          if (state.isWorking) const ListenLoading(),
        ],
      ),
    );
  }

  /// 结束页: the stage dims and the conversation becomes readable — the three
  /// fixed sections of the 回流 (#86 · S9, fixes audit D6). S6 built the room;
  /// this fills it.
  ///
  /// Read top to bottom it is one honest sentence: here is what you said (and
  /// what is still being transcribed), here is where the loop stayed open, and
  /// here is what reached your portrait.
  Widget _debrief(BuildContext context, RealtimeConversationState state) {
    final readout = conversationDebriefReadoutOf(state);
    final targets = conversationDebriefTargetsOf(state);
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(ListenSpacing.gap12),
            child: TextButton.icon(
              key: const ValueKey('realtime-debrief-back'),
              onPressed: () => setState(() => _debriefDismissed = true),
              icon: const Icon(Icons.arrow_back),
              label: Text(l.text('realtimeDebriefBack')),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                ListenSpacing.gap24,
                0,
                ListenSpacing.gap24,
                ListenSpacing.gap32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ListenBreakpoints.contentColumnMax,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.error != null)
                        ConversationNoticeBar(notice: state.error!),
                      // P4, first thing on the page: while local Whisper is
                      // still running the debrief says so instead of laying
                      // out a finished-looking transcript.
                      if (!readout.settled) ...[
                        ConversationDebriefProgress(readout: readout),
                        const SizedBox(height: ListenSpacing.gap16),
                      ],
                      for (final item in state.items) ...[
                        ConversationDebriefTurnCard(
                          item: item,
                          onRetryTranscription: _retryTranscription,
                        ),
                        const SizedBox(height: ListenSpacing.gap12),
                      ],
                      const SizedBox(height: ListenSpacing.gap16),
                      ConversationDebriefTargets(
                        targets: targets,
                        onSaveExpression: widget.onSaveExpression == null
                            ? null
                            : _saveExpression,
                        onRetryTranscription: _retryTranscription,
                      ),
                      const SizedBox(height: ListenSpacing.gap24),
                      ConversationDebriefReflow(
                        readout: readout,
                        onOpenVocabulary: widget.onOpenVocabulary == null
                            ? null
                            : () => unawaited(widget.onOpenVocabulary!()),
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
  }

  /// Hands a target turn to 我的表达. Only the provider caption survives such
  /// a turn, so that — clearly the guidance version — is what gets prefilled;
  /// an empty prefill is fine, the learner writes the line themselves.
  void _saveExpression(RealtimeConversationItem item) =>
      unawaited(widget.onSaveExpression!(item.providerText.trim()));

  /// Runs a failed turn's local transcription again. The controller is the one
  /// that decides whether anything can happen: it only kept a rerunnable job
  /// for a failure the backend itself marked retryable, so this is a no-op for
  /// every other failure — and the affordance is not drawn for them either.
  void _retryTranscription(RealtimeConversationItem item) =>
      unawaited(widget.controller.retryLearnerTranscription(item.sequence));

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
    final l = AppLocalizations.of(context);
    bool? discard;
    try {
      discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.text('realtimeDiscardTitle')),
          content: Text(l.text('realtimeDiscardBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.text('realtimeKeepTalking')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.text('realtimeDiscardAndClose')),
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

  String _activityLabel(
    RealtimeConversationActivity activity,
    AppLocalizations l,
  ) => l.text(switch (activity) {
    RealtimeConversationActivity.learnerSpeaking =>
      'realtimeActivityYouSpeaking',
    RealtimeConversationActivity.thinking => 'realtimeActivityThinking',
    RealtimeConversationActivity.assistantSpeaking =>
      'realtimeActivityOtherSpeaking',
    RealtimeConversationActivity.listening => 'realtimeActivityListening',
    RealtimeConversationActivity.inactive => 'realtimeActivityPreparing',
  });

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
///
/// It is **a line of text, not a dropdown**. A form field reads as "you have a
/// choice to make here", and it sat directly above the start button as if the
/// conversation were waiting on it — but essentially every session uses the
/// voice the last one used. So the current voice is stated, and the picker
/// only exists once the learner asks for it by tapping. The dead-end case
/// (no voice configured at all) keeps its explicit way out to settings.
class _LobbyVoiceChoice extends StatefulWidget {
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
  State<_LobbyVoiceChoice> createState() => _LobbyVoiceChoiceState();
}

class _LobbyVoiceChoiceState extends State<_LobbyVoiceChoice> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profiles = widget.profiles;
    if (profiles.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.text('realtimeNoVoiceInLobby')),
          if (widget.onManageVoices != null) ...[
            const SizedBox(height: ListenSpacing.gap8),
            OutlinedButton.icon(
              key: const ValueKey('realtime-manage-voices'),
              onPressed: () => unawaited(widget.onManageVoices!()),
              icon: const Icon(Icons.settings_outlined),
              label: Text(l.text('realtimeManageVoices')),
            ),
          ],
        ],
      );
    }
    final selected = profiles
        .where((profile) => profile.id == widget.selectedProfileId)
        .firstOrNull;
    final line = selected == null
        ? l.text('realtimeLobbyNoVoiceLine')
        : l
              .text('realtimeLobbyVoiceLine')
              .replaceAll('{voice}', _describe(selected));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: '${l.text('realtimeChooseVoice')} · $line',
          child: InkWell(
            key: const ValueKey('realtime-voice-choice'),
            borderRadius: ListenRadii.controlBorder,
            onTap: widget.enabled ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: ListenIconSize.control,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: ListenSpacing.gap4),
          for (final profile in profiles)
            ListTile(
              key: ValueKey('realtime-voice-option-${profile.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              selected: profile.id == widget.selectedProfileId,
              leading: Icon(
                profile.id == widget.selectedProfileId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: widget.enabled
                  ? () {
                      widget.onSelected(profile.id);
                      setState(() => _open = false);
                    }
                  : null,
              title: Text(
                _describe(profile),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (widget.onManageVoices != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('realtime-manage-voices'),
                onPressed: () => unawaited(widget.onManageVoices!()),
                icon: const Icon(Icons.settings_outlined),
                label: Text(l.text('realtimeManageVoices')),
              ),
            ),
        ],
      ],
    );
  }

  String _describe(RealtimeProviderProfileView profile) =>
      '${profile.displayName} · ${profile.voice}';
}

/// What a turn with no text says in the body position.
String _emptyBodyKey(bool learner, bool failed) => switch ((learner, failed)) {
  (true, true) => 'realtimeTurnNotTranscribed',
  (true, false) => 'realtimeTurnListening',
  (false, true) => 'realtimeTurnOtherNotSaved',
  (false, false) => 'realtimeTurnResponding',
};

/// 对方说的话 — one expandable row instead of a switch plus three paragraphs.
///
/// Both things the old block said are still here and still say the same thing:
/// the caption is one dim line that fades (#85 · S8), and the honest layering
/// that matters most — provider captions are guidance, only the local Whisper
/// transcript becomes learner output — is spelled out in full. They are simply
/// no longer mandatory reading before every conversation.
class _LobbyCaptionChoice extends StatefulWidget {
  const _LobbyCaptionChoice({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  State<_LobbyCaptionChoice> createState() => _LobbyCaptionChoiceState();
}

class _LobbyCaptionChoiceState extends State<_LobbyCaptionChoice> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = l.text(
      widget.enabled ? 'realtimeCaptionShown' : 'realtimeCaptionHidden',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('realtime-caption-disclosure'),
          borderRadius: ListenRadii.controlBorder,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l.text('realtimeCaptionRow')} · $value',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: ListenIconSize.control,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          // 字幕默认关 (#85 · S8): the choice is remembered, and it only ever
          // governs the other person's line — the learner's own words are not
          // on the stage to switch on.
          SwitchListTile.adaptive(
            key: const ValueKey('realtime-caption-toggle'),
            contentPadding: EdgeInsets.zero,
            value: widget.enabled,
            onChanged: widget.onChanged,
            title: Text(l.text('realtimeCaptionSwitch')),
            subtitle: Text(l.text('realtimeCaptionSwitchHint')),
          ),
          const SizedBox(height: ListenSpacing.gap4),
          Text(
            l.text('realtimeHonestLayering'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // What was said first is demoted to a hint under the row. It is real, but
    // it does not identify anything: in practice most conversations open with
    // the same greeting, so as a title it told the learner nothing.
    final preview = session.conversationPreview?.trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        session.surfaceKind == 'open_chat'
            ? Icons.forum_outlined
            : Icons.topic_outlined,
      ),
      title: Text(
        realtimeHistoryTitle(session, l),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: preview == null || preview.isEmpty
          ? null
          : Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// One replayed turn from a past conversation.
///
/// A learner turn with no text is the case this card used to get wrong. It put
/// the caught exception in the body position — the place that means "this is
/// what you said" — so a failed turn read as the learner having uttered an
/// `HttpException` with a correlation id and a localhost URI in it. The body
/// now says, in one sentence, that the turn was not transcribed; the exception
/// became a typed failure on the model and lives behind [
/// ConversationTurnFailureNotice]'s closed disclosure.
class _ConversationTurnCard extends StatelessWidget {
  const _ConversationTurnCard({required this.item});

  final RealtimeConversationItem item;

  @override
  Widget build(BuildContext context) {
    final learner = item.role == 'learner';
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final failed = item.status == 'failed' || item.status == 'interrupted';
    final body = item.displayText.trim();
    return Align(
      alignment: learner ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.formColumnMax,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: learner
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: ListenRadii.panelBorder,
          ),
          child: Padding(
            // A turn bubble is a card: its own surface, its own border radius,
            // read as one object. 14 was the third-most-common off-ladder inset
            // in the app and it never meant anything but "16, roughly".
            padding: ListenPadding.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.text(
                    learner ? 'realtimeTurnYou' : 'realtimeTurnOtherVoice',
                  ),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: ListenSpacing.gap4),
                if (body.isNotEmpty)
                  SelectableText(body)
                else
                  // No words came back. Say that — the exception that
                  // explains why is diagnostics, not the learner's turn.
                  Text(
                    key: ValueKey('realtime-turn-empty-${item.sequence}'),
                    l.text(_emptyBodyKey(learner, failed)),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: ListenSpacing.gap6),
                Text(
                  l.text(
                    learner
                        ? switch (item.status) {
                            'finalized' => 'realtimeTurnLearnerOutput',
                            'failed' ||
                            'interrupted' => 'realtimeTurnNotTranscribed',
                            'local_transcription_pending' ||
                            'awaiting_local_transcript' =>
                              'realtimeTurnTranscribingLocally',
                            _ => 'realtimeTurnGuidanceOnly',
                          }
                        : switch (item.status) {
                            'finalized' => 'realtimeTurnOtherResponse',
                            'failed' ||
                            'interrupted' => 'realtimeTurnOtherNotSaved',
                            _ => 'realtimeTurnOtherResponding',
                          },
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                // History is a replay: the backend stores the failure kind,
                // not the exchange that produced it, so there is normally
                // nothing to disclose and no rerun to offer here.
                if (item.failure != null)
                  ConversationTurnFailureNotice(failure: item.failure!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
