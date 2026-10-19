import 'dart:io';

import 'package:file_selector/file_selector.dart';

sealed class DiagnosticLogExportOutcome {
  const DiagnosticLogExportOutcome();
}

final class DiagnosticLogUnavailable extends DiagnosticLogExportOutcome {
  const DiagnosticLogUnavailable();
}

final class DiagnosticLogExportCancelled extends DiagnosticLogExportOutcome {
  const DiagnosticLogExportCancelled();
}

final class DiagnosticLogExported extends DiagnosticLogExportOutcome {
  const DiagnosticLogExported(this.path);

  final String path;
}

final class DiagnosticLogExportFailed extends DiagnosticLogExportOutcome {
  const DiagnosticLogExportFailed(this.error);

  final Object error;
}

abstract interface class DiagnosticLogExportService {
  Future<DiagnosticLogExportOutcome> export();
}

abstract interface class DiagnosticLogSource {
  String? get path;
}

final class CallbackDiagnosticLogSource implements DiagnosticLogSource {
  const CallbackDiagnosticLogSource(this._path);

  final String? Function() _path;

  @override
  String? get path => _path();
}

abstract interface class DiagnosticLogFileService {
  Future<bool> exists(String path);
  Future<void> copy(String sourcePath, String destinationPath);
}

final class LocalDiagnosticLogFileService implements DiagnosticLogFileService {
  const LocalDiagnosticLogFileService();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<void> copy(String sourcePath, String destinationPath) async {
    await File(sourcePath).copy(destinationPath);
  }
}

abstract interface class DiagnosticLogDestinationService {
  Future<String?> choosePath();
}

final class LocalDiagnosticLogDestinationService
    implements DiagnosticLogDestinationService {
  const LocalDiagnosticLogDestinationService();

  @override
  Future<String?> choosePath() async =>
      (await getSaveLocation(suggestedName: 'listen-core.log'))?.path;
}

final class LocalDiagnosticLogExportService
    implements DiagnosticLogExportService {
  const LocalDiagnosticLogExportService(
    this.source, {
    this.fileService = const LocalDiagnosticLogFileService(),
    this.destinationService = const LocalDiagnosticLogDestinationService(),
  });

  final DiagnosticLogSource source;
  final DiagnosticLogFileService fileService;
  final DiagnosticLogDestinationService destinationService;

  @override
  Future<DiagnosticLogExportOutcome> export() async {
    try {
      final sourcePath = source.path;
      if (sourcePath == null || !await fileService.exists(sourcePath)) {
        return const DiagnosticLogUnavailable();
      }
      final destinationPath = await destinationService.choosePath();
      if (destinationPath == null) {
        return const DiagnosticLogExportCancelled();
      }
      await fileService.copy(sourcePath, destinationPath);
      return DiagnosticLogExported(destinationPath);
    } catch (error) {
      return DiagnosticLogExportFailed(error);
    }
  }
}
