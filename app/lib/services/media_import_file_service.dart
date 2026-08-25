import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

class TimelineFileDocument {
  const TimelineFileDocument({required this.path, required this.document});
  final String path;
  final Map<String, dynamic> document;
}

abstract interface class MediaImportFileService {
  Future<String?> pickMedia();
  Future<String?> pickSubtitle();
  Future<String?> pickLearningPackage();
  Future<TimelineFileDocument?> pickTimeline();
  String basename(String path);
  Future<String?> pickDownloadDirectory({required String confirmButtonText});
}

class LocalMediaImportFileService implements MediaImportFileService {
  const LocalMediaImportFileService();
  @override
  Future<String?> pickMedia() async {
    const group = XTypeGroup(
      label: 'media',
      extensions: ['mp4', 'mkv', 'mov', 'webm', 'm4a', 'mp3', 'wav', 'flac'],
    );
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }

  @override
  Future<String?> pickSubtitle() async {
    const group = XTypeGroup(label: 'subtitles', extensions: ['srt', 'vtt']);
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }

  @override
  Future<String?> pickLearningPackage() async {
    const group = XTypeGroup(
      label: 'learningPackage',
      extensions: ['listenpkg', 'zip'],
    );
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }

  @override
  Future<TimelineFileDocument?> pickTimeline() async {
    const group = XTypeGroup(label: 'LLTimeline', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    final decoded = jsonDecode(await File(file.path).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('LLTimeline JSON must be an object');
    }
    return TimelineFileDocument(path: file.path, document: decoded);
  }

  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;

  @override
  Future<String?> pickDownloadDirectory({required String confirmButtonText}) =>
      getDirectoryPath(confirmButtonText: confirmButtonText);
}
