import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/lexical_repository.dart';
import '../models/api_failure.dart';
import '../models/practice.dart';
import '../models/production_corpus.dart';
import '../models/projection_review.dart';
import '../models/semantic_embedding.dart';
import '../models/semantic_task.dart';
import '../models/types.dart';
import '../services/external_link_opener.dart';
import '../state/store.dart';
import 'occurrence_media_resolver.dart';

/// Everything the listening dictionary renders from, as one immutable
/// snapshot. Field order and meaning follow
/// `design-notes/vocabulary-behavior-contract.md` §1 so the two can be read
/// side by side.
///
/// `==` is deliberately **not** overridden: [Store.update] skips a
/// notification when the new state equals the old one, and identity equality
/// is what makes every `copyWith` publish — the same contract `setState` had.
class VocabularyState {
  VocabularyState({
    this.capability = 'listening',
    this.assessment,
    this.search = '',
    this.loading = true,
    List<LexicalEntryDetails> words = const [],
    this.details,
    this.gapLoading = true,
    List<CrossModalReviewCandidateView>? gapCandidates,
    this.gapCandidatesError,
    this.gapProduction,
    this.gapProductionError,
    this.gapHighlightCandidates = false,
    this.narrowGapOpen = false,
    this.semanticCanSearch = false,
    this.semanticMode = false,
    List<SemanticSearchHitView> semanticHits = const [],
    this.semanticSearching = false,
    List<UpgradeSuggestion> suggestions = const [],
    this.suggestionsLoading = false,
    this.pronunciationAudioUrl,
    this.pronunciationLoading = false,
    List<ProductionCorpusHitView>? productionHits,
    this.productionLoadFailed = false,
    List<CorpusOccurrence>? homeResults,
    this.homeSearching = false,
  }) : _words = List.unmodifiable(words),
       _gapCandidates = gapCandidates == null
           ? null
           : List.unmodifiable(gapCandidates),
       _semanticHits = List.unmodifiable(semanticHits),
       _suggestions = List.unmodifiable(suggestions),
       _productionHits = productionHits == null
           ? null
           : List.unmodifiable(productionHits),
       _homeResults = homeResults == null
           ? null
           : List.unmodifiable(homeResults);

  /// The four-channel capability axis is the primary lens. [capability] picks
  /// the channel; [assessment] `null` means "all" (no capability filter).
  final String capability;
  final String? assessment;

  /// The search box's text.
  final String search;

  /// The book query is in flight. There is no matching failure field: a failed
  /// list has no state at all today (contract D1).
  final bool loading;
  final List<LexicalEntryDetails> _words;
  List<LexicalEntryDetails> get words => List.unmodifiable(_words);

  /// Non-null while the in-page entry detail is open (master → detail).
  final LexicalEntryDetails? details;

  /// The gap instrument room — the right pane's default page. Two independent
  /// best-effort sources are juxtaposed here; each degrades to a notice
  /// instead of failing the workbench, and one switch covers both.
  final bool gapLoading;
  final List<CrossModalReviewCandidateView>? _gapCandidates;
  List<CrossModalReviewCandidateView>? get gapCandidates =>
      _gapCandidates == null ? null : List.unmodifiable(_gapCandidates);
  final ApiFailure? gapCandidatesError;
  final ProductionGapReviewView? gapProduction;
  final ApiFailure? gapProductionError;

  /// Set when the coach's cross-modal hand-off lands here, so the candidates
  /// section is emphasised (the number the coach clicked).
  final bool gapHighlightCandidates;

  /// Narrow (single-column, "B") form only: whether the gap pane is showing
  /// full-width instead of the word list.
  final bool narrowGapOpen;

  /// Whether semantic search can run, so the search box can offer a toggle.
  final bool semanticCanSearch;
  final bool semanticMode;
  final List<SemanticSearchHitView> _semanticHits;
  List<SemanticSearchHitView> get semanticHits =>
      List.unmodifiable(_semanticHits);
  final bool semanticSearching;

  /// The open entry's three decorations, each on its own clock (V6).
  final List<UpgradeSuggestion> _suggestions;
  List<UpgradeSuggestion> get suggestions => List.unmodifiable(_suggestions);
  final bool suggestionsLoading;
  final String? pronunciationAudioUrl;
  final bool pronunciationLoading;

  /// `null` = still loading; empty + [productionLoadFailed] = unavailable;
  /// empty alone = nothing produced yet. The three stay distinct.
  final List<ProductionCorpusHitView>? _productionHits;
  List<ProductionCorpusHitView>? get productionHits =>
      _productionHits == null ? null : List.unmodifiable(_productionHits);
  final bool productionLoadFailed;

  /// Corpus fallback when the vocabulary list has no match for [search].
  final List<CorpusOccurrence>? _homeResults;
  List<CorpusOccurrence>? get homeResults =>
      _homeResults == null ? null : List.unmodifiable(_homeResults);
  final bool homeSearching;

  VocabularyState copyWith({
    String? capability,
    String? assessment,
    bool clearAssessment = false,
    String? search,
    bool? loading,
    List<LexicalEntryDetails>? words,
    LexicalEntryDetails? details,
    bool clearDetails = false,
    bool? gapLoading,
    List<CrossModalReviewCandidateView>? gapCandidates,
    bool clearGapCandidates = false,
    ApiFailure? gapCandidatesError,
    bool clearGapCandidatesError = false,
    ProductionGapReviewView? gapProduction,
    bool clearGapProduction = false,
    ApiFailure? gapProductionError,
    bool clearGapProductionError = false,
    bool? gapHighlightCandidates,
    bool? narrowGapOpen,
    bool? semanticCanSearch,
    bool? semanticMode,
    List<SemanticSearchHitView>? semanticHits,
    bool? semanticSearching,
    List<UpgradeSuggestion>? suggestions,
    bool? suggestionsLoading,
    String? pronunciationAudioUrl,
    bool clearPronunciationAudioUrl = false,
    bool? pronunciationLoading,
    List<ProductionCorpusHitView>? productionHits,
    bool clearProductionHits = false,
    bool? productionLoadFailed,
    List<CorpusOccurrence>? homeResults,
    bool clearHomeResults = false,
    bool? homeSearching,
  }) => VocabularyState(
    capability: capability ?? this.capability,
    assessment: clearAssessment ? null : assessment ?? this.assessment,
    search: search ?? this.search,
    loading: loading ?? this.loading,
    words: words ?? this.words,
    details: clearDetails ? null : details ?? this.details,
    gapLoading: gapLoading ?? this.gapLoading,
    gapCandidates: clearGapCandidates
        ? null
        : gapCandidates ?? this.gapCandidates,
    gapCandidatesError: clearGapCandidatesError
        ? null
        : gapCandidatesError ?? this.gapCandidatesError,
    gapProduction: clearGapProduction
        ? null
        : gapProduction ?? this.gapProduction,
    gapProductionError: clearGapProductionError
        ? null
        : gapProductionError ?? this.gapProductionError,
    gapHighlightCandidates:
        gapHighlightCandidates ?? this.gapHighlightCandidates,
    narrowGapOpen: narrowGapOpen ?? this.narrowGapOpen,
    semanticCanSearch: semanticCanSearch ?? this.semanticCanSearch,
    semanticMode: semanticMode ?? this.semanticMode,
    semanticHits: semanticHits ?? this.semanticHits,
    semanticSearching: semanticSearching ?? this.semanticSearching,
    suggestions: suggestions ?? this.suggestions,
    suggestionsLoading: suggestionsLoading ?? this.suggestionsLoading,
    pronunciationAudioUrl: clearPronunciationAudioUrl
        ? null
        : pronunciationAudioUrl ?? this.pronunciationAudioUrl,
    pronunciationLoading: pronunciationLoading ?? this.pronunciationLoading,
    productionHits: clearProductionHits
        ? null
        : productionHits ?? this.productionHits,
    productionLoadFailed: productionLoadFailed ?? this.productionLoadFailed,
    homeResults: clearHomeResults ? null : homeResults ?? this.homeResults,
    homeSearching: homeSearching ?? this.homeSearching,
  );
}

/// The outcome of a corpus reindex: a track count, or the failure to name.
typedef ReindexOutcome = ({int? count, ApiFailure? failure});

/// The outcome of asking for an entry's capability proposals. `proposals` is
/// non-null exactly when `failure` is null — a read that failed has no empty
/// list to show, which is what keeps "nothing to propose" a separate sentence.
typedef ProposalsOutcome = ({
  List<ProjectionProposalView>? proposals,
  ApiFailure? failure,
});

/// The outcome of marking one clip heard / not heard. `attempted` is false
/// when the occurrence carries no sentence anchor: no request is sent and
/// nothing is said, which is not the same as a request that failed.
typedef MarkOutcome = ({bool attempted, ApiFailure? failure});

/// The listening dictionary's state and orchestration.
///
/// The screen used to be View, view model and data layer at once: 22 mutable
/// fields, 36 direct `LocalApi` calls and 21 `setState` calls inside a
/// `StatefulWidget`. This owns the middle layer of that — the state, the
/// request sequencing and the degradation policy — and talks to the backend
/// only through [LexicalRepository].
///
/// It deliberately holds **no** localized text and no `BuildContext`. Reads
/// that end in a dialog, and writes whose only visible result is a SnackBar,
/// return their outcome to the view, which owns the sentence and where it is
/// shown. State-changing work publishes through the [Store] instead.
///
/// Same shape as [ReviewController] and the other controllers here: a private
/// [Store] of an immutable state, re-broadcast as a [ChangeNotifier] so a
/// whole-subtree `ListenableBuilder` behaves exactly like the `setState` it
/// replaces.
class VocabularyViewModel extends ChangeNotifier {
  VocabularyViewModel({
    required LexicalRepository repository,
    required this.language,
    ExternalLinkOpener linkOpener = const ExternalLinkOpener(),
    OccurrenceMediaResolver? mediaResolver,
  }) : _repository = repository,
       _store = Store(VocabularyState()) {
    _linkOpener = linkOpener;
    _mediaResolver =
        mediaResolver ?? OccurrenceMediaResolver(repository: repository);
    _store.addListener(notifyListeners);
  }

  /// The interface language's learning target. The book query, the gap pane
  /// and the dictionary lookup all read it; an entry's own `language` is used
  /// where the entry can differ from it (contract D10 keeps that asymmetry).
  final String language;

  final LexicalRepository _repository;
  final Store<VocabularyState> _store;

  /// Collaborators with defaults, assigned in the constructor body so the
  /// injected value stays optional without a public field.
  late final ExternalLinkOpener _linkOpener;
  late final OccurrenceMediaResolver _mediaResolver;

  bool _disposed = false;

  /// Monotonic id of the newest detail request. A decoration that resolves
  /// after the user moved to another entry is dropped instead of painting the
  /// previous word's data onto the current one.
  ///
  /// Its question is "which entry is newest", **not** "is the detail still
  /// open": closing a detail deliberately does not advance it (contract D12).
  int _detailRequest = 0;

  Store<VocabularyState> get store => _store;
  VocabularyState get state => _store.state;

  /// Publishes a new state unless this model is gone. Stands in for the
  /// `if (mounted)` that guarded every `setState` before.
  void _set(VocabularyState Function(VocabularyState) transform) {
    if (_disposed) return;
    _store.update(transform);
  }

  @override
  void dispose() {
    _disposed = true;
    _store.dispose();
    super.dispose();
  }

  // ── The book ──

  /// Runs the book query for the current lens and search text.
  ///
  /// No `try`: a failed list has no state today, so the error escapes as an
  /// unhandled async error and `loading` stays true forever (contract D1).
  /// There is no sequence guard either, so a slower older query still wins
  /// (contract D4). Both are pinned by the characterization tests.
  Future<void> load() async {
    _set((state) => state.copyWith(loading: true));
    final values = await _repository.listVocabulary(
      language: language,
      capability: state.assessment == null ? null : state.capability,
      assessment: state.assessment,
      search: state.search,
    );
    _set((state) => state.copyWith(words: values, loading: false));
  }

  void selectCapability(String value) {
    _set((state) => state.copyWith(capability: value));
    // The channel always re-lenses the rings (presentation); it only
    // re-queries once an assessment is picked, which is when the backend
    // filters by capability at all.
    if (state.assessment != null) unawaited(load());
  }

  void selectAssessment(String? value) {
    _set(
      (state) =>
          state.copyWith(assessment: value, clearAssessment: value == null),
    );
    unawaited(load());
  }

  void searchChanged(String value) {
    _set((state) => state.copyWith(search: value, clearHomeResults: true));
    if (!state.semanticMode) unawaited(load());
  }

  void submitSearch() {
    if (state.semanticMode) unawaited(runSemanticSearch());
  }

  // ── The open entry ──

  /// Opens an entry's detail. The entry itself is awaited (it *is* the page);
  /// its three decorations then load in parallel, each publishing on its own
  /// (V6: serial waiting is what made the identity card hostage to the
  /// slowest provider).
  ///
  /// The read is uncaught: a failed open has no visible consequence at all
  /// (contract D5).
  Future<void> openEntry(String entryId) async {
    final request = ++_detailRequest;
    _set(
      (state) => state.copyWith(
        suggestions: const [],
        suggestionsLoading: true,
        clearPronunciationAudioUrl: true,
        pronunciationLoading: true,
        clearProductionHits: true,
        productionLoadFailed: false,
      ),
    );
    final value = await _repository.entryDetails(entryId);
    if (!_detailStillCurrent(request)) return;
    // The identity card can paint now — nothing below is awaited here.
    _set((state) => state.copyWith(details: value));
    unawaited(_loadEntrySuggestions(entryId, request));
    unawaited(_loadEntryPronunciation(value.entry, request));
    unawaited(_loadEntryProduction(value.entry, request));
  }

  /// Whether a decoration that just resolved still belongs to the open entry.
  bool _detailStillCurrent(int request) =>
      !_disposed && request == _detailRequest;

  Future<void> _loadEntrySuggestions(String entryId, int request) async {
    List<UpgradeSuggestion> pending;
    try {
      pending = await _repository.upgradeSuggestions(lexicalEntryId: entryId);
    } catch (_) {
      // A missing suggestion source degrades to "no suggestions", never to a
      // broken detail page.
      pending = const [];
    }
    if (!_detailStillCurrent(request)) return;
    _set(
      (state) =>
          state.copyWith(suggestions: pending, suggestionsLoading: false),
    );
  }

  Future<void> _loadEntryPronunciation(LexicalEntry entry, int request) async {
    String? audio;
    try {
      // Contract D10: the *interface* learning language, not `entry.language`.
      final bundle = await _repository.lookupDictionary(
        entry.normalizedForm,
        language: language,
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
    _set(
      (state) => state.copyWith(
        pronunciationAudioUrl: audio,
        clearPronunciationAudioUrl: audio == null,
        pronunciationLoading: false,
      ),
    );
  }

  Future<void> _loadEntryProduction(LexicalEntry entry, int request) async {
    List<ProductionCorpusHitView> output;
    var outputLoadFailed = false;
    try {
      output = await _repository.searchProductionCorpus(
        language: entry.language,
        query: entry.normalizedForm,
      );
    } catch (_) {
      // "Unavailable" and "you have not produced this yet" stay distinct.
      output = const [];
      outputLoadFailed = true;
    }
    if (!_detailStillCurrent(request)) return;
    _set(
      (state) => state.copyWith(
        productionHits: output,
        productionLoadFailed: outputLoadFailed,
      ),
    );
  }

  /// Closes the in-page detail. Deliberately does **not** advance
  /// [_detailRequest]: in-flight decorations for the entry that was open still
  /// land (contract D12), and the guard keeps meaning "which entry is newest".
  void closeDetails() => _set((state) => state.copyWith(clearDetails: true));

  /// Lands on the gap pane (the default right pane): closes any open detail
  /// and, in the narrow form, brings the gap surface forward.
  void landOnGapPane({bool highlightCandidates = false}) {
    _set(
      (state) => state.copyWith(
        clearDetails: true,
        narrowGapOpen: true,
        gapHighlightCandidates: highlightCandidates
            ? true
            : state.gapHighlightCandidates,
      ),
    );
  }

  /// Narrow form only: leave the gap surface for the word list.
  void closeNarrowGap() =>
      _set((state) => state.copyWith(narrowGapOpen: false));

  // ── The gap pane ──

  /// Loads the two gap-pane sources. Each is best-effort and degrades to an
  /// inline notice — the workbench never fails because a decoration source is
  /// down. Rendering only: neither query is changed, they are juxtaposed.
  Future<void> loadGapPanel() async {
    List<CrossModalReviewCandidateView>? candidates;
    ApiFailure? candidatesError;
    try {
      candidates = await _repository.crossModalReviewGaps(language: language);
    } catch (error) {
      candidatesError = _repository.failureDetail(error);
    }
    ProductionGapReviewView? production;
    ApiFailure? productionError;
    try {
      final enriched = await _repository.semanticProductionGapReview(
        language: language,
      );
      production = enriched.review;
    } catch (_) {
      // The semantic enrichment is optional; fall back to the plain review.
      try {
        production = await _repository.productionGapReview(language: language);
      } catch (error) {
        productionError = _repository.failureDetail(error);
      }
    }
    // One switch for both sources: the pane either waits or arrives whole.
    _set(
      (state) => state.copyWith(
        gapCandidates: candidates,
        clearGapCandidates: candidates == null,
        gapCandidatesError: candidatesError,
        clearGapCandidatesError: candidatesError == null,
        gapProduction: production,
        clearGapProduction: production == null,
        gapProductionError: productionError,
        clearGapProductionError: productionError == null,
        gapLoading: false,
      ),
    );
  }

  // ── Semantic search ──

  Future<void> probeSemanticSearch() async {
    try {
      final capability = await _repository.semanticEmbeddingCapability();
      _set((state) => state.copyWith(semanticCanSearch: capability.canSearch));
    } catch (_) {
      // Optional capability; the exact-search box stays fully usable.
    }
  }

  void setSemanticMode(bool on) {
    _set((state) => state.copyWith(semanticMode: on, semanticHits: const []));
    if (on) {
      if (state.search.trim().isNotEmpty) unawaited(runSemanticSearch());
    } else {
      unawaited(load());
    }
  }

  /// Runs the semantic query. A failure degrades to an empty hit list, which
  /// the list column then reports as "no matches" (contract D2).
  Future<void> runSemanticSearch() async {
    if (state.search.trim().isEmpty) {
      _set((state) => state.copyWith(semanticHits: const []));
      return;
    }
    _set((state) => state.copyWith(semanticSearching: true));
    List<SemanticSearchHitView> hits;
    try {
      final result = await _repository.semanticSearch(
        query: state.search,
        language: language,
      );
      hits = result.hits;
    } catch (_) {
      hits = const [];
    }
    _set(
      (state) => state.copyWith(semanticHits: hits, semanticSearching: false),
    );
  }

  // ── Capability projection review ──

  Future<ProposalsOutcome> projectionProposals(String lexicalEntryId) async {
    try {
      return (
        proposals: await _repository.projectionProposals(lexicalEntryId),
        failure: null,
      );
    } catch (error) {
      return (proposals: null, failure: _repository.failureDetail(error));
    }
  }

  /// Uncaught by design: a rejected decision has no failure path today
  /// (contract D7).
  Future<void> decideProjectionProposal({
    required String proposalId,
    required String decision,
  }) async {
    await _repository.decideProjectionProposal(
      proposalId: proposalId,
      decision: decision,
    );
  }

  // ── Slice playback sources ──

  Future<OccurrenceMediaResolution> resolveOccurrenceMedia(
    Map<String, dynamic> occurrence,
  ) => _mediaResolver.resolve(
    occurrence,
    currentMediaFingerprint: null,
    currentMediaPath: null,
    filterMediaExtensions: true,
  );

  /// The occurrence map a corpus hit plays from, or `null` when its media
  /// cannot be read (the caller turns that into "this clip needs its source").
  Future<Map<String, dynamic>?> corpusPlaybackOccurrence(
    CorpusOccurrence occurrence,
  ) async {
    final mediaId = occurrence.mediaId;
    if (mediaId == null) return null;
    MediaItem media;
    try {
      media = await _repository.readMedia(mediaId);
    } catch (_) {
      return null;
    }
    return {
      'media_id': mediaId,
      'media_fingerprint_snapshot': media.fingerprint,
      'media_title_snapshot': media.title,
      'sentence_text_snapshot': occurrence.sourceSnapshot,
      'original_form': occurrence.displayText,
      'start_ms_snapshot': occurrence.startMs,
      'end_ms_snapshot': occurrence.endMs,
    };
  }

  /// Uncaught by design: the entry view's own corpus panel owns this
  /// failure's presentation.
  Future<List<CorpusOccurrence>> searchLibraryFor(LexicalEntry entry) =>
      _repository.searchCorpus(
        language: entry.language,
        query: entry.kind == 'phrase'
            ? entry.displayForm
            : entry.normalizedForm,
      );

  /// Saves a corpus hit as a durable slice on [entry] and re-reads the entry
  /// so the new clip joins its list.
  Future<ApiFailure?> collectCorpus(
    LexicalEntry entry,
    CorpusOccurrence occurrence,
  ) async {
    try {
      final media = await _repository.readMedia(occurrence.mediaId!);
      await _repository.upsertEntry({
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
      await openEntry(entry.id);
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  /// The empty-book fallback's library search. A failure degrades to an empty
  /// result, which reads as "your library holds nothing" (contract D3).
  Future<void> searchHomeCorpus() async {
    _set((state) => state.copyWith(homeSearching: true));
    List<CorpusOccurrence> results;
    try {
      results = await _repository.searchCorpus(
        language: language,
        query: state.search,
      );
    } catch (_) {
      results = const [];
    }
    _set((state) => state.copyWith(homeSearching: false, homeResults: results));
  }

  Future<ReindexOutcome> reindexCorpus() async {
    try {
      return (count: await _repository.reindexCorpus(), failure: null);
    } catch (error) {
      return (count: null, failure: _repository.failureDetail(error));
    }
  }

  // ── Entry writes ──
  //
  // Each returns the failure to name, or `null` when it worked. The sentence
  // itself belongs to the view.

  Future<ApiFailure?> setCapabilityOverride(
    LexicalEntry entry,
    String capability,
    String? conclusion,
  ) async {
    try {
      await _repository.setCapabilityOverride(
        entry.id,
        capability,
        conclusion: conclusion,
      );
      await openEntry(entry.id);
      // Capability filters in the book view read the same channels.
      unawaited(load());
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  Future<ApiFailure?> saveContent(
    LexicalEntry entry,
    String? definition,
    String? note,
  ) async {
    try {
      await _repository.updateLearningContent(
        entry.id,
        userDefinition: definition,
        personalNote: note,
      );
      await openEntry(entry.id);
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  Future<ApiFailure?> createSenseFolder(
    LexicalEntry entry,
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  ) => _saveSenseFolderChange(
    () => _repository.createSenseFolder(
      entry.id,
      label: label,
      definition: definition,
      gloss: gloss,
      externalRef: externalRef,
    ),
  );

  Future<ApiFailure?> updateSenseFolder(
    LexicalEntry entry,
    String senseId,
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  ) => _saveSenseFolderChange(
    () => _repository.updateSenseFolder(
      entry.id,
      senseId,
      label: label,
      definition: definition,
      gloss: gloss,
      externalRef: externalRef,
    ),
  );

  Future<ApiFailure?> deleteSenseFolder(LexicalEntry entry, String senseId) =>
      _saveSenseFolderChange(
        () => _repository.deleteSenseFolder(entry.id, senseId),
      );

  Future<ApiFailure?> assignSenseFolder(
    LexicalEntry entry,
    String senseId,
    LexicalOccurrence occurrence,
  ) => _saveSenseFolderChange(
    () => _repository.assignSenseFolderOccurrence(
      entry.id,
      senseId,
      occurrence.id,
    ),
  );

  Future<ApiFailure?> unassignSenseFolder(
    LexicalEntry entry,
    String senseId,
    LexicalOccurrence occurrence,
  ) => _saveSenseFolderChange(
    () => _repository.unassignSenseFolderOccurrence(
      entry.id,
      senseId,
      occurrence.id,
    ),
  );

  /// Sense-folder writes answer with the whole entry, so they publish it
  /// directly instead of re-reading it.
  Future<ApiFailure?> _saveSenseFolderChange(
    Future<LexicalEntryDetails> Function() action,
  ) async {
    try {
      final value = await action();
      _set((state) => state.copyWith(details: value));
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  Future<ApiFailure?> confirmSuggestion(
    LexicalEntry entry,
    UpgradeSuggestion suggestion,
  ) async {
    try {
      await _repository.confirmUpgradeSuggestion(suggestion.id);
      await openEntry(entry.id);
      unawaited(load());
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  /// Rejecting deliberately does **not** re-run the book query, while
  /// confirming does (contract D9).
  Future<ApiFailure?> rejectSuggestion(
    LexicalEntry entry,
    UpgradeSuggestion suggestion,
  ) async {
    try {
      await _repository.rejectUpgradeSuggestion(suggestion.id);
      await openEntry(entry.id);
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  // ── Reads the view turns into a dialog ──

  /// Uncaught by design: opening an output attempt has no failure path today
  /// (contract D8).
  Future<SemanticAttemptView> productionAttempt(String attemptId) =>
      _repository.productionAttempt(attemptId);

  Future<List<LearningObservationView>> observationHistory(
    String lexicalEntryId, {
    String? capability,
    int offset = 0,
  }) => _repository.observationHistory(
    lexicalEntryId,
    capability: capability,
    offset: offset,
  );

  // ── Practice exits ──

  Future<ApiFailure?> reviewClip(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
  ) async {
    try {
      await _repository.createReviewItem(
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
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  Future<ApiFailure?> addToReview(LexicalEntry entry) async {
    try {
      await _repository.createReviewItem(
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
      return null;
    } catch (error) {
      return _repository.failureDetail(error);
    }
  }

  /// Marks one clip heard / not heard. An occurrence with no sentence anchor
  /// is refused before any request goes out, and says nothing.
  Future<MarkOutcome> markOccurrence(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
    bool heard,
  ) async {
    final sentenceId = occurrence.sentenceId;
    if (sentenceId == null) return (attempted: false, failure: null);
    try {
      await _repository.createObservation(
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
      return (attempted: true, failure: null);
    } catch (error) {
      return (attempted: true, failure: _repository.failureDetail(error));
    }
  }

  // ── External references (copyright guardrail: links only) ──

  /// YouGlish covers the current learning target (English); other languages
  /// simply hide the link instead of guessing a locale path.
  String? externalLookupUrlFor(String query, String language) =>
      language == 'en' && query.trim().isNotEmpty
      ? 'https://youglish.com/pronounce/${Uri.encodeComponent(query.trim())}/english'
      : null;

  void openExternal(String url) => unawaited(_linkOpener.open(url));
}
