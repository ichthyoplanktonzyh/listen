import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'localization.dart';
import 'm18_ui.dart';
import 'player_adapter.dart';
import 'settings.dart';
import 'transcription_ui.dart';

import 'models/timeline.dart';
import 'services/api_service.dart';
import 'services/external_tools.dart';
import 'controllers/app_controllers.dart';
import 'controllers/player_controller.dart';
import 'controllers/subtitle_controller.dart';
import 'controllers/learning_controller.dart';
import 'controllers/settings_controller.dart';
import 'utils/subtitle_style.dart';
import 'utils/word_list_parser.dart';
import 'widgets/subtitle/token_line.dart';
import 'widgets/panels/word_learning_panel.dart';
import 'screens/vocabulary_screen.dart';
import 'widgets/panels/diagnosis_card.dart';
import 'widgets/panels/transcript_panel.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/app_bar/player_app_bar.dart';
import 'widgets/player/playback_controls.dart';
import 'widgets/settings/settings_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final bundledFfmpeg =
      '${File(Platform.resolvedExecutable).parent.parent.path}'
      '/Frameworks/mdk.framework/Versions/A/libffmpeg.8.dylib';
  fvp.registerWith(
    options: {
      'platforms': ['macos'],
      'global': {'ffmpeg': bundledFfmpeg, 'libffmpeg': bundledFfmpeg},
    },
  );
  runApp(const LLPlayerNextApp());
}

class LLPlayerNextApp extends StatelessWidget {
  const LLPlayerNextApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: appLanguage,
    builder: (context, language, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LLPlayerNext',
      locale: language == 'system' ? null : Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff6dd6c3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PlayerScreen(),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // ── Service / infrastructure handles ──
  final adapter = DesktopPlayerAdapter();
  final transcriptController = ScrollController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? progressTimer;
  LocalApi? api;

  // ── Controllers ──
  final playerController = PlayerController();
  final subtitleController = SubtitleController();
  final learningController = LearningController();
  final settingsController = SettingsController();

  // ── Local UI state (not managed by controllers) ──
  String status = 'Starting local core...';
  OnlineMediaDownload? activeDownload;
  bool dragging = false;

  // ── Convenience ──
  AppLocalizations get l => AppLocalizations.of(context);

  ExternalTools get tools => ExternalTools(
    ffmpegPath: settingsController.ffmpegPath,
    ffprobePath: settingsController.ffprobePath,
    ytDlpPath: settingsController.ytDlpPath,
  );
  double get transcriptItemExtent => 76;

  // Tracks the last primary cue id for de-duplicating async calls in _onPosition.
  String? _lastPrimaryCueId;

  @override
  void initState() {
    super.initState();
    unawaited(_connectApi());
    unawaited(_loadSettings());
    subscriptions.addAll([
      adapter.position.listen(_onPosition),
      adapter.duration.listen((value) {
        playerController.setDuration(value);
      }),
      adapter.playing.listen((value) {
        playerController.setPlaying(value);
      }),
      adapter.errors.listen((value) {
        setState(() => status = value);
        playerController.setStatus(value);
      }),
      adapter.tracks.listen((value) {
        if (!mounted) return;
        String? defaultId;
        for (final track in value.audio) {
          if (track.isDefault == true) {
            defaultId = track.id;
            break;
          }
        }
        playerController.setAudioTracks(value.audio);
        playerController.setSelectedAudioId(defaultId);
        playerController.setEmbeddedSubtitleTracks(value.subtitle);
      }),
    ]);
  }

  Future<void> _loadSettings() async {
    await settingsController.load();
    if (!mounted) return;
    final s = settingsController.settings;
    // Sync to subtitle controller
    subtitleController.setPrimarySubtitleOffset(
      Duration(milliseconds: s.primarySubtitleOffsetMs),
    );
    subtitleController.setSecondarySubtitleOffset(
      Duration(milliseconds: s.secondarySubtitleOffsetMs),
    );
    subtitleController.setVisible(s.subtitlesVisible);
    subtitleController.setSecondaryVisible(s.secondarySubtitlesVisible);
    subtitleController.setStatusStylesVisible(s.statusStylesVisible);
    subtitleController.setPrimaryFontSize(s.primaryFontSize);
    subtitleController.setSecondaryFontSize(s.secondaryFontSize);
    subtitleController.setPrimaryFontFamily(s.primaryFontFamily);
    subtitleController.setSecondaryFontFamily(s.secondaryFontFamily);
    subtitleController.setPreset(s.subtitlePreset);
    subtitleController.setPositionX(s.subtitlePositionX);
    subtitleController.setPositionY(s.subtitlePositionY);
    subtitleController.setBackgroundOpacity(s.subtitleBackgroundOpacity);
    // Sync to player controller
    playerController.setRate(s.rate);
    playerController.setVolume(s.volume);
    appLanguage.value = s.language;
    await adapter.setRate(playerController.rate);
    await adapter.setVolume(playerController.volume);
  }

  Future<void> _saveSettings() => settingsController.update(
    AppSettings(
      rate: playerController.rate,
      volume: playerController.volume,
      primarySubtitleOffsetMs:
          subtitleController.primarySubtitleOffset.inMilliseconds,
      secondarySubtitleOffsetMs:
          subtitleController.secondarySubtitleOffset.inMilliseconds,
      subtitlesVisible: subtitleController.visible,
      secondarySubtitlesVisible: subtitleController.secondaryVisible,
      statusStylesVisible: subtitleController.statusStylesVisible,
      primaryFontSize: subtitleController.primaryFontSize,
      secondaryFontSize: subtitleController.secondaryFontSize,
      primaryFontFamily: subtitleController.primaryFontFamily,
      secondaryFontFamily: subtitleController.secondaryFontFamily,
      subtitlePreset: subtitleController.preset,
      language: settingsController.language,
      subtitlePositionX: subtitleController.positionX,
      subtitlePositionY: subtitleController.positionY,
      subtitleBackgroundOpacity: subtitleController.backgroundOpacity,
      primaryColor: settingsController.primaryColor.toARGB32(),
      secondaryColor: settingsController.secondaryColor.toARGB32(),
      transcriptWidth: settingsController.transcriptWidth,
      ffmpegPath: settingsController.ffmpegPath,
      ffprobePath: settingsController.ffprobePath,
      ytDlpPath: settingsController.ytDlpPath,
      transcriptionQuality: settingsController.transcriptionQuality,
      transcriptionLanguage: settingsController.transcriptionLanguage,
      transcriptionDestination: settingsController.transcriptionDestination,
      openSubtitlesApiKey: settingsController.openSubtitlesApiKey,
      pronunciationVisible: settingsController.pronunciationVisible,
      wordSyncVisible: settingsController.wordSyncVisible,
      phonemeDisplay: settingsController.phonemeDisplay,
      wordAnimationIntensity: settingsController.wordAnimationIntensity,
      ruleHintsLevel: settingsController.ruleHintsLevel,
      precomputePronunciation: settingsController.precomputePronunciation,
    ),
  );

  Future<void> _connectApi() async {
    try {
      final value = await LocalApi.connect();
      if (!mounted) return value.close();
      setState(() {
        api = value;
        status = 'Local core connected';
      });
      subscriptions.add(value.events().listen(_onEvent));
      progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (playerController.mediaId != null) {
          unawaited(
            api?.saveProgress(
              playerController.mediaId!,
              playerController.position,
            ),
          );
        }
      });
      unawaited(_runSmokeIfConfigured());
    } catch (error) {
      if (mounted) setState(() => status = 'Core unavailable: $error');
    }
  }

  Future<void> _runSmokeIfConfigured() async {
    final media = Platform.environment['LLPLAYERNEXT_SMOKE_MEDIA'];
    final subtitle = Platform.environment['LLPLAYERNEXT_SMOKE_SUBTITLE'];
    final secondary =
        Platform.environment['LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE'];
    if (media == null) return;
    await _openMediaPath(media);
    if (subtitle != null) await _openSubtitlePath(subtitle, secondary: false);
    if (secondary != null) await _openSubtitlePath(secondary, secondary: true);
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['event'] == 'service-started') {
      unawaited(_loadWordProfiles());
      return;
    }
    if (event['event'] == 'transcription-job-changed') {
      final job = event['payload'] as Map<String, dynamic>;
      if (job['status'] == 'completed' &&
          job['media_id'] == playerController.mediaId &&
          job['generated_track_id'] != null) {
        unawaited(
          api!
              .readSubtitle(job['generated_track_id'] as String)
              .then(
                (track) => _loadGeneratedTrack(
                  track,
                  job['destination'] == 'secondary',
                ),
              ),
        );
      } else if (mounted && job['media_id'] == playerController.mediaId) {
        setState(
          () => status =
              'ASR ${job['status']} · ${job['phase_progress'] as int}%',
        );
      }
      return;
    }
    if (event['event'] != 'word-profile-changed') return;
    final profile = event['payload'] as Map<String, dynamic>;
    learningController.updateSingleWordProfile(
      profile['normalized_lemma'] as String,
      profile,
    );
  }

  void _onPosition(Duration value) {
    subtitleController.updatePosition(value);
    subtitleController.updateCurrentWord(
      value,
      enabled: settingsController.wordSyncVisible,
    );

    final primaryCue = subtitleController.currentPrimaryCue;
    if (subtitleController.loopCue &&
        primaryCue != null &&
        value >= subtitleController.primaryCursor.mediaEnd(primaryCue)) {
      unawaited(
        adapter.seek(subtitleController.primaryCursor.mediaStart(primaryCue)),
      );
      return;
    }
    if (playerController.sourceLoopStart != null &&
        playerController.sourceLoopEnd != null &&
        value >= playerController.sourceLoopEnd!) {
      unawaited(adapter.seek(playerController.sourceLoopStart!));
      return;
    }
    if (primaryCue?.id != _lastPrimaryCueId) {
      _lastPrimaryCueId = primaryCue?.id;
      _keepCurrentVisible(primaryCue);
      unawaited(_refreshDiagnosis());
      unawaited(_loadPhraseCandidates(primaryCue));
      unawaited(_ensureCurrentPronunciation(primaryCue));
    }
    playerController.setPosition(value);
  }

  Future<void> _openMedia() async {
    const group = XTypeGroup(
      label: 'media',
      extensions: ['mp4', 'mkv', 'mov', 'webm', 'm4a', 'mp3', 'wav', 'flac'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    await _openMediaPath(file.path);
  }

  Future<void> _openMediaPath(String path) async {
    final previousMediaId = playerController.mediaId;
    final previousPosition = playerController.position;
    final previousProgressSave = previousMediaId == null
        ? Future<void>.value()
        : api?.saveProgress(previousMediaId, previousPosition) ??
              Future<void>.value();
    setState(() {
      status = 'Opening ${path.split(Platform.pathSeparator).last}';
    });
    playerController.clearMedia();
    playerController.setMediaPath(path);
    playerController.setPosition(Duration.zero);
    playerController.setDuration(Duration.zero);
    subtitleController.setPrimaryTrack(null);
    subtitleController.setSecondaryTrack(null);
    subtitleController.setCurrentPrimaryCue(null);
    subtitleController.setCurrentSecondaryCue(null);
    subtitleController.clearSpeechEnhancements();
    playerController.setSourceLoop(null, null);
    try {
      await adapter.open(path, play: false);
    } catch (error) {
      if (mounted) setState(() => status = 'Playback failed: $error');
      return;
    }
    Object? coreError;
    try {
      await previousProgressSave;
      final media = await api?.registerMedia(path);
      if (media != null) {
        final id = media['id'] as String;
        final saved = await api?.readProgress(id);
        playerController.setMedia(
          id: id,
          path: path,
          title: media['title'] as String,
          fingerprint: media['fingerprint'] as String,
        );
        if (saved != null && saved > Duration.zero) {
          await adapter.seek(saved);
          playerController.setPosition(saved);
        }
      }
    } catch (error) {
      coreError = error;
    }
    try {
      await adapter.play();
      if (mounted) {
        setState(
          () => status = coreError == null
              ? 'Playing ${path.split(Platform.pathSeparator).last}'
              : 'Playing locally; core unavailable: $coreError',
        );
      }
    } catch (error) {
      if (mounted) setState(() => status = 'Playback failed: $error');
    }
  }

  Future<void> _openSubtitle({required bool secondary}) async {
    if (playerController.mediaId == null || api == null) {
      setState(() => status = 'Open media and connect the local core first');
      return;
    }
    const group = XTypeGroup(label: 'subtitles', extensions: ['srt', 'vtt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    await _openSubtitlePath(file.path, secondary: secondary);
  }

  Future<void> _openSubtitlePath(String path, {required bool secondary}) async {
    try {
      final value = await api!.importSubtitle(playerController.mediaId!, path);
      await adapter.disableNativeSubtitles();
      final imported = SubtitleTrack.fromJson(value);
      if (secondary) {
        subtitleController.setSecondaryTrack(imported);
        subtitleController.setCurrentSecondaryCue(
          subtitleController.secondaryCursor.current(playerController.position),
        );
      } else {
        subtitleController.clearSpeechEnhancements();
        subtitleController.setPrimaryTrack(imported);
        subtitleController.setCurrentPrimaryCue(
          subtitleController.primaryCursor.current(playerController.position),
        );
      }
      setState(() {
        status =
            'Loaded ${secondary ? 'secondary' : 'primary'} subtitle: '
            '${path.split(Platform.pathSeparator).last}';
      });
      if (!secondary) await _loadWordProfiles();
      if (!secondary) await _loadPhraseProfiles();
      if (!secondary) {
        await _loadPhraseCandidates(subtitleController.currentPrimaryCue);
      }
      if (!secondary) await _loadSpeechEnhancements(imported.id);
    } catch (error) {
      setState(() => status = 'Subtitle import failed: $error');
    }
  }

  Future<void> _loadGeneratedTrack(
    Map<String, dynamic> value,
    bool secondary,
  ) async {
    await adapter.disableNativeSubtitles();
    if (!mounted) return;
    final imported = SubtitleTrack.fromJson(value);
    if (secondary) {
      subtitleController.setSecondaryTrack(imported);
      subtitleController.setCurrentSecondaryCue(
        subtitleController.secondaryCursor.current(playerController.position),
      );
    } else {
      subtitleController.clearSpeechEnhancements();
      subtitleController.setPrimaryTrack(imported);
      subtitleController.setCurrentPrimaryCue(
        subtitleController.primaryCursor.current(playerController.position),
      );
    }
    setState(() {
      status =
          'Loaded generated ${secondary ? 'secondary' : 'primary'} subtitle';
    });
    if (!secondary) await _loadWordProfiles();
    if (!secondary) await _loadPhraseProfiles();
    if (!secondary) {
      await _loadPhraseCandidates(subtitleController.currentPrimaryCue);
    }
    if (!secondary) await _loadSpeechEnhancements(imported.id);
  }

  Future<void> _loadSpeechEnhancements(String trackId) async {
    final service = api;
    if (service == null) return;
    try {
      final timings = await service.trackWordTimings(trackId);
      final grouped = <String, List<WordTiming>>{};
      for (final raw in timings) {
        final value = WordTiming.fromJson(raw);
        grouped.putIfAbsent(value.sentenceId, () => []).add(value);
      }
      final analyses = settingsController.precomputePronunciation
          ? await service.trackPronunciation(trackId)
          : subtitleController.currentPrimaryCue == null
          ? <Map<String, dynamic>>[]
          : [
              await service.analyzePronunciation(
                subtitleController.currentPrimaryCue!.id,
              ),
            ];
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      subtitleController.setSpeechEnhancements(
        timingsBySentence: grouped,
        pronunciationBySentence: Map<String, Map<String, dynamic>>.fromEntries(
          analyses.map(
            (value) => MapEntry(value['sentence_id'] as String, value),
          ),
        ),
      );
      subtitleController.updateCurrentWord(
        playerController.position,
        enabled: settingsController.wordSyncVisible,
      );
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Speech enhancements unavailable: $error');
      }
    }
  }

  Future<void> _ensureCurrentPronunciation(Cue? cue) async {
    final service = api;
    if (cue == null ||
        service == null ||
        subtitleController.pronunciationBySentence.containsKey(cue.id)) {
      return;
    }
    try {
      final value = await service.analyzePronunciation(cue.id);
      if (mounted && subtitleController.currentPrimaryCue?.id == cue.id) {
        subtitleController.setSentencePronunciation(cue.id, value);
      }
    } catch (_) {
      // Pronunciation is optional and must never block playback.
    }
  }

  Future<void> _generateSubtitles({required bool secondary}) async {
    if (api == null || playerController.mediaId == null) {
      setState(() => status = 'Open media and connect the local core first');
      return;
    }
    await showGenerateSubtitles(
      context: context,
      api: api!,
      mediaId: playerController.mediaId!,
      secondary: secondary,
      preferredQuality: settingsController.transcriptionQuality,
      preferredLanguage: settingsController.transcriptionLanguage,
    );
  }

  Future<void> _openTranscriptionCenter() async {
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            TranscriptionCenter(api: api!, loadTrack: _loadGeneratedTrack),
      ),
    );
  }

  Future<void> _handleDrop(List<String> paths) async {
    final media = paths.where(_isMediaPath).toList(growable: false);
    final subtitles = paths.where(_isSubtitlePath).toList(growable: false);
    if (media.isNotEmpty) await _openMediaPath(media.first);
    for (final path in subtitles) {
      if (playerController.mediaId == null || api == null) {
        setState(() => status = 'Drop or open media before subtitles');
        return;
      }
      await _openSubtitlePath(
        path,
        secondary: subtitleController.primaryTrack != null,
      );
    }
    if (media.isEmpty && subtitles.isEmpty) {
      setState(() => status = 'Unsupported dropped file type');
    }
  }

  bool _isMediaPath(String path) => const {
    'mp4',
    'mkv',
    'mov',
    'webm',
    'm4a',
    'mp3',
    'wav',
    'flac',
  }.contains(path.split('.').last.toLowerCase());

  bool _isSubtitlePath(String path) =>
      const {'srt', 'vtt'}.contains(path.split('.').last.toLowerCase());

  Future<void> _openOnline() async {
    final controller = TextEditingController();
    final pageUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('openOnlineTitle')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.text('pageUrl'),
              helperText: 'Only open content you are authorized to access.',
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('cancel')),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, 'download:$value');
            },
            icon: const Icon(Icons.download),
            label: Text(l.text('downloadVideo')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.text('resolvePlay')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pageUrl == null || pageUrl.isEmpty) return;
    if (pageUrl.startsWith('download:')) {
      await _downloadOnline(pageUrl.substring('download:'.length));
      return;
    }
    setState(() => status = 'Resolving online media...');
    try {
      final resolved = await tools.resolveOnlineMedia(pageUrl);
      await adapter.open(resolved);
      playerController.clearMedia();
      playerController.setMediaPath(pageUrl);
      subtitleController.setPrimaryTrack(null);
      subtitleController.setSecondaryTrack(null);
      subtitleController.setCurrentPrimaryCue(null);
      subtitleController.setCurrentSecondaryCue(null);
      subtitleController.clearSpeechEnhancements();
      subtitleController.setCurrentPrimaryCue(null);
      subtitleController.setCurrentSecondaryCue(null);
      setState(() => status = 'Playing online media');
    } catch (error) {
      setState(() => status = 'Online media failed: $error');
    }
  }

  Future<void> _downloadOnline(String pageUrl) async {
    final directory = await getDirectoryPath(
      confirmButtonText: l.text('downloadHere'),
    );
    if (directory == null) return;
    setState(() => status = l.text('startingDownload'));
    try {
      final download = await tools.downloadOnlineMedia(pageUrl, directory);
      if (!mounted) {
        download.cancel();
        return;
      }
      setState(() {
        activeDownload = download;
        status = l.text('downloadingInBackground');
      });
      playerController.setDownloadProgress(0);
      playerController.setDownloadedMediaPath('');
      subscriptions.add(
        download.progress.listen((value) {
          if (mounted) playerController.setDownloadProgress(value);
        }),
      );
      unawaited(
        download.completed.then(
          (path) {
            if (!mounted) return;
            setState(() {
              activeDownload = null;
              status = '${l.text('downloadComplete')}: $path';
            });
            if (path != null) playerController.setDownloadedMediaPath(path);
            playerController.setDownloadProgress(0);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              activeDownload = null;
              status = '${l.text('downloadFailed')}: $error';
            });
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => status = '${l.text('downloadFailed')}: $error');
      }
    }
  }

  Future<void> _importEmbeddedSubtitle() async {
    final path = playerController.mediaPath;
    if (path == null ||
        !_isMediaPath(path) ||
        playerController.mediaId == null ||
        api == null) {
      setState(() => status = 'Open a local media file first');
      return;
    }
    setState(() => status = 'Inspecting embedded subtitles...');
    try {
      final subtitles = await tools.probeSubtitles(path);
      if (!mounted) return;
      if (subtitles.isEmpty) {
        setState(() => status = 'No embedded subtitles found');
        return;
      }
      final choice = await showDialog<(EmbeddedSubtitle, bool)>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.text('importEmbeddedText')),
          children: [
            for (final subtitle in subtitles)
              ListTile(
                enabled: subtitle.isText,
                title: Text(subtitle.label),
                subtitle: Text(
                  subtitle.isText
                      ? 'Import as an interactive learning subtitle'
                      : 'Bitmap subtitle: learning interaction is deferred',
                ),
                trailing: subtitle.isText
                    ? PopupMenuButton<bool>(
                        onSelected: (secondary) =>
                            Navigator.pop(context, (subtitle, secondary)),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: false,
                            child: Text(l.text('usePrimary')),
                          ),
                          PopupMenuItem(
                            value: true,
                            child: Text(l.text('useSecondary')),
                          ),
                        ],
                      )
                    : null,
              ),
          ],
        ),
      );
      if (choice == null) {
        setState(() => status = 'Embedded subtitle import cancelled');
        return;
      }
      setState(() => status = 'Extracting embedded text subtitle...');
      final extracted = await tools.extractTextSubtitle(path, choice.$1);
      await _openSubtitlePath(extracted, secondary: choice.$2);
    } catch (error) {
      setState(() => status = 'Embedded subtitle import failed: $error');
    }
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        language: settingsController.language,
        subtitlePreset: subtitleController.preset,
        primaryFontSize: subtitleController.primaryFontSize,
        primaryFontFamily: subtitleController.primaryFontFamily,
        secondaryFontSize: subtitleController.secondaryFontSize,
        secondaryFontFamily: subtitleController.secondaryFontFamily,
        subtitlePositionX: subtitleController.positionX,
        subtitlePositionY: subtitleController.positionY,
        subtitleBackgroundOpacity: subtitleController.backgroundOpacity,
        transcriptWidth: settingsController.transcriptWidth,
        primaryColor: settingsController.primaryColor,
        secondaryColor: settingsController.secondaryColor,
        transcriptionQuality: settingsController.transcriptionQuality,
        transcriptionLanguage: settingsController.transcriptionLanguage,
        transcriptionDestination: settingsController.transcriptionDestination,
        ffmpegPath: settingsController.ffmpegPath,
        ffprobePath: settingsController.ffprobePath,
        ytDlpPath: settingsController.ytDlpPath,
        openSubtitlesApiKey: settingsController.openSubtitlesApiKey,
        pronunciationVisible: settingsController.pronunciationVisible,
        wordSyncVisible: settingsController.wordSyncVisible,
        phonemeDisplay: settingsController.phonemeDisplay,
        wordAnimationIntensity: settingsController.wordAnimationIntensity,
        ruleHintsLevel: settingsController.ruleHintsLevel,
        precomputePronunciation: settingsController.precomputePronunciation,
        onLanguageChanged: (v) {
          appLanguage.value = v;
          settingsController.update(
            settingsController.settings.copyWith(language: v),
          );
        },
        onSubtitlePresetChanged: (v) {
          subtitleController.setPreset(v);
          unawaited(_saveSettings());
        },
        onPrimaryFontSizeChanged: (v) {
          subtitleController.setPrimaryFontSize(v);
          unawaited(_saveSettings());
        },
        onPrimaryFontFamilyChanged: (v) {
          subtitleController.setPrimaryFontFamily(v);
          unawaited(_saveSettings());
        },
        onSecondaryFontSizeChanged: (v) {
          subtitleController.setSecondaryFontSize(v);
          unawaited(_saveSettings());
        },
        onSecondaryFontFamilyChanged: (v) {
          subtitleController.setSecondaryFontFamily(v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionXChanged: (v) {
          subtitleController.setPositionX(v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionYChanged: (v) {
          subtitleController.setPositionY(v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionReset: () {
          subtitleController.setPositionX(0.5);
          subtitleController.setPositionY(0.82);
          unawaited(_saveSettings());
        },
        onBackgroundOpacityChanged: (v) {
          subtitleController.setBackgroundOpacity(v);
          unawaited(_saveSettings());
        },
        onTranscriptWidthChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptWidth: v),
          );
        },
        onPrimaryColorChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(primaryColor: v.toARGB32()),
          );
        },
        onSecondaryColorChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(secondaryColor: v.toARGB32()),
          );
        },
        onTranscriptionQualityChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptionQuality: v),
          );
        },
        onTranscriptionLanguageChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptionLanguage: v),
          );
        },
        onTranscriptionDestinationChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptionDestination: v),
          );
        },
        onPronunciationVisibleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(pronunciationVisible: v),
          );
        },
        onWordSyncVisibleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(wordSyncVisible: v),
          );
          subtitleController.updateCurrentWord(
            playerController.position,
            enabled: v,
          );
        },
        onPhonemeDisplayChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(phonemeDisplay: v),
          );
        },
        onWordAnimationIntensityChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(wordAnimationIntensity: v),
          );
        },
        onRuleHintsLevelChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(ruleHintsLevel: v),
          );
        },
        onPrecomputePronunciationChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(precomputePronunciation: v),
          );
        },
        onSave:
            ({
              required String ffmpegPath,
              required String ffprobePath,
              required String ytDlpPath,
              required String openSubtitlesApiKey,
            }) async {
              await settingsController.update(
                settingsController.settings.copyWith(
                  ffmpegPath: ffmpegPath,
                  ffprobePath: ffprobePath,
                  ytDlpPath: ytDlpPath,
                  openSubtitlesApiKey: openSubtitlesApiKey,
                ),
              );
            },
      ),
    );
  }

  Future<void> _openLearningAssets() async {
    if (api == null) return;
    final occurrence = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => LearningAssetsScreen(api: api!)),
    );
    if (occurrence != null) await _playOccurrence(occurrence);
  }

  Future<void> _openLearningResources() async {
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LearningResourceScreen(api: api!)),
    );
  }

  Future<void> _showCurrentPhraseCandidates() async {
    final cue = subtitleController.currentPrimaryCue;
    if (api == null ||
        cue == null ||
        playerController.mediaFingerprint == null) {
      return;
    }
    await showPhraseCandidates(
      context: context,
      api: api!,
      sentenceId: cue.id,
      source: {
        'media_id': playerController.mediaId,
        'sentence_id': cue.id,
        'sentence_text': cue.text,
        'media_title': playerController.mediaTitle ?? '',
        'media_fingerprint': playerController.mediaFingerprint,
        'start_ms': cue.start.inMilliseconds,
        'end_ms': cue.end.inMilliseconds,
      },
    );
  }

  Future<void> _loadPhraseCandidates(Cue? cue) async {
    if (api == null || cue == null) {
      if (mounted) learningController.setPhraseCandidates(const []);
      return;
    }
    try {
      if (mounted && subtitleController.currentPrimaryCue?.id == cue.id) {
        learningController.setPhraseCandidates(const []);
      }
      final candidates = await api!.phraseCandidates(cue.id);
      if (mounted && subtitleController.currentPrimaryCue?.id == cue.id) {
        learningController.setPhraseCandidates(candidates);
      }
    } catch (_) {
      if (mounted && subtitleController.currentPrimaryCue?.id == cue.id) {
        learningController.setPhraseCandidates(const []);
      }
    }
  }

  Future<void> _openPhrase(Map<String, dynamic> candidate, Cue cue) async {
    if (api == null || playerController.mediaFingerprint == null) return;
    final canonical = candidate['canonical_form'] as String;
    final details = await showPhraseCandidate(
      context: context,
      api: api!,
      candidate: candidate,
      initialStatus:
          (learningController.phraseProfiles[canonical]?['entry']
                  as Map<String, dynamic>?)?['status']
              as String?,
      source: {
        'media_id': playerController.mediaId,
        'sentence_id': cue.id,
        'sentence_text': cue.text,
        'media_title': playerController.mediaTitle ?? '',
        'media_fingerprint': playerController.mediaFingerprint,
        'start_ms': cue.start.inMilliseconds,
        'end_ms': cue.end.inMilliseconds,
      },
    );
    if (details != null && mounted) {
      learningController.updateSinglePhraseProfile(canonical, details);
      setState(() {
        status = 'Saved phrase "${candidate['display_form']}"';
      });
    }
  }

  Future<void> _correctCurrentLemma() async {
    final token = learningController.selectedToken;
    if (api == null || token?.normalized == null) return;
    final controller = TextEditingController(text: token!.normalized);
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct lemma'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.text('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (corrected == null || corrected.isEmpty) return;
    await api!.correctLemma(token.normalized!, corrected);
    if (mounted) setState(() => status = l.text('lemmaCorrectionSaved'));
  }

  Future<void> _searchOpenSubtitles({bool? secondary}) async {
    if (api == null) return;
    if (playerController.mediaId == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.text('openSubtitles')),
          content: Text(l.text('openMediaForSubtitles')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.text('close')),
            ),
          ],
        ),
      );
      return;
    }
    if (settingsController.openSubtitlesApiKey.isEmpty) {
      final controller = TextEditingController();
      final configured = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.text('openSubtitles')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.text('configureOpenSubtitlesNow')),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l.text('openSubtitlesApiKey'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(l.text('save')),
            ),
          ],
        ),
      );
      controller.dispose();
      if (configured == null || configured.isEmpty) return;
      await settingsController.update(
        settingsController.settings.copyWith(openSubtitlesApiKey: configured),
      );
    }
    if (!mounted) return;
    final path = await showOpenSubtitlesSearch(
      context: context,
      api: api!,
      apiKey: settingsController.openSubtitlesApiKey,
      initialTitle: playerController.mediaTitle ?? '',
      initialFilename: playerController.mediaPath == null
          ? ''
          : playerController.mediaPath!.split(Platform.pathSeparator).last,
      mediaPath: playerController.mediaPath,
    );
    if (path == null || !mounted) return;
    final destination =
        secondary ??
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.text('openSubtitles')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.text('usePrimary')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.text('useSecondary')),
              ),
            ],
          ),
        );
    if (destination != null) {
      await _openSubtitlePath(path, secondary: destination);
    }
  }

  Future<void> _markFirstWord(String? wordStatus) async {
    final cue = subtitleController.currentPrimaryCue;
    final service = api;
    if (cue == null || service == null) return;
    final tokens = cue.tokens
        .where((value) => value.kind == 'word' && value.normalized != null)
        .toList(growable: false);
    final token = tokens.isEmpty ? null : tokens.first;
    if (token == null) return;
    final profile = await service.updateWordProfile(
      token.normalized!,
      token.text,
      wordStatus,
      _sourceFor(token, cue),
    );
    learningController.updateSingleWordProfile(token.normalized!, profile);
    await _refreshDiagnosis();
  }

  Future<void> _exportLogs() async {
    final source = api?.logPath;
    if (source == null || !await File(source).exists()) {
      setState(() => status = 'No core log is available yet');
      return;
    }
    final location = await getSaveLocation(
      suggestedName: 'LLPlayerNext-core.log',
    );
    if (location == null) return;
    await File(source).copy(location.path);
    setState(() => status = 'Exported diagnostics to ${location.path}');
  }

  Future<void> _loadWordProfiles() async {
    final lemmas = subtitleController.primaryTrack?.cues
        .expand((cue) => cue.tokens)
        .where((token) => token.kind == 'word' && token.normalized != null)
        .map((token) => token.normalized!)
        .toSet()
        .toList();
    if (lemmas == null || api == null) return;
    final values = await api!.readWordProfiles(lemmas);
    final profiles = Map<String, Map<String, dynamic>>.fromEntries(
      values.map(
        (profile) => MapEntry(profile['normalized_lemma'] as String, profile),
      ),
    );
    learningController.setWordProfiles(profiles);
  }

  Future<void> _loadPhraseProfiles() async {
    if (api == null) return;
    final values = await api!.lexicalEntries(kind: 'phrase');
    if (!mounted) return;
    final profiles = Map<String, Map<String, dynamic>>.fromEntries(
      values.map((details) {
        final entry = details['entry'] as Map<String, dynamic>;
        return MapEntry(entry['canonical_form'] as String, details);
      }),
    );
    learningController.setPhraseProfiles(profiles);
  }

  Future<void> _openWord(SubtitleToken token, Cue cue) async {
    final lemma = token.normalized;
    if (lemma == null || api == null) return;
    try {
      var profile = learningController.wordProfiles[lemma];
      profile ??= await api!.updateWordProfile(lemma, token.text, null);
      final details = await api!.wordDetails(profile['id'] as String);
      final dictionary = await api!.lookupDictionary(lemma);
      final pronunciation = await api!.lookupPronunciation(token.text);
      if (!mounted) return;
      learningController.updateSingleWordProfile(lemma, profile);
      learningController.setSelectedToken(token);
      learningController.setSelectedCue(cue);
      learningController.selectWord(details);
      learningController.setSelectedDictionary(dictionary);
      learningController.setSelectedPronunciation(pronunciation);
      learningController.selectSidePanel(1);
    } catch (error) {
      if (mounted) setState(() => status = 'Dictionary unavailable: $error');
    }
  }

  Future<void> _setSelectedWordStatus(String? selected) async {
    final token = learningController.selectedToken;
    final cue = learningController.selectedCue;
    if (token?.normalized == null || cue == null || api == null) return;
    try {
      final profile = await api!.updateWordProfile(
        token!.normalized!,
        token.text,
        selected,
        _sourceFor(token, cue),
      );
      final details = await api!.wordDetails(profile['id'] as String);
      learningController.updateSingleWordProfile(token.normalized!, profile);
      learningController.selectWord(details);
      setState(() {
        status = 'Updated global status for "${token.text}"';
      });
      await _refreshDiagnosis();
    } catch (error) {
      setState(() => status = 'Word update failed: $error');
    }
  }

  Future<void> _saveSelectedLearningContent(
    String? definition,
    String? note,
  ) async {
    final profile =
        learningController.selectedWordDetails?['profile']
            as Map<String, dynamic>?;
    if (profile == null || api == null) return;
    final details = await api!.updateLearningContent(
      profile['id'] as String,
      userDefinition: definition,
      personalNote: note,
    );
    if (mounted) {
      learningController.selectWord(details);
    }
  }

  Future<void> _observeSelected(bool heard) async {
    final token = learningController.selectedToken;
    final cue = learningController.selectedCue;
    final profile =
        learningController.selectedWordDetails?['profile']
            as Map<String, dynamic>?;
    if (token == null || cue == null || profile == null || api == null) return;
    await api!.createObservation(
      wordProfileId: profile['id'] as String,
      sentenceId: cue.id,
      originalForm: token.text,
      heard: heard,
      source: _sourceFor(token, cue),
    );
    if (mounted) {
      setState(() => status = heard ? l.text('heard') : l.text('notHeard'));
    }
    await _refreshDiagnosis();
  }

  Map<String, dynamic>? _sourceFor(SubtitleToken token, Cue cue) {
    if (playerController.mediaFingerprint == null) return null;
    return {
      'language': 'en',
      'normalized_lemma': token.normalized,
      'media_id': playerController.mediaId,
      'sentence_id': cue.id,
      'original_form': token.text,
      'sentence_text': cue.text,
      'media_title': playerController.mediaTitle ?? '',
      'media_fingerprint': playerController.mediaFingerprint,
      'start_ms': cue.start.inMilliseconds,
      'end_ms': cue.end.inMilliseconds,
    };
  }

  Future<void> _openVocabulary() async {
    final service = api;
    if (service == null) return;
    final occurrence = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => VocabularyScreen(
          api: service,
          onExport: _exportVocabulary,
          onImport: _importVocabulary,
        ),
      ),
    );
    if (occurrence == null) return;
    final expectedFingerprint =
        occurrence['media_fingerprint_snapshot'] as String;
    if (expectedFingerprint != playerController.mediaFingerprint) {
      String? sourcePath;
      final linkedMediaId = occurrence['media_id'] as String?;
      if (linkedMediaId != null) {
        try {
          final linkedMedia = await api!.readMedia(linkedMediaId);
          final linkedPath = linkedMedia['path'] as String;
          if (await File(linkedPath).exists()) sourcePath = linkedPath;
        } catch (_) {
          sourcePath = null;
        }
      }
      if (sourcePath == null) {
        const group = XTypeGroup(
          label: 'source media',
          extensions: [
            'mp4',
            'mkv',
            'mov',
            'webm',
            'm4a',
            'mp3',
            'wav',
            'flac',
          ],
        );
        final file = await openFile(acceptedTypeGroups: [group]);
        if (file == null) return;
        final fingerprint = await api!.fingerprintFile(file.path);
        if (fingerprint != expectedFingerprint) {
          setState(
            () =>
                status = 'Selected file does not match the source fingerprint',
          );
          return;
        }
        await api!.registerMedia(file.path);
        sourcePath = file.path;
      }
      await _openMediaPath(sourcePath);
    }
    final start = Duration(
      milliseconds: occurrence['start_ms_snapshot'] as int,
    );
    final end = Duration(milliseconds: occurrence['end_ms_snapshot'] as int);
    setState(() {
      status = 'Looping vocabulary source sentence';
    });
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> _playOccurrence(Map<String, dynamic> occurrence) async {
    final expectedFingerprint =
        occurrence['media_fingerprint_snapshot'] as String;
    if (expectedFingerprint != playerController.mediaFingerprint) {
      String? sourcePath;
      final linkedMediaId = occurrence['media_id'] as String?;
      if (linkedMediaId != null) {
        try {
          final linkedMedia = await api!.readMedia(linkedMediaId);
          final linkedPath = linkedMedia['path'] as String;
          if (await File(linkedPath).exists()) sourcePath = linkedPath;
        } catch (_) {
          sourcePath = null;
        }
      }
      if (sourcePath == null) {
        const group = XTypeGroup(label: 'source media');
        final file = await openFile(acceptedTypeGroups: [group]);
        if (file == null) return;
        if (await api!.fingerprintFile(file.path) != expectedFingerprint) {
          setState(
            () =>
                status = 'Selected file does not match the source fingerprint',
          );
          return;
        }
        await api!.registerMedia(file.path);
        sourcePath = file.path;
      }
      await _openMediaPath(sourcePath);
    }
    final start = Duration(
      milliseconds: occurrence['start_ms_snapshot'] as int,
    );
    final end = Duration(milliseconds: occurrence['end_ms_snapshot'] as int);
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> _exportVocabulary() async {
    final service = api;
    if (service == null) return;
    final location = await getSaveLocation(
      suggestedName: 'LLPlayerNext-vocabulary-v1.json',
    );
    if (location == null) return;
    final bundle = await service.exportVocabulary();
    await File(
      location.path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(bundle));
    setState(() => status = 'Exported vocabulary assets');
  }

  Future<void> _importVocabulary() async {
    final service = api;
    if (service == null) return;
    const group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final bundle =
        jsonDecode(await File(file.path).readAsString())
            as Map<String, dynamic>;
    await service.importVocabulary(bundle);
    await _loadWordProfiles();
    await _loadPhraseProfiles();
    setState(() => status = 'Imported vocabulary assets');
  }

  Future<void> _importWordList() async {
    final service = api;
    if (service == null) return;
    const group = XTypeGroup(label: 'word list', extensions: ['txt', 'csv']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final content = await File(file.path).readAsString();
    final entries = <Map<String, dynamic>>[];
    var defaultStatus = 'known_recognized';
    var overwrite = false;
    try {
      entries.addAll(
        parseExternalWordList(
          content,
          csv: file.path.toLowerCase().endsWith('.csv'),
        ),
      );
    } on FormatException catch (error) {
      setState(() => status = error.message);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(l.text('previewImport')),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                Text(
                  '${entries.length} words · ${entries.take(8).map((e) => e['word']).join(', ')}',
                ),
                DropdownButtonFormField<String>(
                  initialValue: defaultStatus,
                  items:
                      const [
                            'unknown_meaning',
                            'known_not_recognized',
                            'known_recognized',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(l.status(value)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => refresh(() => defaultStatus = value!),
                ),
                CheckboxListTile(
                  value: overwrite,
                  title: Text(l.text('overwriteExisting')),
                  onChanged: (value) =>
                      refresh(() => overwrite = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.text('close')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.text('import')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final result = await service.importExternalVocabulary(
      entries,
      defaultStatus: defaultStatus,
      overwriteExisting: overwrite,
    );
    await _loadWordProfiles();
    setState(() => status = 'Imported word list: $result');
  }

  Future<void> _archiveCurrentMedia() async {
    if (api == null || playerController.mediaId == null) return;
    await api!.setMediaAvailability(playerController.mediaId!, 'archived');
    setState(
      () =>
          status = 'Archived current media record; vocabulary assets preserved',
    );
  }

  Future<void> _refreshDiagnosis() async {
    final cue = subtitleController.currentPrimaryCue;
    final service = api;
    if (cue == null || service == null) {
      if (mounted) learningController.setDiagnosis(null);
      return;
    }
    try {
      final value = await service.diagnose(cue.id);
      if (mounted && cue.id == subtitleController.currentPrimaryCue?.id) {
        learningController.setDiagnosis(value);
      }
    } catch (_) {
      if (mounted && cue.id == subtitleController.currentPrimaryCue?.id) {
        learningController.setDiagnosis(null);
      }
    }
  }

  Future<void> _seekCue(Cue? cue) async {
    if (cue == null) return;
    subtitleController.setCurrentPrimaryCue(cue);
    unawaited(_refreshDiagnosis());
    await adapter.seek(subtitleController.primaryCursor.mediaStart(cue));
  }

  void _keepCurrentVisible(Cue? cue) {
    if (cue == null || !transcriptController.hasClients) return;
    final target = (cue.index * transcriptItemExtent).clamp(
      0,
      transcriptController.position.maxScrollExtent,
    );
    transcriptController.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    final currentMediaId = playerController.mediaId;
    final currentPosition = playerController.position;
    if (currentMediaId != null) {
      unawaited(api?.saveProgress(currentMediaId, currentPosition));
    }
    activeDownload?.cancel();
    unawaited(_saveSettings());
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    transcriptController.dispose();
    progressTimer?.cancel();
    unawaited(adapter.dispose());
    unawaited(api?.close());
    playerController.dispose();
    subtitleController.dispose();
    learningController.dispose();
    settingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (api == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        playerController,
        subtitleController,
        learningController,
        settingsController,
      ]),
      builder: (context, _) => AppControllers(
        player: playerController,
        subtitle: subtitleController,
        learning: learningController,
        settings: settingsController,
        api: api!,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space):
                adapter.playOrPause,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekCue(
              subtitleController.primaryCursor.previous(
                subtitleController.currentPrimaryCue,
              ),
            ),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _seekCue(
                  subtitleController.primaryCursor.next(
                    subtitleController.currentPrimaryCue,
                  ),
                ),
            const SingleActivator(LogicalKeyboardKey.keyL): () =>
                subtitleController.setLoopCue(!subtitleController.loopCue),
            const SingleActivator(LogicalKeyboardKey.keyH): () =>
                subtitleController.setVisible(!subtitleController.visible),
            const SingleActivator(LogicalKeyboardKey.digit1): () =>
                _markFirstWord('unknown_meaning'),
            const SingleActivator(LogicalKeyboardKey.digit2): () =>
                _markFirstWord('known_not_recognized'),
            const SingleActivator(LogicalKeyboardKey.digit3): () =>
                _markFirstWord('known_recognized'),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: PlayerAppBar(
                onOpenVocabulary: _openVocabulary,
                onOpenMedia: _openMedia,
                onOpenOnline: _openOnline,
                onImportPrimarySubtitle: () =>
                    unawaited(_openSubtitle(secondary: false)),
                onGeneratePrimarySubtitles: () =>
                    unawaited(_generateSubtitles(secondary: false)),
                onSearchPrimarySubtitles: () =>
                    unawaited(_searchOpenSubtitles(secondary: false)),
                onImportSecondarySubtitle: () =>
                    unawaited(_openSubtitle(secondary: true)),
                onGenerateSecondarySubtitles: () =>
                    unawaited(_generateSubtitles(secondary: true)),
                onSearchSecondarySubtitles: () =>
                    unawaited(_searchOpenSubtitles(secondary: true)),
                onImportEmbeddedSubtitle: () =>
                    unawaited(_importEmbeddedSubtitle()),
                onOpenSettings: () => unawaited(_openSettings()),
                onExportLogs: () => unawaited(_exportLogs()),
                onExportVocabulary: () => unawaited(_exportVocabulary()),
                onImportVocabulary: () => unawaited(_importVocabulary()),
                onImportWordList: () => unawaited(_importWordList()),
                onArchiveMedia: () => unawaited(_archiveCurrentMedia()),
                onOpenTranscriptionCenter: () =>
                    unawaited(_openTranscriptionCenter()),
                onOpenLearningAssets: () => unawaited(_openLearningAssets()),
                onOpenLearningResources: () =>
                    unawaited(_openLearningResources()),
                onShowPhraseCandidates: () =>
                    unawaited(_showCurrentPhraseCandidates()),
                onCorrectLemma: () => unawaited(_correctCurrentLemma()),
                onSearchOpenSubtitles: () => unawaited(_searchOpenSubtitles()),
              ),
              body: DropTarget(
                onDragEntered: (_) => setState(() => dragging = true),
                onDragExited: (_) => setState(() => dragging = false),
                onDragDone: (details) {
                  setState(() => dragging = false);
                  unawaited(
                    _handleDrop(
                      details.files.map((file) => file.path).toList(),
                    ),
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: dragging
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 4,
                          )
                        : null,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: _playerSurface()),
                            if (subtitleController.visible ||
                                learningController.selectedWordDetails != null)
                              SizedBox(
                                width: settingsController.transcriptWidth,
                                child: _sidePanel(),
                              ),
                          ],
                        ),
                      ),
                      if (activeDownload != null ||
                          playerController.downloadedMediaPath != null)
                        _downloadStatusBar(),
                      _controls(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerSurface() => LayoutBuilder(
    builder: (context, constraints) {
      final primarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: subtitleController.primaryFontSize,
        preset: subtitleController.preset,
        textLength: subtitleController.currentPrimaryCue?.text.length ?? 1,
      );
      final secondarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: subtitleController.secondaryFontSize,
        preset: subtitleController.preset,
        textLength: subtitleController.currentSecondaryCue?.text.length ?? 1,
        secondary: true,
      );
      final backgroundFactor = subtitleController.preset == 'watching'
          ? 0.45
          : subtitleController.preset == 'compact'
          ? 0.3
          : 1.0;
      final subtitlePosition = Offset(
        subtitleController.positionX,
        subtitleController.positionY,
      );
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: PlayerSurface(adapter: adapter),
            ),
          ),
          if (subtitleController.visible &&
              (subtitleController.currentPrimaryCue != null ||
                  (subtitleController.secondaryVisible &&
                      subtitleController.currentSecondaryCue != null)))
            Align(
              alignment: Alignment(
                subtitlePosition.dx * 2 - 1,
                subtitlePosition.dy * 2 - 1,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) {
                    subtitleController.movePosition(
                      details.delta.dx,
                      details.delta.dy,
                      constraints.biggest.width,
                      constraints.biggest.height,
                    );
                  },
                  onPanEnd: (_) => unawaited(_saveSettings()),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.82,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha:
                              subtitleController.backgroundOpacity *
                              backgroundFactor,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: subtitleController.preset == 'compact'
                              ? 10
                              : 18,
                          vertical: subtitleController.preset == 'compact'
                              ? 6
                              : 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitleController.currentPrimaryCue != null)
                              GestureDetector(
                                onTap: () => _seekCue(
                                  subtitleController.currentPrimaryCue,
                                ),
                                child: TokenLine(
                                  cue: subtitleController.currentPrimaryCue!,
                                  profiles: learningController.wordProfiles,
                                  phraseCandidates:
                                      learningController.phraseCandidates,
                                  phraseProfiles:
                                      learningController.phraseProfiles,
                                  showStyles:
                                      subtitleController.statusStylesVisible,
                                  fontSize: primarySize,
                                  fontFamily: _subtitleFont(
                                    subtitleController.primaryFontFamily,
                                  ),
                                  baseColor: settingsController.primaryColor,
                                  currentTokenIndex:
                                      subtitleController.currentWordToken,
                                  currentWordIntensity:
                                      settingsController.wordAnimationIntensity,
                                  onWord: _openWord,
                                  onPhrase: _openPhrase,
                                ),
                              ),
                            if (settingsController.pronunciationVisible &&
                                subtitleController.currentPrimaryCue != null &&
                                subtitleController
                                        .pronunciationBySentence[subtitleController
                                        .currentPrimaryCue!
                                        .id] !=
                                    null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _pronunciationText(
                                    subtitleController
                                        .pronunciationBySentence[subtitleController
                                        .currentPrimaryCue!
                                        .id]!,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: primarySize * 0.55,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            if (settingsController.wordSyncVisible &&
                                subtitleController.currentPrimaryCue != null &&
                                (subtitleController
                                            .timingsBySentence[subtitleController
                                            .currentPrimaryCue!
                                            .id] ??
                                        const [])
                                    .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  _timingQuality(
                                    subtitleController.currentPrimaryCue!.id,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            if (subtitleController.secondaryVisible &&
                                subtitleController.currentSecondaryCue != null)
                              GestureDetector(
                                onTap: () => adapter.seek(
                                  subtitleController.secondaryCursor.mediaStart(
                                    subtitleController.currentSecondaryCue!,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    subtitleController
                                        .currentSecondaryCue!
                                        .text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: secondarySize,
                                      fontFamily: _subtitleFont(
                                        subtitleController.secondaryFontFamily,
                                      ),
                                      color: settingsController.secondaryColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (playerController.mediaPath == null)
            Center(
              child: FilledButton.icon(
                onPressed: _openMedia,
                icon: const Icon(Icons.folder_open),
                label: Text(l.text('openVideoAudio')),
              ),
            ),
        ],
      );
    },
  );

  String? _subtitleFont(String value) => switch (value) {
    'serif' => 'Georgia',
    'monospace' => 'Menlo',
    _ => null,
  };

  String _pronunciationText(Map<String, dynamic> analysis) {
    if (settingsController.phonemeDisplay == 'ipa') {
      return analysis['display_ipa'] as String;
    }
    return ((analysis['phonemes'] as List<dynamic>?) ?? const [])
        .map((value) => (value as Map<String, dynamic>)['symbol'])
        .join(' ');
  }

  String _timingQuality(String sentenceId) {
    final first = subtitleController.timingsBySentence[sentenceId]!.first;
    return '${first.source.replaceAll('_', ' ')} · ${first.provider}';
  }

  Widget _sidePanel() => Material(
    color: const Color(0xff151a20),
    child: Column(
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.subtitles),
              label: Text(l.text('transcript')),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.menu_book),
              label: Text(l.text('wordLearning')),
            ),
            ButtonSegment(
              value: 2,
              icon: const Icon(Icons.analytics_outlined),
              label: Text(l.text('diagnosis')),
            ),
          ],
          selected: {learningController.sidePanel},
          onSelectionChanged: (value) =>
              learningController.selectSidePanel(value.first),
          showSelectedIcon: false,
        ),
        Expanded(
          child: switch (learningController.sidePanel) {
            1 =>
              learningController.selectedWordDetails == null
                  ? Center(child: Text(l.text('noWordSelected')))
                  : WordLearningPanel(
                      details: learningController.selectedWordDetails!,
                      dictionary: learningController.selectedDictionary,
                      pronunciation: learningController.selectedPronunciation,
                      onStatus: _setSelectedWordStatus,
                      onSave: _saveSelectedLearningContent,
                      onSource: _playOccurrence,
                      onHeard: () => _observeSelected(true),
                      onNotHeard: () => _observeSelected(false),
                    ),
            2 =>
              learningController.diagnosis == null
                  ? Center(child: Text(l.text('diagnosis')))
                  : _diagnosisCard(),
            _ => _transcript(),
          },
        ),
      ],
    ),
  );

  Widget _transcript() => TranscriptPanel(
    track: subtitleController.primaryTrack,
    scrollController: transcriptController,
    itemExtent: transcriptItemExtent,
    currentCue: subtitleController.currentPrimaryCue,
    wordProfiles: learningController.wordProfiles,
    showStyles: subtitleController.statusStylesVisible,
    baseColor: settingsController.primaryColor,
    onWord: _openWord,
    onSeekCue: _seekCue,
  );

  Widget _diagnosisCard() => DiagnosisCard(
    diagnosis: learningController.diagnosis!,
    pronunciation: subtitleController.currentPrimaryCue == null
        ? null
        : subtitleController.pronunciationBySentence[subtitleController
              .currentPrimaryCue!
              .id],
    ruleHintsLevel: settingsController.ruleHintsLevel,
  );

  Widget _controls() => PlaybackControls(
    adapter: adapter,
    position: playerController.position,
    duration: playerController.duration,
    playing: playerController.playing,
    loopCue: subtitleController.loopCue,
    sourceLoopStart: playerController.sourceLoopStart,
    statusStylesVisible: subtitleController.statusStylesVisible,
    subtitlesVisible: subtitleController.visible,
    secondarySubtitlesVisible: subtitleController.secondaryVisible,
    rate: playerController.rate,
    volume: playerController.volume,
    muted: playerController.muted,
    audioTracks: playerController.audioTracks as List<PlayerTrack>,
    selectedAudioId: playerController.selectedAudioId,
    embeddedSubtitleTracks:
        playerController.embeddedSubtitleTracks as List<PlayerTrack>,
    selectedEmbeddedSubtitleId: playerController.selectedEmbeddedSubtitleId,
    primarySubtitleOffset: subtitleController.primarySubtitleOffset,
    secondarySubtitleOffset: subtitleController.secondarySubtitleOffset,
    status: playerController.status,
    onSeek: (value) => adapter.seek(value),
    onSeekToPreviousCue: () => _seekCue(
      subtitleController.primaryCursor.previous(
        subtitleController.currentPrimaryCue,
      ),
    ),
    onSeekToZero: () => adapter.seek(Duration.zero),
    onPlayPause: adapter.playOrPause,
    onStop: adapter.stop,
    onSeekToNextCue: () => _seekCue(
      subtitleController.primaryCursor.next(
        subtitleController.currentPrimaryCue,
      ),
    ),
    onLoopCueChanged: (value) {
      subtitleController.setLoopCue(value);
      if (value) playerController.setSourceLoop(null, null);
    },
    onStopSourceLoop: () => playerController.setSourceLoop(null, null),
    onStatusStylesChanged: (value) {
      subtitleController.setStatusStylesVisible(value);
      unawaited(_saveSettings());
    },
    onSubtitlesVisibleChanged: (value) {
      subtitleController.setVisible(value);
      unawaited(_saveSettings());
    },
    onSecondaryVisibleChanged: (value) {
      subtitleController.setSecondaryVisible(value);
      unawaited(_saveSettings());
    },
    onRateChanged: (value) {
      playerController.setRate(value);
      adapter.setRate(value);
      unawaited(_saveSettings());
    },
    onVolumeChanged: (value) {
      playerController.setVolume(value);
      if (!playerController.muted) adapter.setVolume(value);
      unawaited(_saveSettings());
    },
    onMuteToggle: () {
      final newMuted = !playerController.muted;
      playerController.setMuted(newMuted);
      adapter.setVolume(newMuted ? 0 : playerController.volume);
    },
    onAudioTrackChanged: (track) {
      playerController.setSelectedAudioId(track.id);
      adapter.selectAudio(track);
    },
    onEmbeddedSubtitleTrackChanged: (track) {
      playerController.setSelectedEmbeddedSubtitleId(track.id);
      adapter.selectSubtitle(track);
    },
    onPrimaryOffsetChanged: (offset) {
      subtitleController.setPrimarySubtitleOffset(offset);
      unawaited(_saveSettings());
    },
    onSecondaryOffsetChanged: (offset) {
      subtitleController.setSecondarySubtitleOffset(offset);
      unawaited(_saveSettings());
    },
  );

  Widget _downloadStatusBar() => DownloadStatusBar(
    activeDownload: activeDownload,
    downloadProgress: playerController.downloadProgress,
    downloadedMediaPath: playerController.downloadedMediaPath,
    onCancel: () {
      activeDownload?.cancel();
      setState(() => activeDownload = null);
    },
    onOpenMediaPath: () =>
        _openMediaPath(playerController.downloadedMediaPath!),
    onDismiss: () => setState(() {
      playerController.setDownloadedMediaPath('');
      if (activeDownload != null) activeDownload?.cancel();
      activeDownload = null;
    }),
  );
}
