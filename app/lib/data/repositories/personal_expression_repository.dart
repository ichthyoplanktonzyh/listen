import '../../models/api_failure.dart';
import '../../models/personal_expression.dart';
import '../../services/api_service.dart';

Future<T> _request<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(describeApiFailure(error), stackTrace);
  }
}

/// The complete backend boundary used by the personal-expression feature.
///
/// Keeping this interface narrower than [LocalApi] makes the UI and its view
/// models independent of transport details and straightforward to test.
abstract interface class PersonalExpressionRepository {
  /// Every failed operation throws an [ApiFailure], never a transport error.
  Future<List<SentencePatternAssetView>> listPatterns({
    required String language,
    String query = '',
  });

  Future<List<PersonalExpressionAttemptView>> listAttempts(String patternId);

  Future<List<SentencePatternVersionView>> listVersions(String patternId);

  Future<PersonalExpressionExportBundleView> export({required String language});

  Future<SentencePatternAssetView> create({
    required String language,
    required PersonalExpressionSourceView source,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
  });

  Future<SentencePatternAssetView> revise({
    required String id,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
    String? systemConstructionId,
  });

  Future<void> delete(String patternId);

  Future<PersonalExpressionAttemptView> recordAttempt({
    required String patternId,
    required String patternVersionId,
    required String channel,
    required String assistance,
    required String responseText,
    required String selfAssessment,
  });
}

/// Production implementation backed by the typed local API client.
class LocalPersonalExpressionRepository
    implements PersonalExpressionRepository {
  LocalPersonalExpressionRepository(this._api);

  final LocalApi _api;

  @override
  Future<List<SentencePatternAssetView>> listPatterns({
    required String language,
    String query = '',
  }) => _request(() => _api.sentencePatterns(language: language, query: query));

  @override
  Future<List<PersonalExpressionAttemptView>> listAttempts(String patternId) =>
      _request(() => _api.personalExpressionAttempts(patternId));

  @override
  Future<List<SentencePatternVersionView>> listVersions(String patternId) =>
      _request(() => _api.sentencePatternVersions(patternId));

  @override
  Future<PersonalExpressionExportBundleView> export({
    required String language,
  }) => _request(() => _api.exportPersonalExpression(language: language));

  @override
  Future<SentencePatternAssetView> create({
    required String language,
    required PersonalExpressionSourceView source,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
  }) => _request(
    () => _api.createSentencePattern(
      language: language,
      source: source,
      name: name,
      patternText: patternText,
      slots: slots,
      note: note,
    ),
  );

  @override
  Future<SentencePatternAssetView> revise({
    required String id,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
    String? systemConstructionId,
  }) => _request(
    () => _api.reviseSentencePattern(
      id: id,
      name: name,
      patternText: patternText,
      slots: slots,
      note: note,
      systemConstructionId: systemConstructionId,
    ),
  );

  @override
  Future<void> delete(String patternId) =>
      _request(() => _api.deleteSentencePattern(patternId));

  @override
  Future<PersonalExpressionAttemptView> recordAttempt({
    required String patternId,
    required String patternVersionId,
    required String channel,
    required String assistance,
    required String responseText,
    required String selfAssessment,
  }) => _request(
    () => _api.recordPersonalExpressionAttempt(
      patternId: patternId,
      patternVersionId: patternVersionId,
      channel: channel,
      assistance: assistance,
      responseText: responseText,
      selfAssessment: selfAssessment,
    ),
  );
}
