import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

void main() {
  test('parses the pinned Core import receipt including provenance', () async {
    final body = await File(
      'test/fixtures/content-package/core-import-success.json',
    ).readAsString();
    final receipt = parseContentPackageImportReceipt(
      jsonDecode(body) as Map<String, dynamic>,
    );

    expect(receipt.manifestSha256, startsWith('sha256:'));
    expect(receipt.track.id, 'track-local-1');
    expect(receipt.resources, hasLength(2));
    expect(receipt.resources.first.reviewStatus, 'machine_checked');
    expect(receipt.resources.first.provenance?.tool.label, 'listen-gen/0.1.0');
    expect(receipt.resources.last.provenance, isNull);
  });

  test('sends package path to the media-scoped Core route', () async {
    late String method;
    late String path;
    late Map<String, dynamic> request;
    final fixture = await File(
      'test/fixtures/content-package/core-import-success.json',
    ).readAsString();
    final api = LocalApi.withTransport(
      baseUrl: 'http://127.0.0.1:1',
      token: 'test-token',
      transport: (nextMethod, nextPath, body) async {
        method = nextMethod;
        path = nextPath;
        request = jsonDecode(body!) as Map<String, dynamic>;
        return (statusCode: 200, body: fixture);
      },
    );

    final receipt = await api.importContentPackage(
      'media/id',
      '/tmp/lesson.listenpkg',
    );

    expect(method, 'POST');
    expect(path, '/v1/media/media%2Fid/content-packages/import');
    expect(request, {'package_path': '/tmp/lesson.listenpkg'});
    expect(receipt.track.id, 'track-local-1');
  });

  test('parses strict Gen v1 machine events fixture', () async {
    final lines = await File(
      'test/fixtures/content-package/gen-machine-events.ndjson',
    ).readAsLines();
    final events = lines
        .map(
          (line) => parseListenGenMachineEvent(
            jsonDecode(line) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);

    expect(events.map((event) => event.sequence), [0, 1, 2, 3]);
    expect(events.first.kind, ListenGenEventKind.protocol);
    expect(events.last.kind, ListenGenEventKind.completed);
    expect(events.last.packageSha256, startsWith('sha256:fedcba'));
  });

  test('rejects unknown Gen protocol versions and tool identities', () {
    Map<String, dynamic> event({required int version, required String tool}) =>
        {
          'schema': 'listen_gen.machine-event.v1',
          'protocol_version': version,
          'sequence': 0,
          'tool': {'id': tool, 'version': '0.1.0'},
          'event': 'protocol',
        };

    expect(
      () => parseListenGenMachineEvent(event(version: 2, tool: 'listen-gen')),
      throwsFormatException,
    );
    expect(
      () => parseListenGenMachineEvent(event(version: 1, tool: 'other')),
      throwsFormatException,
    );
  });
}
