import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Picks the paths for `.apkg` interop. The backend does the reading and
/// writing — it needs a package path and, on import, a directory to unpack the
/// package's media into — so this service only chooses locations.
abstract interface class AnkiPackageFileService {
  /// The `.apkg` to import, or null when the learner cancelled.
  Future<String?> pickPackageToImport();

  /// A writable directory for the package's media files, derived from the
  /// package path so import needs one prompt rather than two.
  Future<String> mediaDirectoryFor(String packagePath);

  /// Where to write the exported `.apkg`, or null when cancelled.
  Future<String?> pickExportDestination();
}

class LocalAnkiPackageFileService implements AnkiPackageFileService {
  const LocalAnkiPackageFileService();

  static const _group = XTypeGroup(label: 'Anki package', extensions: ['apkg']);

  @override
  Future<String?> pickPackageToImport() async =>
      (await openFile(acceptedTypeGroups: [_group]))?.path;

  @override
  Future<String> mediaDirectoryFor(String packagePath) async {
    final separator = Platform.pathSeparator;
    final name = packagePath.split(separator).last;
    final stem = name.endsWith('.apkg')
        ? name.substring(0, name.length - '.apkg'.length)
        : name;
    final directory = Directory(
      '${File(packagePath).parent.path}$separator$stem-media',
    );
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> pickExportDestination() async => (await getSaveLocation(
    suggestedName: 'listen-export.apkg',
    acceptedTypeGroups: const [_group],
  ))?.path;
}
