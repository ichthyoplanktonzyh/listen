import 'package:flutter/material.dart';

import '../../localization.dart';

enum DownloadStatusKind { downloading, completed, failed }

class DownloadStatusSnapshot {
  const DownloadStatusSnapshot.downloading({required this.progress})
    : kind = DownloadStatusKind.downloading,
      downloadedMediaPath = null,
      error = null;

  const DownloadStatusSnapshot.completed(this.downloadedMediaPath)
    : kind = DownloadStatusKind.completed,
      progress = 1.0,
      error = null;

  const DownloadStatusSnapshot.failed(this.error)
    : kind = DownloadStatusKind.failed,
      progress = 1.0,
      downloadedMediaPath = null;

  final DownloadStatusKind kind;
  final double progress;
  final String? downloadedMediaPath;
  final String? error;
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
            const Icon(Icons.download, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: LinearProgressIndicator(
                value: downloading
                    ? status.progress.clamp(0.0, 1.0).toDouble()
                    : 1.0,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                switch (status.kind) {
                  DownloadStatusKind.downloading =>
                    '${l.text('downloadingInBackground')} ${(status.progress * 100).toStringAsFixed(1)}%',
                  DownloadStatusKind.completed => l.text('downloadComplete'),
                  DownloadStatusKind.failed =>
                    '${l.text('downloadFailed')}: ${status.error}',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
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
