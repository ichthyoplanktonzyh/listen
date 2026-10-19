import 'dart:io';

import '../data/repositories/capability_repository.dart';
import '../models/adopted_composition.dart';
import '../models/learning_material.dart';
import 'capability_request_encoder.dart';

/// Resolves the reusable base resources of the adopted composition for one
/// production request.
///
/// A Structured Reading the current Material already owns is the generator's
/// compatibility evidence; its exact payload bytes are materialized to a
/// run-owned temporary file so Gen can verify before consuming. A Material
/// with no adopted composition, or a payload that cannot be read,
/// contributes nothing — generation then produces the resource itself
/// rather than failing on a half-truth.
class ReusableResourceResolver {
  ReusableResourceResolver(this._repository);

  final CapabilityRepository _repository;
  Future<Directory>? _resourceDirectoryFuture;

  Future<List<RequestAvailableResource>> resolve(
    MaterialDetails material,
  ) async {
    final AdoptedComposition composition;
    try {
      composition = await _repository.readAdoptedComposition(
        material.material.id,
      );
    } on Object {
      return const [];
    }
    final results = <RequestAvailableResource>[];
    for (final resource in composition.resources) {
      if (resource.kind != 'structured_reading' || resource.role != 'base') {
        continue;
      }
      final List<int> payload;
      try {
        payload = await _repository.readCompositionResourcePayload(
          material.material.id,
          resource.resourceId,
        );
      } on Object {
        // A resource whose payload is not readable is not reusable; the run
        // proceeds without declaring it.
        continue;
      }
      if (payload.isEmpty) continue;
      final directory = await _resourceDirectory();
      final path = '${directory.path}/${_safeFileName(resource.resourceId)}';
      try {
        await File(path).writeAsBytes(payload, flush: true);
      } on Object {
        continue;
      }
      results.add(
        RequestAvailableResource(
          resourceId: resource.resourceId,
          kind: resource.kind,
          schema: resource.schema,
          role: resource.role,
          contentLanguage: resource.contentLanguage,
          materialRevisionId: composition.materialRevisionId,
          payloadDigest: resource.payloadDigest,
          payloadSizeBytes: resource.payloadSizeBytes,
          payloadPath: path,
        ),
      );
    }
    return results;
  }

  Future<Directory> _resourceDirectory() =>
      _resourceDirectoryFuture ??= Directory.systemTemp.createTemp(
        'listen-capability-resources-',
      );

  Future<void> dispose() async {
    final future = _resourceDirectoryFuture;
    if (future == null) return;
    try {
      final directory = await future;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on Object {
      // Best-effort: a stale temporary directory is harmless.
    }
  }

  static String _safeFileName(String resourceId) {
    // Resource ids are sha256 hex; keep the prefix and let the digest stay
    // unique without ever turning a path separator into a hazard.
    final hex = resourceId.replaceAll(RegExp('[^0-9a-f]'), '');
    return '${hex.isEmpty ? 'resource' : hex.substring(0, 16)}.json';
  }
}
