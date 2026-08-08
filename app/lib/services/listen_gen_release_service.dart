import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'listen_gen_process_service.dart' show ListenGenProcessFailure;

/// Loads the committed `listen_gen.lock.json` bytes.
///
/// A seam so tests can supply an arbitrary lock without shipping it as an
/// asset; production reads the asset the app was built with.
typedef ListenGenLockBytesLoader = Future<List<int>> Function();

/// The single trusted fact the release verifier hands back: the exact bytes
/// on disk are the pinned bundle, and here is where they live plus which
/// versioned identity they carry.
final class VerifiedListenGenRelease {
  const VerifiedListenGenRelease({
    required this.artifactPath,
    required this.artifactFilename,
    required this.toolVersion,
    required this.sourceCommit,
    required this.artifactSha256,
  });

  final String artifactPath;
  final String artifactFilename;
  final String toolVersion;
  final String sourceCommit;
  final String artifactSha256;
}

/// Decides whether a local `listen-gen` bundle may run at all.
///
/// The app trusts one bundle: the one whose bytes match the committed lock.
/// Nothing here trusts a path, an executable, or a source checkout — only a
/// manifest hash and an artifact hash that pin exact bytes.
abstract interface class ListenGenReleaseService {
  /// Whether a release manifest is even pointed at. False here keeps the whole
  /// generation surface unavailable without pretending anything was verified.
  bool get isConfigured;

  /// Re-reads and re-hashes the manifest and artifact from scratch, every call.
  /// Never returns a cached verdict: the bundle on disk can be swapped between
  /// two generations, and the app must notice.
  Future<VerifiedListenGenRelease> verify();
}

final class LocalListenGenReleaseService implements ListenGenReleaseService {
  LocalListenGenReleaseService({
    String? manifestPath,
    ListenGenLockBytesLoader? loadLockBytes,
  }) : _manifestPath =
           manifestPath ?? Platform.environment[_manifestEnvironmentKey],
       _loadLockBytes = loadLockBytes ?? _loadLockFromBundle;

  static const _manifestEnvironmentKey = 'LISTEN_GEN_RELEASE_MANIFEST';
  static const _lockAssetKey = 'listen_gen.lock.json';

  /// The one repository this app's bundle is allowed to originate from.
  static const _generatorRepository =
      'https://github.com/ichthyoplanktonzyh/listen-gen';

  /// Compatibility identity the committed lock must declare. These are what the
  /// app is built to talk to; a lock that names a different repository, schema,
  /// protocol, or contract authority is not a newer pin but an incompatible
  /// one. Version pins (tool.version, source_git_sha, artifact hash/size) stay
  /// owned by the committed lock and are deliberately not hardcoded here.
  static const _lockRepository = 'ichthyoplanktonzyh/listen-gen';
  static const _releaseBundleSchema = 'listen_gen.release-bundle.v1';
  static const _toolId = 'listen-gen';
  static const _machineSchema = 'listen_gen.machine-event.v1';
  static const _machineVersion = 1;
  static const _authorityRepository = 'ichthyoplanktonzyh/listen-core';
  static const _authorityPath = 'contracts/content-package/v1';
  static const _packageSchema = 'listen.resource-package.v1';
  static const _contractSchemaVersion = 1;
  static const _pythonRequires = '>=3.11';

  /// The shebang the zipapp must begin with. Binding it means a swapped file
  /// that is not a python zipapp fails before it is ever launched.
  static const _artifactShebang = '#!/usr/bin/env python3\n';

  /// The provider requirements the current Gen v1 must at least declare. The
  /// manifest may add providers or arguments; it may not drop any of these.
  static const Map<String, List<String>> _requiredProviderRequirements = {
    'fixture': [],
    'command': ['ffprobe', 'ffmpeg', 'asr-wrapper'],
    'whisper-cpp': ['ffprobe', 'ffmpeg', 'whisper-cli', 'whisper-model'],
  };

  final String? _manifestPath;
  final ListenGenLockBytesLoader _loadLockBytes;

  static Future<List<int>> _loadLockFromBundle() async {
    final data = await rootBundle.load(_lockAssetKey);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  bool get isConfigured {
    final path = _manifestPath;
    if (path == null || path.isEmpty) return false;
    // A regular file, and not a symlink standing in for one.
    return FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.file;
  }

  @override
  Future<VerifiedListenGenRelease> verify() async {
    final lock = await _loadAndParseLock();
    return _verifyRelease(lock);
  }

  // ── Lock ────────────────────────────────────────────────────────────────

  Future<_ListenGenLock> _loadAndParseLock() async {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(await _loadLockBytes()));
    } catch (_) {
      throw _lockInvalid;
    }
    final read = _StrictReader(() => throw _lockInvalid);
    final root = read.object(decoded);
    read.exactKeys(root, const {
      'manifest_version',
      'repository',
      'source_git_sha',
      'release_manifest',
      'tool',
      'machine_protocol',
      'content_package_contract',
      'runtime',
      'artifact',
    });
    read.expect(read.integer(root, 'manifest_version') == 1);
    read.expect(read.string(root, 'repository') == _lockRepository);
    final sourceGitSha = read.commit(root, 'source_git_sha');

    final releaseManifest = read.object(root['release_manifest']);
    read.exactKeys(releaseManifest, const {'schema', 'filename', 'sha256'});
    final manifestSchema = read.string(releaseManifest, 'schema');
    read.expect(manifestSchema == _releaseBundleSchema);
    final manifestFilename = read.basename(releaseManifest, 'filename');
    final manifestSha256 = read.sha256(releaseManifest, 'sha256');

    final tool = read.object(root['tool']);
    read.exactKeys(tool, const {'id', 'version'});
    final toolId = read.string(tool, 'id');
    read.expect(toolId == _toolId);
    final toolVersion = read.string(tool, 'version');

    final machineProtocol = read.object(root['machine_protocol']);
    read.exactKeys(machineProtocol, const {'schema', 'version'});
    final machineSchema = read.string(machineProtocol, 'schema');
    read.expect(machineSchema == _machineSchema);
    final machineVersion = read.integer(machineProtocol, 'version');
    read.expect(machineVersion == _machineVersion);

    final contract = read.object(root['content_package_contract']);
    read.exactKeys(contract, const {
      'authority',
      'manifest_schema_id',
      'resource_schema_id',
      'package_schema',
      'schema_version',
      'canonical_sha256',
    });
    final authority = read.object(contract['authority']);
    read.exactKeys(authority, const {'repository', 'path'});
    final authorityRepository = read.string(authority, 'repository');
    read.expect(authorityRepository == _authorityRepository);
    final authorityPath = read.string(authority, 'path');
    read.expect(authorityPath == _authorityPath);
    final packageSchema = read.string(contract, 'package_schema');
    read.expect(packageSchema == _packageSchema);
    final contractSchemaVersion = read.integer(contract, 'schema_version');
    read.expect(contractSchemaVersion == _contractSchemaVersion);
    final contractLock = _ContractIdentity(
      authorityRepository: authorityRepository,
      authorityPath: authorityPath,
      manifestSchemaId: read.string(contract, 'manifest_schema_id'),
      resourceSchemaId: read.string(contract, 'resource_schema_id'),
      packageSchema: packageSchema,
      schemaVersion: contractSchemaVersion,
      canonicalSha256: read.sha256(contract, 'canonical_sha256'),
    );

    final runtime = read.object(root['runtime']);
    read.exactKeys(runtime, const {'python_requires'});
    final pythonRequires = read.string(runtime, 'python_requires');
    read.expect(pythonRequires == _pythonRequires);

    final artifact = read.object(root['artifact']);
    read.exactKeys(artifact, const {
      'filename',
      'format',
      'entrypoint',
      'size_bytes',
      'sha256',
    });
    final artifactFilename = read.basename(artifact, 'filename');
    final artifactFormat = read.string(artifact, 'format');
    final artifactEntrypoint = read.string(artifact, 'entrypoint');
    final artifactSize = read.integer(artifact, 'size_bytes');
    read.expect(artifactSize >= 0);
    final artifactSha256 = read.sha256(artifact, 'sha256');

    return _ListenGenLock(
      sourceGitSha: sourceGitSha,
      manifestSchema: manifestSchema,
      manifestFilename: manifestFilename,
      manifestSha256: manifestSha256,
      toolId: toolId,
      toolVersion: toolVersion,
      machineSchema: machineSchema,
      machineVersion: machineVersion,
      contract: contractLock,
      pythonRequires: pythonRequires,
      artifactFilename: artifactFilename,
      artifactFormat: artifactFormat,
      artifactEntrypoint: artifactEntrypoint,
      artifactSize: artifactSize,
      artifactSha256: artifactSha256,
    );
  }

  // ── Manifest + artifact ──────────────────────────────────────────────────

  Future<VerifiedListenGenRelease> _verifyRelease(_ListenGenLock lock) async {
    final manifestPath = _manifestPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      throw _manifestMissing;
    }
    // 1. A regular file, not a symlink or directory.
    switch (FileSystemEntity.typeSync(manifestPath, followLinks: false)) {
      case FileSystemEntityType.notFound:
        throw _manifestMissing;
      case FileSystemEntityType.file:
        break;
      default:
        throw _manifestInvalid;
    }
    // 2. The name on disk is the name the lock declares.
    if (_basename(manifestPath) != lock.manifestFilename) {
      throw _manifestInvalid;
    }
    // 3-5. Hash the raw bytes and gate on the lock before parsing anything.
    final List<int> manifestBytes;
    try {
      manifestBytes = await File(manifestPath).readAsBytes();
    } catch (_) {
      throw _manifestInvalid;
    }
    if (_digest(manifestBytes) != lock.manifestSha256) {
      throw _manifestInvalid;
    }
    // 6-7. Only now decode and strictly check identity against the lock.
    _validateManifest(manifestBytes, lock);

    // Artifact lives beside the manifest and carries the pinned name.
    final artifactPath =
        '${_dirname(manifestPath)}${Platform.pathSeparator}'
        '${lock.artifactFilename}';
    switch (FileSystemEntity.typeSync(artifactPath, followLinks: false)) {
      case FileSystemEntityType.notFound:
        throw _artifactMissing;
      case FileSystemEntityType.file:
        break;
      default:
        throw _artifactInvalid;
    }
    final List<int> artifactBytes;
    try {
      artifactBytes = await File(artifactPath).readAsBytes();
    } catch (_) {
      throw _artifactInvalid;
    }
    if (artifactBytes.length != lock.artifactSize) throw _artifactInvalid;
    if (_digest(artifactBytes) != lock.artifactSha256) throw _artifactInvalid;
    if (!_startsWithShebang(artifactBytes)) throw _artifactInvalid;

    return VerifiedListenGenRelease(
      artifactPath: artifactPath,
      artifactFilename: lock.artifactFilename,
      toolVersion: lock.toolVersion,
      sourceCommit: lock.sourceGitSha,
      artifactSha256: lock.artifactSha256,
    );
  }

  void _validateManifest(List<int> bytes, _ListenGenLock lock) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw _manifestInvalid;
    }
    final read = _StrictReader(() => throw _manifestInvalid);
    final root = read.object(decoded);
    // Strict shape: an unknown or missing field anywhere fails the manifest.
    read.exactKeys(root, const {
      'schema',
      'source',
      'tool',
      'machine_protocol',
      'content_package_contract',
      'runtime',
      'artifact',
    });

    read.expect(read.string(root, 'schema') == lock.manifestSchema);

    final source = read.object(root['source']);
    read.exactKeys(source, const {'repository', 'commit'});
    read.expect(read.string(source, 'repository') == _generatorRepository);
    read.expect(read.string(source, 'commit') == lock.sourceGitSha);

    final tool = read.object(root['tool']);
    read.exactKeys(tool, const {'id', 'version'});
    read.expect(read.string(tool, 'id') == lock.toolId);
    read.expect(read.string(tool, 'version') == lock.toolVersion);

    final machineProtocol = read.object(root['machine_protocol']);
    read.exactKeys(machineProtocol, const {'schema', 'version'});
    read.expect(read.string(machineProtocol, 'schema') == lock.machineSchema);
    read.expect(
      read.integer(machineProtocol, 'version') == lock.machineVersion,
    );

    final contract = read.object(root['content_package_contract']);
    read.exactKeys(contract, const {
      'authority',
      'manifest_schema_id',
      'resource_schema_id',
      'package_schema',
      'schema_version',
      'canonical_sha256',
    });
    final authority = read.object(contract['authority']);
    read.exactKeys(authority, const {'repository', 'path'});
    read.expect(
      read.string(authority, 'repository') == lock.contract.authorityRepository,
    );
    read.expect(read.string(authority, 'path') == lock.contract.authorityPath);
    read.expect(
      read.string(contract, 'manifest_schema_id') ==
          lock.contract.manifestSchemaId,
    );
    read.expect(
      read.string(contract, 'resource_schema_id') ==
          lock.contract.resourceSchemaId,
    );
    read.expect(
      read.string(contract, 'package_schema') == lock.contract.packageSchema,
    );
    read.expect(
      read.integer(contract, 'schema_version') == lock.contract.schemaVersion,
    );
    read.expect(
      read.sha256(contract, 'canonical_sha256') ==
          lock.contract.canonicalSha256,
    );

    final runtime = read.object(root['runtime']);
    read.exactKeys(runtime, const {'python_requires', 'provider_requirements'});
    read.expect(read.string(runtime, 'python_requires') == lock.pythonRequires);
    _validateProviderRequirements(read, runtime['provider_requirements']);

    final artifact = read.object(root['artifact']);
    read.exactKeys(artifact, const {
      'filename',
      'format',
      'entrypoint',
      'size_bytes',
      'sha256',
    });
    read.expect(read.string(artifact, 'filename') == lock.artifactFilename);
    read.expect(read.string(artifact, 'format') == lock.artifactFormat);
    read.expect(read.string(artifact, 'entrypoint') == lock.artifactEntrypoint);
    read.expect(read.integer(artifact, 'size_bytes') == lock.artifactSize);
    read.expect(read.sha256(artifact, 'sha256') == lock.artifactSha256);
  }

  void _validateProviderRequirements(_StrictReader read, Object? value) {
    final requirements = read.object(value);
    _requiredProviderRequirements.forEach((provider, required) {
      final declared = requirements[provider];
      if (declared is! List) read.fail();
      final declaredSet = declared.whereType<String>().toSet();
      read.expect(declaredSet.length == declared.length);
      for (final tool in required) {
        read.expect(declaredSet.contains(tool));
      }
    });
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  static String _digest(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

  static bool _startsWithShebang(List<int> bytes) {
    final expected = utf8.encode(_artifactShebang);
    if (bytes.length < expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (bytes[i] != expected[i]) return false;
    }
    return true;
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;

  static String _dirname(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index <= 0 ? '' : path.substring(0, index);
  }

  // Stable, path-free failure codes. Never carry a filesystem path, raw JSON,
  // or an OS error into these — only the code the UI can act on.
  static const _lockInvalid = ListenGenProcessFailure(
    'generator_release_lock_invalid',
    retryable: false,
  );
  static const _manifestMissing = ListenGenProcessFailure(
    'generator_release_manifest_missing',
    retryable: false,
  );
  static const _manifestInvalid = ListenGenProcessFailure(
    'generator_release_manifest_invalid',
    retryable: false,
  );
  static const _artifactMissing = ListenGenProcessFailure(
    'generator_release_artifact_missing',
    retryable: false,
  );
  static const _artifactInvalid = ListenGenProcessFailure(
    'generator_release_artifact_invalid',
    retryable: false,
  );
}

/// Strictly reads a decoded-JSON tree, failing with a caller-chosen error on
/// any missing field, wrong type, unknown key, or malformed value. Nothing
/// here blind-casts, so a hostile document can only ever trip [fail].
final class _StrictReader {
  const _StrictReader(this.fail);

  final Never Function() fail;

  Never _fail() => fail();

  void expect(bool ok) {
    if (!ok) _fail();
  }

  Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) _fail();
    return value;
  }

  void exactKeys(Map<String, dynamic> map, Set<String> expected) {
    if (map.length != expected.length) _fail();
    for (final key in expected) {
      if (!map.containsKey(key)) _fail();
    }
    for (final key in map.keys) {
      if (!expected.contains(key)) _fail();
    }
  }

  String string(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) _fail();
    return value;
  }

  int integer(Map<String, dynamic> map, String key) {
    final value = map[key];
    // Rejects strings, booleans, and doubles — only a real JSON integer passes.
    if (value is! int) _fail();
    return value;
  }

  String sha256(Map<String, dynamic> map, String key) {
    final value = string(map, key);
    if (!_sha256Reference.hasMatch(value)) _fail();
    return value;
  }

  String commit(Map<String, dynamic> map, String key) {
    final value = string(map, key);
    if (!_commitReference.hasMatch(value)) _fail();
    return value;
  }

  String basename(Map<String, dynamic> map, String key) {
    final value = string(map, key);
    if (value.contains('/') || value.contains(r'\') || value.contains('..')) {
      _fail();
    }
    return value;
  }

  static final _sha256Reference = RegExp(r'^sha256:[0-9a-f]{64}$');
  static final _commitReference = RegExp(r'^[0-9a-f]{40}$');
}

final class _ContractIdentity {
  const _ContractIdentity({
    required this.authorityRepository,
    required this.authorityPath,
    required this.manifestSchemaId,
    required this.resourceSchemaId,
    required this.packageSchema,
    required this.schemaVersion,
    required this.canonicalSha256,
  });

  final String authorityRepository;
  final String authorityPath;
  final String manifestSchemaId;
  final String resourceSchemaId;
  final String packageSchema;
  final int schemaVersion;
  final String canonicalSha256;
}

final class _ListenGenLock {
  const _ListenGenLock({
    required this.sourceGitSha,
    required this.manifestSchema,
    required this.manifestFilename,
    required this.manifestSha256,
    required this.toolId,
    required this.toolVersion,
    required this.machineSchema,
    required this.machineVersion,
    required this.contract,
    required this.pythonRequires,
    required this.artifactFilename,
    required this.artifactFormat,
    required this.artifactEntrypoint,
    required this.artifactSize,
    required this.artifactSha256,
  });

  final String sourceGitSha;
  final String manifestSchema;
  final String manifestFilename;
  final String manifestSha256;
  final String toolId;
  final String toolVersion;
  final String machineSchema;
  final int machineVersion;
  final _ContractIdentity contract;
  final String pythonRequires;
  final String artifactFilename;
  final String artifactFormat;
  final String artifactEntrypoint;
  final int artifactSize;
  final String artifactSha256;
}
