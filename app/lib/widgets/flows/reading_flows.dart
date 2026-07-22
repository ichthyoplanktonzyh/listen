import '../../localization.dart';
import '../../models/semantic_task.dart';

/// Localized preset points for a reading-comprehension paragraph task.
List<RubricPointView> readingTaskTemplate(AppLocalizations l) => [
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

/// Fallback preset for the listening retell when the segment has no reading
/// rubric to mirror: plain information points, no title/inference games.
List<RubricPointView> listeningRetellTemplate(AppLocalizations l) => [
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
];
