import '../../models/api_failure.dart';
import '../../models/content_package.dart';
import '../../services/api_service.dart';
import '../../services/listen_gen_process_service.dart';
import '../../services/media_import_file_service.dart';

abstract interface class ContentPackageRepository {
  bool get coreAvailable;
  bool get generatorConfigured;
  ApiFailure failureDetail(Object error);
  Future<String?> pickPackage();
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  });
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  );
}

final class LocalContentPackageRepository implements ContentPackageRepository {
  const LocalContentPackageRepository(
    this._getApi,
    this._files,
    this._generator,
  );

  final LocalApi? Function() _getApi;
  final MediaImportFileService _files;
  final ListenGenProcessService _generator;

  @override
  bool get coreAvailable => _getApi() != null;
  @override
  bool get generatorConfigured => _generator.isConfigured;
  @override
  ApiFailure failureDetail(Object error) => error is ListenGenProcessFailure
      ? ApiFailure(raw: '', code: error.code, retryable: true)
      : describeApiFailure(error);
  @override
  Future<String?> pickPackage() => _files.pickContentPackage();
  @override
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  }) => (_getApi() ?? (throw StateError('Local core is unavailable')))
      .importContentPackage(mediaId, packagePath);
  @override
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  ) => _generator.start(request);
}
