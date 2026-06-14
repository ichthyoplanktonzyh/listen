import 'package:flutter/material.dart';

import '../../localization.dart';

class PlayerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PlayerAppBar({
    super.key,
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
      title: const Text('LLPlayerNext'),
      actions: [
        TextButton.icon(
          onPressed: onOpenVocabulary,
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(l.text('vocabulary')),
        ),
        TextButton.icon(
          onPressed: onOpenMedia,
          icon: const Icon(Icons.video_file_outlined),
          label: Text(l.text('openMedia')),
        ),
        TextButton.icon(
          onPressed: onOpenOnline,
          icon: const Icon(Icons.language),
          label: Text(l.text('openUrl')),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'import') onImportPrimarySubtitle();
            if (value == 'generate') onGeneratePrimarySubtitles();
            if (value == 'opensubtitles') onSearchPrimarySubtitles();
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
            PopupMenuItem(
              value: 'opensubtitles',
              child: Text(l.text('openSubtitles')),
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
            if (value == 'import') onImportSecondarySubtitle();
            if (value == 'generate') onGenerateSecondarySubtitles();
            if (value == 'opensubtitles') onSearchSecondarySubtitles();
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
            PopupMenuItem(
              value: 'opensubtitles',
              child: Text(l.text('openSubtitles')),
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
            if (value == 'embedded') onImportEmbeddedSubtitle();
            if (value == 'settings') onOpenSettings();
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
            PopupMenuItem(value: 'settings', child: Text(l.text('settings'))),
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
        const SizedBox(width: 12),
      ],
    );
  }
}
