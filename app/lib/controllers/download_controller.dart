import 'dart:async';

import 'package:flutter/foundation.dart';

import '../widgets/player/download_status_bar.dart';

/// Owns the full online-download lifecycle as a single source of truth.
///
/// This replaces the split state that used to live across `_PlayerScreenState`
/// (`activeDownload` + `downloadError` + `downloadGeneration`) and
/// `PlayerController` (`downloadProgress` + `downloadedMediaPath`), which could
/// disagree between frames (Phase 2.22 SM-03).
///
/// State machine:
///
/// ```
/// none --starting/attach--> downloading --complete--> completed
///                                        --error----> failed
/// downloading|completed|failed --cancel/dismiss--> none
/// ```
///
/// A monotonic [_generation] guard drops late progress/completion callbacks from
/// a cancelled, dismissed or superseded download, and a [_disposed] guard stops
/// notifications after the owning widget is gone (replacing the old `mounted`
/// checks). The controller depends only on plain `Stream`/`Future` primitives,
/// not on the concrete download service, so it is unit-testable.
class DownloadController extends ChangeNotifier {
  DownloadController({this.failedAutoDismiss = const Duration(seconds: 10)});

  /// How long a `failed` bar stays before it auto-dismisses. A `completed` bar
  /// intentionally persists so its "Open" action stays available (opening the
  /// media dismisses it).
  final Duration failedAutoDismiss;

  void Function()? _cancelActive;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _autoDismissTimer;
  int _generation = 0;
  bool _disposed = false;
  DownloadStatusSnapshot? _snapshot;

  /// Current typed download state, or `null` when no bar should show.
  DownloadStatusSnapshot? get snapshot => _snapshot;

  bool get isDownloading => _snapshot?.kind == DownloadStatusKind.downloading;

  /// Completed download path, if the bar is currently in the completed state.
  String? get downloadedMediaPath => _snapshot?.downloadedMediaPath;

  /// A new download is starting: bump the generation, drop any active handle
  /// and clear a stale completed/failed bar so it cannot linger.
  void starting() {
    _generation++;
    _disposeActive();
    _setSnapshot(null);
  }

  /// Attach a live download's [progress]/[completed] streams and its [cancel]
  /// handle, then wire them to the typed snapshot.
  ///
  /// [onCompleted]/[onFailed] are optional side effects (e.g. status text). They
  /// only fire for the current generation and while the controller is alive, so
  /// they cannot run after cancel/dismiss/dispose.
  void attach({
    required Stream<double> progress,
    required Future<String?> completed,
    required void Function() cancel,
    void Function(String path)? onCompleted,
    void Function(String error)? onFailed,
  }) {
    final generation = _generation;
    _cancelActive = cancel;
    _setSnapshot(const DownloadStatusSnapshot.downloading(progress: 0));
    _subscriptions.add(
      progress.listen((value) {
        if (_stale(generation)) return;
        _setSnapshot(DownloadStatusSnapshot.downloading(progress: value));
      }),
    );
    completed.then(
      (path) {
        if (_stale(generation)) return;
        _cancelActive = null;
        final trimmed = path?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          _setSnapshot(DownloadStatusSnapshot.completed(trimmed));
          onCompleted?.call(trimmed);
        } else {
          _setSnapshot(null);
        }
      },
      onError: (Object error) {
        if (_stale(generation)) return;
        _cancelActive = null;
        _setSnapshot(DownloadStatusSnapshot.failed(error.toString()));
        _scheduleFailedAutoDismiss();
        onFailed?.call(error.toString());
      },
    );
  }

  /// The download could not even start (e.g. the launch call threw).
  void fail(String error) {
    _cancelActive = null;
    _setSnapshot(DownloadStatusSnapshot.failed(error));
    _scheduleFailedAutoDismiss();
  }

  void _scheduleFailedAutoDismiss() {
    _autoDismissTimer?.cancel();
    final generation = _generation;
    _autoDismissTimer = Timer(failedAutoDismiss, () {
      if (_stale(generation)) return;
      if (_snapshot?.kind == DownloadStatusKind.failed) _setSnapshot(null);
    });
  }

  /// Cancel an in-flight download and hide the bar.
  void cancel() {
    _generation++;
    _disposeActive();
    _setSnapshot(null);
  }

  /// Dismiss a completed/failed bar (also safe on an in-flight download).
  void dismiss() => cancel();

  bool _stale(int generation) => _disposed || generation != _generation;

  void _setSnapshot(DownloadStatusSnapshot? value) {
    _snapshot = value;
    if (!_disposed) notifyListeners();
  }

  void _disposeActive() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _cancelActive?.call();
    _cancelActive = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeActive();
    super.dispose();
  }
}
