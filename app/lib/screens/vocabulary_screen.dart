import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../controllers/auxiliary_audio_controller.dart';
import '../controllers/hunting_controller.dart';
import '../controllers/occurrence_media_resolver.dart';
import '../controllers/slice_player_controller.dart';
import '../localization.dart';
import '../models/api_failure.dart';
import '../models/practice.dart';
import '../models/production_corpus.dart';
import '../models/projection_review.dart';
import '../models/semantic_embedding.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../widgets/common/api_failure_disclosure.dart';
import '../widgets/common/listen_empty_state.dart';
import '../widgets/common/listen_loading.dart';
import '../widgets/vocabulary/hunting_list_panel.dart';
import '../widgets/vocabulary/semantic_search_dialog.dart';
import '../widgets/vocabulary/listening_dictionary_entry_view.dart';
import '../widgets/common/capability_viz.dart';
import '../widgets/vocabulary/vocabulary_book_view.dart';
import '../widgets/vocabulary/vocabulary_gap_panel.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onExport,
    required this.onImport,
    required this.huntingController,
    required this.auxiliaryAudio,
    this.initialEntryId,
    this.openCrossModalReviewOnStart = false,
    this.onPauseBackgroundPlayback,
    this.onStartShadowing,
  });

  final LocalApi api;
  final String language;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final HuntingController huntingController;
  final AuxiliaryAudioController auxiliaryAudio;
  final String? initialEntryId;
  final bool openCrossModalReviewOnStart;

  /// Pauses whatever is playing behind this route (the primary player) so a
  /// slice owns audio focus alone, matching the workbench behaviour.
  final Future<void> Function()? onPauseBackgroundPlayback;
  final Future<void> Function(String path, Map<String, dynamic> occurrence)?
  onStartShadowing;

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
  List<LexicalEntryDetails> words = const [];

  /// Non-null while the in-page entry detail is open (master → detail).
  LexicalEntryDetails? details;

  /// The gap instrument room — the right pane's default page. Two independent
  /// best-effort backend sources are juxtaposed here (rendering only); each
  /// degrades to a notice instead of failing the workbench.
  bool gapLoading = true;
  List<CrossModalReviewCandidateView>? gapCandidates;
  ApiFailure? gapCandidatesError;
  ProductionGapReviewView? gapProduction;
  ApiFailure? gapProductionError;

  /// Set when the coach's cross-modal hand-off lands us here so the candidates
  /// section is emphasised (the number the coach clicked).
  bool gapHighlightCandidates = false;

  /// Narrow (single-column, "B") form only: whether the gap pane is showing
  /// full-width instead of the word list. Ignored in the two-pane form where
  /// the gap pane is simply the right pane whenever no entry is open.
  bool narrowGapOpen = false;

  /// Whether semantic search can run, so the main search box can offer a
  /// "semantic" toggle; management lives in the tools menu. Best-effort.
  bool semanticCanSearch = false;
  bool semanticMode = false;
  List<SemanticSearchHitView> semanticHits = const [];
  bool semanticSearching = false;

  /// Pending listening upgrade suggestions and the dictionary-provider
  /// pronunciation audio for the open entry (both best-effort).
  ///
  /// S4 (#82 / V6): these are *decorations* of the open entry and each one
  /// loads on its own clock. The identity card renders from `details` alone,
  /// so a slow dictionary provider can no longer hold the whole detail pane.
  List<UpgradeSuggestion> suggestions = const [];
  bool suggestionsLoading = false;
  String? pronunciationAudioUrl;
  bool pronunciationLoading = false;
  List<ProductionCorpusHitView>? productionHits;
  bool productionLoadFailed = false;

  /// Monotonic id of the newest detail request. A decoration that resolves
  /// after the user moved to another entry is dropped instead of painting
  /// the previous word's data onto the current one.
  int detailRequest = 0;

  /// Corpus fallback when the vocabulary list has no match for [search].
  List<CorpusOccurrence>? homeResults;
  bool homeSearching = false;

  /// The dictionary hosts its own second-decoder slice playback so playing an
  /// example never leaves this screen or touches the primary player.
  final SlicePlayerController slicePlayer = SlicePlayerController();
  HuntingController get hunting => widget.huntingController;

  Future<void> _acquireAuxiliaryAudioFocus() async {
    await slicePlayer.pause();
    await widget.onPauseBackgroundPlayback?.call();
  }

  Future<void> _playPronunciationAudio(String url) async {
    await widget.auxiliaryAudio.playRemote(
      url,
      acquireAudioFocus: _acquireAuxiliaryAudioFocus,
    );
    if (mounted && widget.auxiliaryAudio.error != null) {
      _snack(AppLocalizations.of(context).text('pronunciationUnavailable'));
    }
  }

  Future<void> _speakSynthetic(String text, String purpose) async {
    final asset = await widget.auxiliaryAudio.speak(
      widget.api,
      text: text,
      language: details?.entry.language ?? widget.language,
      purpose: purpose,
      acquireAudioFocus: _acquireAuxiliaryAudioFocus,
    );
    if (mounted && asset == null) {
      _snack(AppLocalizations.of(context).text('ttsUnavailable'));
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // The gap instrument room is the default right pane, so its two sources
    // load up front (best-effort, each caught) rather than behind a click.
    unawaited(_loadGapPanel());
    unawaited(_probeSemanticSearch());
    // The hunting controller is shared with the app shell, whose
    // ListenableBuilder is already subscribed while this route's first build
    // is in progress — load() notifies synchronously, so defer it past the
    // frame (same pattern as realtime_conversation_panel).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(hunting.load(widget.api));
    });
    final initialEntryId = widget.initialEntryId;
    if (initialEntryId != null) {
      unawaited(_openEntryById(initialEntryId));
    }
    if (widget.openCrossModalReviewOnStart) {
      // The coach's cross-modal hand-off lands on the gap pane (the default
      // right pane) rather than a dialog; emphasise the candidates section.
      _landOnGapPane(highlightCandidates: true);
    }
  }

  @override
  void dispose() {
    unawaited(widget.auxiliaryAudio.stop());
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

  /// Opens an entry's detail. The entry itself is awaited (it *is* the page);
  /// its three decorations then load in parallel, each publishing on its own
  /// (V6: serial waiting is what made the identity card hostage to the
  /// slowest provider).
  Future<void> _openEntryById(String entryId) async {
    final request = ++detailRequest;
    if (mounted) {
      setState(() {
        suggestions = const [];
        suggestionsLoading = true;
        pronunciationAudioUrl = null;
        pronunciationLoading = true;
        productionHits = null;
        productionLoadFailed = false;
      });
    }
    final value = await widget.api.lexicalEntryDetails(entryId);
    if (!mounted || request != detailRequest) return;
    // The identity card can paint now — nothing below is awaited here.
    setState(() => details = value);
    unawaited(_loadEntrySuggestions(entryId, request));
    unawaited(_loadEntryPronunciation(value.entry, request));
    unawaited(_loadEntryProduction(value.entry, request));
  }

  /// Whether a decoration that just resolved still belongs to the open entry.
  bool _detailStillCurrent(int request) => mounted && request == detailRequest;

  Future<void> _loadEntrySuggestions(String entryId, int request) async {
    List<UpgradeSuggestion> pending;
    try {
      pending = await widget.api.upgradeSuggestions(lexicalEntryId: entryId);
    } catch (_) {
      // A missing suggestion source degrades to "no suggestions", never to a
      // broken detail page.
      pending = const [];
    }
    if (!_detailStillCurrent(request)) return;
    setState(() {
      suggestions = pending;
      suggestionsLoading = false;
    });
  }

  Future<void> _loadEntryPronunciation(LexicalEntry entry, int request) async {
    String? audio;
    try {
      final bundle = await widget.api.lookupDictionary(
        entry.normalizedForm,
        language: widget.language,
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
    if (!_detailStillCurrent(request)) return;
    setState(() {
      pronunciationAudioUrl = audio;
      pronunciationLoading = false;
    });
  }

  Future<void> _loadEntryProduction(LexicalEntry entry, int request) async {
    List<ProductionCorpusHitView> output;
    var outputLoadFailed = false;
    try {
      output = await widget.api.searchProductionCorpus(
        language: entry.language,
        query: entry.normalizedForm,
      );
    } catch (_) {
      // "Unavailable" and "you have not produced this yet" stay distinct.
      output = const [];
      outputLoadFailed = true;
    }
    if (!_detailStillCurrent(request)) return;
    setState(() {
      productionHits = output;
      productionLoadFailed = outputLoadFailed;
    });
  }

  Future<void> _openDetails(LexicalEntryDetails value) async {
    await _openEntryById(value.entry.id);
  }

  void _closeDetails() {
    unawaited(widget.auxiliaryAudio.stop());
    setState(() => details = null);
  }

  Future<void> _openProductionAttempt(ProductionCorpusHitView hit) async {
    final attemptId = hit.document.attemptId;
    final attempt = attemptId == null
        ? null
        : await widget.api.semanticAttempt(attemptId);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('myOutputAttempt')),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                '${hit.document.activityKind} · ${l.text('revision')} ${hit.document.responseRevision}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              if (attempt == null) ...[
                SelectableText(hit.document.responseText),
              ],
              // `attempt?.responses ?? const []` would infer `List<dynamic>`
              // here (a for-in gives the literal an `Iterable<dynamic>`
              // context), so promote instead and keep `response` typed.
              if (attempt != null)
                for (final response in attempt.responses) ...[
                  Text(
                    '${l.text('revision')} ${response.revision}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: ListenSpacing.gap4),
                  SelectableText(response.transcript),
                  const SizedBox(height: ListenSpacing.gap12),
                ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

  /// Loads the two gap-pane sources. Each is best-effort and degrades to an
  /// inline notice — the workbench never fails because a decoration source is
  /// down. Rendering only: neither query is changed, they are juxtaposed.
  Future<void> _loadGapPanel() async {
    List<CrossModalReviewCandidateView>? candidates;
    ApiFailure? candidatesError;
    try {
      candidates = await widget.api.crossModalReviewGaps(
        language: widget.language,
      );
    } catch (error) {
      candidatesError = describeApiFailure(error);
    }
    ProductionGapReviewView? production;
    ApiFailure? productionError;
    try {
      final enriched = await widget.api.semanticProductionGapReview(
        language: widget.language,
      );
      production = enriched.review;
    } catch (_) {
      // The semantic enrichment is optional; fall back to the plain review.
      try {
        production = await widget.api.productionGapReview(
          language: widget.language,
        );
      } catch (error) {
        productionError = describeApiFailure(error);
      }
    }
    if (mounted) {
      setState(() {
        gapCandidates = candidates;
        gapCandidatesError = candidatesError;
        gapProduction = production;
        gapProductionError = productionError;
        gapLoading = false;
      });
    }
  }

  /// Lands on the gap pane (the default right pane): closes any open detail
  /// and, in the narrow form, brings the gap surface forward. Replaces the two
  /// old app-bar dialogs and the coach's cross-modal dialog hand-off.
  void _landOnGapPane({bool highlightCandidates = false}) {
    if (!mounted) return;
    setState(() {
      details = null;
      narrowGapOpen = true;
      if (highlightCandidates) gapHighlightCandidates = true;
    });
  }

  Future<void> _probeSemanticSearch() async {
    try {
      final capability = await widget.api.semanticEmbeddingCapability();
      if (mounted) setState(() => semanticCanSearch = capability.canSearch);
    } catch (_) {
      // Optional capability; the exact-search box stays fully usable.
    }
  }

  Future<void> _runSemanticSearch() async {
    if (search.trim().isEmpty) {
      setState(() => semanticHits = const []);
      return;
    }
    setState(() => semanticSearching = true);
    List<SemanticSearchHitView> hits;
    try {
      final result = await widget.api.semanticSearch(
        query: search,
        language: widget.language,
      );
      hits = result.hits;
    } catch (_) {
      hits = const [];
    }
    if (mounted) {
      setState(() {
        semanticHits = hits;
        semanticSearching = false;
      });
    }
  }

  void _openSemanticIndexManager() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) =>
            SemanticSearchDialog(api: widget.api, language: widget.language),
      ),
    );
  }

  Future<void> _openProjectionReview(String lexicalEntryId) async {
    final l = AppLocalizations.of(context);
    List<ProjectionProposalView> proposals;
    try {
      proposals = await widget.api.auditProjectionEntry(lexicalEntryId);
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('projectionReviewUnavailable'),
          failure: describeApiFailure(error),
        );
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('projectionReviewTitle')),
        content: SizedBox(
          width: 680,
          child: proposals.isEmpty
              ? Text(l.text('projectionReviewEmpty'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final proposal in proposals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${proposal.capability} → ${proposal.proposedConclusion}',
                        ),
                        subtitle: Text(
                          '${proposal.rationale}\n${proposal.algorithmVersion} · ${proposal.status}',
                        ),
                        isThreeLine: true,
                        trailing: proposal.status != 'pending'
                            ? null
                            : Wrap(
                                children: [
                                  IconButton(
                                    tooltip: l.text('reject'),
                                    onPressed: () async {
                                      await widget.api.decideProjectionProposal(
                                        proposalId: proposal.id,
                                        decision: 'reject',
                                      );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                      if (mounted) {
                                        unawaited(
                                          _openProjectionReview(lexicalEntryId),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                  IconButton(
                                    tooltip: l.text('confirm'),
                                    onPressed: () async {
                                      await widget.api.decideProjectionProposal(
                                        proposalId: proposal.id,
                                        decision: 'confirm',
                                      );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                      if (mounted) {
                                        unawaited(
                                          _openEntryById(lexicalEntryId),
                                        );
                                        unawaited(
                                          _openProjectionReview(lexicalEntryId),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

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

  Future<void> _startShadowingOccurrence(LexicalOccurrence occurrence) async {
    final path = slicePlayer.state.path;
    final callback = widget.onStartShadowing;
    if (path == null || callback == null) return;
    await slicePlayer.pause();
    if (mounted) Navigator.of(context).pop();
    await callback(path, occurrence.toJson());
  }

  Future<void> _playCorpus(CorpusOccurrence occurrence) async {
    final mediaId = occurrence.mediaId;
    if (mediaId == null) return;
    MediaItem media;
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
      'media_fingerprint_snapshot': media.fingerprint,
      'media_title_snapshot': media.title,
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
    return values;
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
          'media_title': media.title,
          'media_fingerprint': media.fingerprint,
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
          l.text('dictionaryCollectFailed'),
          failure: describeApiFailure(error),
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
      results = values;
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
          l.text('dictionaryReindexFailed'),
          failure: describeApiFailure(error),
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
          l.text('dictionaryUpdateFailed'),
          failure: describeApiFailure(error),
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
          l.text('dictionaryUpdateFailed'),
          failure: describeApiFailure(error),
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
    Future<LexicalEntryDetails> Function() action,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      final value = await action();
      if (mounted) setState(() => details = value);
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed'),
          failure: describeApiFailure(error),
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
          l.text('dictionaryUpdateFailed'),
          failure: describeApiFailure(error),
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
          l.text('dictionaryUpdateFailed'),
          failure: describeApiFailure(error),
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
          l.text('dictionaryReviewFailed'),
          failure: describeApiFailure(error),
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
          l.text('dictionaryReviewFailed'),
          failure: describeApiFailure(error),
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
      // The controller's own `error` is already a named sentence (#66), so the
      // localized one wins here rather than being pasted into a placeholder.
      _snack(l.text('huntingUpdateFailed'));
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
          AppLocalizations.of(context).text('dictionaryMarkFailed'),
          failure: describeApiFailure(error),
        );
      }
      return false;
    }
  }

  /// A SnackBar that names what failed, with the diagnostics one tap away.
  ///
  /// Every call here used to read
  /// `_snack(l.text('…').replaceAll('{error}', '$error'))`, which put the whole
  /// exception in the bar. A bar is one line and cannot hold a disclosure, so
  /// [failure] becomes an action that opens the same fields in a dialog — and
  /// the reference id a bug report needs stops being thrown away.
  void _snack(String message, {ApiFailure? failure}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: ApiFailureDisclosure.hasDetail(failure)
            ? SnackBarAction(
                label: AppLocalizations.of(context).text('failureDetailsShow'),
                onPressed: () =>
                    unawaited(showApiFailureDetails(context, failure!)),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two panes side by side above the fold, single column below it (the
        // narrow "B" form). Same semantics, two breakpoint shapes (S0).
        final twoPane =
            constraints.maxWidth >= ListenBreakpoints.vocabularyTwoPane;
        return ListenableBuilder(
          listenable: Listenable.merge([hunting, widget.auxiliaryAudio]),
          builder: (context, _) {
            final openDetails = details;
            // The narrow form stacks the list, gap pane and detail, so a
            // sub-surface needs a back affordance. The two-pane form keeps the
            // list beside the pane, so its app bar never grows a leading — it
            // never transforms (V5).
            final narrowSubSurface =
                !twoPane && (openDetails != null || narrowGapOpen);
            return Scaffold(
              appBar: AppBar(
                leading: narrowSubSurface
                    ? BackButton(
                        onPressed: () {
                          if (details != null) {
                            _closeDetails();
                          } else {
                            setState(() => narrowGapOpen = false);
                          }
                        },
                      )
                    : null,
                // Never transforms: title and tools stay constant whatever the
                // right pane shows. Detail actions live in the detail pane, not
                // the top bar (V5 death).
                title: Text(l.text('listeningDictionary')),
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
                  _toolsMenu(l),
                ],
              ),
              body: twoPane ? _twoPaneBody(l) : _narrowBody(l),
            );
          },
        );
      },
    );
  }

  /// The maintenance domain, permanently layered off the core flow: import,
  /// export, corpus reindex and semantic-index management all live in one
  /// overflow menu (C3/V5).
  Widget _toolsMenu(AppLocalizations l) => PopupMenuButton<String>(
    tooltip: l.text('vocabToolsMenu'),
    icon: const Icon(Icons.more_vert),
    onSelected: (value) {
      switch (value) {
        case 'import':
          unawaited(widget.onImport());
        case 'export':
          unawaited(widget.onExport());
        case 'reindex':
          unawaited(_reindexCorpus());
        case 'semantic':
          _openSemanticIndexManager();
      }
    },
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'import',
        child: _toolsItem(Icons.file_download_outlined, l.text('importAssets')),
      ),
      PopupMenuItem(
        value: 'export',
        child: _toolsItem(Icons.file_upload_outlined, l.text('exportAssets')),
      ),
      PopupMenuItem(
        value: 'reindex',
        child: _toolsItem(
          Icons.manage_search_outlined,
          l.text('dictionaryReindex'),
        ),
      ),
      PopupMenuItem(
        value: 'semantic',
        child: _toolsItem(
          Icons.travel_explore_outlined,
          l.text('vocabToolsSemanticIndex'),
        ),
      ),
    ],
  );

  Widget _toolsItem(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: ListenIconSize.control),
      const SizedBox(width: ListenSpacing.gap12),
      Text(label),
    ],
  );

  Widget _twoPaneBody(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final openDetails = details;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: _listColumn(l, gapSelected: openDetails == null),
        ),
        VerticalDivider(width: 1, color: colors.outlineVariant),
        Expanded(
          child: openDetails == null ? _gapPane() : _detailBody(openDetails),
        ),
      ],
    );
  }

  Widget _narrowBody(AppLocalizations l) {
    final openDetails = details;
    if (openDetails != null) return _detailBody(openDetails);
    if (narrowGapOpen) return _gapPane();
    return _listColumn(l, gapSelected: false, showGapStrip: true);
  }

  Widget _gapPane() => VocabularyGapPanel(
    loading: gapLoading,
    candidates: gapCandidates,
    candidatesError: gapCandidatesError,
    production: gapProduction,
    productionError: gapProductionError,
    highlightCandidates: gapHighlightCandidates,
    onOpenEntry: (id) => unawaited(_openEntryById(id)),
  );

  Widget _detailBody(LexicalEntryDetails value) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: ListenBreakpoints.contentColumnMax,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailActionsHeader(value),
          Expanded(
            child: ListeningDictionaryEntryView(
              // Rebind state when switching entries so reveal/mark/search state
              // never leaks from another word.
              key: ValueKey(value.entry.id),
              details: value,
              showProductionCorpus: true,
              productionHits: productionHits,
              productionLoadFailed: productionLoadFailed,
              onOpenProductionAttempt: _openProductionAttempt,
              slicePlayer: slicePlayer,
              onPlay: (occurrence) =>
                  unawaited(_playOccurrenceMap(occurrence.toJson())),
              onShadowing: widget.onStartShadowing == null
                  ? null
                  : _startShadowingOccurrence,
              onMark: (occurrence, heard) =>
                  _markOccurrence(value.entry, occurrence, heard),
              onSearchLibrary: () => _searchLibraryFor(value.entry),
              onPlayCorpus: (occurrence) => unawaited(_playCorpus(occurrence)),
              onCollectCorpus: (occurrence) =>
                  _collectCorpus(value.entry, occurrence),
              suggestions: suggestions,
              suggestionsLoading: suggestionsLoading,
              pronunciationLoading: pronunciationLoading,
              onConfirmSuggestion: (suggestion) =>
                  _confirmSuggestion(value.entry, suggestion),
              onRejectSuggestion: (suggestion) =>
                  _rejectSuggestion(value.entry, suggestion),
              onCapabilityOverride: (capability, conclusion) =>
                  _setOverride(value.entry, capability, conclusion),
              onLoadEvidenceHistory: ({String? capability, int offset = 0}) =>
                  widget.api.learningObservationHistory(
                    value.entry.id,
                    capability: capability,
                    offset: offset,
                  ),
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
              onUpdateSenseFolder:
                  (id, label, definition, gloss, externalRef) =>
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
              onReviewClip: (occurrence) =>
                  _reviewClip(value.entry, occurrence),
              externalLookupUrl: _externalLookupUrlFor(
                value.entry.displayForm,
                value.entry.language,
              ),
              onOpenExternal: _openExternal,
              pronunciationAudioUrl: pronunciationAudioUrl,
              onPlayPronunciationAudio: (url) =>
                  unawaited(_playPronunciationAudio(url)),
              onSpeakSynthetic: (text, purpose) =>
                  unawaited(_speakSynthetic(text, purpose)),
              speechBusy: widget.auxiliaryAudio.busy,
            ),
          ),
        ],
      ),
    ),
  );

  /// The detail pane's own action bar. These used to hijack the app bar (V5);
  /// they now travel with the detail so the shell never transforms.
  ///
  /// Its left slot used to repeat the display form, directly above the
  /// identity card's own word head — the same word twice, 12pt apart, and the
  /// small one carried nothing the big one did not. It now carries the thing
  /// the header could not say: which source the word was met in.
  Widget _detailActionsHeader(LexicalEntryDetails value) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final inHunting = hunting.state.containsLexicalEntry(value.entry.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
      child: Row(
        children: [
          Expanded(child: _detailSourceLabel(value)),
          TextButton.icon(
            onPressed: () => unawaited(_addToReview(value.entry)),
            icon: const Icon(
              Icons.queue_music_outlined,
              size: ListenIconSize.control,
            ),
            label: Text(l.text('dictionaryAddToReview')),
          ),
          IconButton(
            tooltip: inHunting
                ? l.text('huntingAlreadyAdded')
                : l.text('huntingAddCurrent'),
            onPressed: hunting.state.busy || inHunting
                ? null
                : () => unawaited(_addToHuntingList(value.entry)),
            icon: Icon(
              inHunting ? Icons.gps_fixed : Icons.add_location_alt_outlined,
              color: inHunting ? colors.primary : null,
            ),
          ),
          IconButton(
            tooltip: l.text('projectionReviewTitle'),
            onPressed: () => unawaited(_openProjectionReview(value.entry.id)),
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
    );
  }

  /// Where this word was met: the durable media title of its first source
  /// clip, quiet enough to stay context rather than compete with the word
  /// head below it. When the entry has several sources the extra titles are
  /// in the tooltip — the bar has room for one, and the clips section is
  /// where the full list belongs.
  Widget _detailSourceLabel(LexicalEntryDetails value) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final titles = <String>{
      for (final occurrence in value.occurrences)
        if (occurrence.mediaTitleSnapshot.trim().isNotEmpty)
          occurrence.mediaTitleSnapshot.trim(),
    };
    final label = titles.isEmpty
        ? l.text('vocabDetailSourceUnknown')
        : titles.first;
    return Tooltip(
      message: titles.length > 1 ? titles.join('\n') : label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_outlined,
            size: ListenIconSize.inline,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: ListenSpacing.gap6),
          Flexible(
            child: Text(
              label,
              style: ListenType.caption.copyWith(
                color: colors.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// The list column (left of the workbench, or the whole narrow screen): the
  /// search box, the persistent gap entry, the channel/assessment lens, then
  /// the word list.
  Widget _listColumn(
    AppLocalizations l, {
    required bool gapSelected,
    bool showGapStrip = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: semanticMode
                        ? l.text('semanticSearchHint')
                        : l.text('searchVocabulary'),
                  ),
                  onChanged: (value) {
                    search = value;
                    homeResults = null;
                    if (!semanticMode) unawaited(_load());
                  },
                  onSubmitted: (_) {
                    if (semanticMode) unawaited(_runSemanticSearch());
                  },
                ),
              ),
              // The semantic "use" surface folds into the main box; only the
              // "manage" surface stays in the tools menu. The toggle appears
              // only when the capability can actually search.
              if (semanticCanSearch) ...[
                const SizedBox(width: ListenSpacing.gap8),
                FilterChip(
                  label: Text(l.text('semanticSearchToggle')),
                  selected: semanticMode,
                  onSelected: (on) {
                    setState(() {
                      semanticMode = on;
                      semanticHits = const [];
                    });
                    if (on) {
                      if (search.trim().isNotEmpty) {
                        unawaited(_runSemanticSearch());
                      }
                    } else {
                      unawaited(_load());
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        // The gap instrument room is a permanent entry, not a buried icon —
        // the workbench's self-falsification note asks for a visible way back
        // to the gap list. Two-pane uses a selectable entry row; the narrow
        // form uses a compact gap strip with live counts instead.
        if (showGapStrip)
          _narrowGapStrip(l)
        else
          ListTile(
            dense: true,
            selected: gapSelected,
            selectedTileColor: colors.primary.withValues(alpha: 0.08),
            leading: const Icon(Icons.hub_outlined),
            title: Text(l.text('vocabGapEntry')),
            onTap: _landOnGapPane,
          ),
        Divider(height: 1, color: colors.outlineVariant),
        // Primary lens: the four-channel capability axis. The channel always
        // re-lenses the entry rings (presentation); it only re-queries once an
        // assessment is picked, which is when the backend filters by capability.
        _filterRow(
          children: [
            for (final cap in capabilities)
              ChoiceChip(
                label: Text(l.text(_capabilityLabelKey(cap))),
                visualDensity: VisualDensity.compact,
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
                color: capabilityAssessmentColor(
                  Theme.of(context).colorScheme,
                  value,
                ),
              ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(child: _listResults(l)),
      ],
    );
  }

  Widget _listResults(AppLocalizations l) {
    if (semanticMode) {
      if (semanticSearching) return const Center(child: ListenLoading());
      if (semanticHits.isEmpty) {
        return ListenEmptyState(
          icon: Icons.search_off,
          message: l.text('semanticSearchNoHits'),
        );
      }
      return ListView.separated(
        itemCount: semanticHits.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final hit = semanticHits[index];
          return ListTile(
            title: Text(
              hit.source.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${hit.source.kind}'
              '${hit.source.channel == null ? '' : ' · ${hit.source.channel}'}',
            ),
            trailing: Text(hit.similarity.toStringAsFixed(3)),
          );
        },
      );
    }
    if (loading) return const Center(child: ListenLoading());
    if (words.isEmpty && search.trim().isNotEmpty) {
      return _homeCorpusFallback(l);
    }
    return VocabularyBookView(
      words: words,
      onWord: _openDetails,
      focusCapability: capability,
      selectedEntryId: details?.entry.id,
    );
  }

  /// The narrow ("B") form keeps a compact gap strip at the top of the list so
  /// gap-(c) is one tap away even without a second pane.
  Widget _narrowGapStrip(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final candidateCount = gapCandidates?.length;
    final targetCount = gapProduction?.targets.length;
    final subtitle = (candidateCount == null && targetCount == null)
        ? l.text('vocabGapEntry')
        : l
              .text('gapPaneSubtitle')
              .replaceAll('{candidates}', '${candidateCount ?? 0}')
              .replaceAll('{targets}', '${targetCount ?? 0}');
    return InkWell(
      onTap: _landOnGapPane,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              Icons.hub_outlined,
              size: ListenIconSize.control,
              color: colors.secondary,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                subtitle,
                style: ListenType.caption.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              l.text('vocabGapStripAction'),
              style: ListenType.caption.copyWith(color: colors.secondary),
            ),
          ],
        ),
      ),
    );
  }

  /// No vocabulary asset matches the query: the dictionary stays useful as a
  /// pure lookup tool by searching the local corpus directly (play only —
  /// saving a clip needs an entry to attach it to).
  Widget _homeCorpusFallback(AppLocalizations l) {
    final results = homeResults;
    if (results == null) {
      return ListenEmptyState(
        icon: Icons.menu_book_outlined,
        message: l.text('noWords'),
        action: OutlinedButton.icon(
          onPressed: homeSearching
              ? null
              : () => unawaited(_searchHomeCorpus()),
          icon: homeSearching
              ? const ListenLoading.inline(size: 16)
              : const Icon(
                  Icons.travel_explore_outlined,
                  size: ListenIconSize.control,
                ),
          label: Text(l.text('dictionaryFindMore')),
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
              const SizedBox(height: ListenSpacing.gap12),
              OutlinedButton.icon(
                onPressed: () => _openExternal(externalUrl),
                icon: const Icon(
                  Icons.open_in_new,
                  size: ListenIconSize.control,
                ),
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

  /// A lens row wraps; it never scrolls sideways.
  ///
  /// In the two-pane form this column is a fixed 340pt, and a horizontal list
  /// put the assessment filters half off the column edge with nothing to say
  /// more existed — a filter you cannot see is one you cannot tell is off,
  /// which is the opposite of an honest instrument (P4). Wrapping costs one
  /// extra line at the narrowest column and keeps every option on screen.
  Widget _filterRow({required List<Widget> children}) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: ListenSpacing.gap12,
      vertical: ListenSpacing.gap4,
    ),
    child: Wrap(
      spacing: ListenSpacing.gap8,
      runSpacing: ListenSpacing.gap4,
      children: children,
    ),
  );

  Widget _assessmentChip(String label, String? value, {Color? color}) =>
      ChoiceChip(
        avatar: color == null
            ? null
            : CircleAvatar(backgroundColor: color, radius: 5),
        label: Text(label),
        visualDensity: VisualDensity.compact,
        selected: assessment == value,
        onSelected: (_) {
          setState(() => assessment = value);
          unawaited(_load());
        },
      );
}
