import '../../services/api_service.dart';
import '../../models/types.dart';

abstract interface class ExternalVocabularyRepository {
  Future<ExternalVocabularyImportSummary> importEntries(
    List<Map<String, dynamic>> entries, {
    required String language,
    required String defaultStatus,
    required bool overwriteExisting,
  });
}

final class LocalExternalVocabularyRepository
    implements ExternalVocabularyRepository {
  const LocalExternalVocabularyRepository(this._api);

  final LocalApi _api;

  @override
  Future<ExternalVocabularyImportSummary> importEntries(
    List<Map<String, dynamic>> entries, {
    required String language,
    required String defaultStatus,
    required bool overwriteExisting,
  }) => _api.importExternalVocabulary(
    entries,
    language: language,
    defaultStatus: defaultStatus,
    overwriteExisting: overwriteExisting,
  );
}
