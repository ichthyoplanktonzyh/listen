import '../../localization.dart';
import '../../models/semantic_task.dart';

/// Fixed communication checkpoints for role reply. They assess whether the
/// learner's response functions in context, never whether it matches a stored
/// sentence word-for-word.
List<RubricPointView> roleReplyTemplate(AppLocalizations l) => [
  RubricPointView(
    pointId: 'responsive',
    importance: 'required',
    statement: l.text('speakingRolePointResponsive'),
  ),
  RubricPointView(
    pointId: 'meaning',
    importance: 'required',
    statement: l.text('speakingRolePointMeaning'),
  ),
  RubricPointView(
    pointId: 'continuation',
    importance: 'optional',
    statement: l.text('speakingRolePointContinuation'),
  ),
];

List<RubricPointView> personalExpressionTemplate(AppLocalizations l) => const [
  RubricPointView(
    pointId: 'personal_meaning',
    importance: 'required',
    statement: 'I expressed a real idea or experience from my own life.',
  ),
  RubricPointView(
    pointId: 'pattern_use',
    importance: 'required',
    statement: 'I used the saved pattern to express that meaning.',
  ),
];
