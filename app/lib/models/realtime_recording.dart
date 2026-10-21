import 'practice.dart';

class CapturedRecording {
  const CapturedRecording({
    required this.path,
    required this.durationMs,
    required this.byteLength,
    required this.contentSha256,
  });

  final String path;
  final int durationMs;
  final int byteLength;
  final String contentSha256;
}

class RecordingAudioMetadata {
  const RecordingAudioMetadata({
    required this.container,
    required this.codec,
    required this.sampleRateHz,
    required this.channels,
    required this.sampleFormat,
    required this.byteLength,
    required this.contentSha256,
  });

  final String container;
  final String codec;
  final int sampleRateHz;
  final int channels;
  final int byteLength;
  final String sampleFormat;
  final String contentSha256;
}

class PlayableSegment {
  const PlayableSegment({
    required this.mediaId,
    required this.startMs,
    required this.endMs,
    required this.label,
    required this.subtitleSnapshot,
    required this.availability,
  });

  final String? mediaId;
  final int startMs;
  final int endMs;
  final String label;
  final String subtitleSnapshot;
  final String availability;
}

class CreateRecordingAsset {
  const CreateRecordingAsset({
    required this.filePath,
    required this.durationMs,
    required this.target,
    required this.sourceSegment,
    required this.language,
    required this.audio,
    required this.recorderVersion,
  });

  final String filePath;
  final int durationMs;
  final PracticeTarget target;
  final PlayableSegment sourceSegment;
  final String language;
  final RecordingAudioMetadata audio;
  final String recorderVersion;
}

class RecordingAsset {
  const RecordingAsset({required this.id});

  final String id;
}

class RecordingTranscriptSegment {
  const RecordingTranscriptSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int startMs;
  final int endMs;
  final String text;
}

class RecordingTranscriptProvenanceView {
  const RecordingTranscriptProvenanceView({
    required this.providerId,
    required this.providerVersion,
    required this.runtimeId,
    required this.runtimeVersion,
    required this.modelId,
    required this.modelRevision,
    required this.modelChecksumSha256,
    required this.recordingContentSha256,
    this.requestedLanguage,
    this.detectedLanguage,
  });

  final String providerId;
  final String providerVersion;
  final String runtimeId;
  final String runtimeVersion;
  final String modelId;
  final String modelRevision;
  final String modelChecksumSha256;
  final String recordingContentSha256;
  final String? requestedLanguage;
  final String? detectedLanguage;
}

class RecordingTranscriptionJobView {
  const RecordingTranscriptionJobView({
    required this.id,
    required this.recordingAssetId,
    required this.status,
    required this.segments,
    required this.provenance,
    required this.createdAtMs,
    this.rawTranscript,
    this.errorCode,
    this.errorMessage,
    this.startedAtMs,
    this.completedAtMs,
    this.latencyMs,
  });

  final String id;
  final String recordingAssetId;
  final String status;
  final String? rawTranscript;
  final List<RecordingTranscriptSegment> segments;
  final RecordingTranscriptProvenanceView provenance;
  final String? errorCode;
  final String? errorMessage;
  final int createdAtMs;
  final int? startedAtMs;
  final int? completedAtMs;
  final int? latencyMs;
}
