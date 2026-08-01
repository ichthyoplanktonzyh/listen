import '../../models/api_failure.dart';
import '../../models/listening.dart';
import '../../models/practice.dart';
import '../../services/api_service.dart';

typedef ListeningSessionSnapshot = ({
  PracticeSession session,
  List<ListeningInboxItem> items,
});

abstract interface class ListeningRepository {
  bool get isAvailable;

  Future<ListeningSessionSnapshot> startSession({
    required String? mediaId,
    required String? trackId,
    required String source,
  });

  Future<ListeningSessionSnapshot> finishSession({
    required String sessionId,
    String? comprehensionReport,
    HuntingCompletionSummary? huntingSummary,
  });

  Future<List<ListeningInboxItem>> inboxItems({String status = 'active'});

  Future<ListeningInboxItem> captureItem(CaptureListeningInboxItemInput input);

  Future<ListeningInboxItem> processItem({
    required String itemId,
    required String resolution,
  });
}

class ListeningRepositoryFailure implements Exception {
  const ListeningRepositoryFailure(this.detail);

  final ApiFailure detail;
}

class LocalListeningRepository implements ListeningRepository {
  LocalListeningRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Listening API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  Future<T> _request<T>(Future<T> Function(LocalApi api) request) async {
    try {
      return await request(_api);
    } catch (error) {
      throw ListeningRepositoryFailure(describeApiFailure(error));
    }
  }

  @override
  Future<ListeningSessionSnapshot> startSession({
    required String? mediaId,
    required String? trackId,
    required String source,
  }) => _request((api) async {
    final session = await api.createPracticeSession(
      CreatePracticeSession(
        mode: 'extensive',
        mediaId: mediaId,
        trackId: trackId,
        source: source,
      ),
    );
    final items = await api.listeningInboxItems();
    return (
      session: session,
      items: List<ListeningInboxItem>.unmodifiable(items),
    );
  });

  @override
  Future<ListeningSessionSnapshot> finishSession({
    required String sessionId,
    String? comprehensionReport,
    HuntingCompletionSummary? huntingSummary,
  }) => _request((api) async {
    final session = await api.completeListeningSession(
      sessionId,
      comprehensionReport: comprehensionReport,
      huntingSummary: huntingSummary,
    );
    final items = await api.listeningInboxItems();
    return (
      session: session,
      items: List<ListeningInboxItem>.unmodifiable(items),
    );
  });

  @override
  Future<List<ListeningInboxItem>> inboxItems({String status = 'active'}) =>
      _request((api) async {
        final items = await api.listeningInboxItems(status: status);
        return List.unmodifiable(items);
      });

  @override
  Future<ListeningInboxItem> captureItem(
    CaptureListeningInboxItemInput input,
  ) => _request((api) => api.captureListeningInboxItem(input));

  @override
  Future<ListeningInboxItem> processItem({
    required String itemId,
    required String resolution,
  }) => _request(
    (api) => api.processListeningInboxItem(
      itemId,
      ProcessListeningInboxItemInput(resolution: resolution),
    ),
  );
}

class UnavailableListeningRepository implements ListeningRepository {
  const UnavailableListeningRepository();

  Never _unavailable() =>
      throw StateError('Listening repository is unavailable');

  @override
  bool get isAvailable => false;

  @override
  Future<ListeningInboxItem> captureItem(
    CaptureListeningInboxItemInput input,
  ) => _unavailable();

  @override
  Future<ListeningSessionSnapshot> finishSession({
    required String sessionId,
    String? comprehensionReport,
    HuntingCompletionSummary? huntingSummary,
  }) => _unavailable();

  @override
  Future<List<ListeningInboxItem>> inboxItems({String status = 'active'}) =>
      _unavailable();

  @override
  Future<ListeningInboxItem> processItem({
    required String itemId,
    required String resolution,
  }) => _unavailable();

  @override
  Future<ListeningSessionSnapshot> startSession({
    required String? mediaId,
    required String? trackId,
    required String source,
  }) => _unavailable();
}
