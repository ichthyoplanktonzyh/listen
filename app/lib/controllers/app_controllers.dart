import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'learning_controller.dart';
import 'player_controller.dart';
import 'practice_controller.dart';
import 'settings_controller.dart';
import 'subtitle_controller.dart';

/// Top-level InheritedWidget that provides all controllers and services
/// down the widget tree without prop drilling.
///
/// Usage:
/// ```dart
/// final ctrl = AppControllers.of(context);
/// final playing = ctrl.player.playing;
/// ```
class AppControllers extends InheritedWidget {
  const AppControllers({
    required this.player,
    required this.subtitle,
    required this.learning,
    required this.practice,
    required this.settings,
    required this.api,
    required super.child,
    super.key,
  });

  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final PracticeController practice;
  final SettingsController settings;
  final LocalApi api;

  /// Retrieve the nearest [AppControllers] ancestor.
  static AppControllers of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppControllers>();
    assert(result != null, 'No AppControllers found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(AppControllers oldWidget) => false;
}
