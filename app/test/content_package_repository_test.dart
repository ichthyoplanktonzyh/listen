import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/data/repositories/content_package_repository.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/media_import_file_service.dart';

void main() {
  final repository = LocalContentPackageRepository(
    () => null,
    const LocalMediaImportFileService(),
    LocalListenGenProcessService(),
  );

  test('carries a non-retryable generator failure through to ApiFailure', () {
    final failure = repository.failureDetail(
      const ListenGenProcessFailure(
        'generator_release_lock_invalid',
        retryable: false,
      ),
    );

    expect(failure.code, 'generator_release_lock_invalid');
    expect(failure.retryable, isFalse);
  });

  test('carries a retryable generator failure through to ApiFailure', () {
    final failure = repository.failureDetail(
      const ListenGenProcessFailure('provider_timeout'),
    );

    expect(failure.code, 'provider_timeout');
    expect(failure.retryable, isTrue);
  });
}
