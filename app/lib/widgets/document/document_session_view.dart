import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/document_session_controller.dart';
import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/document_session.dart';
import '../../models/learning_material.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_error_state.dart';
import '../common/listen_loading.dart';

/// Renders the current [DocumentSessionState]. Reusable and pure: it emits
/// intent through the controller's methods and renders nothing but state.
class DocumentSessionView extends StatelessWidget {
  const DocumentSessionView({super.key, required this.controller});

  final DocumentSessionController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => switch (controller.state) {
        DocumentSessionIdle() => _IdlePane(
          onChooseFile: () => unawaited(controller.openFile()),
          onPaste: (title, body) =>
              unawaited(controller.openPastedText(title: title, body: body)),
        ),
        DocumentSessionOpening() => Center(
          child: ListenLoading(label: l.text('documentOpening')),
        ),
        DocumentSessionChoosingAsset(:final details, :final documentAssets) =>
          _ChoosingAssetPane(
            title: details.currentRevision.title,
            documentAssets: documentAssets,
            onChoose: controller.chooseDocumentAsset,
          ),
        DocumentSessionReady(
          :final details,
          :final documentAsset,
          :final isRetained,
          :final retentionInFlight,
          :final retentionFailure,
        ) =>
          _ReadyPane(
            title: details.currentRevision.title,
            text: documentAsset.text,
            isRetained: isRetained,
            retentionInFlight: retentionInFlight,
            retentionFailure: retentionFailure,
            onKeep: () => unawaited(controller.retain()),
            onUnkeep: () => unawaited(controller.unretain()),
          ),
        DocumentSessionFailed(:final failure) => _FailedPane(
          failure: failure,
          onRetry: () => unawaited(controller.retry()),
          onBack: controller.close,
        ),
      },
    );
  }
}

class _IdlePane extends StatefulWidget {
  const _IdlePane({required this.onChooseFile, required this.onPaste});

  final VoidCallback onChooseFile;
  final void Function(String title, String body) onPaste;

  @override
  State<_IdlePane> createState() => _IdlePaneState();
}

class _IdlePaneState extends State<_IdlePane> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _showPasteForm = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: ListenPadding.pageCompact,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.wideColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.text('documentSessionIdleTitle'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                l.text('documentSessionIdleBody'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap16),
              FilledButton.icon(
                onPressed: widget.onChooseFile,
                icon: const Icon(Icons.description_outlined),
                label: Text(l.text('chooseTextFile')),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showPasteForm = !_showPasteForm),
                icon: Icon(
                  _showPasteForm
                      ? Icons.expand_less
                      : Icons.content_paste_outlined,
                  size: ListenIconSize.control,
                ),
                label: Text(l.text('pasteText')),
              ),
              if (_showPasteForm) ...[
                const SizedBox(height: ListenSpacing.gap16),
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: l.text('pasteTextTitle'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                TextField(
                  controller: _body,
                  minLines: 6,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: l.text('pasteTextBody'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () {
                      widget.onPaste(_title.text, _body.text);
                    },
                    child: Text(l.text('pasteTextOpen')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoosingAssetPane extends StatelessWidget {
  const _ChoosingAssetPane({
    required this.title,
    required this.documentAssets,
    required this.onChoose,
  });

  final String title;
  final List<DocumentTextMaterialAsset> documentAssets;
  final void Function(String assetId) onChoose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: ListenPadding.pageCompact,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.wideColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                l.text('documentChooseAssetHint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap12),
              for (final asset in documentAssets) ...[
                _DocumentAssetTile(
                  asset: asset,
                  onChoose: () => onChoose(asset.id),
                ),
                const SizedBox(height: ListenSpacing.gap6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable document asset. [ListTile]'s focus traversal makes the
/// choice keyboard-operable; the internal asset id is never shown.
class _DocumentAssetTile extends StatelessWidget {
  const _DocumentAssetTile({required this.asset, required this.onChoose});

  final DocumentTextMaterialAsset asset;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final language = asset.language;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onChoose,
        leading: Icon(
          Icons.description_outlined,
          color: colors.onSurfaceVariant,
        ),
        title: Text(
          language == null
              ? l.text('documentAssetUntagged')
              : l
                    .text('documentAssetLanguage')
                    .replaceAll('{language}', language),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatBytes(asset.byteSize, l)} · ${_preview(asset.text)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: ListenIconSize.control,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  String _preview(String text) {
    const limit = 120;
    final flat = text.replaceAll('\n', ' ');
    if (flat.length <= limit) return flat;
    return '${flat.substring(0, limit)}…';
  }
}

class _ReadyPane extends StatelessWidget {
  const _ReadyPane({
    required this.title,
    required this.text,
    required this.isRetained,
    required this.retentionInFlight,
    required this.retentionFailure,
    required this.onKeep,
    required this.onUnkeep,
  });

  final String title;
  final String text;
  final bool isRetained;
  final bool retentionInFlight;
  final ApiFailure? retentionFailure;
  final VoidCallback onKeep;
  final VoidCallback onUnkeep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final failure = retentionFailure;
    return SingleChildScrollView(
      padding: ListenPadding.pageCompact,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // A reading measure, not a media column: the cap is `contentColumnMax`
          // so lines stay legible on a wide window (charter principle 5).
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.contentColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: ListenSpacing.gap4),
                        Text(
                          isRetained
                              ? l.text('retentionRetainedLabel')
                              : l.text('documentTemporary'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ListenSpacing.gap12),
                  if (retentionInFlight)
                    const ListenLoading.inline()
                  else if (isRetained)
                    OutlinedButton(
                      onPressed: onUnkeep,
                      child: Text(l.text('retentionUnkeepAction')),
                    )
                  else
                    FilledButton(
                      onPressed: onKeep,
                      child: Text(l.text('retentionKeepAction')),
                    ),
                ],
              ),
              if (failure != null) ...[
                const SizedBox(height: ListenSpacing.gap8),
                ListenErrorNotice(message: l.text('documentRetentionFailed')),
                ApiFailureDisclosure(failure: failure),
              ],
              const SizedBox(height: ListenSpacing.gap16),
              // Direct document view: the exact source text, selectable, line
              // breaks and trailing spaces preserved. No fabricated cues or
              // paragraphs, no reading-position tracking.
              SelectionArea(child: SelectableText(text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailedPane extends StatelessWidget {
  const _FailedPane({
    required this.failure,
    required this.onRetry,
    required this.onBack,
  });

  final DocumentSessionFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final message = switch (failure.kind) {
      DocumentSessionFailureKind.coreUnavailable => l.text(
        'documentFailedCoreUnavailable',
      ),
      DocumentSessionFailureKind.tooLarge => l.text('documentFailedTooLarge'),
      DocumentSessionFailureKind.invalidUtf8 => l.text(
        'documentFailedInvalidUtf8',
      ),
      DocumentSessionFailureKind.emptyDocument => l.text('documentFailedEmpty'),
      DocumentSessionFailureKind.unreadable => l.text(
        'documentFailedUnreadable',
      ),
      DocumentSessionFailureKind.missingTitle => l.text(
        'documentFailedMissingTitle',
      ),
      DocumentSessionFailureKind.apiFailure => l.text('documentFailedApi'),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.noticeColumnMax,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: ListenIconSize.illustration,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: ListenSpacing.gap12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: ListenSpacing.gap16),
            Wrap(
              spacing: ListenSpacing.gap8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onBack,
                  child: Text(l.text('documentBack')),
                ),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(l.text('documentRetry')),
                ),
              ],
            ),
            if (failure.apiFailure != null)
              ApiFailureDisclosure(failure: failure.apiFailure!),
          ],
        ),
      ),
    );
  }
}

/// Compact byte-size label for a document asset (≤ 1 MiB by intake policy).
String _formatBytes(int size, AppLocalizations l) {
  if (size >= 1024 * 1024) {
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} ${l.text('unitMegabytes')}';
  }
  if (size >= 1024) {
    return '${(size / 1024).toStringAsFixed(1)} ${l.text('unitKilobytes')}';
  }
  return '$size ${l.text('unitBytes')}';
}
