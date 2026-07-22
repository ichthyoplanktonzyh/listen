import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../controllers/occurrence_media_resolver.dart';
import '../controllers/auxiliary_audio_controller.dart';
import '../controllers/hunting_controller.dart';
import '../controllers/slice_player_controller.dart';
import '../localization.dart';
import '../models/practice.dart';
import '../models/production_corpus.dart';
import '../models/projection_review.dart';
import '../models/semantic_embedding.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import '../widgets/vocabulary/vocabulary_book_view.dart';
import '../widgets/vocabulary/listening_dictionary_entry_view.dart';
import '../widgets/vocabulary/hunting_list_panel.dart';
import '../widgets/vocabulary/vocabulary_transfer_actions.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onExport,
    required this.onImport,
    required this.huntingController,
    required this.auxiliaryAudio,
    this.initialEntryId,
    this.openCrossModalReviewOnStart = false,
    this.onPauseBackgroundPlayback,
    this.onStartShadowing,
  });

  final LocalApi api;
  final String language;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final HuntingController huntingController;
  final AuxiliaryAudioController auxiliaryAudio;
  final String? initialEntryId;
  final bool openCrossModalReviewOnStart;

  /// Pauses whatever is playing behind this route (the primary player) so a
  /// slice owns audio focus alone, matching the workbench behaviour.
  final Future<void> Function()? onPauseBackgroundPlayback;
  final Future<void> Function(String path, Map<String, dynamic> occurrence)?
  onStartShadowing;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _SemanticSearchDialog extends StatefulWidget {
  const _SemanticSearchDialog({required this.api, required this.language});

  final LocalApi api;
  final String language;

  @override
  State<_SemanticSearchDialog> createState() => _SemanticSearchDialogState();
}

class _SemanticSearchDialogState extends State<_SemanticSearchDialog> {
  final query = TextEditingController();
  SemanticEmbeddingCapabilityView? capability;
  List<SemanticSearchHitView> hits = const [];
  bool busy = true;
  String? busyLabel;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCapability());
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _loadCapability() async {
    try {
      final value = await widget.api.semanticEmbeddingCapability();
      if (mounted) {
        setState(() {
          capability = value;
          busy = false;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$failure';
        });
      }
    }
  }

  Future<void> _install() async {
    final l = AppLocalizations.of(context);
    setState(() {
      busy = true;
      busyLabel = l.text('semanticSearchInstalling');
      error = null;
    });
    try {
      final value = await widget.api.installSemanticEmbedding();
      if (mounted) {
        setState(() {
          capability = value;
          busy = false;
          busyLabel = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          busyLabel = null;
          error = '$failure';
        });
      }
    }
  }

  Future<void> _rebuild() async {
    final l = AppLocalizations.of(context);
    setState(() {
      busy = true;
      busyLabel = l.text('semanticSearchIndexing');
      error = null;
    });
    try {
      final value = await widget.api.rebuildSemanticEmbedding();
      if (mounted) {
        setState(() {
          capability = value;
          busy = false;
          busyLabel = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          busyLabel = null;
          error = '$failure';
        });
      }
    }
  }

  Future<void> _disable() async {
    setState(() => busy = true);
    try {
      final value = await widget.api.disableSemanticEmbedding();
      if (mounted) {
        setState(() {
          capability = value;
          busy = false;
          hits = const [];
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$failure';
        });
      }
    }
  }

  Future<void> _enable() async {
    setState(() => busy = true);
    try {
      final value = await widget.api.enableSemanticEmbedding();
      if (mounted) {
        setState(() {
          capability = value;
          busy = false;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$failure';
        });
      }
    }
  }

  Future<void> _uninstall() async {
    setState(() => busy = true);
    try {
      final value = await widget.api.uninstallSemanticEmbedding();
      if (mounted) {
        setState(() {
          capability = value;
          busy = false;
          hits = const [];
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$failure';
        });
      }
    }
  }

  Future<void> _search() async {
    if (query.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      busyLabel = null;
      error = null;
    });
    try {
      final result = await widget.api.semanticSearch(
        query: query.text,
        language: widget.language,
      );
      if (mounted) {
        setState(() {
          capability = result.capability;
          hits = result.hits;
          busy = false;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$failure';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final value = capability;
    return AlertDialog(
      title: Text(l.text('semanticSearchTitle')),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) ...[
              const LinearProgressIndicator(),
              if (busyLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(busyLabel!),
                ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.text('semanticSearchFailure').replaceAll('{error}', error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (value != null) ...[
              Text(
                '${value.status} · ${value.indexedSourceCount} sources'
                '${value.descriptor == null ? '' : ' · ${value.descriptor!.dimension}d · ${value.descriptor!.modelFingerprint.substring(0, 8)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (value.status == 'not_installed')
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _install,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l.text('semanticSearchInstall')),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (value.status == 'ready' || value.status == 'stale')
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : _rebuild,
                        icon: Icon(
                          value.status == 'stale'
                              ? Icons.refresh
                              : Icons.account_tree_outlined,
                        ),
                        label: Text(l.text('semanticSearchRebuild')),
                      ),
                    if (value.status == 'ready' || value.status == 'stale')
                      OutlinedButton(
                        onPressed: busy ? null : _disable,
                        child: Text(l.text('semanticSearchDisable')),
                      ),
                    if (value.status == 'disabled')
                      OutlinedButton(
                        onPressed: busy ? null : _enable,
                        child: Text(l.text('semanticSearchEnable')),
                      ),
                    TextButton(
                      onPressed: busy ? null : _uninstall,
                      child: Text(l.text('semanticSearchUninstall')),
                    ),
                  ],
                ),
            ] else if (!busy)
              Text(l.text('semanticSearchUnavailable')),
            const SizedBox(height: 12),
            TextField(
              controller: query,
              enabled: !busy && (value?.canSearch ?? false),
              decoration: InputDecoration(
                hintText: l.text('semanticSearchHint'),
                suffixIcon: IconButton(
                  onPressed: !busy && (value?.canSearch ?? false)
                      ? _search
                      : null,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: hits.isEmpty
                  ? Center(child: Text(l.text('semanticSearchNoHits')))
                  : ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final hit = hits[index];
                        return ListTile(
                          title: Text(
                            hit.source.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${hit.source.kind}${hit.source.channel == null ? '' : ' · ${hit.source.channel}'}',
                          ),
                          trailing: Text(hit.similarity.toStringAsFixed(3)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: !busy && (value?.canSearch ?? false) ? _search : null,
          child: Text(l.text('semanticSearchAction')),
        ),
      ],
    );
  }
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  static const capabilities = ['reading', 'listening', 'speaking', 'writing'];
  static const assessmentFilters = ['acquired', 'not_acquired', 'unassessed'];

  // The four-channel capability axis is the primary lens. [capability] picks the
  // channel; [assessment] `null` means "all" (no capability filter applied).
  String capability = 'listening';
  String? assessment;
  String search = '';
  bool loading = true;
  List<LexicalEntryDetails> words = const [];

  /// Non-null while the in-page entry detail is open (master → detail).
  LexicalEntryDetails? details;
  bool returnToCrossModalReview = false;

  /// Pending listening upgrade suggestions and the dictionary-provider
  /// pronunciation audio for the open entry (both best-effort).
  List<UpgradeSuggestion> suggestions = const [];
  String? pronunciationAudioUrl;
  List<ProductionCorpusHitView>? productionHits;
  bool productionLoadFailed = false;

  /// Corpus fallback when the vocabulary list has no match for [search].
  List<CorpusOccurrence>? homeResults;
  bool homeSearching = false;

  /// The dictionary hosts its own second-decoder slice playback so playing an
  /// example never leaves this screen or touches the primary player.
  final SlicePlayerController slicePlayer = SlicePlayerController();
  HuntingController get hunting => widget.huntingController;

  Future<void> _acquireAuxiliaryAudioFocus() async {
    await slicePlayer.pause();
    await widget.onPauseBackgroundPlayback?.call();
  }

  Future<void> _playPronunciationAudio(String url) async {
    await widget.auxiliaryAudio.playRemote(
      url,
      acquireAudioFocus: _acquireAuxiliaryAudioFocus,
    );
    if (mounted && widget.auxiliaryAudio.error != null) {
      _snack(AppLocalizations.of(context).text('pronunciationUnavailable'));
    }
  }

  Future<void> _speakSynthetic(String text, String purpose) async {
    final asset = await widget.auxiliaryAudio.speak(
      widget.api,
      text: text,
      language: details?.entry.language ?? widget.language,
      purpose: purpose,
      acquireAudioFocus: _acquireAuxiliaryAudioFocus,
    );
    if (mounted && asset == null) {
      _snack(AppLocalizations.of(context).text('ttsUnavailable'));
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(hunting.load(widget.api));
    final initialEntryId = widget.initialEntryId;
    if (initialEntryId != null) {
      unawaited(_openEntryById(initialEntryId));
    }
    if (widget.openCrossModalReviewOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openCrossModalReview());
      });
    }
  }

  @override
  void dispose() {
    unawaited(widget.auxiliaryAudio.stop());
    slicePlayer.dispose();
    super.dispose();
  }

  String _capabilityLabelKey(String value) => switch (value) {
    'reading' => 'capabilityReading',
    'listening' => 'capabilityListening',
    'speaking' => 'capabilitySpeaking',
    _ => 'capabilityWriting',
  };

  Future<void> _load() async {
    setState(() => loading = true);
    final values = await widget.api.listVocabulary(
      language: widget.language,
      capability: assessment == null ? null : capability,
      assessment: assessment,
      search: search,
    );
    if (mounted) {
      setState(() {
        words = values;
        loading = false;
      });
    }
  }

  Future<void> _openEntryById(String entryId) async {
    if (mounted) {
      setState(() {
        productionHits = null;
        productionLoadFailed = false;
      });
    }
    final value = await widget.api.lexicalEntryDetails(entryId);
    // Suggestions and dictionary audio are decorations: each degrades to
    // absence instead of failing the detail page.
    List<UpgradeSuggestion> pending;
    try {
      pending = await widget.api.upgradeSuggestions(lexicalEntryId: entryId);
    } catch (_) {
      pending = const [];
    }
    String? audio;
    try {
      final bundle = await widget.api.lookupDictionary(
        value.entry.normalizedForm,
        language: widget.language,
      );
      audio = bundle.results
          .expand(
            (result) =>
                result.lookup?.phonetics ?? const <DictionaryPhonetic>[],
          )
          .map((phonetic) => phonetic.audioUrl)
          .firstWhere(
            (url) => url != null && url.isNotEmpty,
            orElse: () => null,
          );
    } catch (_) {
      audio = null;
    }
    List<ProductionCorpusHitView> output;
    var outputLoadFailed = false;
    try {
      output = await widget.api.searchProductionCorpus(
        language: value.entry.language,
        query: value.entry.normalizedForm,
      );
    } catch (_) {
      output = const [];
      outputLoadFailed = true;
    }
    if (mounted) {
      setState(() {
        details = value;
        suggestions = pending;
        pronunciationAudioUrl = audio;
        productionHits = output;
        productionLoadFailed = outputLoadFailed;
      });
    }
  }

  Future<void> _openDetails(LexicalEntryDetails value) async {
    await _openEntryById(value.entry.id);
  }

  void _closeDetails() {
    unawaited(widget.auxiliaryAudio.stop());
    setState(() => details = null);
    if (returnToCrossModalReview) {
      returnToCrossModalReview = false;
      unawaited(_openCrossModalReview());
    }
  }

  Future<void> _openProductionAttempt(ProductionCorpusHitView hit) async {
    final attemptId = hit.document.attemptId;
    final attempt = attemptId == null
        ? null
        : await widget.api.semanticAttempt(attemptId);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('myOutputAttempt')),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                '${hit.document.activityKind} · ${l.text('revision')} ${hit.document.responseRevision}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (attempt == null) ...[
                SelectableText(hit.document.responseText),
              ],
              for (final response in attempt?.responses ?? const []) ...[
                Text(
                  '${l.text('revision')} ${response.revision}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                SelectableText(response.transcript),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _openProductionGapReview() async {
    final l = AppLocalizations.of(context);
    ProductionGapReviewView review;
    Map<String, List<NearSemanticProductionMatchView>> semanticMatches =
        const {};
    try {
      final enriched = await widget.api.semanticProductionGapReview(
        language: widget.language,
      );
      review = enriched.review;
      semanticMatches = enriched.matchesByTarget;
    } catch (error) {
      try {
        review = await widget.api.productionGapReview(
          language: widget.language,
        );
      } catch (fallbackError) {
        if (mounted) {
          _snack(
            l
                .text('productionGapUnavailable')
                .replaceAll('{error}', '$fallbackError'),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('productionGapTitle')),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                l
                    .text('productionGapFacts')
                    .replaceAll('{documents}', '${review.documentCount}')
                    .replaceAll('{tokens}', '${review.tokenCount}')
                    .replaceAll('{lemmas}', '${review.lemmaCount}'),
              ),
              if (review.readiness == 'empty') ...[
                const SizedBox(height: 12),
                Text(l.text('productionGapEmpty')),
              ] else ...[
                if (review.readiness == 'starter') ...[
                  const SizedBox(height: 12),
                  Text(
                    l.text('productionGapStarter'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final target in review.targets) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(target.displayForm),
                    subtitle: Text(
                      l
                          .text('productionGapTargetReason')
                          .replaceAll(
                            '{frequency}',
                            target.frequencyRank == null
                                ? l.text('productionGapFrequencyUnavailable')
                                : 'BNC #${target.frequencyRank}',
                          )
                          .replaceAll(
                            '{evidence}',
                            '${target.evidenceStrength}',
                          )
                          .replaceAll('{recency}', '${target.recencyBand}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        unawaited(_openEntryById(target.lexicalEntryId));
                      },
                      child: Text(l.text('productionGapOpenTarget')),
                    ),
                  ),
                  for (final match
                      in semanticMatches[target.lexicalEntryId] ?? const [])
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                        l
                            .text('productionGapSemanticClue')
                            .replaceAll('{word}', match.normalizedKey)
                            .replaceAll(
                              '{score}',
                              match.similarity.toStringAsFixed(3),
                            ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
                if (review.targets.isEmpty)
                  Text(l.text('productionGapNoCandidates')),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _openCrossModalReview() async {
    final l = AppLocalizations.of(context);
    List<CrossModalReviewCandidateView> candidates;
    try {
      candidates = await widget.api.crossModalReviewGaps(
        language: widget.language,
      );
    } catch (error) {
      if (mounted) _snack('${l.text('crossModalReviewUnavailable')}: $error');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('crossModalReviewTitle')),
        content: SizedBox(
          width: 680,
          child: candidates.isEmpty
              ? Text(l.text('crossModalReviewEmpty'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final candidate in candidates)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(candidate.displayForm),
                        subtitle: Text(
                          '${candidate.reviewKind}\n'
                          '${candidate.reading} · ${candidate.listening} · '
                          '${candidate.speaking} · ${candidate.writing}\n'
                          '${candidate.reason}\n${candidate.source.snapshot}',
                        ),
                        isThreeLine: false,
                        trailing: TextButton(
                          onPressed: () {
                            returnToCrossModalReview = true;
                            Navigator.pop(dialogContext);
                            unawaited(_openEntryById(candidate.lexicalEntryId));
                          },
                          child: Text(l.text('productionGapOpenTarget')),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _openProjectionReview(String lexicalEntryId) async {
    final l = AppLocalizations.of(context);
    List<ProjectionProposalView> proposals;
    try {
      proposals = await widget.api.auditProjectionEntry(lexicalEntryId);
    } catch (error) {
      if (mounted) _snack('${l.text('projectionReviewUnavailable')}: $error');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('projectionReviewTitle')),
        content: SizedBox(
          width: 680,
          child: proposals.isEmpty
              ? Text(l.text('projectionReviewEmpty'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final proposal in proposals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${proposal.capability} → ${proposal.proposedConclusion}',
                        ),
                        subtitle: Text(
                          '${proposal.rationale}\n${proposal.algorithmVersion} · ${proposal.status}',
                        ),
                        isThreeLine: true,
                        trailing: proposal.status != 'pending'
                            ? null
                            : Wrap(
                                children: [
                                  IconButton(
                                    tooltip: l.text('reject'),
                                    onPressed: () async {
                                      await widget.api.decideProjectionProposal(
                                        proposalId: proposal.id,
                                        decision: 'reject',
                                      );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                      if (mounted) {
                                        unawaited(
                                          _openProjectionReview(lexicalEntryId),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                  IconButton(
                                    tooltip: l.text('confirm'),
                                    onPressed: () async {
                                      await widget.api.decideProjectionProposal(
                                        proposalId: proposal.id,
                                        decision: 'confirm',
                                      );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                      if (mounted) {
                                        unawaited(
                                          _openEntryById(lexicalEntryId),
                                        );
                                        unawaited(
                                          _openProjectionReview(lexicalEntryId),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
  }

  // ── Slice playback (in-page, second decoder) ──

  OccurrenceMediaResolver get _resolver => OccurrenceMediaResolver(
    readMedia: widget.api.readMedia,
    fingerprintFile: widget.api.fingerprintFile,
    registerMedia: (path) async {
      await widget.api.registerMedia(path);
    },
    pickFile: (groups) => openFile(acceptedTypeGroups: groups),
  );

  Future<void> _playOccurrenceMap(Map<String, dynamic> occurrence) async {
    final resolution = await _resolver.resolve(
      occurrence,
      currentMediaFingerprint: null,
      currentMediaPath: null,
      filterMediaExtensions: true,
    );
    if (!mounted) return;
    if (resolution is UnresolvedOccurrenceMedia) {
      await slicePlayer.showError(resolution.message, occurrence: occurrence);
      return;
    }
    await widget.onPauseBackgroundPlayback?.call();
    await slicePlayer.open(
      path: (resolution as ResolvedOccurrenceMedia).path,
      occurrence: occurrence,
    );
    slicePlayer.setShowVideo(true);
  }

  Future<void> _startShadowingOccurrence(LexicalOccurrence occurrence) async {
    final path = slicePlayer.state.path;
    final callback = widget.onStartShadowing;
    if (path == null || callback == null) return;
    await slicePlayer.pause();
    if (mounted) Navigator.of(context).pop();
    await callback(path, occurrence.toJson());
  }

  Future<void> _playCorpus(CorpusOccurrence occurrence) async {
    final mediaId = occurrence.mediaId;
    if (mediaId == null) return;
    MediaItem media;
    try {
      media = await widget.api.readMedia(mediaId);
    } catch (_) {
      if (!mounted) return;
      await slicePlayer.showError(
        AppLocalizations.of(context).text('dictionaryClipNeedsSource'),
      );
      return;
    }
    await _playOccurrenceMap({
      'media_id': mediaId,
      'media_fingerprint_snapshot': media.fingerprint,
      'media_title_snapshot': media.title,
      'sentence_text_snapshot': occurrence.sourceSnapshot,
      'original_form': occurrence.displayText,
      'start_ms_snapshot': occurrence.startMs,
      'end_ms_snapshot': occurrence.endMs,
    });
  }

  // ── Corpus enrichment (Slice 3) ──

  Future<List<CorpusOccurrence>> _searchLibraryFor(LexicalEntry entry) async {
    final values = await widget.api.searchCorpus(
      language: entry.language,
      query: entry.kind == 'phrase' ? entry.displayForm : entry.normalizedForm,
    );
    return values;
  }

  Future<bool> _collectCorpus(
    LexicalEntry entry,
    CorpusOccurrence occurrence,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      final media = await widget.api.readMedia(occurrence.mediaId!);
      await widget.api.upsertLexicalEntry({
        'language': entry.language,
        'kind': entry.kind,
        // The normalized form re-normalizes to itself, so the upsert can only
        // land on this entry's identity and never fork a sibling entry.
        'canonical_form': entry.normalizedForm,
        'display_form': entry.displayForm,
        'status': null,
        'source': {
          'media_id': occurrence.mediaId,
          'sentence_id': occurrence.sentenceId,
          'original_form': occurrence.kind == 'lexical'
              ? occurrence.displayText
              : entry.displayForm,
          'sentence_text': occurrence.sourceSnapshot,
          'media_title': media.title,
          'media_fingerprint': media.fingerprint,
          'start_ms': occurrence.startMs,
          'end_ms': occurrence.endMs,
        },
      });
      // Refresh so the new durable slice joins the entry's clip list.
      await _openEntryById(entry.id);
      if (mounted) {
        _snack(l.text('dictionaryCollected'));
      }
      return true;
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryCollectFailed').replaceAll('{error}', '$error'),
        );
      }
      return false;
    }
  }

  Future<void> _searchHomeCorpus() async {
    setState(() => homeSearching = true);
    List<CorpusOccurrence> results;
    try {
      final values = await widget.api.searchCorpus(
        language: widget.language,
        query: search,
      );
      results = values;
    } catch (_) {
      results = const [];
    }
    if (mounted) {
      setState(() {
        homeSearching = false;
        homeResults = results;
      });
    }
  }

  Future<void> _reindexCorpus() async {
    final l = AppLocalizations.of(context);
    try {
      final count = await widget.api.reindexCorpus();
      if (mounted) {
        _snack(l.text('dictionaryReindexDone').replaceAll('{count}', '$count'));
      }
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryReindexFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  // ── Detail editing (restored from the pre-dictionary detail dialog) ──

  Future<void> _setOverride(
    LexicalEntry entry,
    String capability,
    String? conclusion,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.setCapabilityOverride(
        entry.id,
        capability,
        conclusion: conclusion,
      );
      await _openEntryById(entry.id);
      // Capability filters in the book view read the same channels.
      unawaited(_load());
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _saveContent(
    LexicalEntry entry,
    String? definition,
    String? note,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.updateLexicalLearningContent(
        entry.id,
        userDefinition: definition,
        personalNote: note,
      );
      await _openEntryById(entry.id);
      if (mounted) _snack(l.text('dictionaryContentSaved'));
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _createSenseFolder(
    LexicalEntry entry,
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.createLexicalSenseFolder(
      entry.id,
      label: label,
      definition: definition,
      gloss: gloss,
      externalRef: externalRef,
    ),
  );

  Future<void> _updateSenseFolder(
    LexicalEntry entry,
    String senseId,
    String label,
    String? definition,
    String? gloss,
    String? externalRef,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.updateLexicalSenseFolder(
      entry.id,
      senseId,
      label: label,
      definition: definition,
      gloss: gloss,
      externalRef: externalRef,
    ),
  );

  Future<void> _deleteSenseFolder(LexicalEntry entry, String senseId) =>
      _saveSenseFolderChange(
        entry,
        () => widget.api.deleteLexicalSenseFolder(entry.id, senseId),
      );

  Future<void> _assignSenseFolder(
    LexicalEntry entry,
    String senseId,
    LexicalOccurrence occurrence,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.assignLexicalSenseFolderOccurrence(
      entry.id,
      senseId,
      occurrence.id,
    ),
  );

  Future<void> _unassignSenseFolder(
    LexicalEntry entry,
    String senseId,
    LexicalOccurrence occurrence,
  ) => _saveSenseFolderChange(
    entry,
    () => widget.api.unassignLexicalSenseFolderOccurrence(
      entry.id,
      senseId,
      occurrence.id,
    ),
  );

  Future<void> _saveSenseFolderChange(
    LexicalEntry entry,
    Future<LexicalEntryDetails> Function() action,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      final value = await action();
      if (mounted) setState(() => details = value);
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _confirmSuggestion(
    LexicalEntry entry,
    UpgradeSuggestion suggestion,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.confirmUpgradeSuggestion(suggestion.id);
      await _openEntryById(entry.id);
      unawaited(_load());
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _rejectSuggestion(
    LexicalEntry entry,
    UpgradeSuggestion suggestion,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.rejectUpgradeSuggestion(suggestion.id);
      await _openEntryById(entry.id);
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryUpdateFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  // ── External references (copyright guardrail: links only) ──

  /// YouGlish covers the current learning target (English); other languages
  /// simply hide the link instead of guessing a locale path.
  String? _externalLookupUrlFor(String query, String language) =>
      language == 'en' && query.trim().isNotEmpty
      ? 'https://youglish.com/pronounce/${Uri.encodeComponent(query.trim())}/english'
      : null;

  // The consumer app is macOS-only, so the system opener is sufficient; no
  // url_launcher dependency for one reference link.
  void _openExternal(String url) => unawaited(Process.run('open', [url]));

  // ── Action exits ──

  Future<void> _reviewClip(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.createReviewItem(
        CreateReviewItem(
          source: ReviewSource(
            kind: 'lexical_entry',
            id: entry.id,
            lexicalEntryId: entry.id,
            mediaId: occurrence.mediaId,
          ),
          // The sentence anchor carries the clip's durable window so the
          // review queue can derive playback/cloze-style cards from it.
          anchors: [
            if (occurrence.sentenceId != null)
              PracticeAnchor(
                kind: 'sentence',
                id: occurrence.sentenceId!,
                label: occurrence.sentenceTextSnapshot,
                sentenceId: occurrence.sentenceId,
                startMs: occurrence.startMsSnapshot,
                endMs: occurrence.endMsSnapshot,
              ),
            PracticeAnchor(
              kind: 'lexical_entry',
              id: entry.id,
              label: occurrence.originalForm ?? entry.displayForm,
              lexicalEntryId: entry.id,
              sentenceId: occurrence.sentenceId,
            ),
          ],
          promptSnapshot: occurrence.sentenceTextSnapshot,
        ),
      );
      if (mounted) _snack(l.text('dictionaryReviewQueued'));
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryReviewFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _addToReview(LexicalEntry entry) async {
    final l = AppLocalizations.of(context);
    try {
      await widget.api.createReviewItem(
        CreateReviewItem(
          source: ReviewSource(
            kind: 'lexical_entry',
            id: entry.id,
            lexicalEntryId: entry.id,
          ),
          anchors: const [],
          promptSnapshot: entry.displayForm,
        ),
      );
      if (mounted) _snack(l.text('dictionaryReviewQueued'));
    } catch (error) {
      if (mounted) {
        _snack(
          l.text('dictionaryReviewFailed').replaceAll('{error}', '$error'),
        );
      }
    }
  }

  Future<void> _openHuntingList() async {
    await hunting.load(widget.api);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: HuntingListPanel(
            controller: hunting,
            onRefresh: () async {
              await hunting.load(widget.api);
            },
            onPromoteCandidate: (candidate) async {
              final saved = await hunting.promoteCandidate(
                widget.api,
                candidate,
              );
              if (mounted && saved) {
                _snack(AppLocalizations.of(context).text('huntingAdded'));
              }
            },
            onArchiveTarget: (target) async {
              final saved = await hunting.archive(widget.api, target);
              if (mounted && saved) {
                _snack(AppLocalizations.of(context).text('huntingArchived'));
              }
            },
            onOpenEntry: (entryId) {
              Navigator.of(sheetContext).pop();
              unawaited(_openEntryById(entryId));
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addToHuntingList(LexicalEntry entry) async {
    final l = AppLocalizations.of(context);
    if (hunting.state.containsLexicalEntry(entry.id)) {
      _snack(l.text('huntingAlreadyAdded'));
      return;
    }
    final saved = await hunting.addManual(widget.api, entry);
    if (!mounted) return;
    if (saved) {
      _snack(l.text('huntingAdded'));
    } else if (hunting.state.error != null) {
      _snack(
        l
            .text('huntingUpdateFailed')
            .replaceAll('{error}', hunting.state.error!),
      );
    }
  }

  Future<bool> _markOccurrence(
    LexicalEntry entry,
    LexicalOccurrence occurrence,
    bool heard,
  ) async {
    final sentenceId = occurrence.sentenceId;
    if (sentenceId == null) return false;
    try {
      await widget.api.createLexicalObservation(
        lexicalEntryId: entry.id,
        sentenceId: sentenceId,
        originalForm: occurrence.originalForm ?? entry.displayForm,
        heard: heard,
        source: {
          'media_id': occurrence.mediaId,
          'sentence_id': sentenceId,
          'original_form': occurrence.originalForm ?? entry.displayForm,
          'sentence_text': occurrence.sentenceTextSnapshot,
          'media_title': occurrence.mediaTitleSnapshot,
          'media_fingerprint': occurrence.mediaFingerprintSnapshot,
          'start_ms': occurrence.startMsSnapshot,
          'end_ms': occurrence.endMsSnapshot,
        },
      );
      if (mounted) {
        _snack(
          AppLocalizations.of(
            context,
          ).text(heard ? 'dictionaryMarkedHeard' : 'dictionaryMarkedNotHeard'),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        _snack(
          AppLocalizations.of(
            context,
          ).text('dictionaryMarkFailed').replaceAll('{error}', '$error'),
        );
      }
      return false;
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final openDetails = details;
    return ListenableBuilder(
      listenable: Listenable.merge([hunting, widget.auxiliaryAudio]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: openDetails == null
              ? null
              : BackButton(onPressed: _closeDetails),
          title: Text(
            openDetails?.entry.displayForm ?? l.text('listeningDictionary'),
          ),
          actions: [
            IconButton(
              tooltip: l.text('huntingOpen'),
              onPressed: () => unawaited(_openHuntingList()),
              icon: Badge(
                isLabelVisible: hunting.state.targets.isNotEmpty,
                label: Text('${hunting.state.targets.length}'),
                child: const Icon(Icons.gps_fixed),
              ),
            ),
            if (openDetails != null)
              IconButton(
                tooltip:
                    hunting.state.containsLexicalEntry(openDetails.entry.id)
                    ? l.text('huntingAlreadyAdded')
                    : l.text('huntingAddCurrent'),
                onPressed:
                    hunting.state.busy ||
                        hunting.state.containsLexicalEntry(openDetails.entry.id)
                    ? null
                    : () => unawaited(_addToHuntingList(openDetails.entry)),
                icon: Icon(
                  hunting.state.containsLexicalEntry(openDetails.entry.id)
                      ? Icons.gps_fixed
                      : Icons.add_location_alt_outlined,
                ),
              ),
            if (openDetails != null)
              TextButton.icon(
                onPressed: () => unawaited(_addToReview(openDetails.entry)),
                icon: const Icon(Icons.queue_music_outlined, size: 18),
                label: Text(l.text('dictionaryAddToReview')),
              )
            else
              const SizedBox.shrink(),
            if (openDetails != null)
              IconButton(
                tooltip: l.text('projectionReviewTitle'),
                onPressed: () =>
                    unawaited(_openProjectionReview(openDetails.entry.id)),
                icon: const Icon(Icons.fact_check_outlined),
              )
            else ...[
              IconButton(
                tooltip: l.text('semanticSearchTitle'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _SemanticSearchDialog(
                    api: widget.api,
                    language: widget.language,
                  ),
                ),
                icon: const Icon(Icons.travel_explore_outlined),
              ),
              IconButton(
                tooltip: l.text('productionGapTitle'),
                onPressed: () => unawaited(_openProductionGapReview()),
                icon: const Icon(Icons.compare_arrows_outlined),
              ),
              IconButton(
                tooltip: l.text('crossModalReviewTitle'),
                onPressed: () => unawaited(_openCrossModalReview()),
                icon: const Icon(Icons.hub_outlined),
              ),
              IconButton(
                tooltip: l.text('dictionaryReindex'),
                onPressed: () => unawaited(_reindexCorpus()),
                icon: const Icon(Icons.manage_search_outlined),
              ),
              VocabularyTransferActions(
                onExport: widget.onExport,
                onImport: widget.onImport,
              ),
            ],
          ],
        ),
        body: openDetails == null ? _bookBody(l) : _detailBody(openDetails),
      ),
    );
  }

  Widget _detailBody(LexicalEntryDetails value) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: ListeningDictionaryEntryView(
        // Rebind state when switching entries so reveal/mark/search state
        // never leaks from another word.
        key: ValueKey(value.entry.id),
        details: value,
        showProductionCorpus: true,
        productionHits: productionHits,
        productionLoadFailed: productionLoadFailed,
        onOpenProductionAttempt: _openProductionAttempt,
        slicePlayer: slicePlayer,
        onPlay: (occurrence) =>
            unawaited(_playOccurrenceMap(occurrence.toJson())),
        onShadowing: widget.onStartShadowing == null
            ? null
            : _startShadowingOccurrence,
        onMark: (occurrence, heard) =>
            _markOccurrence(value.entry, occurrence, heard),
        onSearchLibrary: () => _searchLibraryFor(value.entry),
        onPlayCorpus: (occurrence) => unawaited(_playCorpus(occurrence)),
        onCollectCorpus: (occurrence) =>
            _collectCorpus(value.entry, occurrence),
        suggestions: suggestions,
        onConfirmSuggestion: (suggestion) =>
            _confirmSuggestion(value.entry, suggestion),
        onRejectSuggestion: (suggestion) =>
            _rejectSuggestion(value.entry, suggestion),
        onCapabilityOverride: (capability, conclusion) =>
            _setOverride(value.entry, capability, conclusion),
        onLoadEvidenceHistory: ({String? capability, int offset = 0}) =>
            widget.api.learningObservationHistory(
              value.entry.id,
              capability: capability,
              offset: offset,
            ),
        onSaveContent: (definition, note) =>
            _saveContent(value.entry, definition, note),
        onCreateSenseFolder: (label, definition, gloss, externalRef) =>
            _createSenseFolder(
              value.entry,
              label,
              definition,
              gloss,
              externalRef,
            ),
        onUpdateSenseFolder: (id, label, definition, gloss, externalRef) =>
            _updateSenseFolder(
              value.entry,
              id,
              label,
              definition,
              gloss,
              externalRef,
            ),
        onDeleteSenseFolder: (id) => _deleteSenseFolder(value.entry, id),
        onAssignSenseFolder: (senseId, occurrence) =>
            _assignSenseFolder(value.entry, senseId, occurrence),
        onUnassignSenseFolder: (senseId, occurrence) =>
            _unassignSenseFolder(value.entry, senseId, occurrence),
        onReviewClip: (occurrence) => _reviewClip(value.entry, occurrence),
        externalLookupUrl: _externalLookupUrlFor(
          value.entry.displayForm,
          value.entry.language,
        ),
        onOpenExternal: _openExternal,
        pronunciationAudioUrl: pronunciationAudioUrl,
        onPlayPronunciationAudio: (url) =>
            unawaited(_playPronunciationAudio(url)),
        onSpeakSynthetic: (text, purpose) =>
            unawaited(_speakSynthetic(text, purpose)),
        speechBusy: widget.auxiliaryAudio.busy,
      ),
    ),
  );

  Widget _bookBody(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: l.text('searchVocabulary'),
            ),
            onChanged: (value) {
              search = value;
              homeResults = null;
              unawaited(_load());
            },
          ),
        ),
        // Primary lens: the four-channel capability axis. The channel picker
        // only affects results once a specific assessment is chosen.
        _filterRow(
          children: [
            for (final cap in capabilities)
              ChoiceChip(
                label: Text(l.text(_capabilityLabelKey(cap))),
                selected: capability == cap,
                onSelected: (_) {
                  setState(() => capability = cap);
                  if (assessment != null) unawaited(_load());
                },
              ),
          ],
        ),
        _filterRow(
          children: [
            _assessmentChip(l.text('vocabFilterAll'), null),
            for (final value in assessmentFilters)
              _assessmentChip(
                l.text(value),
                value,
                color: capabilityAssessmentColor(
                  Theme.of(context).colorScheme,
                  value,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : words.isEmpty && search.trim().isNotEmpty
              ? _homeCorpusFallback(l)
              : VocabularyBookView(words: words, onWord: _openDetails),
        ),
      ],
    );
  }

  /// No vocabulary asset matches the query: the dictionary stays useful as a
  /// pure lookup tool by searching the local corpus directly (play only —
  /// saving a clip needs an entry to attach it to).
  Widget _homeCorpusFallback(AppLocalizations l) {
    final results = homeResults;
    if (results == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.text('noWords')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: homeSearching
                  ? null
                  : () => unawaited(_searchHomeCorpus()),
              icon: homeSearching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.travel_explore_outlined, size: 18),
              label: Text(l.text('dictionaryFindMore')),
            ),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      final externalUrl = _externalLookupUrlFor(search, widget.language);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.text('dictionaryNoLibraryResults')),
            if (externalUrl != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openExternal(externalUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.text('dictionaryYouglish')),
              ),
            ],
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final result in results)
          CorpusResultTile(
            occurrence: result,
            target: search.trim(),
            onPlay: result.mediaId == null
                ? null
                : () => unawaited(_playCorpus(result)),
            onCollect: null,
          ),
      ],
    );
  }

  Widget _filterRow({required List<Widget> children}) => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, index) => Center(child: children[index]),
    ),
  );

  Widget _assessmentChip(String label, String? value, {Color? color}) =>
      ChoiceChip(
        avatar: color == null
            ? null
            : CircleAvatar(backgroundColor: color, radius: 5),
        label: Text(label),
        selected: assessment == value,
        onSelected: (_) {
          setState(() => assessment = value);
          unawaited(_load());
        },
      );
}
