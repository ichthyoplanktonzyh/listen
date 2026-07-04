import 'package:flutter/material.dart';

import '../../localization.dart';

class PlayerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PlayerAppBar({
    super.key,
    required this.onOpenSubtitleResources,
    required this.onOpenVocabulary,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onImportPrimarySubtitle,
    required this.onGeneratePrimarySubtitles,
    required this.onSearchPrimarySubtitles,
    required this.onImportSecondarySubtitle,
    required this.onGenerateSecondarySubtitles,
    required this.onSearchSecondarySubtitles,
    required this.onImportEmbeddedSubtitle,
    required this.onOpenSettings,
    required this.onExportLogs,
    required this.onExportVocabulary,
    required this.onImportVocabulary,
    required this.onImportWordList,
    required this.onArchiveMedia,
    required this.onOpenTranscriptionCenter,
    required this.onOpenPhoneticAnalysisCenter,
    required this.onOpenLearningAssets,
    required this.onOpenLearningResources,
    required this.onShowPhraseCandidates,
    required this.onCorrectLemma,
    required this.onSearchOpenSubtitles,
  });

  final VoidCallback onOpenSubtitleResources;
  final VoidCallback onOpenVocabulary;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onImportPrimarySubtitle;
  final VoidCallback onGeneratePrimarySubtitles;
  final VoidCallback onSearchPrimarySubtitles;
  final VoidCallback onImportSecondarySubtitle;
  final VoidCallback onGenerateSecondarySubtitles;
  final VoidCallback onSearchSecondarySubtitles;
  final VoidCallback onImportEmbeddedSubtitle;
  final VoidCallback onOpenSettings;
  final VoidCallback onExportLogs;
  final VoidCallback onExportVocabulary;
  final VoidCallback onImportVocabulary;
  final VoidCallback onImportWordList;
  final VoidCallback onArchiveMedia;
  final VoidCallback onOpenTranscriptionCenter;
  final VoidCallback onOpenPhoneticAnalysisCenter;
  final VoidCallback onOpenLearningAssets;
  final VoidCallback onOpenLearningResources;
  final VoidCallback onShowPhraseCandidates;
  final VoidCallback onCorrectLemma;
  final VoidCallback onSearchOpenSubtitles;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      titleSpacing: 20,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          const Text('listen', style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      shape: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      actions: [
        IconButton(
          tooltip: l.text('openMedia'),
          onPressed: onOpenMedia,
          icon: const Icon(Icons.video_file_outlined),
        ),
        IconButton(
          tooltip: l.text('openUrl'),
          onPressed: onOpenOnline,
          icon: const Icon(Icons.language_outlined),
        ),
        IconButton(
          tooltip: l.text('subtitleResources'),
          onPressed: onOpenSubtitleResources,
          icon: const Icon(Icons.inventory_2_outlined),
        ),
        IconButton(
          tooltip: l.text('vocabulary'),
          onPressed: onOpenVocabulary,
          icon: const Icon(Icons.menu_book_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: l.text('subtitles'),
          icon: const Icon(Icons.subtitles_outlined),
          onSelected: (value) {
            if (value == 'primary-import') onImportPrimarySubtitle();
            if (value == 'primary-generate') onGeneratePrimarySubtitles();
            if (value == 'primary-search') onSearchPrimarySubtitles();
            if (value == 'secondary-import') onImportSecondarySubtitle();
            if (value == 'secondary-generate') onGenerateSecondarySubtitles();
            if (value == 'secondary-search') onSearchSecondarySubtitles();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: Text(l.text('primarySubtitle')),
            ),
            PopupMenuItem(
              value: 'primary-import',
              child: Text(l.text('importSubtitleHint')),
            ),
            PopupMenuItem(
              value: 'primary-generate',
              child: Text(l.text('generateSubtitles')),
            ),
            PopupMenuItem(
              value: 'primary-search',
              child: Text(l.text('openSubtitles')),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              enabled: false,
              child: Text(l.text('secondarySubtitle')),
            ),
            PopupMenuItem(
              value: 'secondary-import',
              child: Text(l.text('importSubtitleHint')),
            ),
            PopupMenuItem(
              value: 'secondary-generate',
              child: Text(l.text('generateSubtitles')),
            ),
            PopupMenuItem(
              value: 'secondary-search',
              child: Text(l.text('openSubtitles')),
            ),
          ],
        ),
        IconButton(
          tooltip: l.text('settings'),
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: l.text('moreActions'),
          onSelected: (value) {
            if (value == 'embedded') onImportEmbeddedSubtitle();
            if (value == 'logs') onExportLogs();
            if (value == 'export-vocabulary') onExportVocabulary();
            if (value == 'import-vocabulary') onImportVocabulary();
            if (value == 'import-word-list') onImportWordList();
            if (value == 'archive-media') onArchiveMedia();
            if (value == 'transcription') onOpenTranscriptionCenter();
            if (value == 'phonetic-analysis') onOpenPhoneticAnalysisCenter();
            if (value == 'learning-assets') onOpenLearningAssets();
            if (value == 'learning-resources') onOpenLearningResources();
            if (value == 'phrase-candidates') onShowPhraseCandidates();
            if (value == 'correct-lemma') onCorrectLemma();
            if (value == 'opensubtitles') onSearchOpenSubtitles();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'embedded',
              child: Text(l.text('importEmbeddedText')),
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
              value: 'phonetic-analysis',
              child: Text(l.text('phoneticAnalysisCenter')),
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
        const SizedBox(width: 8),
      ],
    );
  }
}
