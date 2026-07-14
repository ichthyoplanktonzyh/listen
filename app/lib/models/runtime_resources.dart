class LearningResourceDescriptor {
  const LearningResourceDescriptor({
    required this.id,
    required this.displayName,
    required this.version,
    required this.license,
    required this.checksumSha256,
    required this.sizeBytes,
    required this.state,
    required this.installedBytes,
    this.error,
  });

  factory LearningResourceDescriptor.fromJson(Map<String, dynamic> json) =>
      LearningResourceDescriptor(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        version: json['version'] as String,
        license: json['license'] as String,
        checksumSha256: json['checksum_sha256'] as String,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        state: json['state'] as String,
        installedBytes: (json['installed_bytes'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
      );

  final String id;
  final String displayName;
  final String version;
  final String license;
  final String checksumSha256;
  final int sizeBytes;
  final String state;
  final int installedBytes;
  final String? error;
}

class TranscriptionProviderView {
  const TranscriptionProviderView({
    required this.id,
    required this.displayName,
    required this.runtimeId,
    required this.runtimeVersion,
    required this.available,
    this.diagnostic,
  });

  factory TranscriptionProviderView.fromJson(Map<String, dynamic> json) =>
      TranscriptionProviderView(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        runtimeId: json['runtime_id'] as String,
        runtimeVersion: json['runtime_version'] as String,
        available: json['available'] as bool,
        diagnostic: json['diagnostic'] as String?,
      );

  final String id;
  final String displayName;
  final String runtimeId;
  final String runtimeVersion;
  final bool available;
  final String? diagnostic;
}

class TranscriptionModelView {
  const TranscriptionModelView({
    required this.id,
    required this.displayName,
    required this.revision,
    required this.sizeBytes,
    required this.quality,
    required this.englishOnly,
    required this.state,
    required this.installedBytes,
    required this.license,
    this.error,
  });

  factory TranscriptionModelView.fromJson(Map<String, dynamic> json) =>
      TranscriptionModelView(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        revision: json['revision'] as String,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        quality: json['quality'] as String,
        englishOnly: json['english_only'] as bool,
        state: json['state'] as String,
        installedBytes: (json['installed_bytes'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
        license: json['license'] as String,
      );

  final String id;
  final String displayName;
  final String revision;
  final int sizeBytes;
  final String quality;
  final bool englishOnly;
  final String state;
  final int installedBytes;
  final String? error;
  final String license;
}

class TranscriptionJobView {
  const TranscriptionJobView({
    required this.id,
    required this.mediaId,
    required this.mediaTitle,
    required this.modelId,
    required this.destination,
    required this.status,
    required this.phaseProgress,
    required this.createdAtMs,
    this.errorMessage,
    this.generatedTrackId,
    this.archivedAtMs,
  });

  factory TranscriptionJobView.fromJson(Map<String, dynamic> json) =>
      TranscriptionJobView(
        id: json['id'] as String,
        mediaId: json['media_id'] as String,
        mediaTitle: json['media_title'] as String,
        modelId: json['model_id'] as String,
        destination: json['destination'] as String,
        status: json['status'] as String,
        phaseProgress: (json['phase_progress'] as num).toInt(),
        errorMessage: json['error_message'] as String?,
        generatedTrackId: json['generated_track_id'] as String?,
        createdAtMs: (json['created_at_ms'] as num).toInt(),
        archivedAtMs: (json['archived_at_ms'] as num?)?.toInt(),
      );

  final String id;
  final String mediaId;
  final String mediaTitle;
  final String modelId;
  final String destination;
  final String status;
  final int phaseProgress;
  final String? errorMessage;
  final String? generatedTrackId;
  final int createdAtMs;
  final int? archivedAtMs;
}

class PhoneticProviderView {
  const PhoneticProviderView({
    required this.id,
    required this.displayName,
    required this.runtimeId,
    required this.runtimeVersion,
    required this.available,
    required this.experimental,
    this.diagnostic,
  });

  factory PhoneticProviderView.fromJson(Map<String, dynamic> json) =>
      PhoneticProviderView(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        runtimeId: json['runtime_id'] as String,
        runtimeVersion: json['runtime_version'] as String,
        available: json['available'] as bool,
        experimental: json['experimental'] as bool,
        diagnostic: json['diagnostic'] as String?,
      );

  final String id;
  final String displayName;
  final String runtimeId;
  final String runtimeVersion;
  final bool available;
  final bool experimental;
  final String? diagnostic;
}

class PhoneticModelView {
  const PhoneticModelView({
    required this.id,
    required this.providerId,
    required this.displayName,
    required this.revision,
    required this.sizeBytes,
    required this.state,
    required this.installedBytes,
    required this.license,
    required this.trainingDataProvenance,
    required this.distributionAllowed,
    required this.applicationVerified,
    this.error,
  });

  factory PhoneticModelView.fromJson(Map<String, dynamic> json) =>
      PhoneticModelView(
        id: json['id'] as String,
        providerId: json['provider_id'] as String,
        displayName: json['display_name'] as String,
        revision: json['revision'] as String,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        state: json['state'] as String,
        installedBytes: (json['installed_bytes'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
        license: json['license'] as String,
        trainingDataProvenance: json['training_data_provenance'] as String,
        distributionAllowed: json['distribution_allowed'] as bool,
        applicationVerified: json['application_verified'] as bool,
      );

  final String id;
  final String providerId;
  final String displayName;
  final String revision;
  final int sizeBytes;
  final String state;
  final int installedBytes;
  final String? error;
  final String license;
  final String trainingDataProvenance;
  final bool distributionAllowed;
  final bool applicationVerified;
}

class PhoneticJobView {
  const PhoneticJobView({
    required this.id,
    required this.trackId,
    required this.scope,
    required this.providerId,
    required this.runtimeId,
    required this.runtimeVersion,
    required this.modelRevision,
    required this.status,
    required this.phaseProgress,
    required this.createdAtMs,
    this.errorMessage,
  });

  factory PhoneticJobView.fromJson(Map<String, dynamic> json) =>
      PhoneticJobView(
        id: json['id'] as String,
        trackId: json['track_id'] as String,
        scope: json['scope'] as String,
        providerId: json['provider_id'] as String,
        runtimeId: json['runtime_id'] as String,
        runtimeVersion: json['runtime_version'] as String,
        modelRevision: json['model_revision'] as String,
        status: json['status'] as String,
        phaseProgress: (json['phase_progress'] as num).toInt(),
        errorMessage: json['error_message'] as String?,
        createdAtMs: (json['created_at_ms'] as num).toInt(),
      );

  final String id;
  final String trackId;
  final String scope;
  final String providerId;
  final String runtimeId;
  final String runtimeVersion;
  final String modelRevision;
  final String status;
  final int phaseProgress;
  final String? errorMessage;
  final int createdAtMs;
}

class PhoneticFindingFeedbackView {
  const PhoneticFindingFeedbackView({
    required this.findingId,
    required this.value,
    required this.updatedAtMs,
    this.note,
  });

  factory PhoneticFindingFeedbackView.fromJson(Map<String, dynamic> json) =>
      PhoneticFindingFeedbackView(
        findingId: json['finding_id'] as String,
        value: json['value'] as String,
        note: json['note'] as String?,
        updatedAtMs: (json['updated_at_ms'] as num).toInt(),
      );

  final String findingId;
  final String value;
  final String? note;
  final int updatedAtMs;
}

class DeletedResourceCount {
  const DeletedResourceCount(this.deleted);

  factory DeletedResourceCount.fromJson(Map<String, dynamic> json) =>
      DeletedResourceCount((json['deleted'] as num).toInt());

  final int deleted;
}
