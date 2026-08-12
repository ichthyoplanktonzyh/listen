/// One bounded generation request the app sends to `listen-gen` through the
/// `package from-capability` command. [requestJson] is a
/// `listen_gen.capability-request.v2` document; [providerArguments] are CLI
/// arguments naming the TTS/ASR/OCR providers for the run (provider choice
/// and secrets never enter the request document).
final class CapabilityGenerationRequest {
  const CapabilityGenerationRequest({
    required this.requestJson,
    required this.providerArguments,
  });

  final Map<String, dynamic> requestJson;
  final List<String> providerArguments;
}
