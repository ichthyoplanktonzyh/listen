import 'timeline.dart';

enum PackageTrustStatus { unsignedLocal }

enum PackageFactStatus {
  unknown,
  machineChecked,
  sampleReviewed,
  humanReviewed,
}

class ContentPackageProvenance {
  const ContentPackageProvenance({
    this.trust = PackageTrustStatus.unsignedLocal,
    this.publisher = PackageFactStatus.unknown,
    this.review = PackageFactStatus.unknown,
    this.license = PackageFactStatus.unknown,
  });

  final PackageTrustStatus trust;
  final PackageFactStatus publisher;
  final PackageFactStatus review;
  final PackageFactStatus license;
}

class ContentPackageResourceDisposition {
  ContentPackageResourceDisposition({
    required this.resourceId,
    required this.kind,
    required this.outcome,
    this.reason,
    this.reviewStatus,
    this.provenance,
    List<String> localIds = const [],
  }) : _localIds = List.unmodifiable(localIds);

  final String resourceId;
  final String kind;
  final String outcome;
  final String? reason;
  final String? reviewStatus;
  final ContentPackageResourceProvenance? provenance;
  final List<String> _localIds;
  List<String> get localIds => List.unmodifiable(_localIds);
}

class ContentPackageResourceProvenance {
  const ContentPackageResourceProvenance({
    required this.createdAtMs,
    required this.tool,
    this.provider,
    this.model,
    this.configSha256,
  });

  final int createdAtMs;
  final ContentPackageProducerIdentity tool;
  final ContentPackageProducerIdentity? provider;
  final ContentPackageProducerIdentity? model;
  final String? configSha256;
}

class ContentPackageProducerIdentity {
  const ContentPackageProducerIdentity({
    required this.id,
    required this.version,
  });

  final String id;
  final String version;
  String get label => '$id/$version';
}

class ContentPackageImportReceipt {
  ContentPackageImportReceipt({
    required this.manifestSha256,
    required this.track,
    List<ContentPackageResourceDisposition> resources = const [],
    List<String> warnings = const [],
    this.provenance = const ContentPackageProvenance(),
  }) : _resources = List.unmodifiable(resources),
       _warnings = List.unmodifiable(warnings);

  final String manifestSha256;
  final SubtitleTrack track;
  final List<ContentPackageResourceDisposition> _resources;
  List<ContentPackageResourceDisposition> get resources =>
      List.unmodifiable(_resources);
  final List<String> _warnings;
  List<String> get warnings => List.unmodifiable(_warnings);
  final ContentPackageProvenance provenance;
}

enum ListenGenEventKind {
  protocol,
  started,
  phase,
  completed,
  failed,
  cancelled,
}

class ListenGenResourceView {
  const ListenGenResourceView({
    required this.resourceId,
    required this.kind,
    this.reviewStatus,
  });

  final String resourceId;
  final String kind;
  final String? reviewStatus;
}

class ListenGenMachineEvent {
  ListenGenMachineEvent({
    required this.sequence,
    required this.kind,
    this.phase,
    this.packageSha256,
    this.mediaFingerprint,
    this.code,
    this.message,
    List<ListenGenResourceView> resources = const [],
    List<String> warnings = const [],
  }) : _resources = List.unmodifiable(resources),
       _warnings = List.unmodifiable(warnings);

  final int sequence;
  final ListenGenEventKind kind;
  final String? phase;
  final String? packageSha256;
  final String? mediaFingerprint;
  final String? code;
  final String? message;
  final List<ListenGenResourceView> _resources;
  List<ListenGenResourceView> get resources => List.unmodifiable(_resources);
  final List<String> _warnings;
  List<String> get warnings => List.unmodifiable(_warnings);
}

class ContentPackageGenerationRequest {
  const ContentPackageGenerationRequest({
    required this.mediaPath,
    required this.title,
    required this.mediaKind,
    required this.durationMs,
    required this.createdAtMs,
  });

  final String mediaPath;
  final String title;
  final String mediaKind;
  final int durationMs;
  final int createdAtMs;
}
