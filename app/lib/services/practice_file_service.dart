import 'dart:io';

import 'external_tools.dart';

abstract interface class PracticeFileService {
  String basename(String path);
  Future<bool> deleteIfExists(String path);
  Future<String> extractReferenceWav(
    String mediaPath, {
    required int startMs,
    required int endMs,
    required String ffmpegPath,
    required String ffprobePath,
    required String ytDlpPath,
  });
}

final class LocalPracticeFileService implements PracticeFileService {
  const LocalPracticeFileService();

  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;

  @override
  Future<bool> deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<String> extractReferenceWav(
    String mediaPath, {
    required int startMs,
    required int endMs,
    required String ffmpegPath,
    required String ffprobePath,
    required String ytDlpPath,
  }) => ExternalTools(
    ffmpegPath: ffmpegPath,
    ffprobePath: ffprobePath,
    ytDlpPath: ytDlpPath,
  ).extractPcm16AudioSegment(mediaPath, startMs: startMs, endMs: endMs);
}
