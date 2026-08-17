import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/cold_start_marking_view_model.dart';
import '../../controllers/phonetic_analysis_view_model.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/resource_actions_coordinator.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../phonetic_analysis_ui.dart';
import '../panels/cold_start_marking_sheet.dart';

/// Dialog-driven analysis flows shared by the workbench.
/// Parameter names mirror the host's controller fields.

typedef ColdStartMarkingViewModelFactory =
    ColdStartMarkingViewModel Function({
      required String trackId,
      required String language,
    });

class _OwnedNotifierRoute extends StatefulWidget {
  const _OwnedNotifierRoute({required this.notifier, required this.child});

  final ChangeNotifier notifier;
  final Widget child;

  @override
  State<_OwnedNotifierRoute> createState() => _OwnedNotifierRouteState();
}

class _OwnedNotifierRouteState extends State<_OwnedNotifierRoute> {
  @override
  void dispose() {
    widget.notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> openPhoneticAnalysisCenterFlow({
  required BuildContext context,
  required PhoneticAnalysisViewModel? viewModel,
  required PlayerController playerController,
}) async {
  if (viewModel == null) {
    // Unavailable State (CONTEXT.md): the analysis center is a user menu
    // entry; report the missing core instead of swallowing the click.
    final l = AppLocalizations.of(context);
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _OwnedNotifierRoute(
        notifier: viewModel,
        child: PhoneticAnalysisCenter(viewModel: viewModel),
      ),
    ),
  );
}

void openColdStartMarkingFlow({
  required BuildContext context,
  required ColdStartMarkingViewModelFactory? createViewModel,
  required PlayerController playerController,
  required SubtitleController subtitleController,
  required ResourceActionsCoordinator resourceActions,
}) {
  final l = AppLocalizations.of(context);
  final trackId = subtitleController.primaryTrack?.id;
  final language = subtitleController.primaryTrack?.language;
  // Unavailable State (CONTEXT.md): the cold-start button renders whenever
  // the content-fit card does, so each missing prerequisite names its own
  // recovery action instead of leaving a dead button.
  if (createViewModel == null) {
    playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
    return;
  }
  if (trackId == null) {
    playerController.setStatus(l.text('statusActivateSubtitleFirst'));
    return;
  }
  if (language == null) {
    playerController.setStatus(l.text('statusSetSubtitleLanguageFirst'));
    return;
  }
  final viewModel = createViewModel(trackId: trackId, language: language);
  showDialog<void>(
    context: context,
    builder: (_) => ColdStartMarkingSheet(
      viewModel: viewModel,
      onDone: () => resourceActions.loadContentFit(trackId),
    ),
  ).whenComplete(viewModel.dispose);
}
