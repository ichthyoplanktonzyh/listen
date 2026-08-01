import 'api_failure.dart';

/// The mutually exclusive presentation states of an online download.
enum DownloadStatusKind { downloading, completed, failed }

/// Immutable state exposed by [DownloadController] to download status views.
///
/// This presentation model lives outside the widget layer so the controller
/// remains independent of the concrete view that renders it.
class DownloadStatusSnapshot {
  const DownloadStatusSnapshot.downloading({required this.progress})
    : kind = DownloadStatusKind.downloading,
      downloadedMediaPath = null,
      failure = null;

  const DownloadStatusSnapshot.completed(this.downloadedMediaPath)
    : kind = DownloadStatusKind.completed,
      progress = 1.0,
      failure = null;

  /// A failed download carries a typed failure rather than user-facing text.
  ///
  /// Diagnostic details remain available to an explicit disclosure view, but
  /// cannot accidentally become part of the status sentence.
  const DownloadStatusSnapshot.failed(this.failure)
    : kind = DownloadStatusKind.failed,
      progress = 1.0,
      downloadedMediaPath = null;

  final DownloadStatusKind kind;
  final double progress;
  final String? downloadedMediaPath;
  final ApiFailure? failure;
}
