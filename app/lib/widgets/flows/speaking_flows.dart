import '../../localization.dart';
import '../../models/semantic_task.dart';

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
