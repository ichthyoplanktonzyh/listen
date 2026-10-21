import 'package:llplayer_next/services/anki_package_file_service.dart';

final class FakeAnkiPackageFileService implements AnkiPackageFileService {
  const FakeAnkiPackageFileService();

  @override
  Future<String?> pickPackageToImport() async => null;

  @override
  Future<String> mediaDirectoryFor(String packagePath) async =>
      '$packagePath-media';

  @override
  Future<String?> pickExportDestination() async => null;
}
