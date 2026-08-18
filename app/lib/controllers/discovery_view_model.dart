import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/discovery_repository.dart';
import '../data/repositories/learning_material_repository.dart';
import '../data/repositories/media_import_repository.dart';
import '../data/repositories/media_library_repository.dart';
import '../data/repositories/source_identity_repository.dart';
import '../controllers/download_controller.dart';
import '../models/discovery.dart';
import '../models/learning_material.dart';
import '../models/media_download.dart';
import '../models/media_resolution.dart';
import '../models/types.dart';
import '../models/api_failure.dart';
import '../models/source_identity.dart';
import '../services/acquisition_ledger.dart';
import '../services/document_decoding/document_format.dart';
import '../services/document_intake_flow.dart';
import '../services/document_intake_service.dart';
import '../services/media_file_service.dart';
import '../models/embedded_subtitle.dart';
import '../models/saved_vocabulary_count.dart';

/// Immutable snapshot of the discovery home.
@immutable
class DiscoveryState {
  DiscoveryState({
    this.loading = true,
    this.entriesLoading = false,
    this.resolvingUrl = false,
    this.resolveFailed = false,
    List<ContentSource> sources = const [],
    this.selectedSourceId,
    this.sourcesFailure,
    List<DiscoveryItem> entries = const [],
    this.selectedEntryId,
    this.entriesFailure,
    Map<String, ItemAcquisitionSnapshot> acquisitionSnapshots = const {},
  }) : sources = List.unmodifiable(sources),
       entries = List.unmodifiable(entries),
       acquisitionSnapshots = Map.unmodifiable(acquisitionSnapshots);

  /// The first catalog load — the surface has no sources yet.
  final bool loading;

  /// A channel's feed is in flight. Distinct from [loading]: the sources are
  /// already on screen, only the shelf below them is still unknown.
  final bool entriesLoading;

  final bool resolvingUrl;
  final bool resolveFailed;
  final List<ContentSource> sources;
  final String? selectedSourceId;

  /// Set when the catalog itself failed. An empty [sources] with no failure is
  /// an empty catalog; with one it is a broken surface.
  final ApiFailure? sourcesFailure;

  final List<DiscoveryItem> entries;
  final String? selectedEntryId;

  /// Set when the selected channel's feed failed. An empty [entries] with no
  /// failure means the channel is genuinely empty.
  final ApiFailure? entriesFailure;

  /// The observable acquisition state per item, mirrored from the acquisition
  /// machinery. Absent means nothing has been attempted: the item's state is
  /// derived from what its source grants.
  final Map<String, ItemAcquisitionSnapshot> acquisitionSnapshots;

  bool get hasSources => sources.isNotEmpty;

  ContentSource? sourceById(String id) {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  DiscoveryItem? entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  ContentSource? get selectedSource =>
      selectedSourceId == null ? null : sourceById(selectedSourceId!);

  DiscoveryItem? get selectedEntry =>
      selectedEntryId == null ? null : entryById(selectedEntryId!);

  /// Null while a download runs with no known total, so the surface can show
  /// an indeterminate bar rather than a fraction nobody measured.
  double? downloadProgressOf(String entryId) =>
      acquisitionSnapshots[entryId]?.progress;

  /// The item's acquisition state, derived when nothing has been attempted.
  DiscoveryItemState acquisitionStateOf(String entryId) {
    final snapshot = acquisitionSnapshots[entryId];
    if (snapshot != null) return snapshot.state;
    final entry = entryById(entryId);
    return entry?.acquisition == AcquisitionMode.none
        ? DiscoveryItemState.discoverable
        : DiscoveryItemState.acquirable;
  }

  /// Why the last acquisition attempt failed, for the row that offers a retry.
  ApiFailure? acquisitionFailureOf(String entryId) =>
      acquisitionSnapshots[entryId]?.failure;

  /// What an in-flight [DiscoveryItemState.acquiring] attempt is doing.
  ItemAcquisitionPhase acquisitionPhaseOf(String entryId) =>
      acquisitionSnapshots[entryId]?.phase ?? ItemAcquisitionPhase.download;

  /// Nullable fields take an explicit `clear*` flag: `selectedEntryId: null`
  /// cannot mean "drop the selection" when every field merges with `??`.
  DiscoveryState copyWith({
    bool? loading,
    bool? entriesLoading,
    bool? resolvingUrl,
    bool? resolveFailed,
    List<ContentSource>? sources,
    String? selectedSourceId,
    ApiFailure? sourcesFailure,
    bool clearSourcesFailure = false,
    List<DiscoveryItem>? entries,
    String? selectedEntryId,
    bool clearSelectedEntryId = false,
    ApiFailure? entriesFailure,
    bool clearEntriesFailure = false,
    Map<String, ItemAcquisitionSnapshot>? acquisitionSnapshots,
  }) => DiscoveryState(
    loading: loading ?? this.loading,
    entriesLoading: entriesLoading ?? this.entriesLoading,
    resolvingUrl: resolvingUrl ?? this.resolvingUrl,
    resolveFailed: resolveFailed ?? this.resolveFailed,
    sources: sources ?? this.sources,
    selectedSourceId: selectedSourceId ?? this.selectedSourceId,
    sourcesFailure: clearSourcesFailure
        ? null
        : sourcesFailure ?? this.sourcesFailure,
    entries: entries ?? this.entries,
    selectedEntryId: clearSelectedEntryId
        ? null
        : selectedEntryId ?? this.selectedEntryId,
    entriesFailure: clearEntriesFailure
        ? null
        : entriesFailure ?? this.entriesFailure,
    acquisitionSnapshots: acquisitionSnapshots ?? this.acquisitionSnapshots,
  );
}

/// One recognised local media plus how it was recognised.
///
/// [fromMapping] is true only when Core's Source Identity answered. A match
/// found any other way means the canonical key is still unwritten, which is
/// the signal to try recording it again.
typedef LocalMediaMatch = ({MediaItem media, bool fromMapping});

/// Owns the content discovery presentation state.
///
/// Discovery's responsibility ends at "which content, and can we get its
/// bytes on this machine". Whether those bytes are learnable — transcript
/// present, one or several, needs generation — is Workbench's fact, owned by
/// the workbench layer after the content opens. This view model therefore
/// knows nothing about packages, generation, or listen-gen.
///
/// Identity is source-scoped: an item's canonical identity is its source plus
/// its own id, and everything else the feed said is typed evidence. When an
/// item's content is acquired and converged on a Material, that mapping is
/// recorded through [SourceIdentityRepository] so a later refresh resolves
/// the same Material instead of creating a second one.
final class DiscoveryViewModel extends ChangeNotifier {
  /// Collaborators are named rather than positional: the list had grown to
  /// seven interchangeable nullable objects, and call sites were reading
  /// `(repo, imports, library, null, identities, materials)` — a shape where
  /// one misplaced argument is a silent behaviour change.
  DiscoveryViewModel(
    this._repository, {
    MediaImportRepository? importRepository,
    MediaLibraryRepository? mediaLibraryRepository,
    AcquisitionLedger? ledger,
    SourceIdentityRepository? sourceIdentity,
    LearningMaterialRepository? learningMaterial,
    DocumentIntakeFileService? documentFileService,
    DocumentIntakeFlow? documentIntake,
    MediaFileService fileService = const LocalMediaFileService(),
    Future<String?> Function()? downloadsDirectory,
  }) : _ledger = ledger ?? AcquisitionLedger.inMemory(),
       // ignore: prefer_initializing_formals
       _downloadsDirectory = downloadsDirectory,
       _importRepository =
           importRepository ?? const _FakeMediaImportRepository(),
       _mediaLibraryRepository =
           mediaLibraryRepository ?? const _FakeMediaLibraryRepository(),
       // ignore: prefer_initializing_formals
       _sourceIdentity = sourceIdentity,
       // ignore: prefer_initializing_formals
       _learningMaterial = learningMaterial,
       // ignore: prefer_initializing_formals
       _documentFileService = documentFileService,
       // ignore: prefer_initializing_formals
       _documentIntake = documentIntake,
       // ignore: prefer_initializing_formals
       _fileService = fileService;

  final DiscoveryRepository _repository;
  final MediaImportRepository _importRepository;
  final MediaLibraryRepository _mediaLibraryRepository;

  /// Where an acquisition writes, resolved per download from the persisted
  /// downloads location.
  ///
  /// Absent in previews and in tests that do not care, which fall back to the
  /// folder chooser — the behaviour the whole app used to have. That is what
  /// made the picker reopen on the first download of every launch: the answer
  /// lived in a field on this object and died with it.
  final Future<String?> Function()? _downloadsDirectory;

  /// Confirms a recognised media's bytes are still on disk.
  ///
  /// Core records a media row, never the file's continued existence: nothing
  /// tells it that a folder was emptied. So "Core knows this media" and "the
  /// episode is on this machine" are two questions, and only the second one
  /// is what a row claiming *available* is promising.
  final MediaFileService _fileService;

  /// Reads downloaded article files for the document intake path. Absent in
  /// widget previews; an article item then has no way to acquire its bytes.
  final DocumentIntakeFileService? _documentFileService;

  /// The shared document intake — the same decode/bind/create an article and
  /// a locally picked file travel. Absent in widget previews.
  final DocumentIntakeFlow? _documentIntake;

  /// The Core Source Identity boundary, when the composition root supplied
  /// one. Absent in widget previews; the ledger and the local-media lookup
  /// then answer for recognition alone.
  final SourceIdentityRepository? _sourceIdentity;

  /// Reads the Material a discovered item converged on, to complete the
  /// identity mapping and to recognise already-converged items. Absent in
  /// widget previews.
  final LearningMaterialRepository? _learningMaterial;

  /// What earlier sessions acquired, so a restart does not offer a download
  /// that already happened.
  final AcquisitionLedger _ledger;

  static const customSource = ContentSource(
    id: 'custom_imports',
    name: 'Imports',
    language: 'en',
    description: 'Items imported by pasting a link.',
    cover: ChannelCoverTone.slate,
    kind: ContentSourceKind.youtube,
    avatarUrl: null,
  );

  DiscoveryState _state = DiscoveryState();
  DiscoveryState get state => _state;

  final Map<String, String> _localPaths = {};
  final Map<String, String> _mediaIds = {};
  final Map<String, String> _fingerprints = {};

  /// The Material an article item converged on (taken in through the document
  /// intake), keyed by entry id. A document item's content is a Material, not
  /// a media file, so opening it never goes through the media path.
  final Map<String, String> _documentMaterialIds = {};

  final Map<String, int?> _mediaDurations = {};
  final Map<String, DownloadController> _downloadControllers = {};

  /// Per-entry single-flight for the "start learning" intent: one intent owns
  /// one acquisition, and a second caller joins the same future instead of
  /// starting a second download.
  final Map<String, Completer<DiscoveryOpenTarget?>> _acquisitionCompleters =
      {};

  /// Per-entry in-flight local-media checks, so a reconnect recheck and a
  /// selection-triggered check share one lookup and callers can await it.
  final Map<String, Future<void>> _availabilityChecks = {};

  /// Which launch attempt is currently awaiting its download handle, per
  /// entry. Present while a `startDownload` is between `controller.starting()`
  /// and `controller.attach()` — the window where the controller has no
  /// downloading state yet and a second caller must join instead of relaunch.
  ///
  /// The value is the attempt token: cancellation bumps the token so the
  /// pending launch sees itself as stale when its handle finally lands.
  final Map<String, int> _launchesInFlight = {};

  /// Monotonic per-entry launch token. A launch records the token it started
  /// with; `cancelDownload` bumps it to invalidate the in-flight launch. A
  /// handle that returns after its token was bumped belongs to an attempt
  /// nobody wants and is dropped without attach or adoption.
  final Map<String, int> _launchTokens = {};

  final List<DiscoveryItem> _customEntries = [];
  bool _disposed = false;

  /// The source each entry id belongs to, remembered across channel switches.
  ///
  /// Recognition keys are source-scoped: two different feeds may publish the
  /// same item id (`ep-001` on two shows), and a record written for one must
  /// never answer for the other. This registry is how a row keeps its source
  /// once its channel's entries have been replaced by another channel's.
  final Map<String, String> _entrySources = {};

  /// The source-scoped recognition key of a row: the source identity plus the
  /// item identity. Item ids are unique inside a source, never across sources.
  String _rowKey(String entryId) => AcquisitionLedger.keyFor(
    sourceId: _entrySources[entryId] ?? '',
    itemId: entryId,
  );

  Future<void> load() async {
    if (!_ledger.isLoaded) await _ledger.load();
    _state = _state.copyWith(loading: true, clearSourcesFailure: true);
    notifyListeners();

    final List<ContentSource> repoSources;
    try {
      repoSources = await _repository.sources();
    } catch (error) {
      // A catalog that failed is not a catalog that is empty, and leaving
      // `loading` set would spin forever.
      debugPrint('Error loading discovery sources: $error');
      if (_disposed) return;
      _state = _state.copyWith(
        loading: false,
        sourcesFailure: ApiFailure(raw: error.toString()),
      );
      notifyListeners();
      return;
    }
    if (_disposed) return;

    final allSources = [...repoSources, customSource];
    final first = allSources.isEmpty ? null : allSources.first.id;

    _state = _state.copyWith(
      loading: false,
      sources: allSources,
      selectedSourceId: first,
    );

    if (first != null) {
      await _loadEntriesFor(first);
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> selectChannel(String sourceId) async {
    if (sourceId == _state.selectedSourceId) return;

    _state = _state.copyWith(
      selectedSourceId: sourceId,
      clearSelectedEntryId: true,
    );
    notifyListeners();
    await _loadEntriesFor(sourceId);
  }

  /// Re-runs the selected channel's feed after a failure.
  Future<void> retryEntries() async {
    final sourceId = _state.selectedSourceId;
    if (sourceId == null) return;
    await _loadEntriesFor(sourceId);
  }

  /// Refreshes the selected source: drops its cached feed state and re-reads
  /// the items from the source. A feed that changed since the last read (new
  /// items, edited metadata) is what the next shelf shows.
  Future<void> refreshSource() async {
    final sourceId = _state.selectedSourceId;
    if (sourceId == null) return;
    try {
      await _repository.refreshSource(sourceId);
    } catch (error) {
      // A refresh that fails to drop is not a refresh that failed to show:
      // the entries reload below either way, and its failure is theirs.
      debugPrint('Error refreshing source $sourceId: $error');
    }
    await _loadEntriesFor(sourceId);
  }

  Future<void> _loadEntriesFor(String sourceId) async {
    // The old channel's cards stop standing in for the new one's while its
    // header is already on screen.
    _state = _state.copyWith(
      entriesLoading: true,
      entries: const [],
      clearSelectedEntryId: true,
      clearEntriesFailure: true,
    );
    notifyListeners();

    final List<DiscoveryItem> entries;
    try {
      entries = sourceId == customSource.id
          ? List<DiscoveryItem>.of(_customEntries)
          : await _repository.entriesFor(sourceId);
    } catch (error) {
      debugPrint('Error loading entries for channel $sourceId: $error');
      if (_disposed || sourceId != _state.selectedSourceId) return;
      _state = _state.copyWith(
        entriesLoading: false,
        entriesFailure: ApiFailure(raw: error.toString()),
      );
      notifyListeners();
      return;
    }
    if (_disposed) return;
    // A slow channel must not land on top of the one the learner switched to.
    if (sourceId != _state.selectedSourceId) return;

    for (final entry in entries) {
      _entrySources[entry.id] = sourceId;
    }
    _state = _state.copyWith(
      entriesLoading: false,
      entries: entries,
      selectedEntryId: entries.isEmpty ? null : entries.first.id,
      clearSelectedEntryId: entries.isEmpty,
    );
    notifyListeners();
    unawaited(_reconcileShelf(sourceId, entries));
    unawaited(_hydrateLocalDurations(entries));
    unawaited(_resolveRemoteDurations(sourceId, entries));
  }

  /// How many rows of a shelf are reconciled against local media at once.
  ///
  /// Each row is a couple of small local lookups, so this is about not opening
  /// two hundred of them in the same tick, not about a rate limit.
  static const _shelfReconcileConcurrency = 4;

  /// Reconciles every row of the shelf, not only the selected one.
  ///
  /// Only the selected entry used to be checked, so a shelf of episodes the
  /// learner had already downloaded rendered with a download button on every
  /// row but one — the app had the answer and never asked for it. The selected
  /// row goes first because it is the one being read, and the rest follow.
  ///
  /// The workers belong to [sourceId]: once the learner has switched channels
  /// these rows are off screen, and their answers would land on a shelf nobody
  /// is looking at.
  Future<void> _reconcileShelf(
    String sourceId,
    List<DiscoveryItem> entries,
  ) async {
    if (entries.isEmpty) return;
    await refreshMediaAvailability(entries.first.id);
    // Nothing to ask without the core, and the row above already reported
    // that. Fanning out would only rewrite the same unavailable answer onto
    // every remaining row.
    if (!_mediaLibraryRepository.isAvailable) return;
    var index = 1;
    await Future.wait(
      List.generate(_shelfReconcileConcurrency, (_) async {
        while (!_disposed && _state.selectedSourceId == sourceId) {
          final next = index++;
          if (next >= entries.length) return;
          await refreshMediaAvailability(
            entries[next].id,
            announceChecking: false,
          );
        }
      }),
    );
  }

  void selectItem(String entryId) {
    if (entryId == _state.selectedEntryId) return;

    _state = _state.copyWith(selectedEntryId: entryId);
    notifyListeners();
    final state = _state.acquisitionStateOf(entryId);
    if (state == DiscoveryItemState.available ||
        state == DiscoveryItemState.acquirable ||
        state == DiscoveryItemState.discoverable) {
      unawaited(refreshMediaAvailability(entryId));
    }
  }

  /// Reconciles whether [entryId]'s content exists on this machine.
  ///
  /// The only question asked is "is the content local". Whether it has a
  /// transcript is never consulted: local content whose primary learning
  /// track is not set is still local and still learnable. Workbench decides
  /// whether a transcript is needed after the content opens.
  ///
  /// Result states:
  ///
  /// * core/library unavailable → [DiscoveryItemState.unavailable]
  /// * library query failed → [DiscoveryItemState.unavailable]
  /// * matching local media found → [DiscoveryItemState.available], with
  ///   `_localPaths`/`_mediaIds` filled, the ledger recorded, and the
  ///   acquisition snapshot projected to available
  /// * no match → back to the derived state ([DiscoveryItemState.acquirable]
  ///   or [DiscoveryItemState.discoverable])
  ///
  /// [announceChecking] publishes the in-progress check as a visible state.
  /// A check the learner asked for (selecting the row, the detail panel's
  /// recheck) should say it is working; the shelf-wide background pass should
  /// not — a check is not a download, and the row renders an acquiring state
  /// as a progress bar with a cancel button.
  Future<void> refreshMediaAvailability(
    String entryId, {
    bool announceChecking = true,
  }) {
    final inFlight = _availabilityChecks[entryId];
    if (inFlight != null) return inFlight;
    late final Future<void> future;
    future = _refreshMediaAvailability(
      entryId,
      announceChecking: announceChecking,
    ).whenComplete(() {
      if (identical(_availabilityChecks[entryId], future)) {
        _availabilityChecks.remove(entryId);
      }
    });
    _availabilityChecks[entryId] = future;
    return future;
  }

  /// The same reconciliation for whatever entry is selected, so a meaningful
  /// invalidation (core reconnect, entry change) can re-ask without polling.
  Future<void> refreshSelectedMediaAvailability() async {
    final selectedId = _state.selectedEntryId;
    if (selectedId == null) return;
    await refreshMediaAvailability(selectedId);
  }

  Future<void> _refreshMediaAvailability(
    String entryId, {
    required bool announceChecking,
  }) async {
    // Without the core there is nothing to ask, so the answer stays missing —
    // "not on this machine" would be a guess dressed up as a fact.
    if (!_mediaLibraryRepository.isAvailable) {
      _setSnapshot(entryId, ItemAcquisitionSnapshot.failedUnavailable);
      return;
    }
    if (announceChecking) {
      _setSnapshot(entryId, ItemAcquisitionSnapshot.checking);
    }

    final item = _state.entryById(entryId);
    if (item?.acquisition == AcquisitionMode.article) {
      await _refreshArticleAvailability(entryId, item!);
      return;
    }

    final LocalMediaMatch? local;
    try {
      local = await _findLocalMedia(entryId);
    } catch (error) {
      debugPrint('Error searching local media entry: $error');
      if (_disposed) return;
      _setSnapshot(entryId, ItemAcquisitionSnapshot.failedUnavailable);
      return;
    }
    if (_disposed) return;

    if (local == null) {
      // Definitive answer: this entry's content is not on this machine. Any
      // local identity from an earlier, now-refuted answer must go with it —
      // a stale path would let Start Learning open a file Core no longer
      // knows about, and a projected "available" snapshot would keep saying
      // "on this device" after the media is gone. The check is over, so a
      // snapshot this check left behind (checking, or an available projection)
      // goes too: without a snapshot the item state derives from what its
      // source grants. A live download is the acquisition lifecycle's own
      // fact and survives the reconciliation.
      final hadLocal =
          _localPaths.remove(entryId) != null ||
          _mediaIds.remove(entryId) != null;
      final snapshots = Map<String, ItemAcquisitionSnapshot>.of(
        _state.acquisitionSnapshots,
      );
      final current = snapshots[entryId];
      if (current == null ||
          current.phase != ItemAcquisitionPhase.download) {
        snapshots.remove(entryId);
      }
      // A row that had nothing and still has nothing changed nothing. The
      // shelf-wide pass reconciles every entry of a two-hundred-item feed, and
      // most of them are simply not downloaded — rebuilding the surface once
      // per unremarkable answer would be the whole cost of the reconciliation.
      if (!hadLocal && snapshots.length == _state.acquisitionSnapshots.length) {
        return;
      }
      _state = _state.copyWith(acquisitionSnapshots: snapshots);
      notifyListeners();
      return;
    }

    // Content already on disk reads as an acquisition that is done, whether
    // this session downloaded it or a previous one did.
    final finished = Map<String, ItemAcquisitionSnapshot>.of(
      _state.acquisitionSnapshots,
    )..[entryId] = const ItemAcquisitionSnapshot(
      DiscoveryItemState.available,
      progress: 1,
    );
    _localPaths[entryId] = local.media.path;
    _mediaIds[entryId] = local.media.id;
    _fingerprints[entryId] = local.media.fingerprint;
    unawaited(
      _ledger.record(
        _rowKey(entryId),
        mediaId: local.media.id,
        path: local.media.path,
      ),
    );
    _mediaDurations[entryId] = local.media.durationMs;

    _state = _state.copyWith(acquisitionSnapshots: finished);
    notifyListeners();

    // Recognition that did not come from the canonical mapping means Core has
    // no mapping yet — adoption asks for one the moment the media is
    // registered, which is before any Material is bound to it, so the first
    // attempt always comes back empty. The Material is created later, when
    // the workbench opens the content; this is the retry that finally writes
    // the canonical key down, and it is what stops recognition depending on
    // the app's own ledger forever.
    if (!local.fromMapping) {
      unawaited(_recordIdentity(entryId, fileSha256: local.media.fingerprint));
    }
  }

  void _setSnapshot(String entryId, ItemAcquisitionSnapshot snapshot) {
    if (_disposed) return;
    _state = _state.copyWith(
      acquisitionSnapshots: {
        ..._state.acquisitionSnapshots,
        entryId: snapshot,
      },
    );
    notifyListeners();
  }

  /// Reconciles a document item against Core's Source Identity: a recorded
  /// mapping whose Material still holds a source Document Rendition is
  /// content this machine owns, so the row reads available and opens through
  /// the document session. A missing mapping — or a mapping whose Material no
  /// longer carries the document — is the definitive not-on-this-machine
  /// answer; the row falls back to its derived acquirable state.
  Future<void> _refreshArticleAvailability(
    String entryId,
    DiscoveryItem item,
  ) async {
    final materialId = await _resolveArticleMaterial(item);
    if (_disposed) return;
    if (materialId == null) {
      _documentMaterialIds.remove(entryId);
      final snapshots = Map<String, ItemAcquisitionSnapshot>.of(
        _state.acquisitionSnapshots,
      );
      final current = snapshots[entryId];
      if (current == null ||
          current.phase != ItemAcquisitionPhase.download) {
        snapshots.remove(entryId);
      }
      _state = _state.copyWith(acquisitionSnapshots: snapshots);
      notifyListeners();
      return;
    }
    _documentMaterialIds[entryId] = materialId;
    _setSnapshot(
      entryId,
      const ItemAcquisitionSnapshot(
        DiscoveryItemState.available,
        progress: 1,
      ),
    );
  }

  /// The Material a document item converged on, when the mapping resolves to
  /// one that still holds a source document rendition.
  Future<String?> _resolveArticleMaterial(DiscoveryItem item) async {
    final sourceIdentity = _sourceIdentity;
    final learningMaterial = _learningMaterial;
    if (sourceIdentity == null || learningMaterial == null) return null;
    if (!sourceIdentity.isAvailable) return null;

    final SourceIdentityMapping? mapping;
    try {
      mapping = await sourceIdentity.resolveMapping(
        sourceId: item.sourceId,
        itemId: item.id,
      );
    } catch (error) {
      // A lookup that failed is not "no mapping"; keep the answer honest by
      // answering nothing rather than claiming this item was never acquired.
      debugPrint('Error resolving source identity: $error');
      return null;
    }
    if (mapping == null) return null;

    final MaterialDetails details;
    try {
      details = await learningMaterial.readLearningMaterial(
        mapping.materialId,
      );
    } catch (error) {
      debugPrint('Error reading mapped material: $error');
      return null;
    }
    final hasSourceRendition = details.currentRevision.documentRenditions.any(
      (rendition) => rendition.origin == RenditionOrigin.source,
    );
    return hasSourceRendition ? mapping.materialId : null;
  }

  /// Recognises media this app downloaded for [entryId] in an earlier session.
  ///
  /// Throws when the lookup could not be made; the caller turns that into an
  /// unavailable answer rather than a claim.
  ///
  /// The canonical mapping answers first when the core recorded one: intake
  /// wrote down which Material this source item resolved to, and the media
  /// bound to that Material is the item's content. When the core has no
  /// mapping — an older core, a preview, a mapping written only after the
  /// Material existed — the app's own written record answers next: the app
  /// knows what it downloaded, so it does not have to re-derive it from a
  /// filename. yt-dlp's `[id]` convention stays as the fallback that
  /// recognises media acquired before either record existed, and it only ever
  /// applied to the external-tool path — an enclosure is saved under the
  /// publisher's filename, which has nothing to do with the feed's guid.
  ///
  /// Every candidate is confirmed against Core's *registered* media, never
  /// against the Personal Library listing. The library projection is retained
  /// media only, and an adopted download is deliberately Temporary Material
  /// (`retain: false`, CONTEXT.md Retention Decision) — so asking the library
  /// whether a downloaded episode exists always answered no, the ledger row
  /// was then dropped as stale, and the next visit offered the very download
  /// that had already happened. (Core's own contract test states the rule:
  /// `temporary_registration_is_readable_but_absent_from_library`.)
  ///
  /// Being known to Core is still not the same as being on disk. Core records
  /// a path, never the file's continued existence, so the bytes are confirmed
  /// too: a person who emptied a folder did not consult this file first, and a
  /// row that claimed a file that is gone would be exactly the kind of
  /// confident lie the ledger exists to avoid.
  Future<LocalMediaMatch?> _findLocalMedia(String entryId) async {
    final item = _state.entryById(entryId);
    if (item != null) {
      final resolved = await _resolveIdentity(item);
      if (resolved != null) {
        return (media: resolved, fromMapping: true);
      }
    }

    final recorded = _ledger[_rowKey(entryId)];
    if (recorded != null) {
      final media = await _registeredMediaOnDisk(recorded.mediaId);
      if (media != null) return (media: media, fromMapping: false);
      // Core no longer knows this media, or its file is gone: drop the record
      // rather than re-check this row on every visit for the life of the
      // install.
      await _ledger.forget(_rowKey(entryId));
    }

    if (item?.acquisition != AcquisitionMode.externalTool) return null;
    // The filename convention is the only recognition path with nothing to
    // look up by id, so it is the one case that still has to scan. It reads
    // the Personal Library, which is all this fallback ever saw: it exists for
    // media acquired before either record was written, and such media is only
    // still findable if the learner kept it.
    for (final libraryEntry in await _mediaLibraryRepository
        .listMediaLibrary()) {
      if (libraryEntry.media.path.contains('[$entryId]') &&
          _fileService.exists(libraryEntry.media.path)) {
        return (media: libraryEntry.media, fromMapping: false);
      }
    }
    return null;
  }

  /// The registered media with [mediaId] when Core still holds it and its file
  /// is still on disk; null when either answer is no.
  ///
  /// Throws when the lookup itself could not be made, so a core that went away
  /// mid-check never reads as "the episode is gone".
  Future<MediaItem?> _registeredMediaOnDisk(String mediaId) async {
    final media = await _mediaLibraryRepository.findRegisteredMedia(mediaId);
    if (media == null) return null;
    return _fileService.exists(media.path) ? media : null;
  }

  /// Asks Core's Source Identity surface whether this item was already
  /// converged on a Material, and returns that Material's registered media
  /// when its bytes are still on this machine.
  Future<MediaItem?> _resolveIdentity(DiscoveryItem item) async {
    final sourceIdentity = _sourceIdentity;
    final learningMaterial = _learningMaterial;
    if (sourceIdentity == null || learningMaterial == null) return null;
    if (!sourceIdentity.isAvailable) return null;

    final SourceIdentityMapping? mapping;
    try {
      mapping = await sourceIdentity.resolveMapping(
        sourceId: item.sourceId,
        itemId: item.id,
      );
    } catch (error) {
      // A mapping lookup that failed is not "no mapping": keep the answer
      // honest by falling through to the other records rather than claiming
      // this item was never acquired.
      debugPrint('Error resolving source identity: $error');
      return null;
    }
    if (mapping == null) return null;

    // The mapping names a Material; the item's bytes are one of that
    // Material's registered media rows. A mapping whose Material is gone
    // (a reset core) is not the item's content — the other records answer.
    final MaterialDetails details;
    try {
      details = await learningMaterial.readLearningMaterial(
        mapping.materialId,
      );
    } catch (error) {
      debugPrint('Error reading mapped material: $error');
      return null;
    }
    for (final rendition in details.currentRevision.mediaRenditions) {
      final mediaId = rendition.mediaId;
      if (mediaId == null) continue;
      final MediaItem? media;
      try {
        media = await _registeredMediaOnDisk(mediaId);
      } catch (error) {
        // The mapping is good but this rendition could not be checked. Say
        // nothing rather than claim the item was never acquired; the ledger
        // answers next, and a later refresh asks again.
        debugPrint('Error reading mapped media: $error');
        return null;
      }
      if (media != null) return media;
    }
    return null;
  }

  /// One [DownloadController] per entry: several rows can be acquiring at once,
  /// and each needs its own generation guard so a late callback from a
  /// cancelled or superseded run cannot land on the row that replaced it.
  DownloadController _downloadControllerFor(String entryId) =>
      _downloadControllers.putIfAbsent(entryId, () {
        final controller = DownloadController(
          failureMapper: _importRepository.failureDetail,
          // A discovery row stays on screen, so its failure waits for a retry
          // instead of quietly timing out from under the learner.
          failedAutoDismiss: null,
        );
        controller.addListener(
          () => _publishDownloadSnapshot(entryId, controller.snapshot),
        );
        return controller;
      });

  void _publishDownloadSnapshot(
    String entryId,
    DownloadStatusSnapshot? value,
  ) {
    if (_disposed) return;
    final snapshots = Map<String, ItemAcquisitionSnapshot>.of(
      _state.acquisitionSnapshots,
    );
    if (value == null) {
      snapshots.remove(entryId);
    } else {
      snapshots[entryId] = switch (value.kind) {
        DownloadStatusKind.downloading => ItemAcquisitionSnapshot(
          DiscoveryItemState.acquiring,
          progress: value.progress,
        ),
        DownloadStatusKind.completed => ItemAcquisitionSnapshot(
          DiscoveryItemState.available,
          progress: value.progress,
        ),
        DownloadStatusKind.failed => ItemAcquisitionSnapshot(
          DiscoveryItemState.failed,
          failure: value.failure,
        ),
      };
      if (value.kind == DownloadStatusKind.failed) {        // A failed attempt ends the "start learning" intent without a path;
        // Workbench must not open for an acquisition that never landed. The
        // typed failure stays in the download state for the retry surface.
        _completeAcquisition(entryId, null);
      }
    }
    _state = _state.copyWith(acquisitionSnapshots: snapshots);
    notifyListeners();
  }

  /// Also the retry: a failed row calls straight back into this.
  ///
  /// Which acquisition runs is the entry's own fact, not the app's default. A
  /// podcast enclosure is fetched directly because the publisher put it in
  /// the feed for that; a YouTube page goes to the user's external tool; a
  /// document item's page is fetched for its article. An item with nothing to
  /// acquire never starts one.
  Future<void> startDownload(String entryId) async {
    if (_state.acquisitionStateOf(entryId) == DiscoveryItemState.available) {
      return;
    }
    // Established single-flight: once a handle is attached the controller is
    // in `acquiring`, and restarting it would cancel the live handle and
    // relaunch. A joiner (e.g. `acquireForLearning`) waits on the acquisition
    // completer instead, which the original handle's adoption resolves. A
    // local-media check in flight does not count: it is a lookup, not an
    // acquisition, and the download it answers for has not started.
    final live = _state.acquisitionSnapshots[entryId];
    if (live?.state == DiscoveryItemState.acquiring &&
        live?.phase == ItemAcquisitionPhase.download) {
      return;
    }
    // Launch-window single-flight: another attempt is still between
    // `controller.starting()` and `controller.attach()`. A launch whose token
    // was invalidated by a cancel is not in flight anymore and may be
    // superseded by a fresh attempt.
    final inFlight = _launchesInFlight[entryId];
    if (inFlight != null && inFlight == _launchTokens[entryId]) return;

    final entry = _state.entryById(entryId);
    if (entry == null) {
      _completeAcquisition(entryId, null);
      return;
    }

    switch (entry.acquisition) {
      case AcquisitionMode.enclosure:
        await _launchMediaDownload(entry);
      case AcquisitionMode.externalTool:
        await _launchMediaDownload(entry);
      case AcquisitionMode.article:
        await _launchArticleAcquisition(entry);
      case AcquisitionMode.none:
        _completeAcquisition(entryId, null);
    }
  }

  Future<void> _launchMediaDownload(DiscoveryItem entry) async {
    final mediaUrl = entry.mediaUrl;
    if (mediaUrl == null) {
      _completeAcquisition(entry.id, null);
      return;
    }
    final controller = _downloadControllerFor(entry.id);
    controller.starting();
    final token = (_launchTokens[entry.id] ?? 0) + 1;
    _launchTokens[entry.id] = token;
    _launchesInFlight[entry.id] = token;

    try {
      final directory = await _resolveDownloadsDirectory();
      if (_disposed) {
        _completeAcquisition(entry.id, null);
        return;
      }
      if (directory == null) {
        // No place to write: a custom downloads folder that is off disk and a
        // chooser the learner dismissed both end the intent without a path.
        _completeAcquisition(entry.id, null);
        return;
      }

      final handle = switch (entry.acquisition) {
        AcquisitionMode.enclosure => await _importRepository
            .downloadEnclosure(
              mediaUrl,
              directory,
              expectedBytes: entry.mediaByteLength,
            ),
        AcquisitionMode.externalTool => await _importRepository
            .downloadOnlineMedia(mediaUrl, directory),
        _ => throw StateError('guarded above'),
      };
      if (_disposed) {
        handle.cancel();
        _completeAcquisition(entry.id, null);
        return;
      }
      // A cancel during the launch window invalidated this attempt: the
      // handle belongs to nobody and must be dropped without attach, without
      // adoption, and without disturbing the cancelled state.
      if (!_isCurrentLaunch(entry.id, token)) {
        handle.cancel();
        return;
      }

      controller.attach(
        progress: handle.progress,
        completed: handle.completed,
        cancel: handle.cancel,
        onCompleted: (path) =>
            unawaited(_adoptDownloadedMedia(entry.id, path)),
      );
    } catch (error) {
      debugPrint('Error starting download: $error');
      if (_disposed) return;
      // Only a current attempt may surface its launch failure. A stale launch
      // that errors after a cancel must not flip the cancelled/none state to
      // failed.
      if (_isCurrentLaunch(entry.id, token)) {
        controller.fail(_importRepository.failureDetail(error));
      }
    } finally {
      // Remove this attempt's own marker only: a newer attempt that started
      // while this one was still finishing keeps its bookkeeping.
      if (_launchesInFlight[entry.id] == token) {
        _launchesInFlight.remove(entry.id);
      }
    }
  }

  /// Acquires a document item: fetches the article page and takes it in
  /// through the same document intake path a local file would travel.
  ///
  /// The article is never a media file: it is decoded, bound, and created as
  /// a Document Material exactly as a picked file would be — no media
  /// registration, no ffprobe of an HTML page. Intake never implies retention
  /// (the create is explicit non-retained), and the canonical source identity
  /// is recorded once the Material exists.
  Future<void> _launchArticleAcquisition(DiscoveryItem entry) async {
    final entryUrl = entry.entryUrl;
    final intake = _documentIntake;
    final files = _documentFileService;
    if (entryUrl == null || intake == null || files == null) {
      _completeAcquisition(entry.id, null);
      return;
    }
    final controller = _downloadControllerFor(entry.id);
    controller.starting();
    final token = (_launchTokens[entry.id] ?? 0) + 1;
    _launchTokens[entry.id] = token;
    _launchesInFlight[entry.id] = token;

    try {
      final directory = await _resolveDownloadsDirectory();
      if (_disposed) {
        _completeAcquisition(entry.id, null);
        return;
      }
      if (directory == null) {
        // No place to write: a custom downloads folder that is off disk and a
        // chooser the learner dismissed both end the intent without a path.
        _completeAcquisition(entry.id, null);
        return;
      }
      final path = await _importRepository.downloadArticle(
        entryUrl,
        directory,
      );
      if (_disposed || path == null) {
        _completeAcquisition(entry.id, null);
        return;
      }
      if (!_isCurrentLaunch(entry.id, token)) return;

      final read = await files.readDocumentFile(path);
      if (_disposed || !_isCurrentLaunch(entry.id, token)) return;
      switch (read) {
        case DocumentFileCancelled():
          _completeAcquisition(entry.id, null);
        case DocumentFileFailure(:final failure):
          controller.fail(_importRepository.failureDetail(failure));
        case DocumentFileData(:final bytes):
          final format = formatForPath(path);
          if (format == null) {
            controller.fail(
              _importRepository.failureDetail(
                StateError('unsupported article format: $path'),
              ),
            );
            return;
          }
          final outcome = await intake.takeInDocument(
            title: entry.title,
            bytes: bytes,
            format: format,
          );
          if (_disposed || !_isCurrentLaunch(entry.id, token)) return;
          _documentMaterialIds[entry.id] = outcome.details.material.id;
          _setSnapshot(
            entry.id,
            const ItemAcquisitionSnapshot(
              DiscoveryItemState.available,
              progress: 1,
            ),
          );
          _completeAcquisition(
            entry.id,
            DiscoveryOpenTarget.document(outcome.details.material.id),
          );
          unawaited(
            _recordIdentity(
              entry.id,
              materialId: outcome.details.material.id,
              materialRevisionId: outcome.details.material.currentRevisionId,
              fileSha256: outcome.sha256Digest,
            ),
          );
      }
    } catch (error) {
      debugPrint('Error acquiring article: $error');
      if (_disposed) return;
      if (_isCurrentLaunch(entry.id, token)) {
        controller.fail(_importRepository.failureDetail(error));
      }
    } finally {
      if (_launchesInFlight[entry.id] == token) {
        _launchesInFlight.remove(entry.id);
      }
    }
  }

  /// The folder this acquisition writes into.
  ///
  /// Falls back to the chooser when no resolver was injected, so a preview or
  /// a test that never wired settings still behaves the way it always did.
  Future<String?> _resolveDownloadsDirectory() async {
    final resolve = _downloadsDirectory;
    if (resolve != null) return resolve();
    return _importRepository.pickDownloadDirectory(confirmButtonText: 'Select');
  }

  bool _isCurrentLaunch(String entryId, int token) =>
      !_disposed && _launchTokens[entryId] == token;

  /// The "start learning" intent, as a future that resolves to an openable
  /// target.
  ///
  /// Semantics:
  ///
  /// * content already local → returns the target without touching the
  ///   acquisition machinery: registered media for a media item, the Material
  ///   for a document item;
  /// * remote and acquirable → starts (or joins) one acquisition, waits for
  ///   probe → Core registration (or document intake) → ledger/mapping, then
  ///   returns the target;
  /// * cancelled / failed / unacquirable → null; the typed failure (if any)
  ///   is already in the acquisition state for the surface to show and retry.
  ///
  /// Workbench opening is the caller's decision: this only guarantees local
  /// content, and a non-null result is the signal to open it.
  Future<DiscoveryOpenTarget?> acquireForLearning(String entryId) async {
    // Let an in-flight local-media check land first: content already on disk
    // must not be re-downloaded because the check lost the race.
    final inFlightCheck = _availabilityChecks[entryId];
    if (inFlightCheck != null) await inFlightCheck;

    final item = _state.entryById(entryId);
    if (item?.acquisition == AcquisitionMode.article) {
      final materialId = _documentMaterialIds[entryId];
      if (materialId != null) return DiscoveryOpenTarget.document(materialId);
    } else {
      final localPath = _localPaths[entryId];
      if (localPath != null) return DiscoveryOpenTarget.media(localPath);
    }

    final existing = _acquisitionCompleters[entryId];
    if (existing != null) return existing.future;

    final completer = Completer<DiscoveryOpenTarget?>();
    _acquisitionCompleters[entryId] = completer;
    unawaited(
      completer.future.then(
        (_) => _dropAcquisitionCompleter(entryId, completer),
        onError: (_) => _dropAcquisitionCompleter(entryId, completer),
      ),
    );

    // Launch in the background. The returned future resolves the moment the
    // acquisition lifecycle resolves — adoption with the path, failure or
    // cancel with null — so a cancel during the launch window is answered
    // promptly instead of waiting for the stale launch to settle.
    unawaited(() async {
      try {
        await startDownload(entryId);
      } catch (_) {
        // The launch reports its own failures through the acquisition state.
      }
      // Safety net: a launch that decided there is nothing to acquire (no
      // URL, acquisition none, directory pick cancelled) resolves the intent
      // empty rather than hanging the caller. An active acquisition resolves
      // the bridge itself.
      final state = _state.acquisitionStateOf(entryId);
      if (!completer.isCompleted &&
          !_launchesInFlight.containsKey(entryId) &&
          state != DiscoveryItemState.acquiring &&
          state != DiscoveryItemState.available) {
        completer.complete(null);
      }
    }());

    return completer.future;
  }

  void _dropAcquisitionCompleter(
    String entryId,
    Completer<DiscoveryOpenTarget?> completer,
  ) {
    if (identical(_acquisitionCompleters[entryId], completer)) {
      _acquisitionCompleters.remove(entryId);
    }
  }

  void _completeAcquisition(String entryId, DiscoveryOpenTarget? target) {
    final completer = _acquisitionCompleters[entryId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(target);
    }
  }

  /// Registers a freshly downloaded file with the core so the entry stops being
  /// a remote listing and becomes local content.
  ///
  /// A failure here is reported as an acquisition failure rather than dropped:
  /// the bytes may be on disk, but an entry the core never registered is not
  /// something the learner can act on, and silently reverting to "not
  /// downloaded" would invite an identical second attempt.
  Future<void> _adoptDownloadedMedia(String entryId, String path) async {
    try {
      final probedDurationMs = await _importRepository.probeMediaDurationMs(
        path,
      );
      final media = await _mediaLibraryRepository.registerMedia(
        path,
        durationMs: probedDurationMs,
        // Download adoption is acquisition, not retention: the bytes landing
        // on disk must not silently create a Personal Library row.
        retain: false,
      );
      if (_disposed) return;
      _localPaths[entryId] = path;
      _mediaIds[entryId] = media.id;
      _fingerprints[entryId] = media.fingerprint;
      unawaited(_ledger.record(_rowKey(entryId), mediaId: media.id, path: path));
      _mediaDurations[entryId] = media.durationMs ?? probedDurationMs;
      _setSnapshot(
        entryId,
        const ItemAcquisitionSnapshot(
          DiscoveryItemState.available,
          progress: 1,
        ),
      );
      _completeAcquisition(entryId, DiscoveryOpenTarget.media(path));
      unawaited(_recordIdentity(entryId, fileSha256: _fingerprints[entryId]));
    } catch (error) {
      debugPrint('Error registering downloaded media: $error');
      if (_disposed) return;
      _downloadControllers[entryId]?.fail(
        _importRepository.failureDetail(error),
      );
    }
  }

  /// Records the source-scoped identity mapping for [entryId] once Core has
  /// converged it on a Material.
  ///
  /// Adoption registers media, and the workbench creates the Material when
  /// the content opens — the mapping cannot be written before the Material
  /// exists. So this asks Core whether the media already resolved to a
  /// Material (an earlier session, a later refresh) and records the canonical
  /// key only when there is a real Material to point at. The document intake
  /// path knows its Material immediately and passes it in; the media path
  /// resolves it through the media id. Best-effort and non-blocking:
  /// recognition falls back to the ledger until the mapping lands.
  Future<void> _recordIdentity(
    String entryId, {
    String? materialId,
    String? materialRevisionId,
    String? fileSha256,
  }) async {
    final sourceIdentity = _sourceIdentity;
    final learningMaterial = _learningMaterial;
    final item = _state.entryById(entryId);
    if (sourceIdentity == null || learningMaterial == null) return;
    if (!sourceIdentity.isAvailable) return;
    if (item == null) return;

    final effectiveSha = fileSha256 ?? _fingerprints[entryId];
    final String effectiveMaterialId;
    final String effectiveRevisionId;
    if (materialId != null && materialRevisionId != null) {
      effectiveMaterialId = materialId;
      effectiveRevisionId = materialRevisionId;
    } else {
      final mediaId = _mediaIds[entryId];
      if (mediaId == null) return;
      final MaterialDetails details;
      try {
        details = await learningMaterial.resolveMaterialForMedia(mediaId);
      } catch (error) {
        // Not converged on a Material yet (typed not-found); the workbench
        // creates one when the content opens, and a later refresh records the
        // mapping then.
        return;
      }
      effectiveMaterialId = details.material.id;
      effectiveRevisionId = details.material.currentRevisionId;
    }
    try {
      await sourceIdentity.recordMapping(
        sourceId: item.sourceId,
        itemId: item.id,
        evidence: item.evidence(fileSha256: effectiveSha),
        materialId: effectiveMaterialId,
        materialRevisionId: effectiveRevisionId,
      );
    } catch (error) {
      debugPrint('Error recording source identity mapping: $error');
    }
  }

  void cancelDownload(String entryId) {
    _downloadControllers[entryId]?.cancel();
    // Invalidate an in-flight launch: a handle that lands later belongs to
    // an attempt nobody wants, so the pending `startDownload` will see a
    // stale token and drop it. (No launch in flight → nothing to invalidate;
    // an attached download is already handled by the controller's own cancel.)
    if (_launchesInFlight.containsKey(entryId)) {
      _launchTokens[entryId] = (_launchTokens[entryId] ?? 0) + 1;
    }
    // A cancelled run ends the intent empty: no adoption, no Workbench.
    _completeAcquisition(entryId, null);
  }

  String? localPathFor(String entryId) => _localPaths[entryId];

  /// Real duration for an entry when known (probed locally or resolved from
  /// the remote video); null falls back to the feed placeholder.
  int? durationMsFor(String entryId) => _mediaDurations[entryId];

  /// Fills known durations from the media library for already-downloaded
  /// entries using one batched query instead of per-entry lookups.
  Future<void> _hydrateLocalDurations(List<DiscoveryItem> entries) async {
    if (entries.isEmpty || !_mediaLibraryRepository.isAvailable) return;
    try {
      final library = await _mediaLibraryRepository.listMediaLibrary();
      if (_disposed) return;
      var changed = false;
      for (final entry in entries) {
        if (_mediaDurations[entry.id] != null) continue;
        // Same filename-convention limit as [_findLocalEntry].
        if (entry.acquisition != AcquisitionMode.externalTool) continue;
        final local = library.where(
          (item) => item.media.path.contains('[${entry.id}]'),
        );
        final duration = local.isEmpty ? null : local.first.media.durationMs;
        if (duration == null) continue;
        _mediaDurations[entry.id] = duration;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('Error hydrating discovery durations: $e');
    }
  }

  /// Resolves real durations for feed entries in the background (yt-dlp) with
  /// a small concurrency cap. Zero/unknown results keep the placeholder until
  /// a real value lands.
  ///
  /// The workers belong to [sourceId]: once the learner has switched channels
  /// their entries are off screen, so they abort instead of piling subprocesses
  /// up behind every switch.
  Future<void> _resolveRemoteDurations(
    String sourceId,
    List<DiscoveryItem> entries,
  ) async {
    final pending = entries
        .where(
          (entry) =>
              _mediaDurations[entry.id] == null &&
              entry.durationMs == null &&
              entry.mediaUrl != null &&
              // Only the external-tool path needs this: a podcast feed states
              // its own durations, and there is no page for yt-dlp to read at
              // an enclosure URL anyway.
              entry.acquisition == AcquisitionMode.externalTool &&
              entry.sourceId != customSource.id,
        )
        .toList(growable: false);
    if (pending.isEmpty) return;

    var index = 0;
    final workers = List.generate(3, (_) async {
      while (!_disposed && _state.selectedSourceId == sourceId) {
        final next = index++;
        if (next >= pending.length) return;
        final entry = pending[next];
        try {
          final details = await _importRepository.resolveVideoDetails(
            entry.mediaUrl!,
          );
          if (_disposed || _state.selectedSourceId != sourceId) return;
          if (details.durationMs <= 0) continue;
          if (_mediaDurations[entry.id] == null) {
            _mediaDurations[entry.id] = details.durationMs;
            notifyListeners();
          }
        } catch (_) {
          // Best-effort: keep the feed placeholder on resolution failure.
        }
      }
    });
    await Future.wait(workers);
  }

  Future<void> importCustomUrl(String url) async {
    if (url.trim().isEmpty) return;

    _state = _state.copyWith(resolvingUrl: true, resolveFailed: false);
    notifyListeners();

    try {
      final isVideo =
          url.contains('watch?v=') ||
          url.contains('youtu.be/') ||
          url.contains('/shorts/') ||
          url.contains('/v/');

      if (isVideo) {
        final entry = await _repository.resolveCustomVideo(
          url,
          _importRepository,
        );
        if (_disposed) return;

        // Insert into custom entries
        if (!_customEntries.any((e) => e.id == entry.id)) {
          _customEntries.add(entry);
        }

        // Switch to Custom Imports channel
        _state = _state.copyWith(
          selectedSourceId: customSource.id,
          entriesLoading: false,
          clearEntriesFailure: true,
          entries: _customEntries,
          selectedEntryId: entry.id,
        );
        notifyListeners();

        await refreshMediaAvailability(entry.id);
      } else {
        // Channel URL
        final channel = await _repository.resolveCustomChannel(
          url,
          _importRepository,
        );
        if (_disposed) return;

        // Reload channels
        await load();
        if (_disposed) return;

        // Select the newly added channel
        await selectChannel(channel.id);
      }
    } catch (e) {
      debugPrint('Error importing custom URL: $e');
      if (_disposed) return;
      _state = _state.copyWith(resolveFailed: true);
      notifyListeners();
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(resolvingUrl: false);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final completer in _acquisitionCompleters.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _acquisitionCompleters.clear();
    for (final controller in _downloadControllers.values) {
      controller.dispose();
    }
    _downloadControllers.clear();
    super.dispose();
  }
}

class _FakeMediaImportRepository implements MediaImportRepository {
  const _FakeMediaImportRepository();
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());
  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async => null;
  @override
  Future<String> resolveOnlineMedia(String pageUrl) async => '';
  @override
  Future<MediaDownloadHandle> downloadOnlineMedia(
    String pageUrl,
    String directory,
  ) async => const _FakeMediaDownloadHandle();
  @override
  Future<MediaDownloadHandle> downloadEnclosure(
    String mediaUrl,
    String directory, {
    int? expectedBytes,
  }) async => const _FakeMediaDownloadHandle();
  @override
  Future<String?> downloadArticle(
    String articleUrl,
    String directory,
  ) async => null;
  @override
  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl) async =>
      const ResolvedVideoDetails(
        id: '',
        title: 'YouTube Video',
        description: '',
        durationMs: 0,
        viewCount: 0,
        thumbnail: null,
        channelId: '',
        uploadDate: '',
      );
  @override
  Future<ResolvedChannelDetails> resolveChannelDetails(
    String channelUrl,
  ) async => const ResolvedChannelDetails(id: '', name: '');
  @override
  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath) async => [];
  @override
  Future<int?> probeMediaDurationMs(String mediaPath) async => null;
  @override
  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  ) async => '';
}

class _FakeMediaDownloadHandle implements MediaDownloadHandle {
  const _FakeMediaDownloadHandle();
  @override
  Stream<double> get progress => const Stream.empty();
  @override
  Future<String?> get completed => Future.value(null);
  @override
  void cancel() {}
}

class _FakeMediaLibraryRepository implements MediaLibraryRepository {
  const _FakeMediaLibraryRepository();
  @override
  bool get isAvailable => false;
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());
  @override
  Future<SavedVocabularyCount> savedVocabularyCount({
    required String language,
  }) async => const SavedVocabularyCount(total: 0, capped: false);
  @override
  Future<MediaItem> readMedia(String mediaId) async =>
      throw StateError('not used in discovery');
  @override
  Future<List<MediaLibraryEntry>> listMediaLibrary() async => [];
  @override
  Future<MediaItem?> findRegisteredMedia(String mediaId) async => null;
  @override
  Future<MediaLibraryEntry> setTriageIntent(
    String mediaId,
    String? intent,
  ) async => throw UnimplementedError();
  @override
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
  }) async => throw UnimplementedError();
}
