class SpeechSynthesisProviderView {
  const SpeechSynthesisProviderView({
    required this.id,
    required this.displayName,
    required this.version,
    required this.locality,
  });

  factory SpeechSynthesisProviderView.fromJson(Map<String, dynamic> json) =>
      SpeechSynthesisProviderView(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        version: json['version'] as String,
        locality: json['locality'] as String,
      );

  final String id;
  final String displayName;
  final String version;
  final String locality;
}

class SpeechSynthesisVoiceView {
  const SpeechSynthesisVoiceView({
    required this.id,
    required this.providerId,
    required this.displayName,
    required this.language,
  });

  factory SpeechSynthesisVoiceView.fromJson(Map<String, dynamic> json) =>
      SpeechSynthesisVoiceView(
        id: json['id'] as String,
        providerId: json['provider_id'] as String,
        displayName: json['display_name'] as String,
        language: json['language'] as String,
      );

  final String id;
  final String providerId;
  final String displayName;
  final String language;
}

class SpeechSynthesisCapabilityView {
  const SpeechSynthesisCapabilityView({
    required this.status,
    required this.providers,
    required this.voices,
    required this.cacheBytes,
    required this.cacheEntries,
    this.error,
  });

  factory SpeechSynthesisCapabilityView.fromJson(
    Map<String, dynamic> json,
  ) => SpeechSynthesisCapabilityView(
    status: json['status'] as String,
    providers: (json['providers'] as List<dynamic>)
        .map(
          (value) => SpeechSynthesisProviderView.fromJson(
            value as Map<String, dynamic>,
          ),
        )
        .toList(growable: false),
    voices: (json['voices'] as List<dynamic>)
        .map(
          (value) =>
              SpeechSynthesisVoiceView.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    cacheBytes: json['cache_bytes'] as int,
    cacheEntries: json['cache_entries'] as int,
    error: json['error'] as String?,
  );

  final String status;
  final List<SpeechSynthesisProviderView> providers;
  final List<SpeechSynthesisVoiceView> voices;
  final int cacheBytes;
  final int cacheEntries;
  final String? error;
}

class SpeechSynthesisAssetView {
  const SpeechSynthesisAssetView({
    required this.audioPath,
    required this.mimeType,
    required this.providerId,
    required this.providerVersion,
    required this.voiceId,
    required this.language,
    required this.rateWordsPerMinute,
    required this.contentHash,
    required this.cacheHit,
    required this.synthetic,
    this.purpose,
  });

  factory SpeechSynthesisAssetView.fromJson(Map<String, dynamic> json) =>
      SpeechSynthesisAssetView(
        audioPath: json['audio_path'] as String,
        mimeType: json['mime_type'] as String,
        providerId: json['provider_id'] as String,
        providerVersion: json['provider_version'] as String,
        voiceId: json['voice_id'] as String,
        language: json['language'] as String,
        rateWordsPerMinute: json['rate_words_per_minute'] as int,
        purpose: json['purpose'] as String?,
        contentHash: json['content_hash'] as String,
        cacheHit: json['cache_hit'] as bool,
        synthetic: json['synthetic'] as bool,
      );

  final String audioPath;
  final String mimeType;
  final String providerId;
  final String providerVersion;
  final String voiceId;
  final String language;
  final int rateWordsPerMinute;
  final String? purpose;
  final String contentHash;
  final bool cacheHit;
  final bool synthetic;
}
