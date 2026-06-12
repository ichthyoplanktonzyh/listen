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
import 'player_adapter.dart';
import 'settings.dart';
import 'transcription_ui.dart';
import 'm18_ui.dart';

import 'models/timeline.dart';
import 'services/api_service.dart';
import 'services/external_tools.dart';
import 'utils/subtitle_position.dart';
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
  final adapter = DesktopPlayerAdapter();
  final transcriptController = ScrollController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? progressTimer;
  LocalApi? api;
  SubtitleTrack? primaryTrack;
  SubtitleTrack? secondaryTrack;
  Cue? currentPrimaryCue;
  Cue? currentSecondaryCue;
  String? mediaId;
  String? mediaPath;
  String? mediaTitle;
  String? mediaFingerprint;
  String status = 'Starting local core...';
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration primarySubtitleOffset = Duration.zero;
  Duration secondarySubtitleOffset = Duration.zero;
  Duration? sourceLoopStart;
  Duration? sourceLoopEnd;
  bool playing = false;
  bool muted = false;
  bool loopCue = false;
  bool subtitlesVisible = true;
  bool secondarySubtitlesVisible = true;
  bool statusStylesVisible = true;
  bool dragging = false;
  double rate = 1;
  double volume = 100;
  double primaryFontSize = 1;
  double secondaryFontSize = 1;
  String primaryFontFamily = 'system';
  String secondaryFontFamily = 'system';
  String subtitlePreset = 'learning';
  String language = 'system';
  double subtitlePositionX = 0.5;
  double subtitlePositionY = 0.82;
  double subtitleBackgroundOpacity = 0.72;
  Color primaryColor = Colors.white;
  Color secondaryColor = const Color(0xffb8d8ff);
  double transcriptWidth = 430;
  String ffmpegPath = '';
  String ffprobePath = '';
  String ytDlpPath = '';
  String transcriptionQuality = 'balanced';
  String transcriptionLanguage = 'auto';
  String transcriptionDestination = 'primary';
  String openSubtitlesApiKey = '';
  OnlineMediaDownload? activeDownload;
  double downloadProgress = 0;
  String? downloadedMediaPath;
  List<PlayerTrack> audioTracks = const [];
  String? selectedAudioId;
  List<PlayerTrack> embeddedSubtitleTracks = const [];
  String? selectedEmbeddedSubtitleId;
  final wordProfiles = <String, Map<String, dynamic>>{};
  final phraseProfiles = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> currentPhraseCandidates = const [];
  Map<String, dynamic>? diagnosis;
  Map<String, dynamic>? selectedWordDetails;
  Map<String, dynamic>? selectedDictionary;
  SubtitleToken? selectedToken;
  Cue? selectedCue;
  int sidePanel = 0;

  AppLocalizations get l => AppLocalizations.of(context);

  TimelineCursor get primaryCursor => TimelineCursor(
    primaryTrack?.cues ?? const [],
    offset: primarySubtitleOffset,
  );
  TimelineCursor get secondaryCursor => TimelineCursor(
    secondaryTrack?.cues ?? const [],
    offset: secondarySubtitleOffset,
  );
  ExternalTools get tools => ExternalTools(
    ffmpegPath: ffmpegPath,
    ffprobePath: ffprobePath,
    ytDlpPath: ytDlpPath,
  );
  double get transcriptItemExtent => 76;

  @override
  void initState() {
    super.initState();
    unawaited(_connectApi());
    unawaited(_loadSettings());
    subscriptions.addAll([
      adapter.position.listen(_onPosition),
      adapter.duration.listen((value) => setState(() => duration = value)),
      adapter.playing.listen((value) => setState(() => playing = value)),
      adapter.errors.listen((value) => setState(() => status = value)),
      adapter.tracks.listen((value) {
        if (!mounted) return;
        String? defaultId;
        for (final track in value.audio) {
          if (track.isDefault == true) {
            defaultId = track.id;
            break;
          }
        }
        setState(() {
          audioTracks = value.audio;
          selectedAudioId = defaultId;
          embeddedSubtitleTracks = value.subtitle;
        });
      }),
    ]);
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettings.load();
    if (!mounted) return;
    setState(() {
      rate = settings.rate;
      volume = settings.volume;
      primarySubtitleOffset = Duration(
        milliseconds: settings.primarySubtitleOffsetMs,
      );
      secondarySubtitleOffset = Duration(
        milliseconds: settings.secondarySubtitleOffsetMs,
      );
      subtitlesVisible = settings.subtitlesVisible;
      secondarySubtitlesVisible = settings.secondarySubtitlesVisible;
      statusStylesVisible = settings.statusStylesVisible;
      primaryFontSize = settings.primaryFontSize;
      secondaryFontSize = settings.secondaryFontSize;
      primaryFontFamily = settings.primaryFontFamily;
      secondaryFontFamily = settings.secondaryFontFamily;
      subtitlePreset = settings.subtitlePreset;
      language = settings.language;
      appLanguage.value = language;
      subtitlePositionX = settings.subtitlePositionX;
      subtitlePositionY = settings.subtitlePositionY;
      subtitleBackgroundOpacity = settings.subtitleBackgroundOpacity;
      primaryColor = Color(settings.primaryColor);
      secondaryColor = Color(settings.secondaryColor);
      transcriptWidth = settings.transcriptWidth;
      ffmpegPath = settings.ffmpegPath;
      ffprobePath = settings.ffprobePath;
      ytDlpPath = settings.ytDlpPath;
      transcriptionQuality = settings.transcriptionQuality;
      transcriptionLanguage = settings.transcriptionLanguage;
      transcriptionDestination = settings.transcriptionDestination;
      openSubtitlesApiKey = settings.openSubtitlesApiKey;
    });
    await adapter.setRate(rate);
    await adapter.setVolume(volume);
  }

  Future<void> _saveSettings() => AppSettings(
    rate: rate,
    volume: volume,
    primarySubtitleOffsetMs: primarySubtitleOffset.inMilliseconds,
    secondarySubtitleOffsetMs: secondarySubtitleOffset.inMilliseconds,
    subtitlesVisible: subtitlesVisible,
    secondarySubtitlesVisible: secondarySubtitlesVisible,
    statusStylesVisible: statusStylesVisible,
    primaryFontSize: primaryFontSize,
    secondaryFontSize: secondaryFontSize,
    primaryFontFamily: primaryFontFamily,
    secondaryFontFamily: secondaryFontFamily,
    subtitlePreset: subtitlePreset,
    language: language,
    subtitlePositionX: subtitlePositionX,
    subtitlePositionY: subtitlePositionY,
    subtitleBackgroundOpacity: subtitleBackgroundOpacity,
    primaryColor: primaryColor.toARGB32(),
    secondaryColor: secondaryColor.toARGB32(),
    transcriptWidth: transcriptWidth,
    ffmpegPath: ffmpegPath,
    ffprobePath: ffprobePath,
    ytDlpPath: ytDlpPath,
    transcriptionQuality: transcriptionQuality,
    transcriptionLanguage: transcriptionLanguage,
    transcriptionDestination: transcriptionDestination,
    openSubtitlesApiKey: openSubtitlesApiKey,
  ).save();

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
        if (mediaId != null) unawaited(api?.saveProgress(mediaId!, position));
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
          job['media_id'] == mediaId &&
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
      } else if (mounted && job['media_id'] == mediaId) {
        setState(
          () => status =
              'ASR ${job['status']} · ${job['phase_progress'] as int}%',
        );
      }
      return;
    }
    if (event['event'] != 'word-profile-changed') return;
    final profile = event['payload'] as Map<String, dynamic>;
    setState(
      () => wordProfiles[profile['normalized_lemma'] as String] = profile,
    );
  }

  void _onPosition(Duration value) {
    final primaryCue = primaryCursor.current(value);
    final secondaryCue = secondaryCursor.current(value);
    if (loopCue &&
        currentPrimaryCue != null &&
        value >= primaryCursor.mediaEnd(currentPrimaryCue!)) {
      unawaited(adapter.seek(primaryCursor.mediaStart(currentPrimaryCue!)));
      return;
    }
    if (sourceLoopStart != null &&
        sourceLoopEnd != null &&
        value >= sourceLoopEnd!) {
      unawaited(adapter.seek(sourceLoopStart!));
      return;
    }
    if (primaryCue?.id != currentPrimaryCue?.id ||
        secondaryCue?.id != currentSecondaryCue?.id) {
      setState(() {
        currentPrimaryCue = primaryCue;
        currentSecondaryCue = secondaryCue;
      });
      _keepCurrentVisible(primaryCue);
      unawaited(_refreshDiagnosis());
      unawaited(_loadPhraseCandidates(primaryCue));
    } else {
      setState(() => position = value);
    }
    position = value;
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
    final previousMediaId = mediaId;
    final previousPosition = position;
    final previousProgressSave = previousMediaId == null
        ? Future<void>.value()
        : api?.saveProgress(previousMediaId, previousPosition) ??
              Future<void>.value();
    setState(() {
      mediaPath = path;
      mediaId = null;
      position = Duration.zero;
      duration = Duration.zero;
      primaryTrack = null;
      secondaryTrack = null;
      currentPrimaryCue = null;
      currentSecondaryCue = null;
      sourceLoopStart = null;
      sourceLoopEnd = null;
      status = 'Opening ${path.split(Platform.pathSeparator).last}';
    });
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
        setState(() {
          mediaId = id;
          mediaTitle = media['title'] as String;
          mediaFingerprint = media['fingerprint'] as String;
        });
        if (saved != null && saved > Duration.zero) {
          await adapter.seek(saved);
          if (mounted) setState(() => position = saved);
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
    if (mediaId == null || api == null) {
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
      final value = await api!.importSubtitle(mediaId!, path);
      await adapter.disableNativeSubtitles();
      setState(() {
        final imported = SubtitleTrack.fromJson(value);
        if (secondary) {
          secondaryTrack = imported;
          currentSecondaryCue = secondaryCursor.current(position);
        } else {
          primaryTrack = imported;
          currentPrimaryCue = primaryCursor.current(position);
        }
        status =
            'Loaded ${secondary ? 'secondary' : 'primary'} subtitle: '
            '${path.split(Platform.pathSeparator).last}';
      });
      if (!secondary) await _loadWordProfiles();
      if (!secondary) await _loadPhraseProfiles();
      if (!secondary) await _loadPhraseCandidates(currentPrimaryCue);
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
    setState(() {
      final imported = SubtitleTrack.fromJson(value);
      if (secondary) {
        secondaryTrack = imported;
        currentSecondaryCue = secondaryCursor.current(position);
      } else {
        primaryTrack = imported;
        currentPrimaryCue = primaryCursor.current(position);
      }
      status =
          'Loaded generated ${secondary ? 'secondary' : 'primary'} subtitle';
    });
    if (!secondary) await _loadWordProfiles();
    if (!secondary) await _loadPhraseProfiles();
    if (!secondary) await _loadPhraseCandidates(currentPrimaryCue);
  }

  Future<void> _generateSubtitles({required bool secondary}) async {
    if (api == null || mediaId == null) {
      setState(() => status = 'Open media and connect the local core first');
      return;
    }
    await showGenerateSubtitles(
      context: context,
      api: api!,
      mediaId: mediaId!,
      secondary: secondary,
      preferredQuality: transcriptionQuality,
      preferredLanguage: transcriptionLanguage,
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
      if (mediaId == null || api == null) {
        setState(() => status = 'Drop or open media before subtitles');
        return;
      }
      await _openSubtitlePath(path, secondary: primaryTrack != null);
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
      setState(() {
        mediaPath = pageUrl;
        mediaId = null;
        primaryTrack = null;
        secondaryTrack = null;
        currentPrimaryCue = null;
        currentSecondaryCue = null;
        status = 'Playing online media';
      });
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
        downloadProgress = 0;
        downloadedMediaPath = null;
        status = l.text('downloadingInBackground');
      });
      subscriptions.add(
        download.progress.listen((value) {
          if (mounted) setState(() => downloadProgress = value);
        }),
      );
      unawaited(
        download.completed.then(
          (path) {
            if (!mounted) return;
            setState(() {
              activeDownload = null;
              downloadedMediaPath = path;
              status = '${l.text('downloadComplete')}: $path';
            });
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
    final path = mediaPath;
    if (path == null || !_isMediaPath(path) || mediaId == null || api == null) {
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
        language: language,
        subtitlePreset: subtitlePreset,
        primaryFontSize: primaryFontSize,
        primaryFontFamily: primaryFontFamily,
        secondaryFontSize: secondaryFontSize,
        secondaryFontFamily: secondaryFontFamily,
        subtitlePositionX: subtitlePositionX,
        subtitlePositionY: subtitlePositionY,
        subtitleBackgroundOpacity: subtitleBackgroundOpacity,
        transcriptWidth: transcriptWidth,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        transcriptionQuality: transcriptionQuality,
        transcriptionLanguage: transcriptionLanguage,
        transcriptionDestination: transcriptionDestination,
        ffmpegPath: ffmpegPath,
        ffprobePath: ffprobePath,
        ytDlpPath: ytDlpPath,
        openSubtitlesApiKey: openSubtitlesApiKey,
        onLanguageChanged: (v) {
          setState(() => language = v);
          appLanguage.value = v;
          unawaited(_saveSettings());
        },
        onSubtitlePresetChanged: (v) {
          setState(() => subtitlePreset = v);
          unawaited(_saveSettings());
        },
        onPrimaryFontSizeChanged: (v) {
          setState(() => primaryFontSize = v);
          unawaited(_saveSettings());
        },
        onPrimaryFontFamilyChanged: (v) {
          setState(() => primaryFontFamily = v);
          unawaited(_saveSettings());
        },
        onSecondaryFontSizeChanged: (v) {
          setState(() => secondaryFontSize = v);
          unawaited(_saveSettings());
        },
        onSecondaryFontFamilyChanged: (v) {
          setState(() => secondaryFontFamily = v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionXChanged: (v) {
          setState(() => subtitlePositionX = v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionYChanged: (v) {
          setState(() => subtitlePositionY = v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionReset: () {
          setState(() {
            subtitlePositionX = 0.5;
            subtitlePositionY = 0.82;
          });
          unawaited(_saveSettings());
        },
        onBackgroundOpacityChanged: (v) {
          setState(() => subtitleBackgroundOpacity = v);
          unawaited(_saveSettings());
        },
        onTranscriptWidthChanged: (v) {
          setState(() => transcriptWidth = v);
          unawaited(_saveSettings());
        },
        onPrimaryColorChanged: (v) {
          setState(() => primaryColor = v);
          unawaited(_saveSettings());
        },
        onSecondaryColorChanged: (v) {
          setState(() => secondaryColor = v);
          unawaited(_saveSettings());
        },
        onTranscriptionQualityChanged: (v) {
          setState(() => transcriptionQuality = v);
          unawaited(_saveSettings());
        },
        onTranscriptionLanguageChanged: (v) {
          setState(() => transcriptionLanguage = v);
          unawaited(_saveSettings());
        },
        onTranscriptionDestinationChanged: (v) {
          setState(() => transcriptionDestination = v);
          unawaited(_saveSettings());
        },
        onSave: ({
          required String ffmpegPath,
          required String ffprobePath,
          required String ytDlpPath,
          required String openSubtitlesApiKey,
        }) async {
          setState(() {
            this.ffmpegPath = ffmpegPath;
            this.ffprobePath = ffprobePath;
            this.ytDlpPath = ytDlpPath;
            this.openSubtitlesApiKey = openSubtitlesApiKey;
          });
          await _saveSettings();
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
    final cue = currentPrimaryCue;
    if (api == null || cue == null || mediaFingerprint == null) return;
    await showPhraseCandidates(
      context: context,
      api: api!,
      sentenceId: cue.id,
      source: {
        'media_id': mediaId,
        'sentence_id': cue.id,
        'sentence_text': cue.text,
        'media_title': mediaTitle ?? '',
        'media_fingerprint': mediaFingerprint,
        'start_ms': cue.start.inMilliseconds,
        'end_ms': cue.end.inMilliseconds,
      },
    );
  }

  Future<void> _loadPhraseCandidates(Cue? cue) async {
    if (api == null || cue == null) {
      if (mounted) setState(() => currentPhraseCandidates = const []);
      return;
    }
    try {
      if (mounted && currentPrimaryCue?.id == cue.id) {
        setState(() => currentPhraseCandidates = const []);
      }
      final candidates = await api!.phraseCandidates(cue.id);
      if (mounted && currentPrimaryCue?.id == cue.id) {
        setState(() => currentPhraseCandidates = candidates);
      }
    } catch (_) {
      if (mounted && currentPrimaryCue?.id == cue.id) {
        setState(() => currentPhraseCandidates = const []);
      }
    }
  }

  Future<void> _openPhrase(Map<String, dynamic> candidate, Cue cue) async {
    if (api == null || mediaFingerprint == null) return;
    final canonical = candidate['canonical_form'] as String;
    final details = await showPhraseCandidate(
      context: context,
      api: api!,
      candidate: candidate,
      initialStatus:
          (phraseProfiles[canonical]?['entry']
                  as Map<String, dynamic>?)?['status']
              as String?,
      source: {
        'media_id': mediaId,
        'sentence_id': cue.id,
        'sentence_text': cue.text,
        'media_title': mediaTitle ?? '',
        'media_fingerprint': mediaFingerprint,
        'start_ms': cue.start.inMilliseconds,
        'end_ms': cue.end.inMilliseconds,
      },
    );
    if (details != null && mounted) {
      setState(() {
        phraseProfiles[canonical] = details;
        status = 'Saved phrase "${candidate['display_form']}"';
      });
    }
  }

  Future<void> _correctCurrentLemma() async {
    final token = selectedToken;
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
    if (mediaId == null) {
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
    if (openSubtitlesApiKey.isEmpty) {
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
      setState(() => openSubtitlesApiKey = configured);
      await _saveSettings();
    }
    if (!mounted) return;
    final path = await showOpenSubtitlesSearch(
      context: context,
      api: api!,
      apiKey: openSubtitlesApiKey,
      initialTitle: mediaTitle ?? '',
      initialFilename: mediaPath == null
          ? ''
          : mediaPath!.split(Platform.pathSeparator).last,
      mediaPath: mediaPath,
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
    final cue = currentPrimaryCue;
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
    setState(() => wordProfiles[token.normalized!] = profile);
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
    final lemmas = primaryTrack?.cues
        .expand((cue) => cue.tokens)
        .where((token) => token.kind == 'word' && token.normalized != null)
        .map((token) => token.normalized!)
        .toSet()
        .toList();
    if (lemmas == null || api == null) return;
    final values = await api!.readWordProfiles(lemmas);
    setState(() {
      wordProfiles
        ..clear()
        ..addEntries(
          values.map(
            (profile) =>
                MapEntry(profile['normalized_lemma'] as String, profile),
          ),
        );
    });
  }

  Future<void> _loadPhraseProfiles() async {
    if (api == null) return;
    final values = await api!.lexicalEntries(kind: 'phrase');
    if (!mounted) return;
    setState(() {
      phraseProfiles
        ..clear()
        ..addEntries(
          values.map((details) {
            final entry = details['entry'] as Map<String, dynamic>;
            return MapEntry(entry['canonical_form'] as String, details);
          }),
        );
    });
  }

  Future<void> _openWord(SubtitleToken token, Cue cue) async {
    final lemma = token.normalized;
    if (lemma == null || api == null) return;
    try {
      var profile = wordProfiles[lemma];
      profile ??= await api!.updateWordProfile(lemma, token.text, null);
      final details = await api!.wordDetails(profile['id'] as String);
      final dictionary = await api!.lookupDictionary(lemma);
      if (!mounted) return;
      setState(() {
        wordProfiles[lemma] = profile!;
        selectedToken = token;
        selectedCue = cue;
        selectedWordDetails = details;
        selectedDictionary = dictionary;
        sidePanel = 1;
      });
    } catch (error) {
      if (mounted) setState(() => status = 'Dictionary unavailable: $error');
    }
  }

  Future<void> _setSelectedWordStatus(String? selected) async {
    final token = selectedToken;
    final cue = selectedCue;
    if (token?.normalized == null || cue == null || api == null) return;
    try {
      final profile = await api!.updateWordProfile(
        token!.normalized!,
        token.text,
        selected,
        _sourceFor(token, cue),
      );
      final details = await api!.wordDetails(profile['id'] as String);
      setState(() {
        wordProfiles[token.normalized!] = profile;
        selectedWordDetails = details;
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
    final profile = selectedWordDetails?['profile'] as Map<String, dynamic>?;
    if (profile == null || api == null) return;
    final details = await api!.updateLearningContent(
      profile['id'] as String,
      userDefinition: definition,
      personalNote: note,
    );
    if (mounted) setState(() => selectedWordDetails = details);
  }

  Future<void> _observeSelected(bool heard) async {
    final token = selectedToken;
    final cue = selectedCue;
    final profile = selectedWordDetails?['profile'] as Map<String, dynamic>?;
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
    if (mediaFingerprint == null) return null;
    return {
      'language': 'en',
      'normalized_lemma': token.normalized,
      'media_id': mediaId,
      'sentence_id': cue.id,
      'original_form': token.text,
      'sentence_text': cue.text,
      'media_title': mediaTitle ?? '',
      'media_fingerprint': mediaFingerprint,
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
    if (expectedFingerprint != mediaFingerprint) {
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
      sourceLoopStart = start;
      sourceLoopEnd = end;
      loopCue = false;
      status = 'Looping vocabulary source sentence';
    });
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> _playOccurrence(Map<String, dynamic> occurrence) async {
    final expectedFingerprint =
        occurrence['media_fingerprint_snapshot'] as String;
    if (expectedFingerprint != mediaFingerprint) {
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
    setState(() {
      sourceLoopStart = start;
      sourceLoopEnd = Duration(
        milliseconds: occurrence['end_ms_snapshot'] as int,
      );
      loopCue = false;
    });
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
    if (api == null || mediaId == null) return;
    await api!.setMediaAvailability(mediaId!, 'archived');
    setState(
      () =>
          status = 'Archived current media record; vocabulary assets preserved',
    );
  }

  Future<void> _refreshDiagnosis() async {
    final cue = currentPrimaryCue;
    final service = api;
    if (cue == null || service == null) {
      if (mounted) setState(() => diagnosis = null);
      return;
    }
    try {
      final value = await service.diagnose(cue.id);
      if (mounted && cue.id == currentPrimaryCue?.id) {
        setState(() => diagnosis = value);
      }
    } catch (_) {
      if (mounted && cue.id == currentPrimaryCue?.id) {
        setState(() => diagnosis = null);
      }
    }
  }

  Future<void> _seekCue(Cue? cue) async {
    if (cue == null) return;
    setState(() => currentPrimaryCue = cue);
    unawaited(_refreshDiagnosis());
    await adapter.seek(primaryCursor.mediaStart(cue));
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
    if (mediaId != null) unawaited(api?.saveProgress(mediaId!, position));
    activeDownload?.cancel();
    unawaited(_saveSettings());
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    transcriptController.dispose();
    progressTimer?.cancel();
    unawaited(adapter.dispose());
    unawaited(api?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.space): adapter.playOrPause,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _seekCue(primaryCursor.previous(currentPrimaryCue)),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _seekCue(primaryCursor.next(currentPrimaryCue)),
      const SingleActivator(LogicalKeyboardKey.keyL): () =>
          setState(() => loopCue = !loopCue),
      const SingleActivator(LogicalKeyboardKey.keyH): () =>
          setState(() => subtitlesVisible = !subtitlesVisible),
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
          onOpenLearningAssets: () =>
              unawaited(_openLearningAssets()),
          onOpenLearningResources: () =>
              unawaited(_openLearningResources()),
          onShowPhraseCandidates: () =>
              unawaited(_showCurrentPhraseCandidates()),
          onCorrectLemma: () => unawaited(_correctCurrentLemma()),
          onSearchOpenSubtitles: () =>
              unawaited(_searchOpenSubtitles()),
        ),
        body: DropTarget(
          onDragEntered: (_) => setState(() => dragging = true),
          onDragExited: (_) => setState(() => dragging = false),
          onDragDone: (details) {
            setState(() => dragging = false);
            unawaited(
              _handleDrop(details.files.map((file) => file.path).toList()),
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
                      if (subtitlesVisible || selectedWordDetails != null)
                        SizedBox(width: transcriptWidth, child: _sidePanel()),
                    ],
                  ),
                ),
                if (activeDownload != null || downloadedMediaPath != null)
                  _downloadStatusBar(),
                _controls(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _playerSurface() => LayoutBuilder(
    builder: (context, constraints) {
      final primarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: primaryFontSize,
        preset: subtitlePreset,
        textLength: currentPrimaryCue?.text.length ?? 1,
      );
      final secondarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: secondaryFontSize,
        preset: subtitlePreset,
        textLength: currentSecondaryCue?.text.length ?? 1,
        secondary: true,
      );
      final backgroundFactor = subtitlePreset == 'watching'
          ? 0.45
          : subtitlePreset == 'compact'
          ? 0.3
          : 1.0;
      final subtitlePosition = Offset(subtitlePositionX, subtitlePositionY);
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: PlayerSurface(adapter: adapter),
            ),
          ),
          if (subtitlesVisible &&
              (currentPrimaryCue != null ||
                  (secondarySubtitlesVisible && currentSecondaryCue != null)))
            Align(
              alignment: Alignment(
                subtitlePosition.dx * 2 - 1,
                subtitlePosition.dy * 2 - 1,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) => setState(() {
                    final moved = moveSubtitlePosition(
                      current: Offset(subtitlePositionX, subtitlePositionY),
                      delta: details.delta,
                      viewport: constraints.biggest,
                    );
                    subtitlePositionX = moved.dx;
                    subtitlePositionY = moved.dy;
                  }),
                  onPanEnd: (_) => unawaited(_saveSettings()),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.82,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha: subtitleBackgroundOpacity * backgroundFactor,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: subtitlePreset == 'compact' ? 10 : 18,
                          vertical: subtitlePreset == 'compact' ? 6 : 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (currentPrimaryCue != null)
                              GestureDetector(
                                onTap: () => _seekCue(currentPrimaryCue),
                                child: TokenLine(
                                  cue: currentPrimaryCue!,
                                  profiles: wordProfiles,
                                  phraseCandidates: currentPhraseCandidates,
                                  phraseProfiles: phraseProfiles,
                                  showStyles: statusStylesVisible,
                                  fontSize: primarySize,
                                  fontFamily: _subtitleFont(primaryFontFamily),
                                  baseColor: primaryColor,
                                  onWord: _openWord,
                                  onPhrase: _openPhrase,
                                ),
                              ),
                            if (secondarySubtitlesVisible &&
                                currentSecondaryCue != null)
                              GestureDetector(
                                onTap: () => adapter.seek(
                                  secondaryCursor.mediaStart(
                                    currentSecondaryCue!,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    currentSecondaryCue!.text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: secondarySize,
                                      fontFamily: _subtitleFont(
                                        secondaryFontFamily,
                                      ),
                                      color: secondaryColor,
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
          if (mediaPath == null)
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
          selected: {sidePanel},
          onSelectionChanged: (value) =>
              setState(() => sidePanel = value.first),
          showSelectedIcon: false,
        ),
        Expanded(
          child: switch (sidePanel) {
            1 =>
              selectedWordDetails == null
                  ? Center(child: Text(l.text('noWordSelected')))
                  : WordLearningPanel(
                      details: selectedWordDetails!,
                      dictionary: selectedDictionary,
                      onStatus: _setSelectedWordStatus,
                      onSave: _saveSelectedLearningContent,
                      onSource: _playOccurrence,
                      onHeard: () => _observeSelected(true),
                      onNotHeard: () => _observeSelected(false),
                    ),
            2 =>
              diagnosis == null
                  ? Center(child: Text(l.text('diagnosis')))
                  : _diagnosisCard(),
            _ => _transcript(),
          },
        ),
      ],
    ),
  );

  Widget _transcript() => TranscriptPanel(
    track: primaryTrack,
    scrollController: transcriptController,
    itemExtent: transcriptItemExtent,
    currentCue: currentPrimaryCue,
    wordProfiles: wordProfiles,
    showStyles: statusStylesVisible,
    baseColor: primaryColor,
    onWord: _openWord,
    onSeekCue: _seekCue,
  );

  Widget _diagnosisCard() => DiagnosisCard(diagnosis: diagnosis!);

  Widget _controls() => PlaybackControls(
    adapter: adapter,
    position: position,
    duration: duration,
    playing: playing,
    loopCue: loopCue,
    sourceLoopStart: sourceLoopStart,
    statusStylesVisible: statusStylesVisible,
    subtitlesVisible: subtitlesVisible,
    secondarySubtitlesVisible: secondarySubtitlesVisible,
    rate: rate,
    volume: volume,
    muted: muted,
    audioTracks: audioTracks,
    selectedAudioId: selectedAudioId,
    embeddedSubtitleTracks: embeddedSubtitleTracks,
    selectedEmbeddedSubtitleId: selectedEmbeddedSubtitleId,
    primarySubtitleOffset: primarySubtitleOffset,
    secondarySubtitleOffset: secondarySubtitleOffset,
    status: status,
    onSeek: (value) => adapter.seek(value),
    onSeekToPreviousCue: () =>
        _seekCue(primaryCursor.previous(currentPrimaryCue)),
    onSeekToZero: () => adapter.seek(Duration.zero),
    onPlayPause: adapter.playOrPause,
    onStop: adapter.stop,
    onSeekToNextCue: () =>
        _seekCue(primaryCursor.next(currentPrimaryCue)),
    onLoopCueChanged: (value) => setState(() {
      loopCue = value;
      if (value) {
        sourceLoopStart = null;
        sourceLoopEnd = null;
      }
    }),
    onStopSourceLoop: () => setState(() {
      sourceLoopStart = null;
      sourceLoopEnd = null;
    }),
    onStatusStylesChanged: (value) {
      setState(() => statusStylesVisible = value);
      unawaited(_saveSettings());
    },
    onSubtitlesVisibleChanged: (value) {
      setState(() => subtitlesVisible = value);
      unawaited(_saveSettings());
    },
    onSecondaryVisibleChanged: (value) {
      setState(() => secondarySubtitlesVisible = value);
      unawaited(_saveSettings());
    },
    onRateChanged: (value) {
      setState(() => rate = value);
      adapter.setRate(value);
      unawaited(_saveSettings());
    },
    onVolumeChanged: (value) {
      setState(() => volume = value);
      if (!muted) adapter.setVolume(value);
      unawaited(_saveSettings());
    },
    onMuteToggle: () {
      setState(() => muted = !muted);
      adapter.setVolume(muted ? 0 : volume);
    },
    onAudioTrackChanged: (track) {
      setState(() => selectedAudioId = track.id);
      adapter.selectAudio(track);
    },
    onEmbeddedSubtitleTrackChanged: (track) {
      setState(() => selectedEmbeddedSubtitleId = track.id);
      adapter.selectSubtitle(track);
    },
    onPrimaryOffsetChanged: (offset) {
      setState(() => primarySubtitleOffset = offset);
      unawaited(_saveSettings());
    },
    onSecondaryOffsetChanged: (offset) {
      setState(() => secondarySubtitleOffset = offset);
      unawaited(_saveSettings());
    },
  );

  Widget _downloadStatusBar() => DownloadStatusBar(
    activeDownload: activeDownload,
    downloadProgress: downloadProgress,
    downloadedMediaPath: downloadedMediaPath,
    onCancel: () {
      activeDownload?.cancel();
      setState(() => activeDownload = null);
    },
    onOpenMediaPath: () => _openMediaPath(downloadedMediaPath!),
    onDismiss: () => setState(() {
      downloadedMediaPath = null;
      if (activeDownload != null) activeDownload?.cancel();
      activeDownload = null;
    }),
  );
}
