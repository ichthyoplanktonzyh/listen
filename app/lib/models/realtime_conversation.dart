class RealtimeProviderProfileView {
  const RealtimeProviderProfileView({
    required this.id,
    required this.displayName,
    required this.adapterKind,
    required this.baseUrl,
    required this.modelId,
    required this.voice,
    required this.hasCredential,
    required this.timeoutMs,
  });

  factory RealtimeProviderProfileView.fromJson(Map<String, dynamic> json) =>
      RealtimeProviderProfileView(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        adapterKind: json['adapter_kind'] as String,
        baseUrl: json['base_url'] as String,
        modelId: json['model_id'] as String,
        voice: json['voice'] as String,
        hasCredential: json['has_credential'] as bool,
        timeoutMs: json['timeout_ms'] as int,
      );

  final String id;
  final String displayName;
  final String adapterKind;
  final String baseUrl;
  final String modelId;
  final String voice;
  final bool hasCredential;
  final int timeoutMs;
}
