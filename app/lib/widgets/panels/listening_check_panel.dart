import 'package:flutter/material.dart';

import '../../controllers/reading_task_controller.dart';
import '../../localization.dart';
import '../../services/api_service.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import 'reading_task_sheet.dart';

/// Hosts the listening-retell flow as a full-pane surface (Phase 3.13
/// Slice 4). It replaces the reading view while active, which is what makes
/// the `source_text_visible=false` condition honest — and it deliberately is
/// NOT a modal, so the slice playback window stays interactive on top.
class ListeningCheckPanel extends StatelessWidget {
  const ListeningCheckPanel({
    super.key,
    required this.controller,
    required this.api,
    required this.audioPlayCount,
    required this.onPlaySegment,
    required this.onClose,
  });

  final ReadingTaskController controller;
  final LocalApi api;
  final int Function() audioPlayCount;
  final VoidCallback onPlaySegment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Padding(
              padding: ListenPadding.row,
              child: Row(
                children: [
                  Icon(Icons.hearing_outlined, color: colors.primary),
                  const SizedBox(width: ListenSpacing.gap8),
                  Text(
                    l.text('readingTaskListenTitle'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('listening-check-back'),
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.arrow_back,
                      size: ListenIconSize.control,
                    ),
                    label: Text(l.text('readingTaskListenBack')),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: ReadingTaskSheet(
                controller: controller,
                api: api,
                audioPlayCount: audioPlayCount,
                onPlaySegment: onPlaySegment,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
