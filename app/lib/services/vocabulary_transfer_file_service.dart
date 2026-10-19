import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

abstract interface class VocabularyTransferFileService {
  Future<bool> exportDocument(Map<String, dynamic> document);
  Future<Map<String, dynamic>?> importDocument();
}

class LocalVocabularyTransferFileService
    implements VocabularyTransferFileService {
  const LocalVocabularyTransferFileService();
  @override
  Future<bool> exportDocument(Map<String, dynamic> document) async {
    final location = await getSaveLocation(
      suggestedName: 'listen-vocabulary-v1.json',
    );
    if (location == null) return false;
    await File(
      location.path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(document));
    return true;
  }

  @override
  Future<Map<String, dynamic>?> importDocument() async {
    const group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    return jsonDecode(await File(file.path).readAsString())
        as Map<String, dynamic>;
  }
}
