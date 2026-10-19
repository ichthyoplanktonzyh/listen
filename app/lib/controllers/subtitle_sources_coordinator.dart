import '../data/repositories/subtitle_analysis_repository.dart';
import '../models/task_status.dart';
import '../models/timeline.dart';
import 'player_controller.dart';
import 'settings_controller.dart';
import 'subtitle_controller.dart';

/// Owns the context-free subtitle-source actions: dropped-file routing,
/// media/subtitle path classification, on-demand pronunciation, and phonetic
/// analysis job dispatch. Extracted verbatim from `_PlayerScreenState`
/// (main.dart decomposition); dialog-driven source flows stay in the host
/// per the codebase convention (coordinators never touch BuildContext).
class SubtitleSourcesCoordinator {
  SubtitleSourcesCoordinator({
    required this.player,
    required this.subtitle,
    required this.settings,
    required this.repository,
  });

  final PlayerController player;
  final SubtitleController subtitle;
  final SettingsController settings;
  final SubtitleAnalysisRepository repository;

  late bool Function() isMounted;
  String Function(String key)? text;

  String _t(String key) => text?.call(key) ?? key;
  late void Function(String message) showSnackBar;
  late void Function(UserTaskStatus value) setTaskStatus;
  late Future<void> Function(String path) openMediaPath;
  late Future<void> Function(String path, {required bool secondary})
  openSubtitlePath;

  void bind({
    required bool Function() isMounted,
    String Function(String key)? text,
    required void Function(String message) showSnackBar,
    required void Function(UserTaskStatus value) setTaskStatus,
    required Future<void> Function(String path) openMediaPath,
    required Future<void> Function(String path, {required bool secondary})
    openSubtitlePath,
  }) {
    this.isMounted = isMounted;
    this.text = text;
    this.showSnackBar = showSnackBar;
    this.setTaskStatus = setTaskStatus;
    this.openMediaPath = openMediaPath;
    this.openSubtitlePath = openSubtitlePath;
  }

  bool _syntaxCapabilityCheckBusy = false;
  bool _syntaxCapabilityWasReady = false;
  String? _syntaxAnalyzedTrackId;

  /// Polled capability monitor: once the optional syntax capability reports
  /// ready, runs whole-track analysis for the current primary track exactly
  /// once per track.
  Future<void> checkSyntaxCapability() async {
    if (!repository.isAvailable || _syntaxCapabilityCheckBusy) return;
    _syntaxCapabilityCheckBusy = true;
    try {
      final ready = await repository.syntaxReady();
      if (!ready) {
        _syntaxCapabilityWasReady = false;
        _syntaxAnalyzedTrackId = null;
        return;
      }
      final trackId = subtitle.primaryTrack?.id;
      if (trackId == null) return;
      if (!_syntaxCapabilityWasReady || _syntaxAnalyzedTrackId != trackId) {
        _syntaxCapabilityWasReady = true;
        _syntaxAnalyzedTrackId = trackId;
        await repository.analyzeTrackSyntax(trackId);
      }
    } catch (_) {
      // Optional capability monitoring never changes core playback state.
    } finally {
      _syntaxCapabilityCheckBusy = false;
    }
  }

  Future<void> ensureCurrentPronunciation(Cue? cue) async {
    if (cue == null ||
        !repository.isAvailable ||
        subtitle.pronunciationBySentence.containsKey(cue.id)) {
      return;
    }
    try {
      final analysis = await repository.analyzePronunciation(cue.id);
      if (isMounted() && subtitle.currentPrimaryCue?.id == cue.id) {
        subtitle.setSentencePronunciation(cue.id, analysis);
      }
    } catch (_) {
      // Pronunciation is optional and must never block playback.
    }
  }

  Future<void> analyzePhonetics({required bool wholeTrack}) async {
    final track = subtitle.primaryTrack;
    final cue = subtitle.currentPrimaryCue;
    if (!repository.isAvailable ||
        track == null ||
        (!wholeTrack && cue == null)) {
      showSnackBar('No media or subtitle loaded');
      return;
    }
    try {
      final status = await repository.startPhoneticAnalysis(
        trackId: track.id,
        sentenceId: wholeTrack ? null : cue!.id,
        preferredModelId: settings.settings.phoneticModelId,
      );
      if (isMounted()) {
        setTaskStatus(
          UserTaskStatus(
            kind: UserTaskKind.audioAnalysis,
            state: UserTaskState.working,
            rawStatus: status,
            progress: 0,
            targetId: track.id,
          ),
        );
        showSnackBar('Audio analysis $status');
      }
    } catch (error) {
      if (isMounted()) {
        setTaskStatus(
          UserTaskStatus(
            kind: UserTaskKind.audioAnalysis,
            state: UserTaskState.error,
            rawStatus: 'failed',
            progress: 0,
            targetId: track.id,
          ),
        );
        showSnackBar(_t('statusAudioAnalysisFailed'));
      }
    }
  }

  Future<void> handleDrop(List<String> paths) async {
    final media = paths.where(isMediaPath).toList(growable: false);
    final subtitles = paths.where(isSubtitlePath).toList(growable: false);
    if (media.isNotEmpty) await openMediaPath(media.first);
    for (final path in subtitles) {
      if (player.mediaId == null || !repository.isAvailable) {
        player.setStatus(_t('statusDropMediaFirst'));
        return;
      }
      await openSubtitlePath(path, secondary: subtitle.primaryTrack != null);
    }
    if (media.isEmpty && subtitles.isEmpty) {
      player.setStatus(_t('statusUnsupportedDrop'), error: true);
    }
  }

  bool isMediaPath(String path) => const {
    'mp4',
    'mkv',
    'mov',
    'webm',
    'm4a',
    'mp3',
    'wav',
    'flac',
  }.contains(path.split('.').last.toLowerCase());

  bool isSubtitlePath(String path) =>
      const {'srt', 'vtt'}.contains(path.split('.').last.toLowerCase());
}
