import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/acquisition_ledger.dart';

/// Remembering what was downloaded, rather than guessing it from a filename.
///
/// The real incident: recognising already-acquired media relied on yt-dlp's
/// `[id]` filename convention, so it worked on the YouTube path alone. A
/// podcast enclosure is saved under the publisher's filename (`p0p1qc9j.mp3`)
/// and the feed's guid is `urn:bbc:podcast:p0p1qc9j`; matching one against the
/// other by substring is a guess. Restarting the app therefore offered a
/// download that had already happened, and taking it wrote `episode (2).mp3`.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ledger-'));
  tearDown(() => root.deleteSync(recursive: true));

  AcquisitionLedger ledger() => AcquisitionLedger(directory: root);

  test('a record survives into a new instance', () async {
    final first = ledger();
    await first.load();
    await first.record(
      'urn:bbc:podcast:p0p1qc9j',
      mediaId: 'm-1',
      path: '/a.mp3',
    );

    final second = ledger();
    await second.load();

    expect(second['urn:bbc:podcast:p0p1qc9j']?.mediaId, 'm-1');
    expect(second['urn:bbc:podcast:p0p1qc9j']?.path, '/a.mp3');
  });

  test('an entry nothing was acquired for reads as null', () async {
    final subject = ledger();
    await subject.load();

    expect(subject['never-downloaded'], isNull);
  });

  test('forgetting removes the record from disk', () async {
    final first = ledger();
    await first.load();
    await first.record('e-1', mediaId: 'm-1', path: '/a.mp3');
    await first.forget('e-1');

    final second = ledger();
    await second.load();

    expect(second['e-1'], isNull);
  });

  test('re-recording the same acquisition is idempotent', () async {
    final subject = ledger();
    await subject.load();
    await subject.record('e-1', mediaId: 'm-1', path: '/a.mp3');
    await subject.record('e-1', mediaId: 'm-1', path: '/a.mp3');

    final decoded =
        jsonDecode(File('${root.path}/acquisitions-v1.json').readAsStringSync())
            as Map<String, dynamic>;

    expect((decoded['acquisitions'] as Map).keys, ['e-1']);
  });

  test('re-recording with a new path replaces the old one', () async {
    // Re-downloading after deleting the file is a real sequence, and the
    // ledger must point at what exists now, not at the first thing ever saved.
    final subject = ledger();
    await subject.load();
    await subject.record('e-1', mediaId: 'm-1', path: '/a.mp3');
    await subject.record('e-1', mediaId: 'm-2', path: '/b.mp3');

    expect(subject['e-1']?.mediaId, 'm-2');
    expect(subject['e-1']?.path, '/b.mp3');
  });

  test(
    'a corrupt file reads as empty rather than failing the session',
    () async {
      // The worst case of an unreadable ledger is offering a download that was
      // already done. Refusing to open the catalog over it would be worse.
      File('${root.path}/acquisitions-v1.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"acquisitions": [not json');

      final subject = ledger();
      await subject.load();

      expect(subject['e-1'], isNull);
      expect(subject.isLoaded, isTrue);
    },
  );

  test('malformed rows are skipped without discarding good ones', () async {
    File('${root.path}/acquisitions-v1.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'acquisitions': {
            'good': {'media_id': 'm-1', 'path': '/a.mp3'},
            'no-path': {'media_id': 'm-2'},
            'empty-id': {'media_id': '', 'path': '/b.mp3'},
            'wrong-shape': 'not an object',
          },
        }),
      );

    final subject = ledger();
    await subject.load();

    expect(subject['good']?.mediaId, 'm-1');
    expect(subject['no-path'], isNull);
    expect(subject['empty-id'], isNull);
    expect(subject['wrong-shape'], isNull);
  });

  test('an absent file is an empty ledger, not an error', () async {
    final subject = ledger();

    await subject.load();

    expect(subject.isLoaded, isTrue);
    expect(subject['e-1'], isNull);
  });
}
