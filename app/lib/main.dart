import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart' hide SubtitleTrack;
import 'package:media_kit/media_kit.dart' as media;
import 'package:media_kit_video/media_kit_video.dart';

import 'local_api.dart';
import 'localization.dart';
import 'external_tools.dart';
import 'player_adapter.dart';
import 'settings.dart';
import 'timeline.dart';
import 'transcription_ui.dart';
import 'm18_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const LLPlayerNextApp());
}

double responsiveSubtitleSize({
  required double width,
  required double scale,
  required String preset,
  required int textLength,
  bool secondary = false,
}) {
  final presetFactor = switch (preset) {
    'watching' => 0.82,
    'compact' => 0.7,
    _ => 1.0,
  };
  final base = (width * 0.034).clamp(18.0, 34.0);
  final targetLength = secondary ? 84 : 72;
  final minimum = secondary ? 0.78 : 0.72;
  final lengthFactor = (targetLength / textLength.clamp(1, 1000)).clamp(
    minimum,
    1.0,
  );
  return base * (secondary ? 0.72 : 1) * scale * presetFactor * lengthFactor;
}

Offset moveSubtitlePosition({
  required Offset current,
  required Offset delta,
  required Size viewport,
}) => Offset(
  (current.dx + delta.dx / viewport.width).clamp(0.0, 1.0),
  (current.dy + delta.dy / viewport.height).clamp(0.0, 1.0),
);

List<Map<String, dynamic>> parseExternalWordList(
  String content, {
  required bool csv,
}) {
  if (!csv) {
    return const LineSplitter()
        .convert(content)
        .where((line) => line.trim().isNotEmpty)
        .map((line) => <String, dynamic>{'word': line.trim(), 'status': null})
        .toList(growable: false);
  }
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(content.replaceAll('\r\n', '\n'));
  if (rows.isEmpty) return const [];
  final headers = rows.first
      .map((value) => value.toString().trim().toLowerCase())
      .toList();
  final wordIndex = headers.indexOf('word');
  final statusIndex = headers.indexOf('status');
  if (wordIndex < 0) {
    throw const FormatException('CSV must contain a word column');
  }
  const statuses = {
    'unknown_meaning',
    'known_not_recognized',
    'known_recognized',
  };
  return rows
      .skip(1)
      .where((row) => wordIndex < row.length)
      .map((row) {
        final importedStatus = statusIndex >= 0 && statusIndex < row.length
            ? row[statusIndex].toString().trim()
            : '';
        return <String, dynamic>{
          'word': row[wordIndex].toString(),
          'status': statuses.contains(importedStatus) ? importedStatus : null,
        };
      })
      .toList(growable: false);
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
  List<AudioTrack> audioTracks = const [];
  String? selectedAudioId;
  List<media.SubtitleTrack> embeddedSubtitleTracks = const [];
  String? selectedEmbeddedSubtitleId;
  final wordProfiles = <String, Map<String, dynamic>>{};
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
    await adapter.open(path);
    setState(() {
      mediaPath = path;
      mediaId = null;
      primaryTrack = null;
      secondaryTrack = null;
      currentPrimaryCue = null;
      currentSecondaryCue = null;
      sourceLoopStart = null;
      sourceLoopEnd = null;
      status = 'Playing ${path.split(Platform.pathSeparator).last}';
    });
    try {
      final media = await api?.registerMedia(path);
      if (media != null) {
        final id = media['id'] as String;
        final saved = await api?.readProgress(id);
        setState(() {
          mediaId = id;
          mediaTitle = media['title'] as String;
          mediaFingerprint = media['fingerprint'] as String;
        });
        if (saved != null && saved > Duration.zero) await adapter.seek(saved);
      }
    } catch (error) {
      setState(() => status = 'Playing locally; core unavailable: $error');
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
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.text('resolvePlay')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pageUrl == null || pageUrl.isEmpty) return;
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
    final ffmpegController = TextEditingController(text: ffmpegPath);
    final ffprobeController = TextEditingController(text: ffprobePath);
    final ytDlpController = TextEditingController(text: ytDlpPath);
    final openSubtitlesController = TextEditingController(
      text: openSubtitlesApiKey,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(l.text('settings')),
          content: SizedBox(
            width: 620,
            height: 650,
            child: ListView(
              children: [
                Text(
                  l.text('subtitles'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButtonFormField<String>(
                  initialValue: language,
                  decoration: InputDecoration(labelText: l.text('language')),
                  items: [
                    DropdownMenuItem(
                      value: 'system',
                      child: Text(l.text('system')),
                    ),
                    DropdownMenuItem(
                      value: 'en',
                      child: Text(l.text('english')),
                    ),
                    DropdownMenuItem(
                      value: 'zh',
                      child: Text(l.text('chinese')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => language = value);
                    appLanguage.value = value;
                    refresh(() {});
                    unawaited(_saveSettings());
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: subtitlePreset,
                  decoration: InputDecoration(
                    labelText: l.text('subtitlePreset'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'watching',
                      child: Text(l.text('watching')),
                    ),
                    DropdownMenuItem(
                      value: 'learning',
                      child: Text(l.text('learning')),
                    ),
                    DropdownMenuItem(
                      value: 'compact',
                      child: Text(l.text('compact')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => subtitlePreset = value);
                    refresh(() {});
                    unawaited(_saveSettings());
                  },
                ),
                _settingSlider(
                  l.text('subtitleScale'),
                  primaryFontSize,
                  0.5,
                  2,
                  (value) => setState(() => primaryFontSize = value),
                  refresh,
                ),
                _fontSelector(
                  l.text('primaryFont'),
                  primaryFontFamily,
                  (value) => setState(() => primaryFontFamily = value),
                  refresh,
                ),
                _settingSlider(
                  l.text('secondaryScale'),
                  secondaryFontSize,
                  0.5,
                  2,
                  (value) => setState(() => secondaryFontSize = value),
                  refresh,
                ),
                _fontSelector(
                  l.text('secondaryFont'),
                  secondaryFontFamily,
                  (value) => setState(() => secondaryFontFamily = value),
                  refresh,
                ),
                Text(
                  l.text('dragSubtitleHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _settingSlider(
                  l.text('horizontalPosition'),
                  subtitlePositionX,
                  0,
                  1,
                  (value) => setState(() => subtitlePositionX = value),
                  refresh,
                ),
                _settingSlider(
                  l.text('verticalPosition'),
                  subtitlePositionY,
                  0,
                  1,
                  (value) => setState(() => subtitlePositionY = value),
                  refresh,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        subtitlePositionX = 0.5;
                        subtitlePositionY = 0.82;
                      });
                      refresh(() {});
                      unawaited(_saveSettings());
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l.text('resetSubtitlePosition')),
                  ),
                ),
                _settingSlider(
                  l.text('backgroundOpacity'),
                  subtitleBackgroundOpacity,
                  0,
                  1,
                  (value) => setState(() => subtitleBackgroundOpacity = value),
                  refresh,
                ),
                _settingSlider(
                  l.text('transcriptWidth'),
                  transcriptWidth,
                  260,
                  900,
                  (value) => setState(() => transcriptWidth = value),
                  refresh,
                ),
                const SizedBox(height: 8),
                Text(l.text('primaryColor')),
                _colorChoices(primaryColor, (value) {
                  setState(() => primaryColor = value);
                  refresh(() {});
                }),
                Text(l.text('secondaryColor')),
                _colorChoices(secondaryColor, (value) {
                  setState(() => secondaryColor = value);
                  refresh(() {});
                }),
                const Divider(),
                Text(
                  l.text('transcriptionDefaults'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButtonFormField<String>(
                  initialValue: transcriptionQuality,
                  decoration: InputDecoration(
                    labelText: l.text('preferredQuality'),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'fast', child: Text('Fast')),
                    DropdownMenuItem(
                      value: 'balanced',
                      child: Text('Balanced'),
                    ),
                    DropdownMenuItem(
                      value: 'accurate',
                      child: Text('Accurate'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => transcriptionQuality = value);
                    refresh(() {});
                    unawaited(_saveSettings());
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: transcriptionLanguage,
                  decoration: InputDecoration(
                    labelText: l.text('transcriptionLanguage'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(l.text('automatic')),
                    ),
                    const DropdownMenuItem(value: 'en', child: Text('English')),
                    const DropdownMenuItem(value: 'zh', child: Text('中文')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => transcriptionLanguage = value);
                    refresh(() {});
                    unawaited(_saveSettings());
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: transcriptionDestination,
                  decoration: InputDecoration(
                    labelText: l.text('defaultDestination'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'primary',
                      child: Text(l.text('primarySubtitle')),
                    ),
                    DropdownMenuItem(
                      value: 'secondary',
                      child: Text(l.text('secondarySubtitle')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => transcriptionDestination = value);
                    refresh(() {});
                    unawaited(_saveSettings());
                  },
                ),
                const Divider(),
                Text(
                  l.text('externalTools'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextField(
                  controller: ffmpegController,
                  decoration: const InputDecoration(
                    labelText: 'ffmpeg path (auto-detect when empty)',
                  ),
                ),
                TextField(
                  controller: ffprobeController,
                  decoration: const InputDecoration(
                    labelText: 'ffprobe path (auto-detect when empty)',
                  ),
                ),
                TextField(
                  controller: ytDlpController,
                  decoration: const InputDecoration(
                    labelText: 'yt-dlp path (auto-detect when empty)',
                  ),
                ),
                TextField(
                  controller: openSubtitlesController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l.text('openSubtitlesApiKey'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.text('close')),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  ffmpegPath = ffmpegController.text.trim();
                  ffprobePath = ffprobeController.text.trim();
                  ytDlpPath = ytDlpController.text.trim();
                  openSubtitlesApiKey = openSubtitlesController.text.trim();
                });
                unawaited(_saveSettings());
                Navigator.pop(context);
              },
              child: Text(l.text('save')),
            ),
          ],
        ),
      ),
    );
    ffmpegController.dispose();
    ffprobeController.dispose();
    ytDlpController.dispose();
    openSubtitlesController.dispose();
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

  Future<void> _searchOpenSubtitles() async {
    if (api == null || mediaId == null) return;
    if (openSubtitlesApiKey.isEmpty) {
      setState(() => status = l.text('configureOpenSubtitles'));
      return;
    }
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
    final secondary = await showDialog<bool>(
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
    if (secondary != null) await _openSubtitlePath(path, secondary: secondary);
  }

  Widget _settingSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update,
    StateSetter refresh,
  ) => Row(
    children: [
      SizedBox(width: 160, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (next) {
            update(next);
            refresh(() {});
            unawaited(_saveSettings());
          },
        ),
      ),
      SizedBox(width: 56, child: Text(value.toStringAsFixed(1))),
    ],
  );

  Widget _colorChoices(Color selected, ValueChanged<Color> update) => Wrap(
    spacing: 8,
    children: [
      for (final color in const [
        Colors.white,
        Color(0xffb8d8ff),
        Colors.amber,
        Colors.greenAccent,
        Colors.pinkAccent,
      ])
        ChoiceChip(
          selected: selected.toARGB32() == color.toARGB32(),
          label: Container(width: 32, height: 16, color: color),
          onSelected: (_) => update(color),
        ),
    ],
  );

  Widget _fontSelector(
    String label,
    String value,
    ValueChanged<String> update,
    StateSetter refresh,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: 'system', child: Text(l.text('systemFont'))),
      DropdownMenuItem(value: 'serif', child: Text(l.text('serifFont'))),
      DropdownMenuItem(
        value: 'monospace',
        child: Text(l.text('monospaceFont')),
      ),
    ],
    onChanged: (next) {
      if (next == null) return;
      update(next);
      refresh(() {});
      unawaited(_saveSettings());
    },
  );

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
        appBar: AppBar(
          title: const Text('LLPlayerNext'),
          actions: [
            TextButton.icon(
              onPressed: _openVocabulary,
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(l.text('vocabulary')),
            ),
            TextButton.icon(
              onPressed: _openMedia,
              icon: const Icon(Icons.video_file_outlined),
              label: Text(l.text('openMedia')),
            ),
            TextButton.icon(
              onPressed: _openOnline,
              icon: const Icon(Icons.language),
              label: Text(l.text('openUrl')),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'import') {
                  unawaited(_openSubtitle(secondary: false));
                } else {
                  unawaited(_generateSubtitles(secondary: false));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'import',
                  child: Text(l.text('importSubtitleHint')),
                ),
                PopupMenuItem(
                  value: 'generate',
                  child: Text(l.text('generateSubtitles')),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.subtitles_outlined),
                    const SizedBox(width: 8),
                    Text(l.text('primarySubtitle')),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'import') {
                  unawaited(_openSubtitle(secondary: true));
                } else {
                  unawaited(_generateSubtitles(secondary: true));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'import',
                  child: Text(l.text('importSubtitleHint')),
                ),
                PopupMenuItem(
                  value: 'generate',
                  child: Text(l.text('generateSubtitles')),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.closed_caption_outlined),
                    const SizedBox(width: 8),
                    Text(l.text('secondarySubtitle')),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'embedded') unawaited(_importEmbeddedSubtitle());
                if (value == 'settings') unawaited(_openSettings());
                if (value == 'logs') unawaited(_exportLogs());
                if (value == 'export-vocabulary') {
                  unawaited(_exportVocabulary());
                }
                if (value == 'import-vocabulary') {
                  unawaited(_importVocabulary());
                }
                if (value == 'import-word-list') unawaited(_importWordList());
                if (value == 'archive-media') unawaited(_archiveCurrentMedia());
                if (value == 'transcription') {
                  unawaited(_openTranscriptionCenter());
                }
                if (value == 'learning-assets') {
                  unawaited(_openLearningAssets());
                }
                if (value == 'learning-resources') {
                  unawaited(_openLearningResources());
                }
                if (value == 'phrase-candidates') {
                  unawaited(_showCurrentPhraseCandidates());
                }
                if (value == 'correct-lemma') unawaited(_correctCurrentLemma());
                if (value == 'opensubtitles') {
                  unawaited(_searchOpenSubtitles());
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'embedded',
                  child: Text(l.text('importEmbeddedText')),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Text(l.text('settings')),
                ),
                PopupMenuItem(value: 'logs', child: Text(l.text('exportLogs'))),
                PopupMenuItem(
                  value: 'export-vocabulary',
                  child: Text(l.text('exportAssets')),
                ),
                PopupMenuItem(
                  value: 'import-vocabulary',
                  child: Text(l.text('importAssets')),
                ),
                PopupMenuItem(
                  value: 'import-word-list',
                  child: Text(l.text('importWordList')),
                ),
                PopupMenuItem(
                  value: 'archive-media',
                  child: Text(l.text('archiveMedia')),
                ),
                PopupMenuItem(
                  value: 'transcription',
                  child: Text(l.text('transcriptionCenter')),
                ),
                PopupMenuItem(
                  value: 'learning-assets',
                  child: Text(l.text('learningAssets')),
                ),
                PopupMenuItem(
                  value: 'learning-resources',
                  child: Text(l.text('resources')),
                ),
                PopupMenuItem(
                  value: 'phrase-candidates',
                  child: Text(l.text('phraseCandidates')),
                ),
                const PopupMenuItem(
                  value: 'correct-lemma',
                  child: Text('Correct selected lemma'),
                ),
                PopupMenuItem(
                  value: 'opensubtitles',
                  child: Text(l.text('openSubtitles')),
                ),
              ],
            ),
            const SizedBox(width: 12),
          ],
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
              child: Video(
                controller: adapter.videoController,
                controls: NoVideoControls,
              ),
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
                                  showStyles: statusStylesVisible,
                                  fontSize: primarySize,
                                  fontFamily: _subtitleFont(primaryFontFamily),
                                  baseColor: primaryColor,
                                  onWord: _openWord,
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

  Widget _transcript() => Material(
    color: const Color(0xff151a20),
    child: primaryTrack == null
        ? Center(child: Text(l.text('importSubtitleHint')))
        : Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: transcriptController,
                  itemExtent: transcriptItemExtent,
                  itemCount: primaryTrack!.cues.length,
                  itemBuilder: (context, index) {
                    final cue = primaryTrack!.cues[index];
                    final selected = cue.id == currentPrimaryCue?.id;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.55),
                      leading: Text(_format(cue.start)),
                      title: TokenLine(
                        cue: cue,
                        profiles: wordProfiles,
                        showStyles: statusStylesVisible,
                        baseColor: primaryColor,
                        onWord: _openWord,
                      ),
                      onTap: () => _seekCue(cue),
                    );
                  },
                ),
              ),
            ],
          ),
  );

  Widget _diagnosisCard() => Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxHeight: 190),
    padding: const EdgeInsets.all(12),
    color: const Color(0xff202832),
    child: ListView(
      shrinkWrap: true,
      children: [
        const Text(
          'Current sentence diagnosis',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final hint in diagnosis!['hints'] as List<dynamic>)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('• ${l.diagnosis(hint['kind'] as String)}'),
          ),
      ],
    ),
  );

  Widget _controls() => Material(
    color: const Color(0xff11161c),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(_format(position)),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds
                      .clamp(0, duration.inMilliseconds.clamp(1, 1 << 31))
                      .toDouble(),
                  max: duration.inMilliseconds.clamp(1, 1 << 31).toDouble(),
                  onChanged: (value) =>
                      adapter.seek(Duration(milliseconds: value.round())),
                ),
              ),
              Text(_format(duration)),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: l.text('previousSentence'),
                  onPressed: () =>
                      _seekCue(primaryCursor.previous(currentPrimaryCue)),
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  tooltip: l.text('restartMedia'),
                  onPressed: () => adapter.seek(Duration.zero),
                  icon: const Icon(Icons.restart_alt),
                ),
                IconButton.filled(
                  tooltip: l.text('playPause'),
                  onPressed: adapter.playOrPause,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: l.text('stop'),
                  onPressed: adapter.stop,
                  icon: const Icon(Icons.stop),
                ),
                IconButton(
                  tooltip: l.text('nextSentence'),
                  onPressed: () =>
                      _seekCue(primaryCursor.next(currentPrimaryCue)),
                  icon: const Icon(Icons.skip_next),
                ),
                FilterChip(
                  label: Text(l.text('loopSentence')),
                  selected: loopCue,
                  onSelected: (value) => setState(() {
                    loopCue = value;
                    if (value) {
                      sourceLoopStart = null;
                      sourceLoopEnd = null;
                    }
                  }),
                ),
                if (sourceLoopStart != null)
                  TextButton(
                    onPressed: () => setState(() {
                      sourceLoopStart = null;
                      sourceLoopEnd = null;
                    }),
                    child: Text(l.text('stopSourceLoop')),
                  ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(l.text('wordStyles')),
                  selected: statusStylesVisible,
                  onSelected: (value) {
                    setState(() => statusStylesVisible = value);
                    unawaited(_saveSettings());
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(l.text('subtitles')),
                  selected: subtitlesVisible,
                  onSelected: (value) {
                    setState(() => subtitlesVisible = value);
                    unawaited(_saveSettings());
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(l.text('secondary')),
                  selected: secondarySubtitlesVisible,
                  onSelected: (value) {
                    setState(() => secondarySubtitlesVisible = value);
                    unawaited(_saveSettings());
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<double>(
                  value: rate,
                  items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('${value}x'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => rate = value);
                    adapter.setRate(value);
                    unawaited(_saveSettings());
                  },
                ),
                const SizedBox(width: 12),
                if (audioTracks.length > 1)
                  DropdownButton<String>(
                    hint: Text(l.text('audioTrack')),
                    value:
                        audioTracks.any((track) => track.id == selectedAudioId)
                        ? selectedAudioId
                        : null,
                    items: audioTracks
                        .map(
                          (track) => DropdownMenuItem(
                            value: track.id,
                            child: Text(
                              track.title ??
                                  track.language ??
                                  'Audio ${track.id}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (id) {
                      final matches = audioTracks.where(
                        (track) => track.id == id,
                      );
                      if (matches.isEmpty) return;
                      final track = matches.first;
                      setState(() => selectedAudioId = id);
                      adapter.selectAudio(track);
                    },
                  ),
                if (audioTracks.length > 1) const SizedBox(width: 12),
                if (embeddedSubtitleTracks.isNotEmpty)
                  DropdownButton<String>(
                    hint: Text(l.text('embeddedSubtitles')),
                    value:
                        embeddedSubtitleTracks.any(
                          (track) => track.id == selectedEmbeddedSubtitleId,
                        )
                        ? selectedEmbeddedSubtitleId
                        : null,
                    items: embeddedSubtitleTracks
                        .map(
                          (track) => DropdownMenuItem(
                            value: track.id,
                            child: Text(
                              track.title ??
                                  track.language ??
                                  'Subtitle ${track.id}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (id) {
                      final matches = embeddedSubtitleTracks.where(
                        (track) => track.id == id,
                      );
                      if (matches.isEmpty) return;
                      setState(() => selectedEmbeddedSubtitleId = id);
                      adapter.selectSubtitle(matches.first);
                    },
                  ),
                if (embeddedSubtitleTracks.isNotEmpty)
                  const SizedBox(width: 12),
                IconButton(
                  tooltip: muted ? 'Unmute' : 'Mute',
                  onPressed: () {
                    setState(() => muted = !muted);
                    adapter.setVolume(muted ? 0 : volume);
                  },
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                ),
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: volume,
                    max: 100,
                    onChanged: (value) {
                      setState(() => volume = value);
                      if (!muted) adapter.setVolume(value);
                      unawaited(_saveSettings());
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text(l.text('primaryOffset')),
                IconButton(
                  onPressed: () {
                    setState(
                      () => primarySubtitleOffset -= const Duration(
                        milliseconds: 100,
                      ),
                    );
                    unawaited(_saveSettings());
                  },
                  icon: const Icon(Icons.remove),
                ),
                Text('${primarySubtitleOffset.inMilliseconds} ms'),
                IconButton(
                  onPressed: () {
                    setState(
                      () => primarySubtitleOffset += const Duration(
                        milliseconds: 100,
                      ),
                    );
                    unawaited(_saveSettings());
                  },
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 12),
                Text(l.text('secondaryOffset')),
                IconButton(
                  onPressed: () {
                    setState(
                      () => secondarySubtitleOffset -= const Duration(
                        milliseconds: 100,
                      ),
                    );
                    unawaited(_saveSettings());
                  },
                  icon: const Icon(Icons.remove),
                ),
                Text('${secondarySubtitleOffset.inMilliseconds} ms'),
                IconButton(
                  onPressed: () {
                    setState(
                      () => secondarySubtitleOffset += const Duration(
                        milliseconds: 100,
                      ),
                    );
                    unawaited(_saveSettings());
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
        ],
      ),
    ),
  );

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${value.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
}

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.api,
    required this.onExport,
    required this.onImport,
  });

  final LocalApi api;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  static const statuses = [
    'unknown_meaning',
    'known_not_recognized',
    'known_recognized',
  ];
  String status = statuses.first;
  String search = '';
  bool loading = true;
  List<Map<String, dynamic>> words = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final values = await widget.api.listVocabulary(status, search: search);
    if (mounted) {
      setState(() {
        words = values;
        loading = false;
      });
    }
  }

  Future<void> _details(Map<String, dynamic> value) async {
    final profile = value['profile'] as Map<String, dynamic>;
    final details = await widget.api.wordDetails(profile['id'] as String);
    final dictionary = await widget.api.lookupDictionary(
      profile['normalized_lemma'] as String,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profile['display_form'] as String),
        content: SizedBox(
          width: 700,
          height: 650,
          child: WordLearningPanel(
            details: details,
            dictionary: dictionary,
            onStatus: (value) async {
              await widget.api.updateWordProfile(
                profile['normalized_lemma'] as String,
                profile['display_form'] as String,
                value,
              );
              if (context.mounted) Navigator.pop(context);
              await _load();
            },
            onSave: (definition, note) async {
              await widget.api.updateLearningContent(
                profile['id'] as String,
                userDefinition: definition,
                personalNote: note,
              );
            },
            onSource: (occurrence) {
              Navigator.pop(context);
              Navigator.pop(this.context, occurrence);
            },
            onHeard: () {},
            onNotHeard: () {},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).text('vocabularyBooks')),
      actions: [
        VocabularyTransferActions(
          onExport: widget.onExport,
          onImport: widget.onImport,
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final value in statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(AppLocalizations.of(context).status(value)),
                    selected: status == value,
                    onSelected: (_) {
                      status = value;
                      unawaited(_load());
                    },
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: AppLocalizations.of(
                      context,
                    ).text('searchVocabulary'),
                  ),
                  onChanged: (value) {
                    search = value;
                    unawaited(_load());
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : VocabularyBookView(words: words, onWord: _details),
        ),
      ],
    ),
  );
}

class VocabularyTransferActions extends StatelessWidget {
  const VocabularyTransferActions({
    super.key,
    required this.onExport,
    required this.onImport,
  });

  final Future<void> Function() onExport;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: AppLocalizations.of(context).text('exportAssets'),
        onPressed: onExport,
        icon: const Icon(Icons.file_upload_outlined),
      ),
      IconButton(
        tooltip: AppLocalizations.of(context).text('importAssets'),
        onPressed: onImport,
        icon: const Icon(Icons.file_download_outlined),
      ),
    ],
  );
}

class VocabularyDetailsView extends StatelessWidget {
  const VocabularyDetailsView({
    super.key,
    required this.profile,
    required this.occurrences,
    required this.history,
    required this.onSource,
  });

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> occurrences;
  final List<Map<String, dynamic>> history;
  final ValueChanged<Map<String, dynamic>> onSource;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 620,
    height: 480,
    child: ListView(
      children: [
        Text(
          '${AppLocalizations.of(context).text('currentStatus')}: ${AppLocalizations.of(context).status(profile['status'] as String?)}',
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context).text('sources'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final occurrence in occurrences)
          ListTile(
            title: Text(occurrence['sentence_text_snapshot'] as String),
            subtitle: Text(
              '${occurrence['media_title_snapshot']} · encountered ${occurrence['encounter_count']} times',
            ),
            trailing: Icon(
              occurrence['media_id'] == null
                  ? Icons.link_off
                  : Icons.play_arrow,
            ),
            onTap: () => onSource(occurrence),
          ),
        const Divider(),
        Text(
          AppLocalizations.of(context).text('statusHistory'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final item in history)
          ListTile(
            dense: true,
            title: Text('${item['previous_status']} → ${item['new_status']}'),
            subtitle: Text(
              '${item['change_source']} · ${item['changed_at_ms']}',
            ),
          ),
      ],
    ),
  );
}

class VocabularyBookView extends StatelessWidget {
  const VocabularyBookView({
    super.key,
    required this.words,
    required this.onWord,
  });

  final List<Map<String, dynamic>> words;
  final ValueChanged<Map<String, dynamic>> onWord;

  @override
  Widget build(BuildContext context) => words.isEmpty
      ? Center(child: Text(AppLocalizations.of(context).text('noWords')))
      : ListView.builder(
          itemCount: words.length,
          itemBuilder: (context, index) {
            final value = words[index];
            final profile = value['profile'] as Map<String, dynamic>;
            final occurrences = value['occurrences'] as List<dynamic>;
            return ListTile(
              title: Text(profile['display_form'] as String),
              subtitle: Text(
                occurrences.isEmpty
                    ? AppLocalizations.of(context).text('noSourceSnapshot')
                    : (occurrences.first
                              as Map<String, dynamic>)['sentence_text_snapshot']
                          as String,
              ),
              trailing: Icon(
                occurrences.isNotEmpty &&
                        (occurrences.first
                                as Map<String, dynamic>)['media_id'] !=
                            null
                    ? Icons.play_arrow
                    : Icons.link_off,
              ),
              onTap: () => onWord(value),
            );
          },
        );
}

class WordLearningPanel extends StatefulWidget {
  const WordLearningPanel({
    super.key,
    required this.details,
    required this.dictionary,
    required this.onStatus,
    required this.onSave,
    required this.onSource,
    required this.onHeard,
    required this.onNotHeard,
  });

  final Map<String, dynamic> details;
  final Map<String, dynamic>? dictionary;
  final ValueChanged<String?> onStatus;
  final Future<void> Function(String?, String?) onSave;
  final ValueChanged<Map<String, dynamic>> onSource;
  final VoidCallback onHeard;
  final VoidCallback onNotHeard;

  @override
  State<WordLearningPanel> createState() => _WordLearningPanelState();
}

class _WordLearningPanelState extends State<WordLearningPanel> {
  late final TextEditingController definition;
  late final TextEditingController note;

  Map<String, dynamic> get profile =>
      widget.details['profile'] as Map<String, dynamic>;

  @override
  void initState() {
    super.initState();
    definition = TextEditingController(
      text: profile['user_definition'] as String? ?? '',
    );
    note = TextEditingController(
      text: profile['personal_note'] as String? ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant WordLearningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details != widget.details) {
      definition.text = profile['user_definition'] as String? ?? '';
      note.text = profile['personal_note'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    definition.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results =
        (widget.dictionary?['results'] as List<dynamic>? ?? const []);
    final occurrences = widget.details['occurrences'] as List<dynamic>;
    final history = widget.details['history'] as List<dynamic>;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(
          profile['display_form'] as String,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          '${l.text('currentStatus')}: ${l.status(profile['status'] as String?)}',
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final value in const [
              null,
              'unknown_meaning',
              'known_not_recognized',
              'known_recognized',
            ])
              ChoiceChip(
                label: Text(l.status(value)),
                selected: profile['status'] == value,
                onSelected: (_) => widget.onStatus(value),
              ),
          ],
        ),
        const Divider(),
        Text(
          l.text('dictionary'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (results.isEmpty) Text(l.text('noDictionary')),
        for (final raw in results)
          Builder(
            builder: (context) {
              final result = raw as Map<String, dynamic>;
              final provider = result['provider'] as Map<String, dynamic>;
              final lookup = result['lookup'] as Map<String, dynamic>?;
              return ExpansionTile(
                initiallyExpanded: true,
                title: Text(provider['display_name'] as String),
                subtitle: result['error'] == null
                    ? null
                    : Text(l.text('providerUnavailable')),
                children: [
                  if (result['error'] != null)
                    ListTile(title: Text(result['error'] as String)),
                  if (lookup != null)
                    for (final value in lookup['phonetics'] as List<dynamic>)
                      ListTile(
                        dense: true,
                        title: Text(
                          (value as Map<String, dynamic>)['text'] as String,
                        ),
                      ),
                  if (lookup != null)
                    for (final value in lookup['definitions'] as List<dynamic>)
                      ListTile(
                        dense: true,
                        title: Text(
                          (value as Map<String, dynamic>)['text'] as String,
                        ),
                        subtitle: Text(
                          value['part_of_speech'] as String? ?? '',
                        ),
                      ),
                ],
              );
            },
          ),
        TextField(
          controller: definition,
          maxLines: 3,
          decoration: InputDecoration(labelText: l.text('userDefinition')),
        ),
        TextField(
          controller: note,
          maxLines: 4,
          decoration: InputDecoration(labelText: l.text('personalNote')),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => widget.onSave(definition.text, note.text),
            child: Text(l.text('save')),
          ),
        ),
        Row(
          children: [
            TextButton(onPressed: widget.onHeard, child: Text(l.text('heard'))),
            TextButton(
              onPressed: widget.onNotHeard,
              child: Text(l.text('notHeard')),
            ),
          ],
        ),
        const Divider(),
        Text(
          l.text('sources'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final raw in occurrences)
          ListTile(
            title: Text(
              (raw as Map<String, dynamic>)['sentence_text_snapshot'] as String,
            ),
            subtitle: Text(
              '${raw['media_title_snapshot']} · ${l.text('encountered')} ${raw['encounter_count']} ${l.text('times')}',
            ),
            trailing: Icon(
              raw['media_id'] == null ? Icons.link_off : Icons.play_arrow,
            ),
            onTap: () => widget.onSource(raw),
          ),
        const Divider(),
        Text(
          l.text('statusHistory'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final raw in history)
          ListTile(
            dense: true,
            title: Text(
              '${l.status((raw as Map<String, dynamic>)['previous_status'] as String?)} → ${l.status(raw['new_status'] as String?)}',
            ),
            subtitle: Text('${raw['change_source']} · ${raw['changed_at_ms']}'),
          ),
      ],
    );
  }
}

class TokenLine extends StatelessWidget {
  const TokenLine({
    super.key,
    required this.cue,
    required this.profiles,
    required this.showStyles,
    required this.onWord,
    this.fontSize = 15,
    this.fontFamily,
    this.baseColor,
  });

  final Cue cue;
  final Map<String, Map<String, dynamic>> profiles;
  final bool showStyles;
  final double fontSize;
  final String? fontFamily;
  final Color? baseColor;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: cue.tokens
          .map((token) {
            final clickable = token.kind == 'word' && token.normalized != null;
            final status = profiles[token.normalized]?['status'] as String?;
            final style = _style(context, status);
            if (!clickable) return TextSpan(text: token.text, style: style);
            return WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: InkWell(
                onTap: () => onWord(token, cue),
                child: Text(token.text, style: style),
              ),
            );
          })
          .toList(growable: false),
    ),
  );

  TextStyle _style(BuildContext context, String? status) {
    final base = TextStyle(
      fontSize: fontSize,
      fontFamily: fontFamily,
      color: baseColor,
    );
    if (!showStyles || status == null) return base;
    return switch (status) {
      'unknown_meaning' => base.copyWith(
        color: Theme.of(context).colorScheme.error,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.double,
      ),
      'known_not_recognized' => base.copyWith(
        color: Colors.amber,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
      ),
      'known_recognized' => base.copyWith(
        color: Colors.greenAccent,
        fontWeight: FontWeight.bold,
      ),
      _ => base,
    };
  }
}
