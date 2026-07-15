import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/reading_controller.dart';
import '../../controllers/reading_task_controller.dart';
import '../../localization.dart';
import '../../models/semantic_task.dart';
import '../../services/api_service.dart';
import '../panels/reading_task_sheet.dart';

/// Opens the paragraph-task flow (Phase 3.13 Slice 3) as a bottom sheet:
/// localized template → rubric v1 (or reuse the segment's existing rubric)
/// → typed answer → per-point self-assessment → adjudication corrections.
Future<void> openReadingTaskFlow({
  required BuildContext context,
  required LocalApi? api,
  required ReadingTaskController taskController,
  required ReadingController readingController,
  required ReadingTaskSource source,
}) async {
  if (api == null) return;
  final l = AppLocalizations.of(context);
  final template = [
    RubricPointView(
      pointId: 'main-idea',
      importance: 'required',
      statement: l.text('readingTaskPresetMainIdea'),
    ),
    RubricPointView(
      pointId: 'detail',
      importance: 'required',
      statement: l.text('readingTaskPresetDetail'),
    ),
    RubricPointView(
      pointId: 'title',
      importance: 'optional',
      statement: l.text('readingTaskPresetTitle'),
    ),
    RubricPointView(
      pointId: 'inference',
      importance: 'optional',
      statement: l.text('readingTaskPresetInference'),
    ),
  ];
  unawaited(
    taskController.openTask(api, source: source, templatePoints: template),
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ReadingTaskSheet(
      controller: taskController,
      api: api,
      audioPlayCount: () =>
          readingController.slicePlayCount(source.anchorCueId),
    ),
  );
  taskController.closeTask();
}
