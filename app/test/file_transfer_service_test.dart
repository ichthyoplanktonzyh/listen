import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/file_transfer_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file-transfer-service-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('personal-expression export writes indented valid JSON', () async {
    final path = '${directory.path}/expression.json';

    await const LocalPersonalExpressionExportFileService().writeToPath(
      path: path,
      document: {
        'version': 1,
        'patterns': [
          {'name': 'Ended up'},
        ],
      },
    );

    final encoded = await File(path).readAsString();
    expect(encoded, contains('\n  "version": 1'));
    expect(jsonDecode(encoded), {
      'version': 1,
      'patterns': [
        {'name': 'Ended up'},
      ],
    });
  });

  test('external word-list service reads and parses TXT and CSV', () async {
    final txtPath = '${directory.path}/words.txt';
    final csvPath = '${directory.path}/words.CSV';
    await File(txtPath).writeAsString('hello\n\nworld\n');
    await File(
      csvPath,
    ).writeAsString('word,status\nhello,known_recognized\nworld,invalid\n');
    const service = LocalExternalWordListFileService();

    final txt = await service.read(txtPath) as ExternalWordListReadSuccess;
    final csv = await service.read(csvPath) as ExternalWordListReadSuccess;

    expect(txt.entries, [
      {'word': 'hello', 'status': null},
      {'word': 'world', 'status': null},
    ]);
    expect(csv.entries, [
      {'word': 'hello', 'status': 'known_recognized'},
      {'word': 'world', 'status': null},
    ]);
    expect(() => txt.entries.add(<String, dynamic>{}), throwsUnsupportedError);
    expect(() => txt.entries.first['word'] = 'changed', throwsUnsupportedError);
  });

  test('external word-list service returns parser format failures', () async {
    final path = '${directory.path}/words.csv';
    await File(path).writeAsString('term,status\nhello,known_recognized\n');

    final result = await const LocalExternalWordListFileService().read(path);

    expect(result, isA<ExternalWordListFormatFailure>());
    expect(
      (result as ExternalWordListFormatFailure).message,
      'CSV must contain a word column',
    );
  });
}
