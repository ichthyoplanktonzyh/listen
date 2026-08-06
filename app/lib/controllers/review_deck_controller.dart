import 'package:flutter/foundation.dart';

import '../data/repositories/review_repository.dart';
import '../models/review_deck.dart';
import '../state/store.dart';

class ReviewDeckState {
  const ReviewDeckState({
    this.overview,
    this.busy = false,
    this.savingLimits = false,
    this.importSummary,
    this.exportSummary,
    this.error,
  });

  /// The deck counts as the backend last reported them. Null before the first
  /// load lands — the page shows nothing rather than zeros it has not been
  /// told, because "0 due" and "not loaded yet" are different facts.
  final ReviewDeckOverview? overview;
  final bool busy;
  final bool savingLimits;

  /// The last completed interop run, kept so its report stays on screen until
  /// the learner dismisses it.
  final AnkiPackageImportSummary? importSummary;
  final AnkiPackageExportSummary? exportSummary;
  final String? error;

  ReviewDeckState copyWith({
    ReviewDeckOverview? overview,
    bool? busy,
    bool? savingLimits,
    AnkiPackageImportSummary? importSummary,
    AnkiPackageExportSummary? exportSummary,
    String? error,
    bool clearError = false,
    bool clearReports = false,
  }) => ReviewDeckState(
    overview: overview ?? this.overview,
    busy: busy ?? this.busy,
    savingLimits: savingLimits ?? this.savingLimits,
    importSummary: clearReports ? null : importSummary ?? this.importSummary,
    exportSummary: clearReports ? null : exportSummary ?? this.exportSummary,
    error: clearError ? null : error ?? this.error,
  );
}

/// Owns the review home: deck counts, the daily budget, and the two Anki
/// interop runs. It deliberately does not own the card session — starting one
/// is the shell's job, so a session outlives a rebuild of this page.
class ReviewDeckController extends ChangeNotifier {
  ReviewDeckController(this._repository)
    : _store = Store(const ReviewDeckState()) {
    _store.addListener(notifyListeners);
  }

  final ReviewRepository _repository;
  final Store<ReviewDeckState> _store;
  bool _disposed = false;
  int _loadGeneration = 0;

  Store<ReviewDeckState> get store => _store;
  ReviewDeckState get state => _store.state;

  void _set(ReviewDeckState Function(ReviewDeckState) update) {
    if (_disposed) return;
    _store.update(update);
  }

  Future<bool> load() async {
    final generation = ++_loadGeneration;
    _set((state) => state.copyWith(busy: true, clearError: true));
    try {
      final overview = await _repository.deckOverview();
      if (_disposed || generation != _loadGeneration) return false;
      _set((state) => state.copyWith(overview: overview, busy: false));
      return true;
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return false;
      _set(
        (state) =>
            state.copyWith(busy: false, error: 'Could not load review decks'),
      );
      return false;
    }
  }

  Future<bool> updateDailyLimits(ReviewDailyLimits limits) async {
    if (state.savingLimits) return false;
    _set((state) => state.copyWith(savingLimits: true, clearError: true));
    try {
      await _repository.updateDailyLimits(limits);
      if (_disposed) return false;
      _set((state) => state.copyWith(savingLimits: false));
      // The budget change moves every count on the page, so the page is
      // re-read rather than patched locally.
      return load();
    } catch (error) {
      _set(
        (state) => state.copyWith(
          savingLimits: false,
          error: 'Could not save the daily limits',
        ),
      );
      return false;
    }
  }

  Future<bool> importAnkiPackage({
    required String packagePath,
    required String mediaDirectory,
  }) async {
    if (state.busy) return false;
    _set(
      (state) =>
          state.copyWith(busy: true, clearError: true, clearReports: true),
    );
    try {
      final summary = await _repository.importAnkiPackage(
        packagePath: packagePath,
        mediaDirectory: mediaDirectory,
      );
      if (_disposed) return false;
      _set((state) => state.copyWith(busy: false, importSummary: summary));
      await load();
      return true;
    } catch (error) {
      _set(
        (state) => state.copyWith(
          busy: false,
          error: 'Could not import the Anki package',
        ),
      );
      return false;
    }
  }

  Future<bool> exportAnkiPackage(AnkiPackageExportRequest request) async {
    if (state.busy) return false;
    _set(
      (state) =>
          state.copyWith(busy: true, clearError: true, clearReports: true),
    );
    try {
      final summary = await _repository.exportAnkiPackage(request);
      if (_disposed) return false;
      _set((state) => state.copyWith(busy: false, exportSummary: summary));
      return true;
    } catch (error) {
      _set(
        (state) => state.copyWith(
          busy: false,
          error: 'Could not export the Anki package',
        ),
      );
      return false;
    }
  }

  void dismissReports() =>
      _set((state) => state.copyWith(clearReports: true, clearError: true));

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _store.dispose();
    super.dispose();
  }
}
