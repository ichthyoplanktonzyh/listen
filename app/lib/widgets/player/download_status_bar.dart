import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../services/external_tools.dart';

class DownloadStatusBar extends StatelessWidget {
  const DownloadStatusBar({
    super.key,
    this.activeDownload,
    required this.downloadProgress,
    this.downloadedMediaPath,
    required this.onCancel,
    required this.onOpenMediaPath,
    required this.onDismiss,
  });

  final OnlineMediaDownload? activeDownload;
  final double downloadProgress;
  final String? downloadedMediaPath;
  final VoidCallback onCancel;
  final VoidCallback onOpenMediaPath;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: const Color(0xff18232b),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.download, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: LinearProgressIndicator(
                value: activeDownload == null ? 1 : downloadProgress,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              activeDownload == null
                  ? l.text('downloadComplete')
                  : '${l.text('downloadingInBackground')} ${(downloadProgress * 100).toStringAsFixed(1)}%',
            ),
            const SizedBox(width: 12),
            if (activeDownload != null)
              TextButton(
                onPressed: onCancel,
                child: Text(l.text('cancel')),
              ),
            if (downloadedMediaPath != null)
              TextButton(
                onPressed: onOpenMediaPath,
                child: Text(l.text('openDownloadedVideo')),
              ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
