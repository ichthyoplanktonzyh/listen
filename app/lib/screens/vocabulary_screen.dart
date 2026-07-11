import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../controllers/occurrence_media_resolver.dart';
import '../controllers/hunting_controller.dart';
import '../controllers/slice_player_controller.dart';
import '../localization.dart';
import '../models/practice.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import '../widgets/vocabulary/vocabulary_book_view.dart';
import '../widgets/vocabulary/listening_dictionary_entry_view.dart';
import '../widgets/vocabulary/hunting_list_panel.dart';
import '../widgets/vocabulary/vocabulary_transfer_actions.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onExport,
    required this.onImport,
    required this.huntingController,
    this.initialEntryId,
    this.onPauseBackgroundPlayback,
  });

  final LocalApi api;
  final String language;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final HuntingController huntingController;
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

  /// Pending listening upgrade suggestions and the dictionary-provider
  /// pronunciation audio for the open entry (both best-effort).
  List<UpgradeSuggestion> suggestions = const [];
  String? pronunciationAudioUrl;

  /// Corpus fallback when the vocabulary list has no match for [search].
  List<CorpusOccurrence>? homeResults;
  bool homeSearching = false;

  /// The dictionary hosts its own second-decoder slice playback so playing an
  /// example never leaves this screen or touches the primary player.
  final SlicePlayerController slicePlayer = SlicePlayerController();
  HuntingController get hunting => widget.huntingController;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(hunting.load(widget.api));
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
    // Suggestions and dictionary audio are decorations: each degrades to
    // absence instead of failing the detail page.
    List<UpgradeSuggestion> pending;
    try {
      pending = await widget.api.upgradeSuggestions(lexicalEntryId: entryId);
    } catch (_) {
      pending = const [];
    }
    String? audio;
    try {
      final bundle = DictionaryLookupBundle.fromJson(
        await widget.api.lookupDictionary(
          value.entry.normalizedForm,
          language: widget.language,
        ),
      );
      audio = bundle.results
          .expand(
            (result) =>
                result.lookup?.phonetics ?? const <DictionaryPhonetic>[],
          )
          .map((phonetic) => phonetic.audioUrl)
          .firstWhere(
            (url) => url != null && url.isNotEmpty,
            orElse: () => null,
          );
    } catch (_) {
      audio = null;
    }
    if (mounted) {
      setState(() {
        details = value;
        suggestions = pending;
        pronunciationAudioUrl = audio;
      });
    }
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
    slicePlayer.setShowVideo(true);
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

  // ── Detail editing (restored from the pre-dictionary detail dialog) ──

  Future<void> _setOverride(
    LexicalEntry entry,
    String capability,
    String? conclusion,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.setCapabilityOverride(
        entry.id,
        capability,
        conclusion: conclusion,
      );
      await _openEntryById(entry.id);
      // Capability filters in the book view read the same channels.
      unawaited(_load());
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _saveContent(
    LexicalEntry entry,
    String? definition,
    String? note,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.updateLexicalLearningContent(
        entry.id,
        userDefinition: definition,
        personalNote: note,
      );
      await _openEntryById(entry.id);
      if (mounted) _snack(l.text('dictionaryContentSaved'));
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _createSenseFolder(
    LexicalEntry entry,
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.createLexicalSenseFolder(
      entry.id,
      label: label,
      definition: definition,
      gloss: gloss,
      externalRef: externalRef,
    ),
  );

  Future<void> _updateSenseFolder(
    LexicalEntry entry,
    String senseId,
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.updateLexicalSenseFolder(
      entry.id,
      senseId,
      label: label,
      definition: definition,
      gloss: gloss,
      externalRef: externalRef,
    ),
  );

  Future<void> _deleteSenseFolder(LexicalEntry entry, String senseId) =>
      _saveSenseFolderChange(
        entry,
        () => widget.api.deleteLexicalSenseFolder(entry.id, senseId),
      );

  Future<void> _assignSenseFolder(
    LexicalEntry entry,
    String senseId,
    LexicalOccurrence occurrence,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.assignLexicalSenseFolderOccurrence(
      entry.id,
      senseId,
      occurrence.id,
    ),
  );

  Future<void> _unassignSenseFolder(
    LexicalEntry entry,
    String senseId,
    LexicalOccurrence occurrence,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.unassignLexicalSenseFolderOccurrence(
      entry.id,
      senseId,
      occurrence.id,
    ),
  );

  Future<void> _saveSenseFolderChange(
    LexicalEntry entry,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      final value = LexicalEntryDetails.fromJson(await action());
      if (mounted) setState(() => details = value);
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _confirmSuggestion(
    LexicalEntry entry,
    UpgradeSuggestion suggestion,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.confirmUpgradeSuggestion(suggestion.id);
      await _openEntryById(entry.id);
      unawaited(_load());
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _rejectSuggestion(
    LexicalEntry entry,
    UpgradeSuggestion suggestion,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.rejectUpgradeSuggestion(suggestion.id);
      await _openEntryById(entry.id);
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  // ── External references (copyright guardrail: links only) ──

  /// YouGlish covers the current learning target (English); other languages
  /// simply hide the link instead of guessing a locale path.
  String? _externalLookupUrlFor(String query, String language) =>
      language == 'en' && query.trim().isNotEmpty
      ? 'https://youglish.com/pronounce/${Uri.encodeComponent(query.trim())}/english'
      : null;

  // The consumer app is macOS-only, so the system opener is sufficient; no
  // url_launcher dependency for one reference link.
  void _openExternal(String url) => unawaited(Process.run('open', [url]));

  // ── Action exits ──

  Future<void> _reviewClip(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.createReviewItem(
        CreateReviewItem(
          source: ReviewSource(
            kind: 'lexical_entry',
            id: entry.id,
            lexicalEntryId: entry.id,
            mediaId: occurrence.mediaId,
          ),
          // The sentence anchor carries the clip's durable window so the
          // review queue can derive playback/cloze-style cards from it.
          anchors: [
            if (occurrence.sentenceId != null)
              PracticeAnchor(
                kind: 'sentence',
                id: occurrence.sentenceId!,
                label: occurrence.sentenceTextSnapshot,
                sentenceId: occurrence.sentenceId,
                startMs: occurrence.startMsSnapshot,
                endMs: occurrence.endMsSnapshot,
              ),
            PracticeAnchor(
              kind: 'lexical_entry',
              id: entry.id,
              label: occurrence.originalForm ?? entry.displayForm,
              lexicalEntryId: entry.id,
              sentenceId: occurrence.sentenceId,
            ),
          ],
          promptSnapshot: occurrence.sentenceTextSnapshot,
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

  Future<void> _openHuntingList() async {
    await hunting.load(widget.api);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: HuntingListPanel(
            controller: hunting,
            onRefresh: () async {
              await hunting.load(widget.api);
            },
            onPromoteCandidate: (candidate) async {
              final saved = await hunting.promoteCandidate(
                widget.api,
                candidate,
              );
              if (mounted && saved) {
                _snack(AppLocalizations.of(context).text('huntingAdded'));
              }
            },
            onArchiveTarget: (target) async {
              final saved = await hunting.archive(widget.api, target);
              if (mounted && saved) {
                _snack(AppLocalizations.of(context).text('huntingArchived'));
              }
            },
            onOpenEntry: (entryId) {
              Navigator.of(sheetContext).pop();
              unawaited(_openEntryById(entryId));
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addToHuntingList(LexicalEntry entry) async {
    final l = AppLocalizations.of(context);
    if (hunting.state.containsLexicalEntry(entry.id)) {
      _snack(l.text('huntingAlreadyAdded'));
      return;
    }
    final saved = await hunting.addManual(widget.api, entry);
    if (!mounted) return;
    if (saved) {
      _snack(l.text('huntingAdded'));
    } else if (hunting.state.error != null) {
      _snack(
        l
            .text('huntingUpdateFailed')
            .replaceAll('{error}', hunting.state.error!),
      );
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
    return ListenableBuilder(
      listenable: hunting,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: openDetails == null
              ? null
              : BackButton(onPressed: _closeDetails),
          title: Text(
            openDetails?.entry.displayForm ?? l.text('listeningDictionary'),
          ),
          actions: [
            IconButton(
              tooltip: l.text('huntingOpen'),
              onPressed: () => unawaited(_openHuntingList()),
              icon: Badge(
                isLabelVisible: hunting.state.targets.isNotEmpty,
                label: Text('${hunting.state.targets.length}'),
                child: const Icon(Icons.gps_fixed),
              ),
            ),
            if (openDetails != null)
              IconButton(
                tooltip:
                    hunting.state.containsLexicalEntry(openDetails.entry.id)
                    ? l.text('huntingAlreadyAdded')
                    : l.text('huntingAddCurrent'),
                onPressed:
                    hunting.state.busy ||
                        hunting.state.containsLexicalEntry(openDetails.entry.id)
                    ? null
                    : () => unawaited(_addToHuntingList(openDetails.entry)),
                icon: Icon(
                  hunting.state.containsLexicalEntry(openDetails.entry.id)
                      ? Icons.gps_fixed
                      : Icons.add_location_alt_outlined,
                ),
              ),
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
        body: openDetails == null ? _bookBody(l) : _detailBody(openDetails),
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
        slicePlayer: slicePlayer,
        onPlay: (occurrence) =>
            unawaited(_playOccurrenceMap(occurrence.toJson())),
        onMark: (occurrence, heard) =>
            _markOccurrence(value.entry, occurrence, heard),
        onSearchLibrary: () => _searchLibraryFor(value.entry),
        onPlayCorpus: (occurrence) => unawaited(_playCorpus(occurrence)),
        onCollectCorpus: (occurrence) =>
            _collectCorpus(value.entry, occurrence),
        suggestions: suggestions,
        onConfirmSuggestion: (suggestion) =>
            _confirmSuggestion(value.entry, suggestion),
        onRejectSuggestion: (suggestion) =>
            _rejectSuggestion(value.entry, suggestion),
        onCapabilityOverride: (capability, conclusion) =>
            _setOverride(value.entry, capability, conclusion),
        onSaveContent: (definition, note) =>
            _saveContent(value.entry, definition, note),
        onCreateSenseFolder: (label, definition, gloss, externalRef) =>
            _createSenseFolder(
              value.entry,
              label,
              definition,
              gloss,
              externalRef,
            ),
        onUpdateSenseFolder: (id, label, definition, gloss, externalRef) =>
            _updateSenseFolder(
              value.entry,
              id,
              label,
              definition,
              gloss,
              externalRef,
            ),
        onDeleteSenseFolder: (id) => _deleteSenseFolder(value.entry, id),
        onAssignSenseFolder: (senseId, occurrence) =>
            _assignSenseFolder(value.entry, senseId, occurrence),
        onUnassignSenseFolder: (senseId, occurrence) =>
            _unassignSenseFolder(value.entry, senseId, occurrence),
        onReviewClip: (occurrence) => _reviewClip(value.entry, occurrence),
        externalLookupUrl: _externalLookupUrlFor(
          value.entry.displayForm,
          value.entry.language,
        ),
        onOpenExternal: _openExternal,
        pronunciationAudioUrl: pronunciationAudioUrl,
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
      final externalUrl = _externalLookupUrlFor(search, widget.language);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.text('dictionaryNoLibraryResults')),
            if (externalUrl != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openExternal(externalUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.text('dictionaryYouglish')),
              ),
            ],
          ],
        ),
      );
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
