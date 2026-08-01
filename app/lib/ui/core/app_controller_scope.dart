import 'package:flutter/widgets.dart';

import '../../controllers/extensive_listening_controller.dart';
import '../../controllers/learning_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/practice_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';

/// Presentation-layer scope for the application-wide controllers and the
/// connected application controllers.
///
/// Object construction remains at the composition root. This widget only
/// exposes already-created dependencies to descendant views; it owns neither
/// their lifecycle nor their business logic.
class AppControllerScope extends InheritedWidget {
  const AppControllerScope({
    required this.player,
    required this.subtitle,
    required this.learning,
    required this.extensiveListening,
    required this.practice,
    required this.settings,
    required super.child,
    super.key,
  });

  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final ExtensiveListeningController extensiveListening;
  final PracticeController practice;
  final SettingsController settings;

  static AppControllerScope of(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(result != null, 'No AppControllerScope found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(AppControllerScope oldWidget) => false;
}
