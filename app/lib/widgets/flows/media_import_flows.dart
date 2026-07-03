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

Future<void> openOnlineMediaFlow({
required BuildContext context,
required DesktopPlayerAdapter adapter,
required PlayerController playerController,
required SubtitleController subtitleController,
required DownloadController downloadController,
required ExternalTools tools,
required void Function() onMediaSwitched,
}) async {
final l = AppLocalizations.of(context);
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
  if (pageUrl == null || pageUrl.isEmpty || !context.mounted) return;
  if (pageUrl.startsWith('download:')) {
    await _downloadOnline(
      context: context,
      pageUrl: pageUrl.substring('download:'.length),
      playerController: playerController,
      downloadController: downloadController,
      tools: tools,
    );
    return;
  }
  playerController.setStatus('Resolving online media...');
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
