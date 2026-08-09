import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';

/// The shebang the verifier requires as the artifact's first bytes.
final _validArtifact = utf8.encode('#!/usr/bin/env python3\nPKbody');
const _manifestName = 'listen-gen-0.2.0.release.json';
const _artifactName = 'listen-gen-0.2.0.pyz';
const _genCommit = 'c3564c357ecd46c3a52326f1362b78874379a56f';
const _otherCommit = 'b980a20666f746685db1fd06bfa425d762d7a678';
const _contractSha =
    'sha256:3a0c67c2e4498dbbe5ad5556bac41eff01e50c06c7d020bd5af1fdcbe46c5dc5';

Map<String, dynamic> _runtimeIdentityTemplate() => {
  'schema': 'listen_gen.runtime-identity.v1',
  'version': 1,
  'runtime': {'family': 'python', 'requires': '>=3.11'},
  'toolchain': {
    'schema': 'listen_gen.toolchain-identity.v1',
    'version': 1,
    'tools': [
      {'id': 'asr-wrapper', 'roles': ['asr']},
      {'id': 'ffmpeg', 'roles': ['media', 'asr', 'alignment', 'acoustics', 'phone']},
      {'id': 'ffprobe', 'roles': ['media', 'asr', 'alignment', 'acoustics', 'phone']},
      {'id': 'whisper-cli', 'roles': ['asr', 'alignment']},
      {'id': 'whisper-model', 'roles': ['asr', 'alignment']},
    ],
  },
};

Map<String, dynamic> _manifestTemplate() => {
  'schema': 'listen_gen.release-bundle.v1',
  'source': {
    'commit': _genCommit,
    'repository': 'https://github.com/ichthyoplanktonzyh/listen-gen',
  },
  'tool': {'id': 'listen-gen', 'version': '0.2.0'},
  'machine_protocol': {'schema': 'listen_gen.machine-event.v1', 'version': 1},
  'content_package_contract': {
    'authority': {
      'repository': 'ichthyoplanktonzyh/listen-core',
      'path': 'contracts/content-package/v1',
    },
    'canonical_sha256': _contractSha,
    'manifest_schema_id':
        'https://listen.dev/contracts/content-package/v1/manifest.schema.json',
    'package_schema': 'listen.resource-package.v1',
    'resource_schema_id':
        'https://listen.dev/contracts/content-package/v1/resource.schema.json',
    'schema_version': 1,
  },
  'runtime': {
    'provider_requirements': {
      'command': ['ffprobe', 'ffmpeg', 'asr-wrapper'],
      'fixture': <String>[],
      'whisper-cpp': ['ffprobe', 'ffmpeg', 'whisper-cli', 'whisper-model'],
    },
    'python_requires': '>=3.11',
  },
  'runtime_identity': _runtimeIdentityTemplate(),
  'artifact': {
    'entrypoint': '__main__.py',
    'filename': _artifactName,
    'format': 'python-zipapp',
    'sha256': 'sha256:${'0' * 64}',
    'size_bytes': 0,
  },
};

Map<String, dynamic> _lockTemplate() => {
  'manifest_version': 1,
  'repository': 'ichthyoplanktonzyh/listen-gen',
  'source_git_sha': _genCommit,
  'release_manifest': {
    'schema': 'listen_gen.release-bundle.v1',
    'filename': _manifestName,
    'sha256': 'sha256:${'0' * 64}',
  },
  'tool': {'id': 'listen-gen', 'version': '0.2.0'},
  'machine_protocol': {'schema': 'listen_gen.machine-event.v1', 'version': 1},
  'content_package_contract': {
    'authority': {
      'repository': 'ichthyoplanktonzyh/listen-core',
      'path': 'contracts/content-package/v1',
    },
    'manifest_schema_id':
        'https://listen.dev/contracts/content-package/v1/manifest.schema.json',
    'resource_schema_id':
        'https://listen.dev/contracts/content-package/v1/resource.schema.json',
    'package_schema': 'listen.resource-package.v1',
    'schema_version': 1,
    'canonical_sha256': _contractSha,
  },
  'runtime': {'python_requires': '>=3.11'},
  'runtime_identity': _runtimeIdentityTemplate(),
  'artifact': {
    'filename': _artifactName,
    'format': 'python-zipapp',
    'entrypoint': '__main__.py',
    'size_bytes': 0,
    'sha256': 'sha256:${'0' * 64}',
  },
};

String _sha(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

/// One assembled release on disk plus a matching service. Every knob defaults
/// to the valid configuration; each test flips exactly one.
final class _Built {
  _Built(this.service, this.manifestPath, this.artifactPath);
  final LocalListenGenReleaseService service;
  final String manifestPath;
  final String artifactPath;
}

Future<_Built> _build(
  Directory dir, {
  List<int>? artifactBytes,
  List<int>?
  artifactFileSuffix, // appended to the file after hashing → size drift
  int?
  flipArtifactByteAt, // change one byte of the file after hashing → sha drift
  bool omitArtifact = false,
  bool manifestSymlink = false,
  bool artifactSymlink = false,
  bool artifactInParentDir = false,
  void Function(Map<String, dynamic> manifest)? mutateManifest,
  void Function(Map<String, dynamic> lock)? mutateLock,
  bool syncManifestShaToLock = true,
  bool syncArtifactToLock = true,
}) async {
  final artifact = artifactBytes ?? _validArtifact;
  final artifactSha = _sha(artifact);
  final artifactSize = artifact.length;

  final manifest = _manifestTemplate();
  (manifest['artifact'] as Map)['sha256'] = artifactSha;
  (manifest['artifact'] as Map)['size_bytes'] = artifactSize;
  mutateManifest?.call(manifest);
  final manifestBytes = utf8.encode(jsonEncode(manifest));

  final lock = _lockTemplate();
  if (syncManifestShaToLock) {
    (lock['release_manifest'] as Map)['sha256'] = _sha(manifestBytes);
  }
  if (syncArtifactToLock) {
    (lock['artifact'] as Map)['sha256'] = artifactSha;
    (lock['artifact'] as Map)['size_bytes'] = artifactSize;
  }
  mutateLock?.call(lock);
  final lockBytes = utf8.encode(jsonEncode(lock));

  // Manifest on disk (real file, or a symlink standing in for one).
  final manifestPath = '${dir.path}/$_manifestName';
  if (manifestSymlink) {
    final target = File('${dir.path}/real-$_manifestName')
      ..writeAsBytesSync(manifestBytes);
    Link(manifestPath).createSync(target.path);
  } else {
    File(manifestPath).writeAsBytesSync(manifestBytes);
  }

  // Artifact beside the manifest (unless a knob relocates or drops it).
  final artifactDir = artifactInParentDir ? dir.parent : dir;
  final artifactPath = '${artifactDir.path}/$_artifactName';
  if (!omitArtifact) {
    if (artifactSymlink) {
      final target = File('${artifactDir.path}/real-$_artifactName')
        ..writeAsBytesSync(artifact);
      Link(artifactPath).createSync(target.path);
    } else {
      var fileBytes = [...artifact];
      if (flipArtifactByteAt != null) {
        fileBytes[flipArtifactByteAt] = fileBytes[flipArtifactByteAt] ^ 0xff;
      }
      if (artifactFileSuffix != null) {
        fileBytes = [...fileBytes, ...artifactFileSuffix];
      }
      File(artifactPath).writeAsBytesSync(fileBytes);
    }
  }

  final service = LocalListenGenReleaseService(
    manifestPath: manifestPath,
    loadLockBytes: () async => lockBytes,
  );
  return _Built(service, manifestPath, artifactPath);
}

Future<Directory> _tempDir() async {
  final parent = await Directory.systemTemp.createTemp('listen-gen-release-');
  final dir = Directory('${parent.path}/bundle')..createSync();
  addTearDown(() => parent.delete(recursive: true));
  return dir;
}

Matcher _failsWith(String code) => throwsA(
  isA<ListenGenProcessFailure>()
      .having((failure) => failure.code, 'code', code)
      .having((failure) => failure.retryable, 'retryable', isFalse),
);

void main() {
  test('verifies a matching lock, manifest, and artifact', () async {
    final built = await _build(await _tempDir());
    final verified = await built.service.verify();

    expect(verified.toolVersion, '0.2.0');
    expect(verified.sourceCommit, _genCommit);
    expect(verified.artifactPath, built.artifactPath);
    expect(verified.artifactSha256, _sha(_validArtifact));
    expect(built.service.isConfigured, isTrue);
  });

  test('rejects a lock missing a required field', () async {
    final built = await _build(
      await _tempDir(),
      mutateLock: (lock) => lock.remove('runtime'),
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_lock_invalid'),
    );
  });

  test('rejects a lock carrying an unknown field', () async {
    final built = await _build(
      await _tempDir(),
      mutateLock: (lock) => lock['unexpected'] = true,
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_lock_invalid'),
    );
  });

  test('rejects a manifest whose file hash does not match the lock', () async {
    final built = await _build(await _tempDir(), syncManifestShaToLock: false);
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_manifest_invalid'),
    );
  });

  test('rejects a manifest source commit that differs from the lock', () async {
    final built = await _build(
      await _tempDir(),
      mutateManifest: (manifest) =>
          (manifest['source'] as Map)['commit'] = _otherCommit,
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_manifest_invalid'),
    );
  });

  test('rejects a manifest tool version that differs from the lock', () async {
    final built = await _build(
      await _tempDir(),
      mutateManifest: (manifest) =>
          (manifest['tool'] as Map)['version'] = '9.9.9',
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_manifest_invalid'),
    );
  });

  test('rejects a manifest machine protocol that differs', () async {
    final built = await _build(
      await _tempDir(),
      mutateManifest: (manifest) =>
          (manifest['machine_protocol'] as Map)['version'] = 2,
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_manifest_invalid'),
    );
  });

  test('rejects a manifest content-package contract mismatch', () async {
    final built = await _build(
      await _tempDir(),
      mutateManifest: (manifest) =>
          (manifest['content_package_contract'] as Map)['canonical_sha256'] =
              'sha256:${'a' * 64}',
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_manifest_invalid'),
    );
  });

  test('rejects a lock manifest filename with path traversal', () async {
    final built = await _build(
      await _tempDir(),
      mutateLock: (lock) =>
          (lock['release_manifest'] as Map)['filename'] = '../evil.json',
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_lock_invalid'),
    );
  });

  test('rejects a lock artifact filename with path traversal', () async {
    final built = await _build(
      await _tempDir(),
      mutateLock: (lock) =>
          (lock['artifact'] as Map)['filename'] = '../evil.pyz',
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_lock_invalid'),
    );
  });

  test('rejects a manifest that is a symlink', () async {
    final built = await _build(await _tempDir(), manifestSymlink: true);
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_manifest_invalid'),
    );
  });

  test('rejects an artifact that is a symlink', () async {
    final built = await _build(await _tempDir(), artifactSymlink: true);
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_artifact_invalid'),
    );
  });

  test('reports a missing artifact', () async {
    final built = await _build(await _tempDir(), omitArtifact: true);
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_artifact_missing'),
    );
  });

  test('rejects an artifact whose size differs from the lock', () async {
    final built = await _build(
      await _tempDir(),
      artifactFileSuffix: utf8.encode('extra'),
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_artifact_invalid'),
    );
  });

  test('rejects an artifact whose hash differs from the lock', () async {
    final built = await _build(await _tempDir(), flipArtifactByteAt: 30);
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_artifact_invalid'),
    );
  });

  test('rejects an artifact without the python shebang', () async {
    final built = await _build(
      await _tempDir(),
      artifactBytes: utf8.encode('#!/bin/sh\necho nope\n'),
    );
    await expectLater(
      built.service.verify(),
      _failsWith('generator_release_artifact_invalid'),
    );
  });

  test(
    'reports a missing artifact when it is not beside the manifest',
    () async {
      // The manifest lives in a subdirectory; the artifact only exists one level
      // up, so nothing sits beside the manifest where the verifier looks.
      final built = await _build(await _tempDir(), artifactInParentDir: true);
      await expectLater(
        built.service.verify(),
        _failsWith('generator_release_artifact_missing'),
      );
    },
  );

  test(
    're-hashes every call and detects an artifact swapped after verify',
    () async {
      final built = await _build(await _tempDir());
      await built.service.verify(); // first pass succeeds

      File(
        built.artifactPath,
      ).writeAsBytesSync(utf8.encode('#!/usr/bin/env python3\nPKdifferent'));

      await expectLater(
        built.service.verify(),
        _failsWith('generator_release_artifact_invalid'),
      );
    },
  );

  test('failure codes never leak a local filesystem path', () async {
    final built = await _build(await _tempDir(), omitArtifact: true);
    try {
      await built.service.verify();
      fail('expected a release failure');
    } on ListenGenProcessFailure catch (failure) {
      expect(failure.code, 'generator_release_artifact_missing');
      expect(failure.code, isNot(contains('/')));
      expect(failure.toString(), isNot(contains(built.manifestPath)));
    }
  });

  test('isConfigured is false when no manifest path is set', () async {
    final service = LocalListenGenReleaseService(
      manifestPath: null,
      loadLockBytes: () async => utf8.encode(jsonEncode(_lockTemplate())),
    );
    expect(service.isConfigured, isFalse);
    await expectLater(
      service.verify(),
      _failsWith('generator_release_manifest_missing'),
    );
  });

  test('rejects an incompatible committed lock identity', () async {
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'repository': (lock) => lock['repository'] = 'someone/else',
      'release schema': (lock) =>
          (lock['release_manifest'] as Map)['schema'] = 'other.schema.v1',
      'tool id': (lock) => (lock['tool'] as Map)['id'] = 'not-listen-gen',
      'machine schema': (lock) =>
          (lock['machine_protocol'] as Map)['schema'] = 'other.event.v1',
      'machine version': (lock) =>
          (lock['machine_protocol'] as Map)['version'] = 2,
      'authority repository': (lock) =>
          ((lock['content_package_contract'] as Map)['authority']
                  as Map)['repository'] =
              'someone/core',
      'authority path': (lock) =>
          ((lock['content_package_contract'] as Map)['authority']
                  as Map)['path'] =
              'contracts/other/v1',
      'package schema': (lock) =>
          (lock['content_package_contract'] as Map)['package_schema'] =
              'other.package.v1',
      'contract schema version': (lock) =>
          (lock['content_package_contract'] as Map)['schema_version'] = 2,
      'python requires': (lock) =>
          (lock['runtime'] as Map)['python_requires'] = '>=3.10',
      'runtime identity schema': (lock) =>
          (lock['runtime_identity'] as Map)['schema'] =
              'listen_gen.runtime-identity.v2',
      'runtime identity version': (lock) =>
          (lock['runtime_identity'] as Map)['version'] = 2,
      'runtime family': (lock) =>
          ((lock['runtime_identity'] as Map)['runtime'] as Map)['family'] =
              'cpython',
      'runtime requires': (lock) =>
          ((lock['runtime_identity'] as Map)['runtime'] as Map)['requires'] =
              '>=3.10',
      'toolchain schema': (lock) =>
          ((lock['runtime_identity'] as Map)['toolchain'] as Map)['schema'] =
              'listen_gen.toolchain-identity.v2',
      'toolchain version': (lock) =>
          ((lock['runtime_identity'] as Map)['toolchain'] as Map)['version'] =
              2,
    };
    for (final entry in mutations.entries) {
      final built = await _build(await _tempDir(), mutateLock: entry.value);
      await expectLater(
        built.service.verify(),
        _failsWith('generator_release_lock_invalid'),
        reason: 'lock identity: ${entry.key}',
      );
    }
  });

  test('rejects a manifest whose runtime identity drifts from the lock', () async {
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'schema': (manifest) =>
          (manifest['runtime_identity'] as Map)['schema'] =
              'listen_gen.runtime-identity.v2',
      'version': (manifest) =>
          (manifest['runtime_identity'] as Map)['version'] = 2,
      'runtime family': (manifest) =>
          ((manifest['runtime_identity'] as Map)['runtime'] as Map)['family'] =
              'cpython',
      'runtime requires': (manifest) =>
          ((manifest['runtime_identity'] as Map)['runtime'] as Map)['requires'] =
              '>=3.10',
      'toolchain schema': (manifest) =>
          ((manifest['runtime_identity'] as Map)['toolchain'] as Map)['schema'] =
              'listen_gen.toolchain-identity.v2',
      'toolchain version': (manifest) =>
          ((manifest['runtime_identity'] as Map)['toolchain'] as Map)['version'] =
              2,
      'toolchain extra tool': (manifest) =>
          ((manifest['runtime_identity'] as Map)['toolchain'] as Map)['tools'] =
              [
                ...(((manifest['runtime_identity'] as Map)['toolchain']
                        as Map)['tools'] as List),
                {'id': 'extra-tool', 'roles': ['phone']},
              ],
      'toolchain dropped tool': (manifest) =>
          (((manifest['runtime_identity'] as Map)['toolchain'] as Map)['tools']
                  as List)
              .removeLast(),
      'toolchain re-roled tool': (manifest) =>
          (((manifest['runtime_identity'] as Map)['toolchain'] as Map)['tools']
                  as List)
              .first['roles'] = ['phone'],
    };
    for (final entry in mutations.entries) {
      final built = await _build(await _tempDir(), mutateManifest: entry.value);
      await expectLater(
        built.service.verify(),
        _failsWith('generator_release_manifest_invalid'),
        reason: 'manifest runtime identity: ${entry.key}',
      );
    }
  });

  test(
    'rejects manifest unknown fields at root, artifact, and runtime',
    () async {
      final mutations = <String, void Function(Map<String, dynamic>)>{
        'root': (manifest) => manifest['surprise'] = true,
        'artifact': (manifest) =>
            (manifest['artifact'] as Map)['surprise'] = true,
        'runtime': (manifest) =>
            (manifest['runtime'] as Map)['surprise'] = true,
      };
      for (final entry in mutations.entries) {
        final built = await _build(
          await _tempDir(),
          mutateManifest: entry.value,
        );
        await expectLater(
          built.service.verify(),
          _failsWith('generator_release_manifest_invalid'),
          reason: 'manifest unknown field: ${entry.key}',
        );
      }
    },
  );
}
