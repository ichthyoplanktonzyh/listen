import 'discovery.dart';

/// The recorded mapping of a discovered item's source-scoped canonical key
/// (source identity + item identity) to the exact Material Revision the item
/// resolved to.
///
/// The canonical key is the only match identity: the typed [evidence] fields
/// are carried facts, never substitutes for the key.
class SourceIdentityMapping {
  const SourceIdentityMapping({
    required this.sourceId,
    required this.itemId,
    required this.evidence,
    required this.materialId,
    required this.materialRevisionId,
    required this.mappedAtMs,
  });

  final String sourceId;
  final String itemId;
  final List<SourceItemEvidence> evidence;
  final String materialId;
  final String materialRevisionId;
  final int mappedAtMs;
}
