import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/realtime_conversation.dart';
import '../../services/api_service.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/listen_loading.dart';

const openAiRealtimeBaselineModel = 'gpt-realtime-2.1';
const qwenRealtimeBaselineModel = 'qwen3.5-omni-plus-realtime';

/// Realtime speech provider management (#87 / S10). The endpoint, workspace,
/// region and API key used to live inside the conversation panel, which made
/// the first screen of a *conversation* a configuration form. Configuration
/// belongs to the settings domain; the conversation lobby keeps only the
/// "which voice speaks with you" choice.
///
/// The API key is write-only here: it is handed to the backend (system
/// keychain) on save and cleared from the field immediately, exactly as the
/// former dialog did. Every [TextEditingController] is owned by this [State]
/// and released in [dispose] (#27) — an inline form has no exit transition to
/// race, so the lifecycle that fix protected is preserved by construction.
class RealtimeProviderSettings extends StatefulWidget {
  const RealtimeProviderSettings({super.key, required this.api});

  final LocalApi api;

  @override
  State<RealtimeProviderSettings> createState() =>
      _RealtimeProviderSettingsState();
}

class _RealtimeProviderSettingsState extends State<RealtimeProviderSettings> {
  List<RealtimeProviderProfileView> _profiles = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  final _name = TextEditingController();
  final _endpoint = TextEditingController(
    text:
        'wss://<workspace-id>.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime',
  );
  final _model = TextEditingController(text: qwenRealtimeBaselineModel);
  final _voice = TextEditingController(text: 'Tina');
  final _secret = TextEditingController();
  final _qwenWorkspace = TextEditingController();
  var _adapter = 'qwen_omni_realtime';
  var _qwenRegion = 'cn';
  String? _workspaceError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // The secret is cleared first so the API key does not linger in the
    // controller's value after it has been handed to the keychain (#27).
    _secret.clear();
    _name.dispose();
    _endpoint.dispose();
    _model.dispose();
    _voice.dispose();
    _secret.dispose();
    _qwenWorkspace.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profiles = await widget.api.realtimeProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _applyQwenEndpoint() {
    final workspace = _qwenWorkspace.text.trim();
    final workspaceLabel = workspace.isEmpty ? '<workspace-id>' : workspace;
    final regionHost = _qwenRegion == 'cn'
        ? 'cn-beijing.maas.aliyuncs.com'
        : 'ap-southeast-1.maas.aliyuncs.com';
    _endpoint.text = 'wss://$workspaceLabel.$regionHost/api-ws/v1/realtime';
  }

  Future<void> _register(AppLocalizations l) async {
    if (_endpoint.text.contains('<workspace-id>')) {
      // Honest feedback (#24/#45 discipline): a user-triggered action never
      // no-ops silently — name what is missing.
      setState(() => _workspaceError = l.text('realtimeWorkspaceMissing'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.registerRealtimeProfile(
        displayName: _name.text.trim().isEmpty
            ? 'Realtime provider'
            : _name.text.trim(),
        adapterKind: _adapter,
        baseUrl: _endpoint.text.trim(),
        modelId: _model.text.trim(),
        voice: _voice.text.trim(),
        secret: _secret.text,
      );
      if (!mounted) return;
      // The secret leaves this widget the moment it is submitted.
      _secret.clear();
      _name.clear();
      setState(() => _submitting = false);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _submitting = false;
      });
    }
  }

  Future<void> _remove(RealtimeProviderProfileView profile) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('realtimeRemoveTitle')),
        content: Text(l.text('realtimeRemoveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.text('realtimeRemove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteRealtimeProfile(profile.id);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('realtimeProvidersDescription'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: ListenRadii.controlBorder,
          ),
          child: Row(
            children: [
              const Icon(Icons.hearing_outlined, size: 18),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Text(
                  l.text('realtimeHonestLayering'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ListenSpacing.gap12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: ListenLoading()),
          )
        else if (_profiles.isEmpty)
          Text(l.text('realtimeNoProviders'), style: theme.textTheme.bodyMedium)
        else
          ..._profiles.map((profile) => _profileTile(profile, l)),
        const Divider(height: 28),
        _addForm(l),
      ],
    );
  }

  Widget _profileTile(RealtimeProviderProfileView profile, AppLocalizations l) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (profile.hasCredential)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(l.text('realtimeKeyStored')),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  tooltip: l.text('realtimeRemove'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(profile),
                ),
              ],
            ),
            Text(
              '${profile.adapterKind} · ${profile.modelId}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${l.text('realtimeVoice')}: ${profile.voice}',
              style: theme.textTheme.bodySmall,
            ),
            Text(profile.baseUrl, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _addForm(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l.text('realtimeAddProvider'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: ListenSpacing.gap8),
      DropdownButtonFormField<String>(
        initialValue: _adapter,
        decoration: InputDecoration(labelText: l.text('realtimeProtocol')),
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
          if (value == null) return;
          setState(() {
            _adapter = value;
            _workspaceError = null;
            if (value == 'qwen_omni_realtime') {
              _model.text = qwenRealtimeBaselineModel;
              _voice.text = 'Tina';
              _applyQwenEndpoint();
            } else {
              _model.text = openAiRealtimeBaselineModel;
              _endpoint.text = 'wss://api.openai.com/v1/realtime';
              _voice.text = 'marin';
            }
          });
        },
      ),
      if (_adapter == 'qwen_omni_realtime') ...[
        DropdownButtonFormField<String>(
          initialValue: _qwenRegion,
          decoration: InputDecoration(labelText: l.text('realtimeRegion')),
          items: const [
            DropdownMenuItem(value: 'sg', child: Text('Singapore')),
            DropdownMenuItem(
              value: 'cn',
              child: Text('China (Model Studio / 百炼)'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _qwenRegion = value;
              _applyQwenEndpoint();
            });
          },
        ),
        TextField(
          controller: _qwenWorkspace,
          decoration: InputDecoration(
            labelText: l.text('realtimeWorkspaceId'),
            helperText: l.text('realtimeWorkspaceHint'),
            errorText: _workspaceError,
          ),
          onChanged: (_) => setState(() {
            _workspaceError = null;
            _applyQwenEndpoint();
          }),
        ),
      ],
      TextField(
        controller: _name,
        decoration: InputDecoration(labelText: l.text('realtimeDisplayName')),
      ),
      TextField(
        controller: _endpoint,
        decoration: InputDecoration(
          labelText: l.text('realtimeEndpoint'),
          // The Workspace ID field carries the error while it is visible;
          // otherwise the endpoint field itself does, so the save guard is
          // never silent.
          errorText: _adapter == 'qwen_omni_realtime' ? null : _workspaceError,
        ),
        onChanged: (_) => setState(() => _workspaceError = null),
      ),
      TextField(
        controller: _model,
        decoration: InputDecoration(labelText: l.text('realtimeModel')),
      ),
      TextField(
        controller: _voice,
        decoration: InputDecoration(labelText: l.text('realtimeVoice')),
      ),
      TextField(
        controller: _secret,
        obscureText: true,
        decoration: InputDecoration(
          labelText: l.text('realtimeApiKey'),
          helperText: l.text('realtimeApiKeyHint'),
        ),
      ),
      const SizedBox(height: ListenSpacing.gap8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: _submitting ? null : () => _register(l),
          child: Text(l.text('realtimeSaveProvider')),
        ),
      ),
    ],
  );
}
