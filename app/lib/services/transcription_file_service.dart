import 'dart:io';

import 'package:file_selector/file_selector.dart';

abstract interface class TranscriptionFileService {
  Future<String?> pickCustomModel();
  Future<String?> saveSrt({
    required String suggestedName,
    required String content,
  });
}

final class LocalTranscriptionFileService implements TranscriptionFileService {
  const LocalTranscriptionFileService();

  @override
  Future<String?> pickCustomModel() async => (await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Whisper model', extensions: ['bin']),
    ],
  ))?.path;

  @override
  Future<String?> saveSrt({
    required String suggestedName,
    required String content,
  }) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return null;
    await File(location.path).writeAsString(content);
    return location.path;
  }
}
