import '../../services/core_transport_service.dart';
import '../../services/api_service.dart' show LocalApi;
import 'coach_dashboard_repository.dart';
import 'cold_start_marking_repository.dart';
import 'external_vocabulary_repository.dart';
import 'hunting_repository.dart';
import 'learning_assets_repository.dart';
import 'learning_repository.dart';
import 'lexical_repository.dart';
import 'listening_repository.dart';
import 'manual_review_repository.dart';
import 'media_library_repository.dart';
import 'media_session_repository.dart';
import 'phonetic_analysis_repository.dart';
import 'personal_expression_repository.dart';
import 'playback_repository.dart';
import 'practice_repository.dart';
import 'reading_session_repository.dart';
import 'reading_task_repository.dart';
import 'realtime_conversation_repository.dart';
import 'resource_repository.dart';
import 'review_repository.dart';
import 'semantic_search_repository.dart';
import 'settings_repository.dart';
import 'speaking_session_repository.dart';
import 'speaking_task_repository.dart';
import 'speech_enhancement_repository.dart';
import 'speech_synthesis_repository.dart';
import 'subtitle_analysis_repository.dart';
import 'transcription_repository.dart';
import 'writing_task_repository.dart';

/// Composition provider that keeps the raw LocalApi handle out of the UI.
/// Long-lived repositories receive a deferred API lookup; route-scoped ones
/// are created only while the core is connected.
final class LocalCoreRepositories {
  LocalCoreRepositories(this._transport)
    : realtimeConversation = LocalRealtimeConversationRepository(
        () => _transport.currentApi!,
      ),
      hunting = LocalHuntingRepository(() => _transport.currentApi),
      learning = LocalLearningRepository(() => _transport.currentApi),
      listening = LocalListeningRepository(() => _transport.currentApi),
      mediaLibrary = LocalMediaLibraryRepository(() => _transport.currentApi),
      mediaSession = LocalMediaSessionRepository(() => _transport.currentApi),
      playback = LocalPlaybackRepository(() => _transport.currentApi),
      resource = LocalResourceRepository(() => _transport.currentApi),
      readingTask = LocalReadingTaskRepository(() => _transport.currentApi),
      readingSession = LocalReadingSessionRepository(
        () => _transport.currentApi,
      ),
      speakingSession = LocalSpeakingSessionRepository(
        () => _transport.currentApi,
      ),
      speechEnhancement = LocalSpeechEnhancementRepository(
        () => _transport.currentApi,
      ),
      subtitleAnalysis = LocalSubtitleAnalysisRepository(
        () => _transport.currentApi,
      ),
      writingTask = LocalWritingTaskRepository(() => _transport.currentApi);

  final LocalCoreTransportService _transport;

  bool get isAvailable => _transport.isConnected;

  final RealtimeConversationRepository realtimeConversation;
  final HuntingRepository hunting;
  final LearningRepository learning;
  final ListeningRepository listening;
  final MediaLibraryRepository mediaLibrary;
  final MediaSessionRepository mediaSession;
  final PlaybackRepository playback;
  final ResourceRepository resource;
  final ReadingTaskRepository readingTask;
  final ReadingSessionRepository readingSession;
  final SpeakingSessionRepository speakingSession;
  final SpeechEnhancementRepository speechEnhancement;
  final SubtitleAnalysisRepository subtitleAnalysis;
  final WritingTaskRepository writingTask;

  LocalApi get _api =>
      _transport.currentApi ?? (throw StateError('Local core is unavailable'));

  PracticeRepository get practice => LocalPracticeRepository(() => _api);
  SpeechSynthesisRepository get speechSynthesis =>
      LocalSpeechSynthesisRepository(() => _api);
  SpeakingTaskRepository get speakingTask =>
      LocalSpeakingTaskRepository(() => _api);
  LearningAssetsRepository get learningAssets =>
      LocalLearningAssetsRepository(_api);
  PersonalExpressionRepository get personalExpression =>
      LocalPersonalExpressionRepository(_api);
  ManualReviewRepository get manualReview => LocalManualReviewRepository(_api);
  TranscriptionRepository get transcription =>
      LocalTranscriptionRepository(_api);
  PhoneticAnalysisRepository get phoneticAnalysis =>
      LocalPhoneticAnalysisRepository(_api);
  LexicalRepository get lexical => LexicalRepository(_api);
  ReviewRepository get review => LocalReviewRepository(_api);
  CoachDashboardRepository get coachDashboard =>
      LocalCoachDashboardRepository(_api);
  SemanticSearchRepository get semanticSearch =>
      LocalSemanticSearchRepository(_api);
  ColdStartMarkingRepository get coldStartMarking =>
      LocalColdStartMarkingRepository(_api);
  ExternalVocabularyRepository get externalVocabulary =>
      LocalExternalVocabularyRepository(_api);
  LearnerSettingsRepository get learnerSettings =>
      LocalLearnerSettingsRepository(_api);
  LlmProviderRepository get llmProvider => LocalLlmProviderRepository(_api);
  RealtimeProviderRepository get realtimeProvider =>
      LocalRealtimeProviderRepository(_api);
  SyntaxCapabilityRepository get syntaxCapability =>
      LocalSyntaxCapabilityRepository(_api);
}
