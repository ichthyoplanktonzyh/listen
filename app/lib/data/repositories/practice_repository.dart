import '../../models/practice.dart';
import '../../services/api_service.dart';

abstract interface class PracticeRepository {
  bool get isAvailable;

  Future<PracticeSession> createSession(CreatePracticeSession input);
  Future<PracticeItem> createItem(CreatePracticeItem input);
  Future<PracticeAttempt> submitAttempt(SubmitPracticeAttempt input);
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
  Future<ReviewItem> createReview(CreateReviewItem input) => _unavailable;
}
