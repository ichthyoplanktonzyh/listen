import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/semantic_embedding.dart';
import '../../services/api_service.dart';
import '../../theme/spacing.dart';
import '../common/listen_empty_state.dart';
import '../common/listen_error_state.dart';

class SemanticSearchDialog extends StatefulWidget {
  const SemanticSearchDialog({
    super.key,
    required this.api,
    required this.language,
  });

  final LocalApi api;
  final String language;

  @override
  State<SemanticSearchDialog> createState() => _SemanticSearchDialogState();
}

class _SemanticSearchDialogState extends State<SemanticSearchDialog> {
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
                child: ListenErrorNotice(
                  message: l
                      .text('semanticSearchFailure')
                      .replaceAll('{error}', error!),
                ),
              ),
            if (value != null) ...[
              Text(
                '${value.status} · ${value.indexedSourceCount} sources'
                '${value.descriptor == null ? '' : ' · ${value.descriptor!.dimension}d · ${value.descriptor!.modelFingerprint.substring(0, 8)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: ListenSpacing.gap8),
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
            const SizedBox(height: ListenSpacing.gap12),
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
            const SizedBox(height: ListenSpacing.gap8),
            Expanded(
              child: hits.isEmpty
                  ? ListenEmptyState(
                      icon: Icons.search_off,
                      message: l.text('semanticSearchNoHits'),
                    )
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
