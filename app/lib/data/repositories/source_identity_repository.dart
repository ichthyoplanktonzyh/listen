import '../../models/discovery.dart';
import '../../models/source_identity.dart';
import '../../services/api_service.dart';

/// The Source Identity boundary: recording and resolving the mapping of a
/// discovered item's source-scoped canonical key to the exact Material
/// Revision it converged on.
///
/// This is how "re-reading, feed reordering, metadata changes, or reacquiring
/// an item resolves the same Material" is enforced: the mapping is written
/// down at intake time and consulted on every refresh, so a second refresh of
/// the same feed item never creates a second Material.
abstract interface class SourceIdentityRepository {
  bool get isAvailable;

  /// Records (or updates) the mapping for [itemId] under [sourceId].
  Future<void> recordMapping({
    required String sourceId,
    required String itemId,
    required List<SourceItemEvidence> evidence,
    required String materialId,
    required String materialRevisionId,
  });

  /// Resolves [itemId] under [sourceId] to its recorded mapping, or null
  /// when none is recorded.
  Future<SourceIdentityMapping?> resolveMapping({
    required String sourceId,
    required String itemId,
  });
}

final class LocalSourceIdentityRepository implements SourceIdentityRepository {
  LocalSourceIdentityRepository(this._getApi);

  final LocalApi? Function() _getApi;
  LocalApi get _api =>
      _getApi() ?? (throw StateError('Source Identity API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  @override
  Future<void> recordMapping({
    required String sourceId,
    required String itemId,
    required List<SourceItemEvidence> evidence,
    required String materialId,
    required String materialRevisionId,
  }) async {
    try {
      await _api.registerSourceIdentityMapping(
        sourceId: sourceId,
        itemId: itemId,
        evidence: evidence,
        materialId: materialId,
        materialRevisionId: materialRevisionId,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(describeApiFailure(error), stackTrace);
    }
  }

  @override
  Future<SourceIdentityMapping?> resolveMapping({
    required String sourceId,
    required String itemId,
  }) async {
    try {
      return await _api.resolveSourceIdentity(
        sourceId: sourceId,
        itemId: itemId,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(describeApiFailure(error), stackTrace);
    }
  }
}
