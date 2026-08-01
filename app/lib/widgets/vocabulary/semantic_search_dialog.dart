import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/semantic_search_view_model.dart';
import '../../localization.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_empty_state.dart';

class SemanticSearchDialog extends StatefulWidget {
  const SemanticSearchDialog({
    super.key,
    required this.viewModel,
    required this.language,
  });

  final String language;
  final SemanticSearchViewModel viewModel;

  @override
  State<SemanticSearchDialog> createState() => _SemanticSearchDialogState();
}

class _SemanticSearchDialogState extends State<SemanticSearchDialog> {
  final query = TextEditingController();
  SemanticSearchViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    unawaited(_viewModel.loadCapability());
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _search() =>
      _viewModel.search(query: query.text, language: widget.language);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => _buildDialog(l),
    );
  }

  Widget _buildDialog(AppLocalizations l) {
    final state = _viewModel.state;
    final value = state.capability;
    final activityLabel = switch (state.activity) {
      SemanticSearchActivity.installing => l.text('semanticSearchInstalling'),
      SemanticSearchActivity.indexing => l.text('semanticSearchIndexing'),
      null => null,
    };
    return AlertDialog(
      title: Text(l.text('semanticSearchTitle')),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.busy) ...[
              const LinearProgressIndicator(),
              if (activityLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(activityLabel),
                ),
            ],
            if (state.failure != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ApiFailureNotice(
                  message: l.text(state.failure!.messageKey),
                  failure: state.failure!.detail,
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
                  onPressed: state.busy ? null : _viewModel.install,
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
                        onPressed: state.busy ? null : _viewModel.rebuild,
                        icon: Icon(
                          value.status == 'stale'
                              ? Icons.refresh
                              : Icons.account_tree_outlined,
                        ),
                        label: Text(l.text('semanticSearchRebuild')),
                      ),
                    if (value.status == 'ready' || value.status == 'stale')
                      OutlinedButton(
                        onPressed: state.busy ? null : _viewModel.disable,
                        child: Text(l.text('semanticSearchDisable')),
                      ),
                    if (value.status == 'disabled')
                      OutlinedButton(
                        onPressed: state.busy ? null : _viewModel.enable,
                        child: Text(l.text('semanticSearchEnable')),
                      ),
                    TextButton(
                      onPressed: state.busy ? null : _viewModel.uninstall,
                      child: Text(l.text('semanticSearchUninstall')),
                    ),
                  ],
                ),
            ] else if (!state.busy)
              Text(l.text('semanticSearchUnavailable')),
            const SizedBox(height: ListenSpacing.gap12),
            TextField(
              controller: query,
              enabled: !state.busy && (value?.canSearch ?? false),
              decoration: InputDecoration(
                hintText: l.text('semanticSearchHint'),
                suffixIcon: IconButton(
                  onPressed: !state.busy && (value?.canSearch ?? false)
                      ? _search
                      : null,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Expanded(
              child: state.hits.isEmpty
                  ? ListenEmptyState(
                      icon: Icons.search_off,
                      message: l.text('semanticSearchNoHits'),
                    )
                  : ListView.separated(
                      itemCount: state.hits.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final hit = state.hits[index];
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
          child: Text(l.text('close')),
        ),
        FilledButton(
          onPressed: !state.busy && (value?.canSearch ?? false)
              ? _search
              : null,
          child: Text(l.text('semanticSearchAction')),
        ),
      ],
    );
  }
}
