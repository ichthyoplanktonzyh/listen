/// Aggregate saved-vocabulary total for the home readiness surface. [capped]
/// signals that at least one status page hit the backend limit.
class SavedVocabularyCount {
  const SavedVocabularyCount({required this.total, required this.capped});

  final int total;
  final bool capped;
}
