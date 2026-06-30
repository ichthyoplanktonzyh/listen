import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

/// Exercises the A1 transport seam: `LocalApi.withTransport` lets the client be
/// driven without a live sidecar, so request building, JSON decoding, and error
/// mapping can be unit tested. (Full method/controller coverage builds on this.)
void main() {
  group('LocalApi transport seam', () {
    test('routes a GET through the transport and decodes the JSON body', () async {
      String? seenMethod;
      String? seenPath;
      String? seenBody;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenMethod = method;
          seenPath = path;
          seenBody = body;
          return (statusCode: 200, body: '{"id":"m1","title":"Clip"}');
        },
      );

      final media = await api.readMedia('m1');

      expect(media['id'], 'm1');
      expect(media['title'], 'Clip');
      expect(seenMethod, 'GET');
      expect(seenPath, '/v1/media/m1');
      expect(seenBody, isNull, reason: 'a GET carries no request body');
    });

    test('maps a non-2xx response to an HttpException', () async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async =>
            (statusCode: 404, body: 'not found'),
      );

      expect(() => api.readMedia('missing'), throwsA(isA<HttpException>()));
    });

    test('encodes the request body and forwards it to the transport', () async {
      String? seenMethod;
      String? seenPath;
      String? seenBody;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenMethod = method;
          seenPath = path;
          seenBody = body;
          return (statusCode: 200, body: '');
        },
      );

      await api.saveProgress('m1', const Duration(seconds: 5));

      expect(seenMethod, 'PUT');
      expect(seenPath, '/v1/media/m1/progress');
      expect(jsonDecode(seenBody!), {'position_ms': 5000});
    });
  });
}
