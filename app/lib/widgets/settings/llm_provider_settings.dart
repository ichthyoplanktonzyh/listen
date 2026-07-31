import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/llm_provider.dart';
import '../../models/named_failure.dart';
import '../../services/api_service.dart';
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
  const LlmProviderSettings({super.key, required this.api});

  final LocalApi api;

  @override
  State<LlmProviderSettings> createState() => _LlmProviderSettingsState();
}

class _LlmProviderSettingsState extends State<LlmProviderSettings> {
  List<LlmProviderProfileView> _providers = const [];
  bool _loading = true;

  /// The last failure, as a *key* plus typed detail. It used to be a
  /// `String? _error = '$e'`, which is how a `correlation_id` and the sidecar's
  /// loopback URI ended up in this panel's red line.
  NamedFailure? _failure;
  bool _submitting = false;

  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  String _adapterKind = 'openai_chat_completions';
  bool _useRubric = false;
  bool _useJudgment = true;

  final Map<String, String> _probeLabels = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final raw = await widget.api.listLlmProviders();
      final providers = raw
          .map(
            (e) => LlmProviderProfileView.fromJson(e as Map<String, dynamic>),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = NamedFailure(
          'llmProvidersLoadFailed',
          detail: describeApiFailure(e),
        );
        _loading = false;
      });
    }
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
    setState(() {
      _submitting = true;
      _failure = null;
    });
    try {
      await widget.api.registerLlmProvider(
        displayName: _nameCtrl.text.trim().isEmpty
            ? _modelCtrl.text.trim()
            : _nameCtrl.text.trim(),
        adapterKind: _adapterKind,
        baseUrl: _baseUrlCtrl.text.trim(),
        modelId: _modelCtrl.text.trim(),
        allowedUses: uses,
        secret: _secretCtrl.text,
      );
      if (!mounted) return;
      // The secret leaves this widget the moment it is submitted.
      _secretCtrl.clear();
      _nameCtrl.clear();
      _baseUrlCtrl.clear();
      _modelCtrl.clear();
      setState(() => _submitting = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = NamedFailure(
          'llmProviderSaveFailed',
          detail: describeApiFailure(e),
        );
        _submitting = false;
      });
    }
  }

  Future<void> _delete(String id) async {
    try {
      await widget.api.deleteLlmProvider(id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _failure = NamedFailure(
          'llmProviderRemoveFailed',
          detail: describeApiFailure(e),
        ),
      );
    }
  }

  Future<void> _probe(String id) async {
    final l = AppLocalizations.of(context);
    setState(() => _probeLabels[id] = l.text('llmProbing'));
    try {
      final result = await widget.api.probeLlmProvider(id);
      if (!mounted) return;
      final claim = result.structuredOutput;
      setState(() {
        _probeLabels[id] = claim.isProbedSupported
            ? l.text('llmProbeSupported')
            : l.text('llmProbeUnsupported');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _probeLabels[id] = l.text('llmProbeFailed'));
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
        if (_failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ApiFailureNotice(
              message: l.text(_failure!.messageKey),
              failure: _failure!.detail,
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: ListenLoading()),
          )
        else if (_providers.isEmpty)
          Text(l.text('llmNoProviders'), style: theme.textTheme.bodyMedium)
        else
          ..._providers.map(_providerTile),
        const Divider(height: 28),
        _addForm(l),
      ],
    );
  }

  Widget _providerTile(LlmProviderProfileView p) {
    final l = AppLocalizations.of(context);
    final probe = _probeLabels[p.id];
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
                  onPressed: () => _probe(p.id),
                  child: Text(l.text('llmTest')),
                ),
                IconButton(
                  tooltip: l.text('llmRemove'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(p.id),
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
                  probe,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

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
            onPressed: _submitting ? null : _register,
            child: Text(l.text('llmRegister')),
          ),
        ),
      ],
    );
  }
}
