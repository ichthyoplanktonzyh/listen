import 'package:flutter/material.dart';

import '../../controllers/provider_settings_view_models.dart';
import '../../data/repositories/settings_repository.dart';
import '../../localization.dart';
import '../../services/api_service.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_error_state.dart';

class SyntaxCapabilitySettings extends StatefulWidget {
  const SyntaxCapabilitySettings({
    super.key,
    this.api,
    this.viewModel,
    this.currentTrackId,
  }) : assert(api != null || viewModel != null);

  final LocalApi? api;
  final SyntaxCapabilitySettingsViewModel? viewModel;
  final String? currentTrackId;

  @override
  State<SyntaxCapabilitySettings> createState() =>
      _SyntaxCapabilitySettingsState();
}

class _SyntaxCapabilitySettingsState extends State<SyntaxCapabilitySettings> {
  late final SyntaxCapabilitySettingsViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel =
        widget.viewModel ??
        SyntaxCapabilitySettingsViewModel(
          LocalSyntaxCapabilityRepository(widget.api!),
          currentTrackId: widget.currentTrackId,
        );
    _viewModel.refresh();
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
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
    final capability = _viewModel.capability;
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
        if (_viewModel.failure != null) ...[
          const SizedBox(height: ListenSpacing.gap6),
          ApiFailureNotice(
            message: l.text(_viewModel.failure!.messageKey),
            failure: _viewModel.failure!.detail,
          ),
        ],
        const SizedBox(height: ListenSpacing.gap8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (capability.status == 'not_installed')
              FilledButton.icon(
                onPressed: _viewModel.busy
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
                onPressed: _viewModel.busy
                    ? null
                    : () => _viewModel.runAction('install'),
                child: Text(l.text('retry')),
              ),
            if (capability.isInstalled && !capability.isDownloading) ...[
              OutlinedButton(
                onPressed: _viewModel.busy
                    ? null
                    : () => _viewModel.runAction('validate'),
                child: Text(l.text('syntaxVerify')),
              ),
              OutlinedButton(
                onPressed: _viewModel.busy
                    ? null
                    : () => _viewModel.runAction('update'),
                child: Text(l.text('syntaxUpdate')),
              ),
              OutlinedButton(
                onPressed: _viewModel.busy
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
                onPressed: _viewModel.busy
                    ? null
                    : () => _viewModel.runAction('uninstall'),
                child: Text(l.text('syntaxUninstall')),
              ),
            ],
          ],
        ),
        if (capability.isReady && widget.currentTrackId != null) ...[
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  _viewModel.track == null
                      ? l.text('syntaxTrackBackground')
                      : '${_statusLabel(l, _viewModel.track!.status)} · ${_viewModel.track!.analyzedSentenceCount}/'
                            '${_viewModel.track!.sentenceCount} ${l.text('syntaxSentences')}'
                            '${_viewModel.track!.cacheHit ? ' · ${l.text('syntaxCacheReused')}' : ''}',
                ),
              ),
              TextButton(
                onPressed: _viewModel.busy
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
