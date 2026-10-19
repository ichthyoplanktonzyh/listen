import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Platform file operations used while recovering occurrence source media.
abstract interface class OccurrenceMediaFileService {
  Future<bool> exists(String path);

  Future<String?> pickSourceMedia({required bool filterMediaExtensions});
}

/// Stateless production adapter around the file system and native picker.
final class LocalOccurrenceMediaFileService
    implements OccurrenceMediaFileService {
  const LocalOccurrenceMediaFileService();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<String?> pickSourceMedia({required bool filterMediaExtensions}) async {
    final group = filterMediaExtensions
        ? const XTypeGroup(
            label: 'source media',
            extensions: [
              'mp4',
              'mkv',
              'mov',
              'webm',
              'm4a',
              'mp3',
              'wav',
              'flac',
            ],
          )
        : const XTypeGroup(label: 'source media');
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }
}
