import '../../models/practice.dart';
import '../../services/api_service.dart';

abstract interface class PracticeRepository {
  bool get isAvailable;

  Future<PracticeSession> createSession(CreatePracticeSession input);
  Future<PracticeItem> createItem(CreatePracticeItem input);
  Future<PracticeAttempt> submitAttempt(SubmitPracticeAttempt input);
  Future<RecordingAsset> createRecording(CreateRecordingAsset input);
  Future<PracticeAttempt> completeShadowing({
    required String itemId,
    required String recordingId,
  });
  Future<ShadowingComparison> compareShadowing({
    required String recordingId,
    required String referenceWavPath,
  });
  Future<void> deleteRecording(String id);
  Future<ReviewItem> createReview(CreateReviewItem input);
}

final class LocalPracticeRepository implements PracticeRepository {
  const LocalPracticeRepository(this._api);

  final LocalApi? Function() _api;

  LocalApi get _current =>
      _api() ?? (throw StateError('Local core is unavailable'));

  @override
  bool get isAvailable => _api() != null;

  @override
  Future<PracticeSession> createSession(CreatePracticeSession input) =>
      _current.createPracticeSession(input);

  @override
  Future<PracticeItem> createItem(CreatePracticeItem input) =>
      _current.createPracticeItem(input);

  @override
  Future<PracticeAttempt> submitAttempt(SubmitPracticeAttempt input) =>
      _current.submitPracticeAttempt(input);

  @override
  Future<RecordingAsset> createRecording(CreateRecordingAsset input) =>
      _current.createRecordingAsset(input);

  @override
  Future<PracticeAttempt> completeShadowing({
    required String itemId,
    required String recordingId,
  }) => _current.completeShadowingAttempt(
    itemId: itemId,
    recordingId: recordingId,
  );

  @override
  Future<ShadowingComparison> compareShadowing({
    required String recordingId,
    required String referenceWavPath,
  }) => _current.compareShadowing(
    recordingId: recordingId,
    referenceWavPath: referenceWavPath,
  );

  @override
  Future<void> deleteRecording(String id) async {
    await _current.deleteRecordingAsset(id);
  }

  @override
  Future<ReviewItem> createReview(CreateReviewItem input) =>
      _current.createReviewItem(input);
}

final class UnavailablePracticeRepository implements PracticeRepository {
  const UnavailablePracticeRepository();

  Never get _unavailable => throw StateError('Local core is unavailable');

  @override
  bool get isAvailable => false;
  @override
  Future<PracticeSession> createSession(CreatePracticeSession input) =>
      _unavailable;
  @override
  Future<PracticeItem> createItem(CreatePracticeItem input) => _unavailable;
  @override
  Future<PracticeAttempt> submitAttempt(SubmitPracticeAttempt input) =>
      _unavailable;
  @override
  Future<RecordingAsset> createRecording(CreateRecordingAsset input) =>
      _unavailable;
  @override
  Future<PracticeAttempt> completeShadowing({
    required String itemId,
    required String recordingId,
  }) => _unavailable;
  @override
  Future<ShadowingComparison> compareShadowing({
    required String recordingId,
    required String referenceWavPath,
  }) => _unavailable;
  @override
  Future<void> deleteRecording(String id) => _unavailable;
  @override
  Future<ReviewItem> createReview(CreateReviewItem input) => _unavailable;
}
