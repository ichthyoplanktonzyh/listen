import '../models/task_status.dart';
import '../models/timeline.dart';
import '../services/api_service.dart';
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
  });

  final PlayerController player;
  final SubtitleController subtitle;
  final SettingsController settings;

  late LocalApi? Function() getApi;
  late bool Function() isMounted;
  late void Function(String message) showSnackBar;
  late void Function(UserTaskStatus value) setTaskStatus;
  late Future<void> Function(String path) openMediaPath;
  late Future<void> Function(String path, {required bool secondary})
  openSubtitlePath;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required void Function(String message) showSnackBar,
    required void Function(UserTaskStatus value) setTaskStatus,
    required Future<void> Function(String path) openMediaPath,
    required Future<void> Function(String path, {required bool secondary})
    openSubtitlePath,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
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
    final service = getApi();
    if (service == null || _syntaxCapabilityCheckBusy) return;
    _syntaxCapabilityCheckBusy = true;
    try {
      final capability = await service.syntaxCapability();
      final ready = capability.isReady;
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
        await service.runTrackSyntaxAnalysis(trackId);
      }
    } catch (_) {
      // Optional capability monitoring never changes core playback state.
    } finally {
      _syntaxCapabilityCheckBusy = false;
    }
  }

  Future<void> ensureCurrentPronunciation(Cue? cue) async {
    final service = getApi();
    if (cue == null ||
        service == null ||
        subtitle.pronunciationBySentence.containsKey(cue.id)) {
      return;
    }
    try {
      final analysis = await service.analyzePronunciation(cue.id);
      if (isMounted() && subtitle.currentPrimaryCue?.id == cue.id) {
        subtitle.setSentencePronunciation(cue.id, analysis);
      }
    } catch (_) {
      // Pronunciation is optional and must never block playback.
    }
  }

  Future<void> analyzePhonetics({required bool wholeTrack}) async {
    final service = getApi();
    final track = subtitle.primaryTrack;
    final cue = subtitle.currentPrimaryCue;
    if (service == null || track == null || (!wholeTrack && cue == null)) {
      showSnackBar('No media or subtitle loaded');
      return;
    }
    try {
      final models = await service.phoneticAnalysisModels();
      final preferred = settings.settings.phoneticModelId;
      final model = models.cast<Map<String, dynamic>?>().firstWhere(
        (value) =>
            value != null &&
            (value['id'] == preferred ||
                (preferred.isEmpty &&
                    (value['state'] == 'installed' ||
                        value['state'] == 'custom'))),
        orElse: () => null,
      );
      if (model == null) {
        throw StateError('No compatible phonetic analysis model is available');
      }
      final job = await service.createPhoneticAnalysisJob(
        trackId: track.id,
        sentenceId: wholeTrack ? null : cue!.id,
        modelId: model['id'] as String,
      );
      if (isMounted()) {
        setTaskStatus(
          UserTaskStatus(
            kind: UserTaskKind.audioAnalysis,
            state: UserTaskState.working,
            rawStatus: job['status'] as String? ?? 'queued',
            progress: 0,
            targetId: track.id,
          ),
        );
        showSnackBar('Audio analysis ${job['status']}');
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
        showSnackBar('Audio analysis failed: $error');
      }
    }
  }

  Future<void> handleDrop(List<String> paths) async {
    final media = paths.where(isMediaPath).toList(growable: false);
    final subtitles = paths.where(isSubtitlePath).toList(growable: false);
    if (media.isNotEmpty) await openMediaPath(media.first);
    for (final path in subtitles) {
      if (player.mediaId == null || getApi() == null) {
        player.setStatus('Drop or open media before subtitles');
        return;
      }
      await openSubtitlePath(path, secondary: subtitle.primaryTrack != null);
    }
    if (media.isEmpty && subtitles.isEmpty) {
      player.setStatus('Unsupported dropped file type');
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
