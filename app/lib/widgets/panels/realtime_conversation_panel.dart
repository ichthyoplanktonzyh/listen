import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../models/realtime_conversation.dart';
import '../../services/api_service.dart';

const openAiRealtimeBaselineModel = 'gpt-realtime-2.1';
const qwenRealtimeBaselineModel = 'qwen3.5-omni-plus-realtime';

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
  });
  final RealtimeConversationController controller;
  final LocalApi api;
  final RealtimeConversationLaunch launch;
  final Future<void> Function() acquireAudioFocus;
  final VoidCallback onClose;

  @override
  State<RealtimeConversationPanel> createState() =>
      _RealtimeConversationPanelState();
}

class _RealtimeConversationPanelState extends State<RealtimeConversationPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadProfiles(widget.api);
      widget.controller.loadHistory(widget.api);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final canClose =
          state.phase == 'idle' ||
          state.phase == 'done' ||
          state.phase == 'failed';
      return PopScope(
        canPop: canClose,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              ListTile(
                leading: IconButton(
                  onPressed: canClose ? widget.onClose : null,
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
                        const SizedBox(height: 6),
                        Text(
                          widget.launch.source?.transcriptSnapshot ??
                              'Start without sending media or subtitle context.',
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: state.selectedProfileId,
                                decoration: const InputDecoration(
                                  labelText: 'Realtime provider',
                                  border: OutlineInputBorder(),
                                ),
                                items: state.profiles
                                    .map(
                                      (profile) => DropdownMenuItem(
                                        value: profile.id,
                                        child: Text(
                                          '${profile.displayName} · ${profile.modelId}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged:
                                    state.phase == 'idle' ||
                                        state.phase == 'done' ||
                                        state.phase == 'failed'
                                    ? (value) {
                                        if (value != null) {
                                          widget.controller.selectProfile(
                                            value,
                                          );
                                        }
                                      }
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () => _showProviderDialog(context),
                              icon: const Icon(Icons.key),
                              label: const Text('Add provider'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        if (state.error != null)
                          _notice(context, state.error!, true),
                        if (state.items.isEmpty && state.phase == 'live')
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'Listening… Start speaking when ready.',
                            ),
                          ),
                        for (final item in state.items) ...[
                          _ConversationTurnCard(item: item),
                          const SizedBox(height: 12),
                        ],
                        if (state.postProcessingCount > 0)
                          Text(
                            '${state.postProcessingCount} learner turn(s) are being transcribed locally.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (state.postProcessingCount > 0)
                          const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          children: [
                            if (state.phase == 'idle' ||
                                state.phase == 'done' ||
                                state.phase == 'failed')
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
                            if (state.phase == 'live')
                              FilledButton.icon(
                                key: const ValueKey('realtime-finish'),
                                onPressed: widget.controller.finish,
                                icon: const Icon(Icons.stop),
                                label: const Text(
                                  'Finish and transcribe locally',
                                ),
                              ),
                            if (state.phase == 'connecting' ||
                                state.phase == 'live')
                              TextButton(
                                onPressed: widget.controller.cancel,
                                child: const Text('Cancel and discard'),
                              ),
                            if (state.phase == 'connecting' ||
                                state.phase == 'draining' ||
                                state.phase == 'post_processing')
                              const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(),
                              ),
                          ],
                        ),
                        if (state.phase == 'idle' ||
                            state.phase == 'done' ||
                            state.phase == 'failed') ...[
                          const SizedBox(height: 32),
                          const Divider(),
                          const SizedBox(height: 12),
                          Text(
                            'Conversation history',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
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
                              const SizedBox(height: 12),
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

  Widget _notice(BuildContext context, String text, bool error) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text),
  );

  Future<void> _showProviderDialog(BuildContext context) async {
    final name = TextEditingController();
    final endpoint = TextEditingController(
      text:
          'wss://<workspace-id>.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime',
    );
    final model = TextEditingController(text: qwenRealtimeBaselineModel);
    final voice = TextEditingController(text: 'Tina');
    final secret = TextEditingController();
    final qwenWorkspace = TextEditingController();
    var adapter = 'qwen_omni_realtime';
    var qwenRegion = 'cn';
    void applyQwenEndpoint() {
      final workspace = qwenWorkspace.text.trim();
      final workspaceLabel = workspace.isEmpty ? '<workspace-id>' : workspace;
      final regionHost = qwenRegion == 'cn'
          ? 'cn-beijing.maas.aliyuncs.com'
          : 'ap-southeast-1.maas.aliyuncs.com';
      endpoint.text = 'wss://$workspaceLabel.$regionHost/api-ws/v1/realtime';
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add realtime provider'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: adapter,
                  items: const [
                    DropdownMenuItem(
                      value: 'open_ai_realtime',
                      child: Text('OpenAI Realtime'),
                    ),
                    DropdownMenuItem(
                      value: 'qwen_omni_realtime',
                      child: Text('Qwen Omni Realtime'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        adapter = value;
                        if (value == 'qwen_omni_realtime') {
                          model.text = qwenRealtimeBaselineModel;
                          voice.text = 'Tina';
                          applyQwenEndpoint();
                        } else {
                          model.text = openAiRealtimeBaselineModel;
                          endpoint.text = 'wss://api.openai.com/v1/realtime';
                          voice.text = 'marin';
                        }
                      });
                    }
                  },
                ),
                if (adapter == 'qwen_omni_realtime') ...[
                  DropdownButtonFormField<String>(
                    initialValue: qwenRegion,
                    decoration: const InputDecoration(labelText: 'Region'),
                    items: const [
                      DropdownMenuItem(value: 'sg', child: Text('Singapore')),
                      DropdownMenuItem(
                        value: 'cn',
                        child: Text('China (Model Studio / 百炼)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          qwenRegion = value;
                          applyQwenEndpoint();
                        });
                      }
                    },
                  ),
                  TextField(
                    controller: qwenWorkspace,
                    decoration: const InputDecoration(
                      labelText: 'Workspace ID',
                      helperText:
                          'Use the workspace and API key from the same region.',
                    ),
                    onChanged: (_) => setDialogState(applyQwenEndpoint),
                  ),
                ],
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                TextField(
                  controller: endpoint,
                  decoration: const InputDecoration(
                    labelText: 'WebSocket endpoint',
                  ),
                ),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                TextField(
                  controller: voice,
                  decoration: const InputDecoration(labelText: 'Voice'),
                ),
                TextField(
                  controller: secret,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API key (stored in macOS Keychain)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (endpoint.text.contains('<workspace-id>')) return;
                await widget.controller.registerProfile(
                  widget.api,
                  displayName: name.text.trim().isEmpty
                      ? 'Realtime provider'
                      : name.text.trim(),
                  adapterKind: adapter,
                  baseUrl: endpoint.text.trim(),
                  modelId: model.text.trim(),
                  voice: voice.text.trim(),
                  secret: secret.text,
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save securely'),
            ),
          ],
        ),
      ),
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
            borderRadius: BorderRadius.circular(16),
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
                const SizedBox(height: 4),
                SelectableText(text),
                const SizedBox(height: 6),
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
                  const SizedBox(height: 4),
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
