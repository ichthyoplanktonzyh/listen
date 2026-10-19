import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/realtime_transcription_model_controller.dart';
import '../../localization.dart';
import '../../models/runtime_resources.dart';
import '../../theme/breakpoints.dart';
import '../../theme/spacing.dart';

Future<RealtimeTranscriptionModelSelected?>
showRealtimeTranscriptionModelDialog({
  required BuildContext context,
  required RealtimeTranscriptionModelController controller,
  required TranscriptionModelView model,
}) => showDialog<RealtimeTranscriptionModelSelected>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      RealtimeTranscriptionModelDialog(controller: controller, model: model),
);

/// Consent and progress view for one Core-catalogued transcription model.
/// The injected controller owns install/cancel state and must outlive this
/// dialog; dismissing the dialog never disposes application state.
class RealtimeTranscriptionModelDialog extends StatefulWidget {
  const RealtimeTranscriptionModelDialog({
    super.key,
    required this.controller,
    required this.model,
  });

  final RealtimeTranscriptionModelController controller;
  final TranscriptionModelView model;

  @override
  State<RealtimeTranscriptionModelDialog> createState() =>
      _RealtimeTranscriptionModelDialogState();
}

class _RealtimeTranscriptionModelDialogState
    extends State<RealtimeTranscriptionModelDialog> {
  bool _closing = false;
  bool _allowPop = false;
  bool _unavailable = false;
  bool _downloadInFlight = false;

  bool get _busy => switch (widget.controller.installState.status) {
    RealtimeTranscriptionModelInstallStatus.starting ||
    RealtimeTranscriptionModelInstallStatus.installing ||
    RealtimeTranscriptionModelInstallStatus.cancelling => true,
    _ => false,
  };

  Future<void> _download() async {
    if (_downloadInFlight || _busy || _closing) return;
    _downloadInFlight = true;
    try {
      final outcome = await widget.controller.installOfferedModel();
      if (!mounted) return;
      if (outcome case final RealtimeTranscriptionModelSelected selected) {
        Navigator.of(context).pop(selected);
      } else if (outcome is RealtimeTranscriptionModelUnavailable) {
        setState(() => _unavailable = true);
      }
    } finally {
      _downloadInFlight = false;
    }
  }

  Future<void> _cancelAndClose() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await widget.controller.cancelInstall();
    } catch (_) {
      // The dialog still closes without launching the conversation. Controller
      // disposal makes one best-effort cancellation if Core did not confirm.
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  void _onPopInvoked(bool didPop) {
    if (didPop || _allowPop || !_busy) return;
    unawaited(_cancelAndClose());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.installState;
        final model = state.model ?? widget.model;
        final status = state.status;
        final busy = _busy;
        final failed =
            status == RealtimeTranscriptionModelInstallStatus.failed ||
            model.state == 'failed';
        final progress = state.progress;
        return PopScope<void>(
          canPop: _allowPop || !busy,
          onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
          child: AlertDialog(
            title: Text(l.text('transcriptionModelDownloadTitle')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ListenBreakpoints.formColumnMax,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.text('transcriptionModelDownloadExplainer')),
                  const SizedBox(height: ListenSpacing.gap12),
                  Text(
                    l
                        .text('transcriptionModelDownloadOffer')
                        .replaceAll('{name}', model.displayName)
                        .replaceAll(
                          '{size}',
                          _sizeInMegabytes(model.sizeBytes),
                        ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: ListenSpacing.gap8),
                  Text(
                    l.text('transcriptionModelDownloadVerify'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (busy) ...[
                    const SizedBox(height: ListenSpacing.gap16),
                    if (status ==
                        RealtimeTranscriptionModelInstallStatus.starting)
                      Text(l.text('transcriptionModelStarting'))
                    else if (status ==
                        RealtimeTranscriptionModelInstallStatus.cancelling)
                      Text(l.text('transcriptionModelCancelling'))
                    else
                      Text(
                        l
                            .text('transcriptionModelDownloading')
                            .replaceAll('{name}', model.displayName)
                            .replaceAll(
                              '{downloaded}',
                              _sizeInMegabytes(model.installedBytes),
                            )
                            .replaceAll(
                              '{total}',
                              _sizeInMegabytes(model.sizeBytes),
                            ),
                      ),
                    const SizedBox(height: ListenSpacing.gap8),
                    LinearProgressIndicator(value: progress),
                  ],
                  if (failed) ...[
                    const SizedBox(height: ListenSpacing.gap12),
                    Text(
                      l.text('transcriptionModelInstallFailed'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_unavailable) ...[
                    const SizedBox(height: ListenSpacing.gap12),
                    Text(l.text('transcriptionModelInstallUnavailable')),
                  ],
                ],
              ),
            ),
            actions: [
              if (busy)
                TextButton(
                  onPressed: _closing ? null : _cancelAndClose,
                  child: Text(
                    _closing
                        ? l.text('transcriptionModelCancelling')
                        : l.text('transcriptionModelCancelDownload'),
                  ),
                )
              else ...[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.text('cancel')),
                ),
                FilledButton(
                  onPressed: _unavailable ? null : _download,
                  child: Text(
                    failed || model.state == 'failed'
                        ? l.text('retry')
                        : l.text('transcriptionModelDownloadAction'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _sizeInMegabytes(int bytes) => (bytes / 1000000).toStringAsFixed(0);
}
