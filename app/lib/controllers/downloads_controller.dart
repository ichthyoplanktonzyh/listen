import 'package:flutter/foundation.dart';

import '../data/repositories/media_library_repository.dart';
import '../models/api_failure.dart';
import '../models/types.dart';
import '../services/acquisition_ledger.dart';
import '../services/media_file_service.dart';

/// One acquired-but-not-kept media, as the library surface shows it.
@immutable
class DownloadedMedia {
  const DownloadedMedia({
    required this.entryId,
    required this.sourceId,
    required this.itemId,
    required this.media,
  });

  /// The ledger's own key, so an action can name exactly the row it acts on.
  final String entryId;

  /// The feed this came from, and the item inside it. Both are already in
  /// [entryId]; they are split out so a surface can group by source without
  /// re-parsing the key.
  final String sourceId;
  final String itemId;

  /// What Core knows about the file. Temporary Material by definition — a
  /// retained media has left this list for the Personal Library.
  final MediaItem media;

  String get path => media.path;
  String get title => media.title;
  int? get durationMs => media.durationMs;
}

/// The downloads shelf: what acquisition put on this machine that the learner
/// has not kept.
///
/// This state had nowhere to be seen. An adopted download is registered with
/// Core as Temporary Material, which is absent from both the Personal Library
/// (retained materials) and the media library projection (retained media), so
/// the only trace of a downloaded episode outside its feed row was a line in
/// [AcquisitionLedger]. Downloading a season and then wondering where it went
/// was the expected outcome.
///
/// Membership here is deliberately *not* Personal Library membership. Keeping
/// is still the learner's explicit act; this only makes the in-between state
/// visible and gives it the two actions it needs — open it, or take the disk
/// space back.
class DownloadsController extends ChangeNotifier {
  DownloadsController({
    required AcquisitionLedger ledger,
    required MediaLibraryRepository repository,
    MediaFileService fileService = const LocalMediaFileService(),
  }) :
       // Collaborators are named publicly and stored privately.
       // ignore: prefer_initializing_formals
       _ledger = ledger,
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _fileService = fileService;

  final AcquisitionLedger _ledger;
  final MediaLibraryRepository _repository;
  final MediaFileService _fileService;

  /// Null until the first load finishes; empty means nothing is downloaded.
  /// The two are different sentences on the surface.
  List<DownloadedMedia>? _entries;
  List<DownloadedMedia>? get entries => _entries;

  ApiFailure? _failure;
  ApiFailure? get failure => _failure;

  bool _loading = false;
  bool get loading => _loading;

  bool _disposed = false;

  /// Monotonic load generation, so a slow refresh cannot publish over a newer
  /// one that already answered.
  int _generation = 0;

  /// Rebuilds the shelf from the ledger, confirming every row against Core and
  /// the disk.
  ///
  /// Rows that no longer hold up are dropped from the ledger as they are
  /// found: a media Core has forgotten, or a file that is gone, is not a
  /// download any more, and re-checking it on every visit for the life of the
  /// install is the other way to be wrong. A row that has since been kept
  /// leaves the shelf but keeps its ledger record — recognition in Discovery
  /// still needs it.
  Future<void> refresh() async {
    final generation = ++_generation;
    if (!_repository.isAvailable) {
      // Nothing can be confirmed without Core, and a list built from the
      // ledger alone would claim files nobody checked. Keep whatever the
      // surface already had.
      return;
    }
    _loading = true;
    if (!_disposed) notifyListeners();
    if (!_ledger.isLoaded) await _ledger.load();

    final rows = <DownloadedMedia>[];
    final stale = <String>[];
    ApiFailure? failure;
    for (final acquisition in _ledger.acquisitions) {
      if (_disposed || generation != _generation) return;
      final MediaItem? media;
      try {
        media = await _repository.findRegisteredMedia(acquisition.media.mediaId);
      } catch (error) {
        // A lookup that could not be made says nothing about this row. Record
        // the failure once and leave every unchecked row out rather than
        // reporting a half-list as the whole shelf.
        failure = _repository.failureDetail(error);
        break;
      }
      if (media == null || !_fileService.exists(media.path)) {
        stale.add(acquisition.entryId);
        continue;
      }
      if (media.isRetained) continue;
      final key = AcquisitionLedger.splitKey(acquisition.entryId);
      rows.add(
        DownloadedMedia(
          entryId: acquisition.entryId,
          sourceId: key.sourceId,
          itemId: key.itemId,
          media: media,
        ),
      );
    }
    for (final entryId in stale) {
      await _ledger.forget(entryId);
    }
    if (_disposed || generation != _generation) return;
    _loading = false;
    _failure = failure;
    if (failure == null) {
      // Newest first: the ledger keeps insertion order and nothing in it
      // carries a date, so the order things arrived in is the only real one.
      _entries = List.unmodifiable(rows.reversed);
    }
    notifyListeners();
  }

  /// Deletes one download's file and forgets it.
  ///
  /// Destructive and deliberate: the caller confirms with the learner first.
  /// Core's media row is left alone — there is no unregister, and a row whose
  /// file is gone already reads as gone everywhere the disk is checked.
  ///
  /// Returns false when the file is still there afterwards, so the caller can
  /// say the space was not reclaimed instead of quietly dropping the row.
  Future<bool> deleteDownload(DownloadedMedia entry) async {
    final removed = await _fileService.delete(entry.path);
    if (!removed) return false;
    await _ledger.forget(entry.entryId);
    if (_disposed) return true;
    final current = _entries;
    if (current != null) {
      _entries = List.unmodifiable([
        for (final row in current)
          if (row.entryId != entry.entryId) row,
      ]);
      notifyListeners();
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
