import 'package:flutter/foundation.dart';

import '../models/api_failure.dart';
import '../models/named_failure.dart';
import '../player_adapter.dart';
import '../state/store.dart';

const _unset = Object();

/// Immutable snapshot of playback state.
/// Used by [PlayerController] to notify listeners.
class PlayerState {
  PlayerState({
    this.mediaId,
    this.mediaPath,
    this.mediaTitle,
    this.mediaFingerprint,
    this.mediaRetained,
    this.retentionInFlight = false,
    this.status = 'Starting local core...',
    this.statusIsError = false,
    this.statusIsPlayback = false,
    this.statusFailure,
    this.duration = Duration.zero,
    this.playing = false,
    this.muted = false,
    this.rate = 1.0,
    this.volume = 100.0,
    List<PlayerTrack> audioTracks = const [],
    this.selectedAudioId,
    List<PlayerTrack> embeddedSubtitleTracks = const [],
    this.selectedEmbeddedSubtitleId,
    this.sourceLoopStart,
    this.sourceLoopEnd,
    this.sourceLoopLabel,
  }) : _audioTracks = List.unmodifiable(audioTracks),
       _embeddedSubtitleTracks = List.unmodifiable(embeddedSubtitleTracks);

  final String? mediaId;
  final String? mediaPath;
  final String? mediaTitle;
  final String? mediaFingerprint;

  /// Whether the current media is in the Personal Library. Null before the
  /// media has been registered with Core, or when Core is unreachable.
  final bool? mediaRetained;

  /// A Keep / unretain / reference operation is running right now. The
  /// affordance uses it for in-flight feedback and to refuse re-entry.
  final bool retentionInFlight;
  final String status;

  /// Whether [status] describes a failure. Error statuses get error styling
  /// in the status line and are surfaced once via SnackBar.
  final bool statusIsError;

  /// Whether [status] merely reports what is playing. Surfaces that show
  /// system health (the home "local core" tile) hide these, since playback
  /// chatter says nothing about the core. Never match on the text to decide
  /// this — [status] is localized.
  final bool statusIsPlayback;

  /// The transport detail behind an error [status], when the failure came from
  /// the backend.
  ///
  /// Kept beside the sentence rather than inside it. [status] used to be built
  /// as `'${text('statusX')}: $error'`, which put an internal error code, a
  /// `correlation_id` and the sidecar's loopback URI on the status line; the
  /// sentence is now the whole message, and everything the exception carried
  /// lives here as a typed value a diagnostics disclosure can read.
  /// `ApiFailure.raw` is not rendered even then.
  final ApiFailure? statusFailure;
  final Duration duration;
  final bool playing;
  final bool muted;
  final double rate;
  final double volume;
  final List<PlayerTrack> _audioTracks;
  List<PlayerTrack> get audioTracks => List.unmodifiable(_audioTracks);
  final String? selectedAudioId;
  final List<PlayerTrack> _embeddedSubtitleTracks;
  List<PlayerTrack> get embeddedSubtitleTracks =>
      List.unmodifiable(_embeddedSubtitleTracks);
  final String? selectedEmbeddedSubtitleId;
  final Duration? sourceLoopStart;
  final Duration? sourceLoopEnd;
  final String? sourceLoopLabel;

  PlayerState copyWith({
    Object? mediaId = _unset,
    Object? mediaPath = _unset,
    Object? mediaTitle = _unset,
    Object? mediaFingerprint = _unset,
    Object? mediaRetained = _unset,
    bool? retentionInFlight,
    String? status,
    bool? statusIsError,
    bool? statusIsPlayback,
    Object? statusFailure = _unset,
    Duration? duration,
    bool? playing,
    bool? muted,
    double? rate,
    double? volume,
    List<PlayerTrack>? audioTracks,
    Object? selectedAudioId = _unset,
    List<PlayerTrack>? embeddedSubtitleTracks,
    Object? selectedEmbeddedSubtitleId = _unset,
    Object? sourceLoopStart = _unset,
    Object? sourceLoopEnd = _unset,
    Object? sourceLoopLabel = _unset,
  }) => PlayerState(
    mediaId: identical(mediaId, _unset) ? this.mediaId : mediaId as String?,
    mediaPath: identical(mediaPath, _unset)
        ? this.mediaPath
        : mediaPath as String?,
    mediaTitle: identical(mediaTitle, _unset)
        ? this.mediaTitle
        : mediaTitle as String?,
    mediaFingerprint: identical(mediaFingerprint, _unset)
        ? this.mediaFingerprint
        : mediaFingerprint as String?,
    mediaRetained: identical(mediaRetained, _unset)
        ? this.mediaRetained
        : mediaRetained as bool?,
    retentionInFlight: retentionInFlight ?? this.retentionInFlight,
    status: status ?? this.status,
    statusIsError: statusIsError ?? this.statusIsError,
    statusIsPlayback: statusIsPlayback ?? this.statusIsPlayback,
    statusFailure: identical(statusFailure, _unset)
        ? this.statusFailure
        : statusFailure as ApiFailure?,
    duration: duration ?? this.duration,
    playing: playing ?? this.playing,
    muted: muted ?? this.muted,
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
    audioTracks: audioTracks ?? this.audioTracks,
    selectedAudioId: identical(selectedAudioId, _unset)
        ? this.selectedAudioId
        : selectedAudioId as String?,
    embeddedSubtitleTracks:
        embeddedSubtitleTracks ?? this.embeddedSubtitleTracks,
    selectedEmbeddedSubtitleId: identical(selectedEmbeddedSubtitleId, _unset)
        ? this.selectedEmbeddedSubtitleId
        : selectedEmbeddedSubtitleId as String?,
    sourceLoopStart: identical(sourceLoopStart, _unset)
        ? this.sourceLoopStart
        : sourceLoopStart as Duration?,
    sourceLoopEnd: identical(sourceLoopEnd, _unset)
        ? this.sourceLoopEnd
        : sourceLoopEnd as Duration?,
    sourceLoopLabel: identical(sourceLoopLabel, _unset)
        ? this.sourceLoopLabel
        : sourceLoopLabel as String?,
  );
}

/// Controls media playback state and actions.
///
/// Uses [Store] internally for fine-grained reactive state.
/// Keeps [ChangeNotifier] for backward compatibility.
class PlayerController extends ChangeNotifier {
  final Store<PlayerState> _store;

  /// Playback position ticks ~10x/sec while media plays, so it lives outside
  /// [PlayerState]: writes go to this dedicated notifier and deliberately do
  /// NOT fire the aggregate [ChangeNotifier]. Widgets that render the live
  /// position must subscribe via [positionListenable]; everything else reads
  /// the [position] getter synchronously.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  PlayerController() : _store = Store(PlayerState()) {
    _store.addListener(notifyListeners);
  }

  /// The reactive store — allows fine-grained field subscriptions via [Store.select].
  Store<PlayerState> get store => _store;

  /// The current immutable state snapshot.
  PlayerState get state => _store.state;

  // ── Convenience accessors ──

  String? get mediaId => _store.state.mediaId;
  String? get mediaPath => _store.state.mediaPath;
  String? get mediaTitle => _store.state.mediaTitle;
  String? get mediaFingerprint => _store.state.mediaFingerprint;
  bool? get mediaRetained => _store.state.mediaRetained;
  bool get retentionInFlight => _store.state.retentionInFlight;
  String get status => _store.state.status;
  bool get statusIsError => _store.state.statusIsError;
  bool get statusIsPlayback => _store.state.statusIsPlayback;
  ApiFailure? get statusFailure => _store.state.statusFailure;
  bool get playing => _store.state.playing;
  bool get muted => _store.state.muted;
  Duration get position => _position.value;
  Duration get duration => _store.state.duration;

  /// High-frequency playback position for widgets that render it live.
  ValueListenable<Duration> get positionListenable => _position;
  double get rate => _store.state.rate;
  double get volume => _store.state.volume;
  Duration? get sourceLoopStart => _store.state.sourceLoopStart;
  Duration? get sourceLoopEnd => _store.state.sourceLoopEnd;
  String? get sourceLoopLabel => _store.state.sourceLoopLabel;
  List<PlayerTrack> get audioTracks => _store.state.audioTracks;
  String? get selectedAudioId => _store.state.selectedAudioId;
  List<PlayerTrack> get embeddedSubtitleTracks =>
      _store.state.embeddedSubtitleTracks;
  String? get selectedEmbeddedSubtitleId =>
      _store.state.selectedEmbeddedSubtitleId;

  /// Create a [ValueNotifier] that tracks a specific derived value.
  /// The notifier only fires when the selected value changes.
  ValueNotifier<R> select<R>(R Function(PlayerState) selector) =>
      _store.select(selector);

  void setPosition(Duration position) => _position.value = position;

  void setDuration(Duration duration) =>
      _store.update((s) => s.copyWith(duration: duration));

  void setPlaying(bool playing) =>
      _store.update((s) => s.copyWith(playing: playing));

  /// Set media metadata after a successful open.
  void setMedia({
    required String id,
    required String path,
    required String title,
    required String fingerprint,
  }) {
    _store.update(
      (s) => s.copyWith(
        mediaId: id,
        mediaPath: path,
        mediaTitle: title,
        mediaFingerprint: fingerprint,
      ),
    );
  }

  void clearMedia() => _store.update(
    (s) => s.copyWith(
      mediaId: null,
      mediaPath: null,
      mediaTitle: null,
      mediaFingerprint: null,
      mediaRetained: null,
    ),
  );

  /// Records whether the current media is in the Personal Library. Set after
  /// registration, Keep, reference-in-place, and unretain — never guessed.
  void setMediaRetained(bool? retained) =>
      _store.update((s) => s.copyWith(mediaRetained: retained));

  /// Marks a retention operation as running. Guards the affordance against
  /// re-entry and drives its in-flight presentation.
  void setRetentionInFlight(bool inFlight) =>
      _store.update((s) => s.copyWith(retentionInFlight: inFlight));

  void setMuted(bool muted) => _store.update((s) => s.copyWith(muted: muted));

  void setRate(double rate) => _store.update((s) => s.copyWith(rate: rate));

  void setVolume(double volume) =>
      _store.update((s) => s.copyWith(volume: volume));

  /// Publish a status-line message. Pass [error] for failures so the UI can
  /// style the line and surface a SnackBar; plain progress updates clear the
  /// error flag. Pass [playback] for "now playing" notices so health
  /// indicators can skip them without matching on localized text.
  ///
  /// [status] is the whole message. Pass [failure] — from `describeApiFailure`
  /// — instead of appending the exception to it: the detail then reaches
  /// [PlayerState.statusFailure] as a typed value rather than the status line
  /// as prose. Every call replaces the previous detail, so a later success
  /// cannot leave a stale failure attached to a healthy status.
  void setStatus(
    String status, {
    bool error = false,
    bool playback = false,
    ApiFailure? failure,
  }) => _store.update(
    (s) => s.copyWith(
      status: status,
      statusIsError: error,
      statusIsPlayback: playback,
      statusFailure: failure,
    ),
  );

  /// Publish a [NamedFailure] — the shape [DesktopPlayerAdapter.errors] emits
  /// — on the status line, localizing its key through [text].
  ///
  /// The seam exists so the composition root does not have to unpack a failure
  /// by hand. It had one line for this (`setStatus(value)`, `value` being a
  /// sentence the adapter had already concatenated an exception into), and a
  /// line in `main.dart` is a line no test can reach.
  void setNamedFailure(
    NamedFailure failure,
    String Function(String key) text,
  ) =>
      setStatus(text(failure.messageKey), error: true, failure: failure.detail);

  void setAudioTracks(List<PlayerTrack> tracks) =>
      _store.update((s) => s.copyWith(audioTracks: tracks));

  void setSelectedAudioId(String? id) =>
      _store.update((s) => s.copyWith(selectedAudioId: id));

  void setEmbeddedSubtitleTracks(List<PlayerTrack> tracks) =>
      _store.update((s) => s.copyWith(embeddedSubtitleTracks: tracks));

  void setSelectedEmbeddedSubtitleId(String? id) =>
      _store.update((s) => s.copyWith(selectedEmbeddedSubtitleId: id));

  void setSourceLoop(Duration? start, Duration? end, {String? label}) =>
      _store.update(
        (s) => s.copyWith(
          sourceLoopStart: start,
          sourceLoopEnd: end,
          sourceLoopLabel: start != null ? label : null,
        ),
      );

  void setMediaPath(String path) =>
      _store.update((s) => s.copyWith(mediaPath: path));

  @override
  void dispose() {
    _position.dispose();
    _store.dispose();
    super.dispose();
  }
}
