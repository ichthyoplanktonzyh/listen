import 'package:flutter/material.dart';

import '../../controllers/media_import_flow_controller.dart';
import '../../learning_assets_ui.dart';
import '../../localization.dart';
import '../../models/embedded_subtitle.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';

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
            const SizedBox(height: ListenSpacing.gap12),
            Row(
              children: [
                Icon(
                  _isYouTube ? Icons.play_circle_outline : Icons.language,
                  size: ListenIconSize.control,
                ),
                const SizedBox(width: ListenSpacing.gap8),
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
            const SizedBox(height: ListenSpacing.gap12),
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
            const SizedBox(height: ListenSpacing.gap12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gavel_outlined, size: ListenIconSize.control),
                const SizedBox(width: ListenSpacing.gap8),
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
  required MediaImportFlowController controller,
  required void Function() onMediaSwitched,
}) async {
  final l = AppLocalizations.of(context);
  final source = await showDialog<OnlineSourceChoice>(
    context: context,
    builder: (context) => const OnlineSourceDialog(),
  );
  if (source == null || !context.mounted) return;
  if (source.action == OnlineSourceAction.download) {
    controller.reportStatus(l.text('startingDownload'));
    final outcome = await controller.startDownload(
      source.url,
      confirmButtonText: l.text('downloadHere'),
      completedStatus: (path) => '${l.text('downloadComplete')}: $path',
      failedStatus: l.text('downloadFailed'),
    );
    if (!context.mounted) return;
    switch (outcome) {
      case MediaImportSucceeded():
        controller.reportStatus(l.text('downloadingInBackground'));
      case MediaImportCancelled():
      case MediaImportUnavailable():
      case MediaImportEmpty():
        return;
      case MediaImportFailed(:final failure):
        controller.reportStatus(
          l.text('downloadFailed'),
          error: true,
          failure: failure,
        );
      case EmbeddedSubtitleChoices():
        return;
    }
    return;
  }
  controller.reportStatus(l.text('statusResolvingOnlineMedia'));
  final outcome = await controller.playOnline(source.url);
  if (!context.mounted) return;
  switch (outcome) {
    case MediaImportSucceeded():
      controller.reportStatus(
        l.text('statusPlayingOnlineMedia'),
        playback: true,
      );
      onMediaSwitched();
    case MediaImportFailed(:final failure):
      controller.reportStatus(
        l.text('statusOnlineMediaFailed'),
        error: true,
        failure: failure,
      );
    case MediaImportCancelled():
    case MediaImportUnavailable():
    case MediaImportEmpty():
    case EmbeddedSubtitleChoices():
      return;
  }
}

Future<void> importEmbeddedSubtitleFlow({
  required BuildContext context,
  required MediaImportFlowController controller,
}) async {
  final l = AppLocalizations.of(context);
  controller.reportStatus(l.text('statusInspectingEmbedded'));
  final inspection = await controller.inspectEmbedded();
  if (!context.mounted) return;
  switch (inspection) {
    case MediaImportUnavailable():
      controller.reportStatus(l.text('statusOpenLocalMediaFirst'));
      return;
    case MediaImportEmpty():
      controller.reportStatus(l.text('statusNoEmbeddedSubtitles'));
      return;
    case MediaImportFailed(:final failure):
      controller.reportStatus(
        l.text('statusEmbeddedImportFailed'),
        error: true,
        failure: failure,
      );
      return;
    case EmbeddedSubtitleChoices(:final values):
      final subtitles = values;
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
        controller.reportStatus(l.text('statusEmbeddedImportCancelled'));
        return;
      }
      controller.reportStatus(l.text('statusExtractingEmbedded'));
      final extraction = await controller.extractEmbedded(
        choice.$1,
        secondary: choice.$2,
      );
      if (!context.mounted) return;
      if (extraction case MediaImportFailed(:final failure)) {
        controller.reportStatus(
          l.text('statusEmbeddedImportFailed'),
          error: true,
          failure: failure,
        );
      }
    case MediaImportSucceeded():
    case MediaImportCancelled():
      return;
  }
}

Future<void> searchOpenSubtitlesFlow({
  required BuildContext context,
  required OpenSubtitlesFlowController controller,
  required bool secondary,
}) async {
  final l = AppLocalizations.of(context);
  var preparation = controller.prepare();
  if (preparation is OpenSubtitlesUnavailable) {
    // Unavailable State (CONTEXT.md): the OpenSubtitles search is a user menu
    // entry; report the missing core instead of swallowing the click.
    controller.reportStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  if (preparation is OpenSubtitlesNoMedia) {
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
  if (preparation is OpenSubtitlesNeedsApiKey) {
    final apiKeyController = TextEditingController();
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
              controller: apiKeyController,
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
            onPressed: () =>
                Navigator.pop(context, apiKeyController.text.trim()),
            child: Text(l.text('save')),
          ),
        ],
      ),
    );
    apiKeyController.dispose();
    // Legitimate silence: the user cancelled the API-key dialog themselves.
    if (configured == null || configured.isEmpty) return;
    preparation = await controller.configureApiKey(configured);
  }
  if (!context.mounted) return;
  if (preparation case OpenSubtitlesSetupFailed(:final failure)) {
    controller.reportStatus(
      l.text('statusSubtitleImportFailed'),
      error: true,
      failure: failure,
    );
    return;
  }
  if (preparation is! OpenSubtitlesReady) return;
  final path = await showOpenSubtitlesSearch(
    context: context,
    viewModel: preparation.viewModel,
  );
  if (path == null || !context.mounted) return;
  await controller.openDownloaded(path, secondary: secondary);
}
