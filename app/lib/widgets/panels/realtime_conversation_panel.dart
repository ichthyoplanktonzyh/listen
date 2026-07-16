import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../controllers/speaking_task_controller.dart';
import '../../services/api_service.dart';

class RealtimeConversationPanel extends StatefulWidget {
  const RealtimeConversationPanel({
    super.key,
    required this.controller,
    required this.api,
    required this.source,
    required this.modelId,
    required this.acquireAudioFocus,
    required this.onClose,
  });
  final RealtimeConversationController controller;
  final LocalApi api;
  final SpeakingTaskSource source;
  final String modelId;
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.loadProfiles(widget.api),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            ListTile(
              leading: IconButton(
                onPressed:
                    state.phase == 'live' || state.phase == 'transcribing'
                    ? null
                    : widget.onClose,
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
                        'Source context',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(widget.source.transcriptSnapshot),
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
                                        widget.controller.selectProfile(value);
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
                      if (state.phase == 'live' ||
                          state.providerTranscript.isNotEmpty) ...[
                        Text(
                          'Live provider caption',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          state.providerTranscript.isEmpty
                              ? 'Listening…'
                              : state.providerTranscript,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (state.assistantTranscript.isNotEmpty) ...[
                        Text(
                          'Assistant',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        SelectableText(state.assistantTranscript),
                        const SizedBox(height: 16),
                      ],
                      if (state.localTranscript.isNotEmpty) ...[
                        Text(
                          'Local Whisper learner transcript',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        _notice(context, state.localTranscript, false),
                        const SizedBox(height: 16),
                      ],
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
                                      widget.source,
                                      acquireAudioFocus:
                                          widget.acquireAudioFocus,
                                    ),
                              icon: const Icon(Icons.mic),
                              label: const Text('Start conversation'),
                            ),
                          if (state.phase == 'live')
                            FilledButton.icon(
                              key: const ValueKey('realtime-finish'),
                              onPressed: () => widget.controller.finish(
                                widget.api,
                                widget.source,
                                widget.modelId,
                              ),
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
                              state.phase == 'transcribing')
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
      text: 'wss://api.openai.com/v1/realtime',
    );
    final model = TextEditingController(text: 'gpt-realtime');
    final voice = TextEditingController(text: 'marin');
    final secret = TextEditingController();
    var adapter = 'open_ai_realtime';
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
                          endpoint.text =
                              'wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime';
                          model.text = 'qwen3-omni-flash-realtime';
                        }
                      });
                    }
                  },
                ),
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
