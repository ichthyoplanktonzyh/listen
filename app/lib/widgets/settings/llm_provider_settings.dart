import 'package:flutter/material.dart';

import '../../controllers/provider_settings_view_models.dart';
import '../../data/repositories/settings_repository.dart';
import '../../localization.dart';
import '../../models/llm_provider.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_loading.dart';

/// Phase 3.12 provider settings: configure vendor-neutral LLM providers for
/// semantic feedback. Keys are write-only (stored in the OS keychain by the
/// backend); this widget never displays or holds a secret after submit.
///
/// Any judgment a provider produces is unqualified `heuristic_proxy` and does
/// not appear as learning feedback until Phase 3.12.1 qualification — the UI
/// says so explicitly so a configured provider is never mistaken for verified
/// assistance.
class LlmProviderSettings extends StatefulWidget {
  const LlmProviderSettings({super.key, this.repository, this.viewModel})
    : assert(repository != null || viewModel != null);

  final LlmProviderRepository? repository;
  final LlmProviderSettingsViewModel? viewModel;

  @override
  State<LlmProviderSettings> createState() => _LlmProviderSettingsState();
}

class _LlmProviderSettingsState extends State<LlmProviderSettings> {
  late final LlmProviderSettingsViewModel _viewModel;
  late final bool _ownsViewModel;

  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  String _adapterKind = 'openai_chat_completions';
  bool _useRubric = false;
  bool _useJudgment = true;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel =
        widget.viewModel ?? LlmProviderSettingsViewModel(widget.repository!);
    _viewModel.load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _secretCtrl.dispose();
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final uses = <String>[
      if (_useRubric) 'rubric_generation',
      if (_useJudgment) 'semantic_judgment',
    ];
    if (_baseUrlCtrl.text.trim().isEmpty ||
        _modelCtrl.text.trim().isEmpty ||
        uses.isEmpty) {
      return;
    }
    final saved = await _viewModel.register(
      LlmProviderDraft(
        displayName: _nameCtrl.text.trim().isEmpty
            ? _modelCtrl.text.trim()
            : _nameCtrl.text.trim(),
        adapterKind: _adapterKind,
        baseUrl: _baseUrlCtrl.text.trim(),
        modelId: _modelCtrl.text.trim(),
        allowedUses: uses,
        secret: _secretCtrl.text,
      ),
    );
    if (saved && mounted) {
      // The secret leaves this widget the moment it is submitted.
      _secretCtrl.clear();
      _nameCtrl.clear();
      _baseUrlCtrl.clear();
      _modelCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('llmProvidersDescription'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Container(
          padding: ListenPadding.row,
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: ListenRadii.controlBorder,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.privacy_tip_outlined,
                size: ListenIconSize.control,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Text(
                  l.text('llmDataWarning'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Text(l.text('llmNotQualified'), style: theme.textTheme.bodySmall),
        const SizedBox(height: ListenSpacing.gap12),
        if (_viewModel.failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ApiFailureNotice(
              message: l.text(_viewModel.failure!.messageKey),
              failure: _viewModel.failure!.detail,
            ),
          ),
        if (_viewModel.loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: ListenLoading()),
          )
        else if (_viewModel.providers.isEmpty)
          Text(l.text('llmNoProviders'), style: theme.textTheme.bodyMedium)
        else
          ..._viewModel.providers.map(_providerTile),
        const Divider(height: 28),
        _addForm(l),
      ],
    );
  }

  Widget _providerTile(LlmProviderProfileView p) {
    final l = AppLocalizations.of(context);
    final probe = _viewModel.probeStatuses[p.id];
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
                    p.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (p.hasCredential)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(l.text('llmKeyStored')),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                TextButton(
                  onPressed: () => _viewModel.probe(p.id),
                  child: Text(l.text('llmTest')),
                ),
                IconButton(
                  tooltip: l.text('llmRemove'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _viewModel.deletingIds.contains(p.id)
                      ? null
                      : () => _viewModel.delete(p.id),
                ),
              ],
            ),
            Text(
              '${p.adapterKind} · ${p.modelId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(p.baseUrl, style: Theme.of(context).textTheme.bodySmall),
            if (probe != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _probeLabel(l, probe),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _probeLabel(AppLocalizations l, LlmProbeStatus status) =>
      switch (status) {
        LlmProbeStatus.probing => l.text('llmProbing'),
        LlmProbeStatus.supported => l.text('llmProbeSupported'),
        LlmProbeStatus.unsupported => l.text('llmProbeUnsupported'),
        LlmProbeStatus.failed => l.text('llmProbeFailed'),
      };

  Widget _addForm(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.text('llmAddProvider'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Row(
          children: [
            Text('${l.text('llmAdapterKind')}: '),
            const SizedBox(width: ListenSpacing.gap8),
            DropdownButton<String>(
              value: _adapterKind,
              items: const [
                DropdownMenuItem(
                  value: 'openai_chat_completions',
                  child: Text('OpenAI Chat Completions'),
                ),
                DropdownMenuItem(
                  value: 'anthropic_messages',
                  child: Text('Anthropic Messages'),
                ),
              ],
              onChanged: (v) =>
                  setState(() => _adapterKind = v ?? _adapterKind),
            ),
          ],
        ),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(labelText: l.text('llmDisplayName')),
        ),
        TextField(
          controller: _baseUrlCtrl,
          decoration: InputDecoration(
            labelText: l.text('llmBaseUrl'),
            hintText: 'https://api.openai.com/v1',
          ),
        ),
        TextField(
          controller: _modelCtrl,
          decoration: InputDecoration(labelText: l.text('llmModelId')),
        ),
        TextField(
          controller: _secretCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l.text('llmApiKey'),
            helperText: l.text('llmApiKeyHint'),
          ),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Text(l.text('llmAllowedUses')),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _useJudgment,
                onChanged: (v) => setState(() => _useJudgment = v ?? false),
                title: Text(l.text('llmUseJudgment')),
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _useRubric,
                onChanged: (v) => setState(() => _useRubric = v ?? false),
                title: Text(l.text('llmUseRubric')),
              ),
            ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _viewModel.submitting ? null : _register,
            child: Text(l.text('llmRegister')),
          ),
        ),
      ],
    );
  }
}
