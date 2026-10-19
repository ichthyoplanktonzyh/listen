import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

abstract interface class ResourceExportFileService {
  Future<bool> saveText({
    required String suggestedName,
    required String content,
  });
  Future<bool> saveJson({
    required String suggestedName,
    required Map<String, dynamic> document,
  });
}

class LocalResourceExportFileService implements ResourceExportFileService {
  const LocalResourceExportFileService();
  @override
  Future<bool> saveText({
    required String suggestedName,
    required String content,
  }) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return false;
    await File(location.path).writeAsString(content);
    return true;
  }

  @override
  Future<bool> saveJson({
    required String suggestedName,
    required Map<String, dynamic> document,
  }) => saveText(
    suggestedName: suggestedName,
    content: const JsonEncoder.withIndent('  ').convert(document),
  );
}
