import '../../models/api_failure.dart';
import '../../models/practice.dart';
import '../../models/production_corpus.dart';
import '../../models/projection_review.dart';
import '../../models/semantic_embedding.dart';
import '../../models/semantic_task.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';
import 'occurrence_media_repository.dart';

/// The vocabulary workbench's data boundary.
///
/// [LocalApi] carries the whole backend surface; the listening dictionary uses
/// a small, fixed slice of it. This repository names exactly that slice, so the
/// view model depends on the endpoints this screen actually needs rather than
/// on the transport as a whole, and a test can substitute the boundary without
/// standing up every unrelated endpoint.
///
/// Deliberately a thin pass-through today: every method forwards to [LocalApi]
/// and returns the project's existing typed client models. It is *not* a
/// domain-model layer, and it holds no cache and no race guard — sequencing
/// still belongs to the view model that owns the state those responses land in.
/// This is the seam where caching and per-query generation guards will move
/// later; nothing here anticipates them yet.
///
/// Failures propagate exactly as [LocalApi] raises them. The screen's honest
/// per-source degradation (a gap source that is down, a dictionary provider
/// that is not answering) is a *policy* decision about what the user should
/// see, and lives with the state, not here.
class LexicalRepository implements OccurrenceMediaRepository {
  LexicalRepository(this._api);

  final LocalApi _api;

  /// Translates transport failures at the data boundary so presentation code
  /// never depends on the concrete API client or its exception types.
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  // ── The book ──

  Future<List<LexicalEntryDetails>> listVocabulary({
    required String language,
    String? capability,
    String? assessment,
    String search = '',
  }) => _api.listVocabulary(
    language: language,
    capability: capability,
    assessment: assessment,
    search: search,
  );

  Future<LexicalEntryDetails> entryDetails(String entryId) =>
      _api.lexicalEntryDetails(entryId);

  Future<LexicalEntryDetails> upsertEntry(Map<String, dynamic> value) =>
      _api.upsertLexicalEntry(value);

  Future<LexicalNormalization> correctLemma(
    String original,
    String corrected, {
    required String language,
  }) => _api.correctLemma(original, corrected, language: language);

  // ── The open entry's decorations ──

  Future<List<UpgradeSuggestion>> upgradeSuggestions({
    required String lexicalEntryId,
  }) => _api.upgradeSuggestions(lexicalEntryId: lexicalEntryId);

  Future<DictionaryLookupBundle> lookupDictionary(
    String lemma, {
    required String language,
  }) => _api.lookupDictionary(lemma, language: language);

  Future<List<ProductionCorpusHitView>> searchProductionCorpus({
    required String language,
    required String query,
  }) => _api.searchProductionCorpus(language: language, query: query);

  Future<SemanticAttemptView> productionAttempt(String attemptId) =>
      _api.semanticAttempt(attemptId);

  Future<List<LearningObservationView>> observationHistory(
    String lexicalEntryId, {
    String? capability,
    int? offset,
  }) => _api.learningObservationHistory(
    lexicalEntryId,
    capability: capability,
    offset: offset,
  );

  // ── The gap pane's two sources ──

  Future<List<CrossModalReviewCandidateView>> crossModalReviewGaps({
    required String language,
  }) => _api.crossModalReviewGaps(language: language);

  Future<ProductionGapSemanticReviewView> semanticProductionGapReview({
    required String language,
  }) => _api.semanticProductionGapReview(language: language);

  Future<ProductionGapReviewView> productionGapReview({
    required String language,
  }) => _api.productionGapReview(language: language);

  // ── Semantic search ──

  Future<SemanticEmbeddingCapabilityView> semanticEmbeddingCapability() =>
      _api.semanticEmbeddingCapability();

  Future<SemanticSearchResultView> semanticSearch({
    required String query,
    required String language,
  }) => _api.semanticSearch(query: query, language: language);

  // ── Capability projection review ──

  Future<List<ProjectionProposalView>> projectionProposals(
    String lexicalEntryId,
  ) => _api.auditProjectionEntry(lexicalEntryId);

  Future<ProjectionProposalView> decideProjectionProposal({
    required String proposalId,
    required String decision,
  }) =>
      _api.decideProjectionProposal(proposalId: proposalId, decision: decision);

  // ── Media behind a slice ──

  @override
  Future<MediaItem> readMedia(String mediaId) => _api.readMedia(mediaId);

  @override
  Future<String> fingerprintFile(String path) => _api.fingerprintFile(path);

  @override
  /// A lexical occurrence relink is temporary until the learner explicitly
  /// keeps that material.
  Future<void> registerMedia(String path) async =>
      _api.registerMedia(path, retain: false);

  // ── The local corpus ──

  Future<List<CorpusOccurrence>> searchCorpus({
    required String language,
    required String query,
  }) => _api.searchCorpus(language: language, query: query);

  Future<int> reindexCorpus() => _api.reindexCorpus();

  // ── Entry writes ──

  Future<LexicalCapabilityProfile> setCapabilityOverride(
    String entryId,
    String capability, {
    String? conclusion,
  }) => _api.setCapabilityOverride(entryId, capability, conclusion: conclusion);

  Future<LexicalEntryDetails> updateLearningContent(
    String entryId, {
    String? userDefinition,
    String? personalNote,
  }) => _api.updateLexicalLearningContent(
    entryId,
    userDefinition: userDefinition,
    personalNote: personalNote,
  );

  Future<LexicalEntryDetails> createSenseFolder(
    String entryId, {
    required String label,
    String? definition,
    String? gloss,
    String? externalRef,
  }) => _api.createLexicalSenseFolder(
    entryId,
    label: label,
    definition: definition,
    gloss: gloss,
    externalRef: externalRef,
  );

  Future<LexicalEntryDetails> updateSenseFolder(
    String entryId,
    String senseId, {
    required String label,
    String? definition,
    String? gloss,
    String? externalRef,
  }) => _api.updateLexicalSenseFolder(
    entryId,
    senseId,
    label: label,
    definition: definition,
    gloss: gloss,
    externalRef: externalRef,
  );

  Future<LexicalEntryDetails> deleteSenseFolder(
    String entryId,
    String senseId,
  ) => _api.deleteLexicalSenseFolder(entryId, senseId);

  Future<LexicalEntryDetails> assignSenseFolderOccurrence(
    String entryId,
    String senseId,
    String occurrenceId,
  ) => _api.assignLexicalSenseFolderOccurrence(entryId, senseId, occurrenceId);

  Future<LexicalEntryDetails> unassignSenseFolderOccurrence(
    String entryId,
    String senseId,
    String occurrenceId,
  ) =>
      _api.unassignLexicalSenseFolderOccurrence(entryId, senseId, occurrenceId);

  Future<UpgradeSuggestion> confirmUpgradeSuggestion(String suggestionId) =>
      _api.confirmUpgradeSuggestion(suggestionId);

  Future<UpgradeSuggestion> rejectUpgradeSuggestion(String suggestionId) =>
      _api.rejectUpgradeSuggestion(suggestionId);

  // ── Practice exits ──

  Future<ReviewItem> createReviewItem(CreateReviewItem input) =>
      _api.createReviewItem(input);

  Future<void> createObservation({
    required String lexicalEntryId,
    required String sentenceId,
    required String originalForm,
    required bool heard,
    Map<String, dynamic>? source,
  }) => _api.createLexicalObservation(
    lexicalEntryId: lexicalEntryId,
    sentenceId: sentenceId,
    originalForm: originalForm,
    heard: heard,
    source: source,
  );
}
