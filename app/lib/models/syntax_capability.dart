class SyntaxCapabilityView {
  const SyntaxCapabilityView({
    required this.status,
    required this.progress,
    required this.enabled,
    required this.runtimeVersion,
    required this.providerVersion,
    required this.modelVersion,
    required this.modelChecksumSha256,
    required this.expectedInstallBytes,
    required this.deliveryChecksumSha256,
    required this.installedBytes,
    required this.error,
  });

  factory SyntaxCapabilityView.fromJson(Map<String, dynamic> json) =>
      SyntaxCapabilityView(
        status: json['status'] as String? ?? 'not_installed',
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        enabled: json['enabled'] as bool? ?? false,
        runtimeVersion: json['runtime_version'] as String? ?? '',
        providerVersion: json['provider_version'] as String? ?? '',
        modelVersion: json['model_version'] as String? ?? '',
        modelChecksumSha256: json['model_checksum_sha256'] as String? ?? '',
        expectedInstallBytes:
            (json['expected_install_bytes'] as num?)?.toInt() ?? 0,
        deliveryChecksumSha256:
            json['delivery_checksum_sha256'] as String? ?? '',
        installedBytes: (json['installed_bytes'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
      );

  final String status;
  final double progress;
  final bool enabled;
  final String runtimeVersion;
  final String providerVersion;
  final String modelVersion;
  final String modelChecksumSha256;
  final int expectedInstallBytes;
  final String deliveryChecksumSha256;
  final int installedBytes;
  final String? error;

  bool get isDownloading => status == 'downloading';
  bool get isReady => status == 'ready' && enabled;
  bool get isInstalled =>
      {'ready', 'partial', 'stale', 'disabled'}.contains(status) ||
      (status == 'failed' && installedBytes > 0);
}

class TrackSyntaxAnalysisView {
  const TrackSyntaxAnalysisView({
    required this.status,
    required this.fingerprint,
    required this.cacheHit,
    required this.sentenceCount,
    required this.analyzedSentenceCount,
    required this.fallbackSentenceCount,
  });

  factory TrackSyntaxAnalysisView.fromJson(Map<String, dynamic> json) =>
      TrackSyntaxAnalysisView(
        status: json['status'] as String? ?? 'unavailable',
        fingerprint: json['fingerprint'] as String? ?? '',
        cacheHit: json['cache_hit'] as bool? ?? false,
        sentenceCount: (json['sentence_count'] as num?)?.toInt() ?? 0,
        analyzedSentenceCount:
            (json['analyzed_sentence_count'] as num?)?.toInt() ?? 0,
        fallbackSentenceCount:
            (json['fallback_sentence_count'] as num?)?.toInt() ?? 0,
      );

  final String status;
  final String fingerprint;
  final bool cacheHit;
  final int sentenceCount;
  final int analyzedSentenceCount;
  final int fallbackSentenceCount;
}
