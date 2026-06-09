import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide SubtitleTrack;
import 'package:media_kit/media_kit.dart' as media;
import 'package:media_kit_video/media_kit_video.dart';

import 'local_api.dart';
import 'external_tools.dart';
import 'player_adapter.dart';
import 'settings.dart';
import 'timeline.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const LLPlayerNextApp());
}

class LLPlayerNextApp extends StatelessWidget {
  const LLPlayerNextApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'LLPlayerNext',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff6dd6c3),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const PlayerScreen(),
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
  String status = 'Starting local core...';
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration primarySubtitleOffset = Duration.zero;
  Duration secondarySubtitleOffset = Duration.zero;
  bool playing = false;
  bool muted = false;
  bool loopCue = false;
  bool subtitlesVisible = true;
  bool secondarySubtitlesVisible = true;
  bool statusStylesVisible = true;
  bool dragging = false;
  double rate = 1;
  double volume = 100;
  double primaryFontSize = 24;
  double secondaryFontSize = 18;
  double subtitleBottomPadding = 48;
  double subtitleBackgroundOpacity = 0.72;
  Color primaryColor = Colors.white;
  Color secondaryColor = const Color(0xffb8d8ff);
  double transcriptWidth = 430;
  String ffmpegPath = '';
  String ffprobePath = '';
  String ytDlpPath = '';
  List<AudioTrack> audioTracks = const [];
  String? selectedAudioId;
  List<media.SubtitleTrack> embeddedSubtitleTracks = const [];
  String? selectedEmbeddedSubtitleId;
  final wordProfiles = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? diagnosis;

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
  double get transcriptItemExtent => primaryFontSize * 2 + 46;

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
      subtitleBottomPadding = settings.subtitleBottomPadding;
      subtitleBackgroundOpacity = settings.subtitleBackgroundOpacity;
      primaryColor = Color(settings.primaryColor);
      secondaryColor = Color(settings.secondaryColor);
      transcriptWidth = settings.transcriptWidth;
      ffmpegPath = settings.ffmpegPath;
      ffprobePath = settings.ffprobePath;
      ytDlpPath = settings.ytDlpPath;
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
    subtitleBottomPadding: subtitleBottomPadding,
    subtitleBackgroundOpacity: subtitleBackgroundOpacity,
    primaryColor: primaryColor.toARGB32(),
    secondaryColor: secondaryColor.toARGB32(),
    transcriptWidth: transcriptWidth,
    ffmpegPath: ffmpegPath,
    ffprobePath: ffprobePath,
    ytDlpPath: ytDlpPath,
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
      status = 'Playing ${path.split(Platform.pathSeparator).last}';
    });
    try {
      final media = await api?.registerMedia(path);
      if (media != null) {
        final id = media['id'] as String;
        final saved = await api?.readProgress(id);
        setState(() => mediaId = id);
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
        title: const Text('Open online media with yt-dlp'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Page URL',
              helperText: 'Only open content you are authorized to access.',
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Resolve and play'),
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
          title: const Text('Import embedded text subtitle'),
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
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: false,
                            child: Text('Use as primary'),
                          ),
                          PopupMenuItem(
                            value: true,
                            child: Text('Use as secondary'),
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
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 620,
            height: 650,
            child: ListView(
              children: [
                const Text(
                  'Subtitles',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _settingSlider(
                  'Primary font size',
                  primaryFontSize,
                  12,
                  72,
                  (value) => setState(() => primaryFontSize = value),
                  refresh,
                ),
                _settingSlider(
                  'Secondary font size',
                  secondaryFontSize,
                  10,
                  64,
                  (value) => setState(() => secondaryFontSize = value),
                  refresh,
                ),
                _settingSlider(
                  'Vertical position',
                  subtitleBottomPadding,
                  0,
                  400,
                  (value) => setState(() => subtitleBottomPadding = value),
                  refresh,
                ),
                _settingSlider(
                  'Background opacity',
                  subtitleBackgroundOpacity,
                  0,
                  1,
                  (value) => setState(() => subtitleBackgroundOpacity = value),
                  refresh,
                ),
                _settingSlider(
                  'Transcript width',
                  transcriptWidth,
                  260,
                  900,
                  (value) => setState(() => transcriptWidth = value),
                  refresh,
                ),
                const SizedBox(height: 8),
                const Text('Primary color'),
                _colorChoices(primaryColor, (value) {
                  setState(() => primaryColor = value);
                  refresh(() {});
                }),
                const Text('Secondary color'),
                _colorChoices(secondaryColor, (value) {
                  setState(() => secondaryColor = value);
                  refresh(() {});
                }),
                const Divider(),
                const Text(
                  'Optional external tools',
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  ffmpegPath = ffmpegController.text.trim();
                  ffprobePath = ffprobeController.text.trim();
                  ytDlpPath = ytDlpController.text.trim();
                });
                unawaited(_saveSettings());
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ffmpegController.dispose();
    ffprobeController.dispose();
    ytDlpController.dispose();
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
    Map<String, dynamic>? dictionary;
    String? dictionaryError;
    try {
      dictionary = await api!.lookupDictionary(lemma);
    } catch (error) {
      dictionaryError = 'Dictionary unavailable: $error';
    }
    if (!mounted) return;
    final selected = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(token.text),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Global status applies everywhere. Context observation records only this sentence.',
            ),
          ),
          if (dictionary != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                [
                  ...(dictionary['phonetics'] as List<dynamic>).map(
                    (value) => value['text'] as String,
                  ),
                  ...(dictionary['definitions'] as List<dynamic>)
                      .take(3)
                      .map((value) => value['text'] as String),
                ].join('\n'),
              ),
            ),
          if (dictionary == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(dictionaryError ?? 'No dictionary result'),
            ),
          for (final choice in const [
            (null, 'Clear global status'),
            ('unknown_meaning', 'Unknown meaning'),
            ('known_not_recognized', 'Known, but not recognized'),
            ('known_recognized', 'Known and recognized'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, choice.$1 ?? 'clear'),
              child: Text(choice.$2),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'observation_heard'),
            child: const Text('This sentence: heard'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'observation_not_heard'),
            child: const Text('This sentence: not heard'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    try {
      var profile = wordProfiles[lemma];
      if (selected.startsWith('observation_')) {
        profile ??= await api!.updateWordProfile(lemma, token.text, null);
        await api!.createObservation(
          wordProfileId: profile['id'] as String,
          sentenceId: cue.id,
          originalForm: token.text,
          heard: selected == 'observation_heard',
        );
        setState(() {
          wordProfiles[lemma] = profile!;
          status = selected == 'observation_heard'
              ? 'Recorded: heard "${token.text}" in this sentence'
              : 'Recorded: did not hear "${token.text}" in this sentence';
        });
        await _refreshDiagnosis();
      } else {
        profile = await api!.updateWordProfile(
          lemma,
          token.text,
          selected == 'clear' ? null : selected,
        );
        setState(() {
          wordProfiles[lemma] = profile!;
          status = 'Updated global status for "${token.text}"';
        });
        await _refreshDiagnosis();
      }
    } catch (error) {
      setState(() => status = 'Word update failed: $error');
    }
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
              onPressed: _openMedia,
              icon: const Icon(Icons.video_file_outlined),
              label: const Text('Open media'),
            ),
            TextButton.icon(
              onPressed: _openOnline,
              icon: const Icon(Icons.language),
              label: const Text('Open URL'),
            ),
            TextButton.icon(
              onPressed: () => _openSubtitle(secondary: false),
              icon: const Icon(Icons.subtitles_outlined),
              label: const Text('Primary subtitle'),
            ),
            TextButton.icon(
              onPressed: () => _openSubtitle(secondary: true),
              icon: const Icon(Icons.closed_caption_outlined),
              label: const Text('Secondary subtitle'),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'embedded') unawaited(_importEmbeddedSubtitle());
                if (value == 'settings') unawaited(_openSettings());
                if (value == 'logs') unawaited(_exportLogs());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'embedded',
                  child: Text('Import embedded subtitle'),
                ),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
                PopupMenuItem(value: 'logs', child: Text('Export logs')),
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
                      if (subtitlesVisible)
                        SizedBox(width: transcriptWidth, child: _transcript()),
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

  Widget _playerSurface() => Stack(
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
        Padding(
          padding: EdgeInsets.fromLTRB(32, 32, 32, subtitleBottomPadding),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: subtitleBackgroundOpacity),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                        fontSize: primaryFontSize,
                        baseColor: primaryColor,
                        onWord: _openWord,
                      ),
                    ),
                  if (secondarySubtitlesVisible && currentSecondaryCue != null)
                    GestureDetector(
                      onTap: () => adapter.seek(
                        secondaryCursor.mediaStart(currentSecondaryCue!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          currentSecondaryCue!.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: secondaryFontSize,
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
      if (mediaPath == null)
        Center(
          child: FilledButton.icon(
            onPressed: _openMedia,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open video or audio'),
          ),
        ),
    ],
  );

  Widget _transcript() => Material(
    color: const Color(0xff151a20),
    child: primaryTrack == null
        ? const Center(child: Text('Import SRT or WebVTT subtitles'))
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
              if (diagnosis != null) _diagnosisCard(),
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
            child: Text('• ${hint['message']}'),
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
                  tooltip: 'Previous sentence',
                  onPressed: () =>
                      _seekCue(primaryCursor.previous(currentPrimaryCue)),
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  tooltip: 'Restart media',
                  onPressed: () => adapter.seek(Duration.zero),
                  icon: const Icon(Icons.restart_alt),
                ),
                IconButton.filled(
                  tooltip: 'Play / pause',
                  onPressed: adapter.playOrPause,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Stop',
                  onPressed: adapter.stop,
                  icon: const Icon(Icons.stop),
                ),
                IconButton(
                  tooltip: 'Next sentence',
                  onPressed: () =>
                      _seekCue(primaryCursor.next(currentPrimaryCue)),
                  icon: const Icon(Icons.skip_next),
                ),
                FilterChip(
                  label: const Text('Loop sentence'),
                  selected: loopCue,
                  onSelected: (value) => setState(() => loopCue = value),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Word styles'),
                  selected: statusStylesVisible,
                  onSelected: (value) {
                    setState(() => statusStylesVisible = value);
                    unawaited(_saveSettings());
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Subtitles'),
                  selected: subtitlesVisible,
                  onSelected: (value) {
                    setState(() => subtitlesVisible = value);
                    unawaited(_saveSettings());
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Secondary'),
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
                    hint: const Text('Audio track'),
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
                    hint: const Text('Embedded subtitles'),
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
                const Text('Primary offset'),
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
                const Text('Secondary offset'),
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

class TokenLine extends StatelessWidget {
  const TokenLine({
    super.key,
    required this.cue,
    required this.profiles,
    required this.showStyles,
    required this.onWord,
    this.fontSize = 15,
    this.baseColor,
  });

  final Cue cue;
  final Map<String, Map<String, dynamic>> profiles;
  final bool showStyles;
  final double fontSize;
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
    final base = TextStyle(fontSize: fontSize, color: baseColor);
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
