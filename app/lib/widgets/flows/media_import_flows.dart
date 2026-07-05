import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/download_controller.dart';
import '../../controllers/media_session_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../m18_ui.dart';
import '../../player_adapter.dart';
import '../../services/api_service.dart';
import '../../services/external_tools.dart';

/// Dialog-driven media/subtitle import flows extracted from the composition
/// root: online URL open/download, embedded subtitle extraction, and
/// OpenSubtitles search. Parameter names mirror the host's controller fields.

enum OnlineSourceAction { play, download }

class OnlineSourceChoice {
  const OnlineSourceChoice({required this.url, required this.action});

  final String url;
  final OnlineSourceAction action;
}

class OnlineSourceDialog extends StatefulWidget {
  const OnlineSourceDialog({super.key});

  @override
  State<OnlineSourceDialog> createState() => _OnlineSourceDialogState();
}

class _OnlineSourceDialogState extends State<OnlineSourceDialog> {
  final TextEditingController _controller = TextEditingController();
  OnlineSourceAction _action = OnlineSourceAction.play;
  bool _submitted = false;

  Uri? get _uri {
    final value = Uri.tryParse(_controller.text.trim());
    if (value == null ||
        (value.scheme != 'http' && value.scheme != 'https') ||
        value.host.isEmpty) {
      return null;
    }
    return value;
  }

  bool get _isYouTube {
    final host = _uri?.host.toLowerCase();
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host?.endsWith('.youtube.com') == true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final uri = _uri;
    return AlertDialog(
      title: Text(l.text('addSource')),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('online-source-url'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.text('pasteSourceLink'),
                prefixIcon: const Icon(Icons.link),
                errorText: _submitted && uri == null
                    ? l.text('invalidSourceUrl')
                    : null,
              ),
              onChanged: (_) => setState(() => _submitted = false),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  _isYouTube ? Icons.play_circle_outline : Icons.language,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('${l.text('recognizedSource')}: '),
                Expanded(
                  child: Text(
                    uri == null
                        ? l.text('notReadyYet')
                        : _isYouTube
                        ? l.text('youtubeSource')
                        : l.text('webSource'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<OnlineSourceAction>(
              segments: [
                ButtonSegment(
                  value: OnlineSourceAction.play,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.text('playOnline')),
                ),
                ButtonSegment(
                  value: OnlineSourceAction.download,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l.text('downloadLocal')),
                ),
              ],
              selected: {_action},
              onSelectionChanged: (value) =>
                  setState(() => _action = value.first),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gavel_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.text('sourceAuthorizationNotice'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.text('cancel')),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: Icon(
            _action == OnlineSourceAction.play
                ? Icons.play_arrow
                : Icons.download_outlined,
          ),
          label: Text(l.text('addSource')),
        ),
      ],
    );
  }

  void _submit() {
    final uri = _uri;
    if (uri == null) {
      setState(() => _submitted = true);
      return;
    }
    Navigator.pop(
      context,
      OnlineSourceChoice(url: uri.toString(), action: _action),
    );
  }
}

Future<void> openOnlineMediaFlow({
  required BuildContext context,
  required DesktopPlayerAdapter adapter,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required DownloadController downloadController,
  required ExternalTools tools,
  required void Function() onMediaSwitched,
}) async {
  final source = await showDialog<OnlineSourceChoice>(
    context: context,
    builder: (context) => const OnlineSourceDialog(),
  );
  if (source == null || !context.mounted) return;
  if (source.action == OnlineSourceAction.download) {
    await _downloadOnline(
      context: context,
      pageUrl: source.url,
      playerController: playerController,
      downloadController: downloadController,
      tools: tools,
    );
    return;
  }
  playerController.setStatus('Resolving online media...');
  try {
    final resolved = await tools.resolveOnlineMedia(source.url);
    await adapter.open(resolved);
    playerController.clearMedia();
    playerController.setMediaPath(source.url);
    subtitleController.setPrimaryTrack(null);
    subtitleController.setSecondaryTrack(null);
    subtitleController.setCurrentPrimaryCue(null);
    subtitleController.setCurrentSecondaryCue(null);
    subtitleController.clearSpeechEnhancements();
    subtitleController.setCurrentPrimaryCue(null);
    subtitleController.setCurrentSecondaryCue(null);
    playerController.setStatus('Playing online media');
    onMediaSwitched();
  } catch (error) {
    playerController.setStatus('Online media failed: $error');
  }
}

Future<void> _downloadOnline({
  required BuildContext context,
  required String pageUrl,
  required PlayerController playerController,
  required DownloadController downloadController,
  required ExternalTools tools,
}) async {
  final l = AppLocalizations.of(context);
  final directory = await getDirectoryPath(
    confirmButtonText: l.text('downloadHere'),
  );
  if (directory == null) return;
  downloadController.starting();
  playerController.setStatus(l.text('startingDownload'));
  try {
    final download = await tools.downloadOnlineMedia(pageUrl, directory);
    if (!context.mounted) {
      download.cancel();
      return;
    }
    downloadController.attach(
      progress: download.progress,
      completed: download.completed,
      cancel: download.cancel,
      onCompleted: (path) =>
          playerController.setStatus('${l.text('downloadComplete')}: $path'),
      onFailed: (error) =>
          playerController.setStatus('${l.text('downloadFailed')}: $error'),
    );
    playerController.setStatus(l.text('downloadingInBackground'));
  } catch (error) {
    if (context.mounted) {
      downloadController.fail(error.toString());
      playerController.setStatus('${l.text('downloadFailed')}: $error');
    }
  }
}

Future<void> importEmbeddedSubtitleFlow({
  required BuildContext context,
  required PlayerController playerController,
  required MediaSessionCoordinator mediaSession,
  required ExternalTools tools,
  required LocalApi? api,
  required bool Function(String path) isMediaPath,
}) async {
  final l = AppLocalizations.of(context);
  final path = playerController.mediaPath;
  if (path == null ||
      !isMediaPath(path) ||
      playerController.mediaId == null ||
      api == null) {
    playerController.setStatus('Open a local media file first');
    return;
  }
  playerController.setStatus('Inspecting embedded subtitles...');
  try {
    final subtitles = await tools.probeSubtitles(path);
    if (!context.mounted) return;
    if (subtitles.isEmpty) {
      playerController.setStatus('No embedded subtitles found');
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
      playerController.setStatus('Embedded subtitle import cancelled');
      return;
    }
    playerController.setStatus('Extracting embedded text subtitle...');
    final extracted = await tools.extractTextSubtitle(path, choice.$1);
    await mediaSession.openSubtitlePath(extracted, secondary: choice.$2);
  } catch (error) {
    playerController.setStatus('Embedded subtitle import failed: $error');
  }
}

Future<void> searchOpenSubtitlesFlow({
  required BuildContext context,
  required PlayerController playerController,
  required SettingsController settingsController,
  required MediaSessionCoordinator mediaSession,
  required LocalApi? api,
  bool? secondary,
}) async {
  final l = AppLocalizations.of(context);
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
  if (!context.mounted) return;
  final path = await showOpenSubtitlesSearch(
    context: context,
    api: api,
    apiKey: settingsController.openSubtitlesApiKey,
    initialTitle: playerController.mediaTitle ?? '',
    initialFilename: playerController.mediaPath == null
        ? ''
        : playerController.mediaPath!.split(Platform.pathSeparator).last,
    mediaPath: playerController.mediaPath,
  );
  if (path == null || !context.mounted) return;
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
    await mediaSession.openSubtitlePath(path, secondary: destination);
  }
}
