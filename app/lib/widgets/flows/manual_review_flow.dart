import 'package:flutter/material.dart';

import '../../controllers/manual_review_flow_controller.dart';
import '../../localization.dart';
import '../panels/manual_timeline_review_dialog.dart';

/// Opens the sentence-level manual word-timing review dialog for the active
/// WordTimeline and saves the user-adjusted revision. Extracted from the
/// composition root. The "status pristine" flag (whether the review status
/// text has not been superseded by a save result) lives entirely within one
/// flow invocation, so it is a local here rather than host state.
Future<void> openManualReviewFlow({
  required BuildContext context,
  required ManualReviewFlowController controller,
}) async {
  final l = AppLocalizations.of(context);
  controller.reportStatus(l.text('statusManualReviewLoading'));
  final preparation = await controller.prepare();
  if (!context.mounted) return;
  switch (preparation) {
    case ManualReviewUnavailable():
      controller.reportStatus(l.text('statusConnectLocalCoreFirst'));
    case ManualReviewNoTrack():
      controller.reportStatus(l.text('statusActivateSubtitleFirst'));
    case ManualReviewNoTimeline():
      controller.reportStatus(l.text('statusManualReviewNoTimeline'));
    case ManualReviewNoWords():
      controller.reportStatus(l.text('statusManualReviewNoWords'));
    case ManualReviewLoadFailed(:final failure):
      controller.reportStatus(
        l.text('statusManualReviewFailed'),
        error: true,
        failure: failure,
      );
    case ManualReviewSuperseded():
      return;
    case ManualReviewReady(:final editor):
      final previousLoopStart = controller.loopStart;
      final previousLoopEnd = controller.loopEnd;
      try {
        await showDialog<void>(
          context: context,
          builder: (_) => ManualTimelineReviewDialog(
            viewModel: editor,
            onPlayRange: controller.playRange,
            onSave: () async {
              controller.reportStatus(l.text('statusManualReviewSaving'));
              await controller.saveCurrent();
              if (context.mounted) {
                controller.reportStatus(l.text('statusManualReviewSaved'));
              }
            },
          ),
        );
      } finally {
        controller.restoreLoop(previousLoopStart, previousLoopEnd);
      }
      if (context.mounted && !controller.state.saveAttempted) {
        controller.reportStatus(l.text('statusManualReviewClosed'));
      }
  }
}
