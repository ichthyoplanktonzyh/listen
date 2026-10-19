import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/data/repositories/personal_expression_repository.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/services/api_service.dart';

LocalApi _failingApi() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'token',
  transport: (method, path, body) async => (
    statusCode: 503,
    body:
        '{"code":"temporarily_unavailable",'
        '"correlation_id":"request-42","retryable":true}',
  ),
);

void main() {
  test('transport failure description preserves an already typed failure', () {
    const failure = ApiFailure(
      raw: 'hidden transport detail',
      correlationId: 'request-42',
    );

    expect(describeApiFailure(failure), same(failure));
  });

  test('personal-expression repository exposes a typed failure', () async {
    final repository = LocalPersonalExpressionRepository(_failingApi());

    await expectLater(
      repository.listPatterns(language: 'en'),
      throwsA(
        isA<ApiFailure>()
            .having(
              (failure) => failure.code,
              'code',
              'temporarily_unavailable',
            )
            .having(
              (failure) => failure.correlationId,
              'correlation id',
              'request-42',
            )
            .having((failure) => failure.isRetryable, 'retryable', isTrue),
      ),
    );
  });

  test('provider repository exposes a typed failure', () async {
    final repository = LocalLlmProviderRepository(_failingApi());

    await expectLater(
      repository.list(),
      throwsA(
        isA<ApiFailure>()
            .having(
              (failure) => failure.code,
              'code',
              'temporarily_unavailable',
            )
            .having(
              (failure) => failure.correlationId,
              'correlation id',
              'request-42',
            ),
      ),
    );
  });
}
