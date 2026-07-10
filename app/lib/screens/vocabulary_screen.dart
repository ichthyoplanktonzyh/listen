import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../controllers/occurrence_media_resolver.dart';
import '../controllers/slice_player_controller.dart';
import '../localization.dart';
import '../models/practice.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import '../widgets/panels/slice_playback_window.dart';
import '../widgets/vocabulary/vocabulary_book_view.dart';
import '../widgets/vocabulary/listening_dictionary_entry_view.dart';
import '../widgets/vocabulary/vocabulary_transfer_actions.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onExport,
    required this.onImport,
    this.initialEntryId,
    this.onPauseBackgroundPlayback,
  });

  final LocalApi api;
  final String language;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final String? initialEntryId;

  /// Pauses whatever is playing behind this route (the primary player) so a
  /// slice owns audio focus alone, matching the workbench behaviour.
  final Future<void> Function()? onPauseBackgroundPlayback;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  static const capabilities = ['reading', 'listening', 'speaking', 'writing'];
  static const assessmentFilters = ['acquired', 'not_acquired', 'unassessed'];

  // The four-channel capability axis is the primary lens. [capability] picks the
  // channel; [assessment] `null` means "all" (no capability filter applied).
  String capability = 'listening';
  String? assessment;
  String search = '';
  bool loading = true;
  List<Map<String, dynamic>> words = const [];

  /// Non-null while the in-page entry detail is open (master → detail).
  LexicalEntryDetails? details;

  /// Corpus fallback when the vocabulary list has no match for [search].
  List<CorpusOccurrence>? homeResults;
  bool homeSearching = false;

  /// The dictionary hosts its own second-decoder slice playback so playing an
  /// example never leaves this screen or touches the primary player.
  final SlicePlayerController slicePlayer = SlicePlayerController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    final initialEntryId = widget.initialEntryId;
    if (initialEntryId != null) {
      unawaited(_openEntryById(initialEntryId));
    }
  }

  @override
  void dispose() {
    slicePlayer.dispose();
    super.dispose();
  }

  String _capabilityLabelKey(String value) => switch (value) {
    'reading' => 'capabilityReading',
    'listening' => 'capabilityListening',
    'speaking' => 'capabilitySpeaking',
    _ => 'capabilityWriting',
  };

  Future<void> _load() async {
    setState(() => loading = true);
    final values = await widget.api.listVocabulary(
      language: widget.language,
      capability: assessment == null ? null : capability,
      assessment: assessment,
      search: search,
    );
    if (mounted) {
      setState(() {
        words = values;
        loading = false;
      });
    }
  }

  Future<void> _openEntryById(String entryId) async {
    final value = LexicalEntryDetails.fromJson(
      await widget.api.lexicalEntryDetails(entryId),
    );
    if (mounted) setState(() => details = value);
  }

  Future<void> _openDetails(Map<String, dynamic> value) async {
    final entry = value['entry'];
    if (entry is! Map || entry['id'] is! String) return;
    await _openEntryById(entry['id'] as String);
  }

  void _closeDetails() => setState(() => details = null);

  // ── Slice playback (in-page, second decoder) ──

  OccurrenceMediaResolver get _resolver => OccurrenceMediaResolver(
    readMedia: widget.api.readMedia,
    fingerprintFile: widget.api.fingerprintFile,
    registerMedia: (path) async {
      await widget.api.registerMedia(path);
    },
    pickFile: (groups) => openFile(acceptedTypeGroups: groups),
  );

  Future<void> _playOccurrenceMap(Map<String, dynamic> occurrence) async {
    final resolution = await _resolver.resolve(
      occurrence,
      currentMediaFingerprint: null,
      currentMediaPath: null,
      filterMediaExtensions: true,
    );
    if (!mounted) return;
    if (resolution is UnresolvedOccurrenceMedia) {
      await slicePlayer.showError(resolution.message, occurrence: occurrence);
      return;
    }
    await widget.onPauseBackgroundPlayback?.call();
    await slicePlayer.open(
      path: (resolution as ResolvedOccurrenceMedia).path,
      occurrence: occurrence,
    );
  }

  Future<void> _playCorpus(CorpusOccurrence occurrence) async {
    final mediaId = occurrence.mediaId;
    if (mediaId == null) return;
    Map<String, dynamic> media;
    try {
      media = await widget.api.readMedia(mediaId);
    } catch (_) {
      if (!mounted) return;
      await slicePlayer.showError(
        AppLocalizations.of(context).text('dictionaryClipNeedsSource'),
      );
      return;
    }
    await _playOccurrenceMap({
      'media_id': mediaId,
      'media_fingerprint_snapshot': media['fingerprint'],
      'media_title_snapshot': media['title'] ?? '',
      'sentence_text_snapshot': occurrence.sourceSnapshot,
      'original_form': occurrence.displayText,
      'start_ms_snapshot': occurrence.startMs,
      'end_ms_snapshot': occurrence.endMs,
    });
  }

  // ── Corpus enrichment (Slice 3) ──

  Future<List<CorpusOccurrence>> _searchLibraryFor(LexicalEntry entry) async {
    final values = await widget.api.searchCorpus(
      language: entry.language,
      query: entry.kind == 'phrase' ? entry.displayForm : entry.normalizedForm,
    );
    return values.map(CorpusOccurrence.fromJson).toList(growable: false);
  }

  Future<bool> _collectCorpus(
    LexicalEntry entry,
    CorpusOccurrence occurrence,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      final media = await widget.api.readMedia(occurrence.mediaId!);
      await widget.api.upsertLexicalEntry({
        'language': entry.language,
        'kind': entry.kind,
        // The normalized form re-normalizes to itself, so the upsert can only
        // land on this entry's identity and never fork a sibling entry.
        'canonical_form': entry.normalizedForm,
        'display_form': entry.displayForm,
        'status': null,
        'source': {
          'media_id': occurrence.mediaId,
          'sentence_id': occurrence.sentenceId,
          'original_form': occurrence.kind == 'lexical'
              ? occurrence.displayText
              : entry.displayForm,
          'sentence_text': occurrence.sourceSnapshot,
          'media_title': media['title'] ?? '',
          'media_fingerprint': media['fingerprint'],
          'start_ms': occurrence.startMs,
          'end_ms': occurrence.endMs,
        },
      });
      // Refresh so the new durable slice joins the entry's clip list.
      await _openEntryById(entry.id);
      if (mounted) {
        _snack(l.text('dictionaryCollected'));
      }
      return true;
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryCollectFailed').replaceAll('{error}', '$error'),
        );
      }
      return false;
    }
  }

  Future<void> _searchHomeCorpus() async {
    setState(() => homeSearching = true);
    List<CorpusOccurrence> results;
    try {
      final values = await widget.api.searchCorpus(
        language: widget.language,
        query: search,
      );
      results = values.map(CorpusOccurrence.fromJson).toList(growable: false);
    } catch (_) {
      results = const [];
    }
    if (mounted) {
      setState(() {
        homeSearching = false;
        homeResults = results;
      });
    }
  }

  Future<void> _reindexCorpus() async {
    final l = AppLocalizations.of(context);
    try {
      final count = await widget.api.reindexCorpus();
      if (mounted) {
        _snack(l.text('dictionaryReindexDone').replaceAll('{count}', '$count'));
      }
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryReindexFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  // ── Action exits ──

  Future<void> _addToReview(LexicalEntry entry) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.createReviewItem(
        CreateReviewItem(
          source: ReviewSource(
            kind: 'lexical_entry',
            id: entry.id,
            lexicalEntryId: entry.id,
          ),
          anchors: const [],
          promptSnapshot: entry.displayForm,
        ),
      );
      if (mounted) _snack(l.text('dictionaryReviewQueued'));
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryReviewFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<bool> _markOccurrence(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
    bool heard,
  ) async {
    final sentenceId = occurrence.sentenceId;
    if (sentenceId == null) return false;
    try {
      await widget.api.createLexicalObservation(
        lexicalEntryId: entry.id,
        sentenceId: sentenceId,
        originalForm: occurrence.originalForm ?? entry.displayForm,
        heard: heard,
        source: {
          'media_id': occurrence.mediaId,
          'sentence_id': sentenceId,
          'original_form': occurrence.originalForm ?? entry.displayForm,
          'sentence_text': occurrence.sentenceTextSnapshot,
          'media_title': occurrence.mediaTitleSnapshot,
          'media_fingerprint': occurrence.mediaFingerprintSnapshot,
          'start_ms': occurrence.startMsSnapshot,
          'end_ms': occurrence.endMsSnapshot,
        },
      );
      if (mounted) {
        _snack(
          AppLocalizations.of(
            context,
          ).text(heard ? 'dictionaryMarkedHeard' : 'dictionaryMarkedNotHeard'),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        _snack(
          AppLocalizations.of(
            context,
          ).text('dictionaryMarkFailed').replaceAll('{error}', '$error'),
        );
      }
      return false;
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final openDetails = details;
    return Scaffold(
      appBar: AppBar(
        leading: openDetails == null
            ? null
            : BackButton(onPressed: _closeDetails),
        title: Text(
          openDetails?.entry.displayForm ?? l.text('listeningDictionary'),
        ),
        actions: [
          if (openDetails != null)
            TextButton.icon(
              onPressed: () => unawaited(_addToReview(openDetails.entry)),
              icon: const Icon(Icons.queue_music_outlined, size: 18),
              label: Text(l.text('dictionaryAddToReview')),
            )
          else ...[
            IconButton(
              tooltip: l.text('dictionaryReindex'),
              onPressed: () => unawaited(_reindexCorpus()),
              icon: const Icon(Icons.manage_search_outlined),
            ),
            VocabularyTransferActions(
              onExport: widget.onExport,
              onImport: widget.onImport,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          if (openDetails == null) _bookBody(l) else _detailBody(openDetails),
          ListenableBuilder(
            listenable: slicePlayer.store,
            builder: (context, _) => slicePlayer.state.open
                ? SlicePlaybackWindow(
                    controller: slicePlayer,
                    onClose: slicePlayer.close,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _detailBody(LexicalEntryDetails value) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: ListeningDictionaryEntryView(
        // Rebind state when switching entries so reveal/mark/search state
        // never leaks from another word.
        key: ValueKey(value.entry.id),
        details: value,
        onPlay: (occurrence) =>
            unawaited(_playOccurrenceMap(occurrence.toJson())),
        onMark: (occurrence, heard) =>
            _markOccurrence(value.entry, occurrence, heard),
        onSearchLibrary: () => _searchLibraryFor(value.entry),
        onPlayCorpus: (occurrence) => unawaited(_playCorpus(occurrence)),
        onCollectCorpus: (occurrence) =>
            _collectCorpus(value.entry, occurrence),
      ),
    ),
  );

  Widget _bookBody(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: l.text('searchVocabulary'),
            ),
            onChanged: (value) {
              search = value;
              homeResults = null;
              unawaited(_load());
            },
          ),
        ),
        // Primary lens: the four-channel capability axis. The channel picker
        // only affects results once a specific assessment is chosen.
        _filterRow(
          children: [
            for (final cap in capabilities)
              ChoiceChip(
                label: Text(l.text(_capabilityLabelKey(cap))),
                selected: capability == cap,
                onSelected: (_) {
                  setState(() => capability = cap);
                  if (assessment != null) unawaited(_load());
                },
              ),
          ],
        ),
        _filterRow(
          children: [
            _assessmentChip(l.text('vocabFilterAll'), null),
            for (final value in assessmentFilters)
              _assessmentChip(
                l.text(value),
                value,
                color: capabilityAssessmentColor(value),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : words.isEmpty && search.trim().isNotEmpty
              ? _homeCorpusFallback(l)
              : VocabularyBookView(words: words, onWord: _openDetails),
        ),
      ],
    );
  }

  /// No vocabulary asset matches the query: the dictionary stays useful as a
  /// pure lookup tool by searching the local corpus directly (play only —
  /// saving a clip needs an entry to attach it to).
  Widget _homeCorpusFallback(AppLocalizations l) {
    final results = homeResults;
    if (results == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.text('noWords')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: homeSearching
                  ? null
                  : () => unawaited(_searchHomeCorpus()),
              icon: homeSearching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.travel_explore_outlined, size: 18),
              label: Text(l.text('dictionaryFindMore')),
            ),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return Center(child: Text(l.text('dictionaryNoLibraryResults')));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final result in results)
          CorpusResultTile(
            occurrence: result,
            target: search.trim(),
            onPlay: result.mediaId == null
                ? null
                : () => unawaited(_playCorpus(result)),
            onCollect: null,
          ),
      ],
    );
  }

  Widget _filterRow({required List<Widget> children}) => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, index) => Center(child: children[index]),
    ),
  );

  Widget _assessmentChip(String label, String? value, {Color? color}) =>
      ChoiceChip(
        avatar: color == null
            ? null
            : CircleAvatar(backgroundColor: color, radius: 5),
        label: Text(label),
        selected: assessment == value,
        onSelected: (_) {
          setState(() => assessment = value);
          unawaited(_load());
        },
      );
}
