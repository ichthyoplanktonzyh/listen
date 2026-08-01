import 'package:flutter/material.dart';

import '../../controllers/provider_settings_view_models.dart';
import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_error_state.dart';

class SyntaxCapabilitySettings extends StatefulWidget {
  const SyntaxCapabilitySettings({super.key, required this.viewModel});

  final SyntaxCapabilitySettingsViewModel viewModel;

  @override
  State<SyntaxCapabilitySettings> createState() =>
      _SyntaxCapabilitySettingsState();
}

class _SyntaxCapabilitySettingsState extends State<SyntaxCapabilitySettings> {
  SyntaxCapabilitySettingsViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel.refresh();
  }

  @override
  void dispose() {
    super.dispose();
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
    final state = _viewModel.state;
    final capability = state.capability;
    if (capability == null) {
      return const LinearProgressIndicator();
    }
    final installedMb = capability.installedBytes / (1024 * 1024);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.text('syntaxCapabilityDescription')),
        const SizedBox(height: ListenSpacing.gap8),
        Row(
          children: [
            Icon(
              capability.isReady
                  ? Icons.check_circle_outline
                  : capability.status == 'failed' ||
                        capability.status == 'partial'
                  ? Icons.warning_amber_outlined
                  : Icons.extension_outlined,
              size: ListenIconSize.control,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                '${_statusLabel(l, capability.status)} · spaCy '
                '${capability.runtimeVersion} · model ${capability.modelVersion}'
                '${installedMb > 0 ? ' · ${installedMb.toStringAsFixed(0)} MB' : ''}',
              ),
            ),
          ],
        ),
        if (capability.isDownloading) ...[
          const SizedBox(height: ListenSpacing.gap8),
          LinearProgressIndicator(value: capability.progress),
        ],
        if (capability.error != null) ...[
          const SizedBox(height: ListenSpacing.gap6),
          ListenErrorNotice(message: capability.error!),
        ],
        if (state.failure != null) ...[
          const SizedBox(height: ListenSpacing.gap6),
          ApiFailureNotice(
            message: l.text(state.failure!.messageKey),
            failure: state.failure!.detail,
          ),
        ],
        const SizedBox(height: ListenSpacing.gap8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (capability.status == 'not_installed')
              FilledButton.icon(
                onPressed: state.busy
                    ? null
                    : () => _viewModel.runAction('install'),
                icon: const Icon(Icons.download_outlined),
                label: Text(l.text('install')),
              ),
            if (capability.isDownloading)
              OutlinedButton(
                onPressed: () => _viewModel.runAction('cancel'),
                child: Text(l.text('syntaxCancel')),
              ),
            if ({'failed', 'partial'}.contains(capability.status))
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => _viewModel.runAction('install'),
                child: Text(l.text('retry')),
              ),
            if (capability.isInstalled && !capability.isDownloading) ...[
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => _viewModel.runAction('validate'),
                child: Text(l.text('syntaxVerify')),
              ),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => _viewModel.runAction('update'),
                child: Text(l.text('syntaxUpdate')),
              ),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => _viewModel.runAction(
                        capability.enabled ? 'disable' : 'enable',
                      ),
                child: Text(
                  capability.enabled
                      ? l.text('syntaxDisable')
                      : l.text('syntaxEnable'),
                ),
              ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => _viewModel.runAction('uninstall'),
                child: Text(l.text('syntaxUninstall')),
              ),
            ],
          ],
        ),
        if (capability.isReady && _viewModel.currentTrackId != null) ...[
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  state.track == null
                      ? l.text('syntaxTrackBackground')
                      : '${_statusLabel(l, state.track!.status)} · ${state.track!.analyzedSentenceCount}/'
                            '${state.track!.sentenceCount} ${l.text('syntaxSentences')}'
                            '${state.track!.cacheHit ? ' · ${l.text('syntaxCacheReused')}' : ''}',
                ),
              ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => _viewModel.analyze(force: true),
                child: Text(l.text('syntaxRebuild')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _statusLabel(AppLocalizations l, String status) => switch (status) {
    'not_installed' => l.text('syntaxNotInstalled'),
    'downloading' || 'analyzing' => l.text('syntaxDownloading'),
    'ready' => l.text('syntaxReady'),
    'partial' => l.text('syntaxPartial'),
    'failed' || 'unavailable' => l.text('syntaxFailed'),
    'stale' => l.text('syntaxStale'),
    'disabled' => l.text('syntaxDisabled'),
    _ => status,
  };
}
