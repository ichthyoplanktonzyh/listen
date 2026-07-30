import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/named_failure.dart';
import '../../models/syntax_capability.dart';
import '../../services/api_service.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_error_state.dart';

class SyntaxCapabilitySettings extends StatefulWidget {
  const SyntaxCapabilitySettings({
    super.key,
    required this.api,
    this.currentTrackId,
  });

  final LocalApi api;
  final String? currentTrackId;

  @override
  State<SyntaxCapabilitySettings> createState() =>
      _SyntaxCapabilitySettingsState();
}

class _SyntaxCapabilitySettingsState extends State<SyntaxCapabilitySettings> {
  SyntaxCapabilityView? _capability;
  TrackSyntaxAnalysisView? _track;

  /// The last failure, as a *key* plus typed detail — see `NamedFailure`.
  /// This was a `String? _error = '$error'`, handed straight to
  /// [ListenErrorNotice], so a failed install printed the whole exception.
  NamedFailure? _failure;
  bool _busy = false;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final next = await widget.api.syntaxCapability();
      if (!mounted) return;
      final becameReady = _capability?.isReady != true && next.isReady;
      setState(() {
        _capability = next;
        _failure = null;
      });
      if (next.isDownloading) {
        _poller ??= Timer.periodic(
          const Duration(seconds: 1),
          (_) => _refresh(),
        );
      } else {
        _poller?.cancel();
        _poller = null;
      }
      if (becameReady && widget.currentTrackId != null) {
        await _analyze(force: false);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = NamedFailure(
            'syntaxCapabilityLoadFailed',
            detail: describeApiFailure(error),
          ),
        );
      }
    }
  }

  Future<void> _action(String action) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final next = await widget.api.syntaxCapabilityAction(action);
      if (!mounted) return;
      setState(() {
        _capability = next;
        _busy = false;
      });
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = NamedFailure(
          'syntaxCapabilityActionFailed',
          detail: describeApiFailure(error),
        );
      });
    }
  }

  Future<void> _analyze({required bool force}) async {
    final trackId = widget.currentTrackId;
    if (trackId == null || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final result = await widget.api.runTrackSyntaxAnalysis(
        trackId,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _track = result;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = NamedFailure(
          'syntaxTrackAnalysisFailed',
          detail: describeApiFailure(error),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final capability = _capability;
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
        if (_failure != null) ...[
          const SizedBox(height: ListenSpacing.gap6),
          ApiFailureNotice(
            message: l.text(_failure!.messageKey),
            failure: _failure!.detail,
          ),
        ],
        const SizedBox(height: ListenSpacing.gap8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (capability.status == 'not_installed')
              FilledButton.icon(
                onPressed: _busy ? null : () => _action('install'),
                icon: const Icon(Icons.download_outlined),
                label: Text(l.text('install')),
              ),
            if (capability.isDownloading)
              OutlinedButton(
                onPressed: () => _action('cancel'),
                child: Text(l.text('syntaxCancel')),
              ),
            if ({'failed', 'partial'}.contains(capability.status))
              FilledButton(
                onPressed: _busy ? null : () => _action('install'),
                child: Text(l.text('retry')),
              ),
            if (capability.isInstalled && !capability.isDownloading) ...[
              OutlinedButton(
                onPressed: _busy ? null : () => _action('validate'),
                child: Text(l.text('syntaxVerify')),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _action('update'),
                child: Text(l.text('syntaxUpdate')),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _action(capability.enabled ? 'disable' : 'enable'),
                child: Text(
                  capability.enabled
                      ? l.text('syntaxDisable')
                      : l.text('syntaxEnable'),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => _action('uninstall'),
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
                  _track == null
                      ? l.text('syntaxTrackBackground')
                      : '${_statusLabel(l, _track!.status)} · ${_track!.analyzedSentenceCount}/'
                            '${_track!.sentenceCount} ${l.text('syntaxSentences')}'
                            '${_track!.cacheHit ? ' · ${l.text('syntaxCacheReused')}' : ''}',
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => _analyze(force: true),
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
