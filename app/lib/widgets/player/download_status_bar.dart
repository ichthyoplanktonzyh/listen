import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';

enum DownloadStatusKind { downloading, completed, failed }

class DownloadStatusSnapshot {
  const DownloadStatusSnapshot.downloading({required this.progress})
    : kind = DownloadStatusKind.downloading,
      downloadedMediaPath = null,
      failure = null;

  const DownloadStatusSnapshot.completed(this.downloadedMediaPath)
    : kind = DownloadStatusKind.completed,
      progress = 1.0,
      failure = null;

  /// A failed download carries a *typed* [ApiFailure], not the tool's own text.
  ///
  /// This used to be `String? error`, filled with `error.toString()`, and the
  /// bar below built `'${l.text('downloadFailed')}: ${status.error}'` out of
  /// it — so a failed download printed yt-dlp's raw stderr, or a whole
  /// `ProcessException` with the executable path in it, where a sentence
  /// belongs. Typing the field is what makes that unrepresentable: the only
  /// way to render the detail now is to reach into a named diagnostic field,
  /// and [ApiFailure.raw] is documented as never rendered.
  const DownloadStatusSnapshot.failed(this.failure)
    : kind = DownloadStatusKind.failed,
      progress = 1.0,
      downloadedMediaPath = null;

  final DownloadStatusKind kind;
  final double progress;
  final String? downloadedMediaPath;
  final ApiFailure? failure;
}

class DownloadStatusBar extends StatelessWidget {
  const DownloadStatusBar({
    super.key,
    required this.status,
    required this.onCancel,
    required this.onOpenMediaPath,
    required this.onDismiss,
  });

  final DownloadStatusSnapshot status;
  final VoidCallback onCancel;
  final VoidCallback onOpenMediaPath;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final downloading = status.kind == DownloadStatusKind.downloading;
    final completed = status.kind == DownloadStatusKind.completed;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.download, size: ListenIconSize.control),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: LinearProgressIndicator(
                value: downloading
                    ? status.progress.clamp(0.0, 1.0).toDouble()
                    : 1.0,
              ),
            ),
            const SizedBox(width: ListenSpacing.gap12),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                switch (status.kind) {
                  DownloadStatusKind.downloading =>
                    '${l.text('downloadingInBackground')} ${(status.progress * 100).toStringAsFixed(1)}%',
                  DownloadStatusKind.completed => l.text('downloadComplete'),
                  DownloadStatusKind.failed => l.text('downloadFailed'),
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: ListenSpacing.gap12),
            // One line has no room to expand in place, so the diagnostics open
            // as a dialog. It appears only when there is something to show.
            if (status.failure != null)
              ApiFailureDetailsButton(failure: status.failure!),
            if (downloading)
              TextButton(onPressed: onCancel, child: Text(l.text('cancel'))),
            if (completed)
              TextButton(
                onPressed: onOpenMediaPath,
                child: Text(l.text('openDownloadedVideo')),
              ),
            IconButton(onPressed: onDismiss, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}
