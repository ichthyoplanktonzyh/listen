import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../controllers/personal_expression_view_model.dart';
import '../data/repositories/personal_expression_repository.dart';
import '../localization.dart';
import '../models/api_failure.dart';
import '../models/personal_expression.dart';
import '../services/api_service.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/listen_theme.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/learning_text_hygiene.dart';
import '../widgets/common/listen_empty_state.dart';
import '../widgets/common/listen_error_state.dart';
import '../widgets/common/listen_loading.dart';

/// Below this many saved patterns the page ends with the starter guide instead
/// of empty space. Three is where the list starts reading as a list: with one
/// or two cards the column is ~85% blank, and blank space that follows content
/// reads as "that's all there is" rather than "here is how you get more".
const _starterGuideThreshold = 3;

/// The scaffolding ladder — four assistance rungs, ordered most help → least.
///
/// The order and the four `value`s mirror the backend `assistance` enum exactly
/// (`template_visible` / `slot_hints` / `keywords` / `no_text`); this list only
/// *presents* them, it never adds semantics (呈现≠语义).
///
/// The 月白→青 light migration (design-notes/listen-expression-redesign.html,
/// owner 方向 A · 2026-07-24): the template is borrowed language (月白
/// [ListenColors.moonWhite]), your own sentence is your signal
/// (`colorScheme.primary`). Retiring one rung of scaffolding moves one part of
/// the light from moon to teal — so `moonFlex` decreases and `signalFlex`
/// increases monotonically down the ladder (0.75 → 0.5 → 0.25 → 0.0 moon).
const _ladderRungs = <_LadderRung>[
  _LadderRung(
    value: 'template_visible',
    labelKey: 'expressionRungTemplateVisible',
    hintKey: 'expressionRungTemplateVisibleHint',
    moonFlex: 3,
    signalFlex: 1,
  ),
  _LadderRung(
    value: 'slot_hints',
    labelKey: 'expressionRungSlotHints',
    hintKey: 'expressionRungSlotHintsHint',
    moonFlex: 2,
    signalFlex: 2,
  ),
  _LadderRung(
    value: 'keywords',
    labelKey: 'expressionRungKeywords',
    hintKey: 'expressionRungKeywordsHint',
    moonFlex: 1,
    signalFlex: 3,
  ),
  _LadderRung(
    value: 'no_text',
    labelKey: 'expressionRungNoText',
    hintKey: 'expressionRungNoTextHint',
    moonFlex: 0,
    signalFlex: 4,
  ),
];

class _LadderRung {
  const _LadderRung({
    required this.value,
    required this.labelKey,
    required this.hintKey,
    required this.moonFlex,
    required this.signalFlex,
  });

  /// The backend `assistance` enum value. Wire vocabulary, never on screen.
  final String value;

  /// Localization keys rather than text: the ladder is a `const` list built
  /// before any `BuildContext` exists, so the wording has to be resolved at
  /// render time or it is welded to whichever language wrote it.
  final String labelKey;
  final String hintKey;

  final int moonFlex;
  final int signalFlex;

  String label(AppLocalizations l) => l.text(labelKey);
  String hint(AppLocalizations l) => l.text(hintKey);
}

int _ladderIndex(String value) {
  final index = _ladderRungs.indexWhere((rung) => rung.value == value);
  return index < 0 ? 0 : index;
}

_LadderRung _rungFor(String value) => _ladderRungs[_ladderIndex(value)];

/// The self-assessment scale: backend value paired with its localization key.
///
/// Order is the scale's order, weakest first. Descriptive words, never a score
/// (charter P4) — and never the raw enum, which is what `template_visible ·
/// partly_expressed` used to put on a history row.
const _assessments = <(String, String)>[
  ('needs_work', 'expressionAssessNeedsWork'),
  ('partly_expressed', 'expressionAssessPartlyExpressed'),
  ('expressed', 'expressionAssessExpressed'),
];

/// The sentence for an assessment value. An unrecognised value degrades to
/// itself rather than to a wrong label — a new scale point from the backend
/// shows up as unfamiliar, not as a lie.
String _assessmentLabel(String value, AppLocalizations l) {
  for (final entry in _assessments) {
    if (entry.$1 == value) return l.text(entry.$2);
  }
  return value;
}

/// Human relative time for a `completed_at_ms` epoch, so a history row reads as
/// a moment instead of a millisecond stamp.
String _relativeTime(int ms, AppLocalizations l) {
  String at(String key, int count) =>
      l.text(key).replaceAll('{count}', '$count');
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60000) return l.text('expressionTimeJustNow');
  final minutes = diff ~/ 60000;
  if (minutes < 60) return at('expressionTimeMinutesAgo', minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) return at('expressionTimeHoursAgo', hours);
  final days = hours ~/ 24;
  if (days < 30) return at('expressionTimeDaysAgo', days);
  final months = days ~/ 30;
  if (months < 12) return at('expressionTimeMonthsAgo', months);
  return at('expressionTimeYearsAgo', days ~/ 365);
}

/// The most recent `writing` attempt, or null when the learner has never
/// written for this pattern. Pure front-end aggregation over existing attempts.
PersonalExpressionAttemptView? _lastWriting(
  List<PersonalExpressionAttemptView> attempts,
) {
  PersonalExpressionAttemptView? latest;
  for (final attempt in attempts) {
    if (attempt.channel != 'writing') continue;
    if (latest == null || attempt.completedAtMs > latest.completedAtMs) {
      latest = attempt;
    }
  }
  return latest;
}

/// Count of `writing` attempts per assistance rung — the "用过 N 次" source.
/// Returns an empty map when there is no writing history, so callers can tell
/// "0 for this rung" apart from "no history at all" and avoid fabricating.
Map<String, int> _writingUsage(List<PersonalExpressionAttemptView> attempts) {
  final counts = <String, int>{};
  for (final attempt in attempts) {
    if (attempt.channel != 'writing') continue;
    counts[attempt.assistance] = (counts[attempt.assistance] ?? 0) + 1;
  }
  return counts;
}

/// A two-segment light bar: 月白 (borrowed language) on the left giving way to
/// signal teal (your own language) on the right. The same color language as the
/// conversation page's echo water (design charter 光源家族) — but the数据 here
/// is scaffolding retirement, not the four-channel capability of
/// [CapabilityEchoBars], so it is a dedicated small mark rather than a reuse.
class _LightMixBar extends StatelessWidget {
  const _LightMixBar({
    required this.moonFlex,
    required this.signalFlex,
    this.height = 9,
    this.width,
  });

  final int moonFlex;
  final int signalFlex;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: ListenRadii.tightBorder,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (moonFlex > 0)
            Expanded(
              flex: moonFlex,
              child: const ColoredBox(color: ListenColors.moonWhite),
            ),
          if (signalFlex > 0)
            Expanded(
              flex: signalFlex,
              child: ColoredBox(color: scheme.primary),
            ),
        ],
      ),
    );
  }
}

/// The visible ladder used inside the writing desk. Four rungs, current one
/// highlighted, each tail-labelled 「你在这」/「用过 N 次」/「还没试过」.
///
/// When [usage] is null (no writing history) only the current rung is marked
/// 「你在这」 — the other rungs stay silent rather than claim 「还没试过」, so an
/// empty history never fabricates a trajectory (owner 拍板 · 前端聚合).
class _AssistanceLadder extends StatelessWidget {
  const _AssistanceLadder({
    required this.current,
    required this.usage,
    required this.onSelect,
  });

  final String current;
  final Map<String, int>? usage;
  final ValueChanged<String> onSelect;

  String? _tail(_LadderRung rung, AppLocalizations l) {
    if (rung.value == current) return l.text('expressionRungCurrent');
    if (usage == null) return null;
    final count = usage![rung.value] ?? 0;
    return count > 0
        ? l.text('expressionRungUsed').replaceAll('{count}', '$count')
        : l.text('expressionRungUntried');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rung in _ladderRungs)
          Semantics(
            button: true,
            selected: rung.value == current,
            label: '${rung.label(l)} · ${rung.hint(l)}',
            child: InkWell(
              borderRadius: ListenRadii.controlBorder,
              onTap: () => onSelect(rung.value),
              child: AnimatedContainer(
                duration: reduceMotion ? Duration.zero : ListenMotion.base,
                curve: ListenMotion.move,
                padding: ListenPadding.row,
                decoration: BoxDecoration(
                  borderRadius: ListenRadii.controlBorder,
                  color: rung.value == current
                      ? scheme.secondaryContainer
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: rung.value == current
                          ? scheme.secondary
                          : scheme.outlineVariant,
                      width: rung.value == current ? 3 : 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rung.label(l), style: textTheme.labelLarge),
                          Text(
                            rung.hint(l),
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: ListenSpacing.gap12),
                    _LightMixBar(
                      moonFlex: rung.moonFlex,
                      signalFlex: rung.signalFlex,
                      width: 132,
                    ),
                    const SizedBox(width: ListenSpacing.gap12),
                    Expanded(
                      child: Text(
                        _tail(rung, l) ?? '',
                        textAlign: TextAlign.right,
                        style: textTheme.labelSmall?.copyWith(
                          color: rung.value == current
                              ? scheme.secondary
                              : (usage?[rung.value] ?? 0) > 0
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PersonalExpressionScreen extends StatefulWidget {
  const PersonalExpressionScreen({
    super.key,
    this.api,
    this.repository,
    this.viewModel,
    required this.language,
    this.initialSource,
    this.onPlaySource,
    this.onStartSpeaking,
  }) : assert(api != null || repository != null);

  /// [api] keeps existing composition roots source-compatible. New callers
  /// should inject the narrow [repository] boundary directly.
  final LocalApi? api;
  final PersonalExpressionRepository? repository;
  final PersonalExpressionViewModel? viewModel;
  final String language;
  final PersonalExpressionSourceView? initialSource;
  final Future<void> Function(PersonalExpressionSourceView source)?
  onPlaySource;
  final Future<void> Function(SentencePatternAssetView pattern)?
  onStartSpeaking;

  @override
  State<PersonalExpressionScreen> createState() =>
      _PersonalExpressionScreenState();
}

class _PersonalExpressionScreenState extends State<PersonalExpressionScreen> {
  late final PersonalExpressionRepository _repository =
      widget.repository ?? LocalPersonalExpressionRepository(widget.api!);
  late final PersonalExpressionViewModel _viewModel =
      widget.viewModel ??
      PersonalExpressionViewModel(_repository, language: widget.language);
  late final bool _ownsViewModel = widget.viewModel == null;

  @override
  void initState() {
    super.initState();
    unawaited(
      _viewModel.load().then((_) {
        if (mounted && widget.initialSource != null) {
          unawaited(_edit(source: widget.initialSource));
        }
      }),
    );
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    try {
      final bundle = await _viewModel.export();
      final location = await getSaveLocation(
        suggestedName: 'llplayer-personal-expression.json',
      );
      if (location == null) return;
      await File(location.path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundle.toJson()),
      );
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      _notify(
        l
            .text('expressionExported')
            .replaceAll('{count}', '${bundle.patternCount}')
            .replaceAll('{path}', location.path),
      );
    } catch (error) {
      if (!mounted) return;
      // The export can fail in the API *or* in the file write, and neither
      // exception says anything a learner can use. One named state, and the
      // reference id only when the backend supplied one.
      final l = AppLocalizations.of(context);
      final detail = describeApiFailure(error);
      final reference = detail.correlationId;
      _notify(
        reference == null
            ? l.text('expressionExportFailed')
            : '${l.text('expressionExportFailed')} '
                  '${l.text('failureReference').replaceAll('{id}', reference)}',
        isError: true,
      );
    }
  }

  /// The load failure's sentence, plus the reference id when the backend gave
  /// one. The error code, the operator-facing message and [ApiFailure.raw] stay
  /// off screen entirely.
  String _loadNotice(AppLocalizations l) {
    final sentence = l.text('expressionListFailed');
    final reference = _viewModel.failure?.correlationId;
    if (reference == null) return sentence;
    return '$sentence '
        '${l.text('failureReference').replaceAll('{id}', reference)}';
  }

  void _notify(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError ? scheme.onError : scheme.onInverseSurface,
          ),
        ),
        backgroundColor: isError ? scheme.error : scheme.inverseSurface,
      ),
    );
  }

  List<SentencePatternSlotView> _slots(String raw) => raw
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map((name) => SentencePatternSlotView(name: name))
      .toList(growable: false);

  Future<void> _edit({
    SentencePatternAssetView? pattern,
    PersonalExpressionSourceView? source,
  }) async {
    final current = pattern?.currentVersion;
    final effectiveSource =
        source ??
        pattern?.source ??
        const PersonalExpressionSourceView(kind: 'manual', text: '');
    final name = TextEditingController(text: current?.name ?? '');
    // A new pattern is seeded from the captured line, so it is seeded clean —
    // otherwise every subtitle's `- ` is typed straight into stored data and
    // display cleaning only hides it. The immutable source snapshot below
    // keeps the raw line exactly as captured.
    final patternText = TextEditingController(
      text:
          current?.patternText ??
          cleanLearningText(effectiveSource.text, language: widget.language),
    );
    final slotNames = TextEditingController(
      text: current?.slots.map((slot) => slot.name).join(', ') ?? '',
    );
    final note = TextEditingController(text: current?.note ?? '');
    final sourceText = TextEditingController(text: effectiveSource.text);
    final l = AppLocalizations.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          l.text(
            pattern == null ? 'expressionSaveTitle' : 'expressionEditTitle',
          ),
        ),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: l.text('expressionFieldName'),
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: sourceText,
                  enabled: pattern == null && source == null,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l.text('expressionFieldSource'),
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: patternText,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: l.text('expressionFieldPattern'),
                    // The example is in the *learning* language, not the
                    // interface language: it demonstrates the shape a pattern
                    // takes, and translating it would demonstrate the wrong
                    // one (AGENT.md keeps the two separate).
                    hintText: 'I ended up {result}.',
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: slotNames,
                  decoration: InputDecoration(
                    labelText: l.text('expressionFieldSlots'),
                    hintText: 'result, reason',
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: l.text('expressionFieldNote'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty ||
                  patternText.text.trim().isEmpty ||
                  sourceText.text.trim().isEmpty) {
                return;
              }
              if (pattern == null) {
                await _viewModel.create(
                  source: PersonalExpressionSourceView(
                    kind: effectiveSource.kind,
                    text: sourceText.text.trim(),
                    title: effectiveSource.title,
                    mediaId: effectiveSource.mediaId,
                    mediaFingerprint: effectiveSource.mediaFingerprint,
                    trackId: effectiveSource.trackId,
                    sentenceId: effectiveSource.sentenceId,
                    semanticAttemptId: effectiveSource.semanticAttemptId,
                    startMs: effectiveSource.startMs,
                    endMs: effectiveSource.endMs,
                    candidateRef: effectiveSource.candidateRef,
                  ),
                  name: name.text.trim(),
                  patternText: patternText.text.trim(),
                  slots: _slots(slotNames.text),
                  note: note.text.trim().isEmpty ? null : note.text.trim(),
                );
              } else {
                await _viewModel.revise(
                  pattern: pattern,
                  name: name.text.trim(),
                  patternText: patternText.text.trim(),
                  slots: _slots(slotNames.text),
                  note: note.text.trim().isEmpty ? null : note.text.trim(),
                );
              }
              if (context.mounted) Navigator.pop(context, true);
            },
            child: Text(l.text('save')),
          ),
        ],
      ),
    );
    name.dispose();
    patternText.dispose();
    slotNames.dispose();
    note.dispose();
    sourceText.dispose();
    if (saved == true) await _viewModel.refresh();
  }

  Future<void> _open(SentencePatternAssetView pattern) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PatternDetail(
          repository: _repository,
          pattern: pattern,
          onEdit: () async {
            Navigator.of(context).pop();
            await _edit(pattern: pattern);
          },
          onPlaySource: widget.onPlaySource,
          onStartSpeaking: widget.onStartSpeaking == null
              ? null
              : (value) async {
                  Navigator.of(context).pop();
                  await widget.onStartSpeaking!(value);
                },
        ),
      ),
    );
    await _viewModel.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.text('personalExpressions')),
        actions: [
          _ChromeAction(
            icon: Icons.download_outlined,
            label: l.text('expressionExportAction'),
            onPressed: () => unawaited(_export()),
          ),
          _ChromeAction(
            icon: Icons.add,
            label: l.text('expressionNewAction'),
            onPressed: () => unawaited(_edit()),
          ),
        ],
      ),
      // One measurement basis for the whole page. The search field used to sit
      // outside the column cap and stretched to the window (~950pt) while the
      // cards below stopped at 780 — two rulers on one page, so the field read
      // as chrome belonging to some other screen. The cap now wraps search,
      // error and list together, which makes "same width" structural rather
      // than a number repeated in three places (§1.3).
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ListenBreakpoints.contentColumnMax,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: ListenPadding.pageCompact.copyWith(bottom: 0),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.search,
                        size: ListenIconSize.control,
                      ),
                      hintText: l.text('search'),
                    ),
                    onChanged: _viewModel.setQuery,
                  ),
                ),
                if (_viewModel.failure != null)
                  Padding(
                    padding: ListenPadding.pageCompact.copyWith(bottom: 0),
                    child: ListenErrorNotice(message: _loadNotice(l)),
                  ),
                Expanded(child: _list(l)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(AppLocalizations l) {
    if (_viewModel.loading) return const Center(child: ListenLoading());
    if (_viewModel.patterns.isEmpty) {
      return ListenEmptyState(
        icon: Icons.edit_note,
        message:
            '${l.text('expressionStarterTitle')}\n'
            '${l.text('expressionStarterBody')}',
        action: TextButton.icon(
          onPressed: () => unawaited(_edit()),
          icon: const Icon(Icons.add, size: ListenIconSize.control),
          label: Text(l.text('expressionStarterCreate')),
        ),
      );
    }
    // The guide is a tail item of the same list rather than a sibling below
    // it, so a short list scrolls as one thing and the guide is never pinned
    // to the bottom of a mostly empty page.
    final showGuide = _viewModel.patterns.length < _starterGuideThreshold;
    return ListView.separated(
      padding: ListenPadding.pageCompact.copyWith(top: ListenSpacing.gap16),
      itemCount: _viewModel.patterns.length + (showGuide ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: ListenSpacing.gap8),
      itemBuilder: (context, index) {
        if (index == _viewModel.patterns.length) {
          return _StarterGuide(onCreate: () => unawaited(_edit()));
        }
        final pattern = _viewModel.patterns[index];
        return _PatternCard(
          pattern: pattern,
          lastWritten: _viewModel.lastWritten[pattern.id],
          onTap: () => unawaited(_open(pattern)),
        );
      },
    );
  }
}

/// An `AppBar` action that says what it does. Two bare glyphs (download, `+`)
/// with no label is the quietest possible chrome and also the least legible —
/// Things 3's toolbar is quiet *and* named. So the name is always present:
/// as visible text once the window has room ([ListenBreakpoints.appBarLabels],
/// the same threshold the player app bar uses), and as a tooltip below it,
/// which is also what a screen reader announces.
class _ChromeAction extends StatelessWidget {
  const _ChromeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final labelled =
        MediaQuery.sizeOf(context).width >= ListenBreakpoints.appBarLabels;
    if (!labelled) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, size: ListenIconSize.chrome),
        onPressed: onPressed,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: ListenSpacing.gap4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: ListenIconSize.chrome),
        label: Text(label),
      ),
    );
  }
}

/// What to do when there is almost nothing here yet.
///
/// One or two saved patterns leave the column ~85% empty, and that emptiness
/// carries no information. The guide replaces it with the one thing a learner
/// can act on — patterns come from subtitle lines you keep while watching —
/// plus the only entry this page actually owns (writing one by hand). It stays
/// muted and offers no reward, streak or nudge (charter P3).
class _StarterGuide extends StatelessWidget {
  const _StarterGuide({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: ListenSpacing.gap24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.subtitles_outlined,
                size: ListenIconSize.control,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Text(
                l.text('expressionStarterTitle'),
                style: textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap6),
          Text(
            l.text('expressionStarterBody'),
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: ListenSpacing.gap8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: ListenIconSize.control),
              label: Text(l.text('expressionStarterCreate')),
            ),
          ),
        ],
      ),
    );
  }
}

/// E3 list card: the template text is the protagonist (large), the name is a
/// small eyebrow, the source recedes to a footnote, and the last sentence the
/// learner wrote appears in signal teal (你的语言=光).
///
/// Captured text passes through [cleanLearningText] on the way to the screen —
/// the subtitle's `- ` and a stray fullwidth `。` are the file's formatting,
/// not the learner's sentence. The learner's own writing (`你上次写`) is
/// rendered exactly as written.
class _PatternCard extends StatelessWidget {
  const _PatternCard({
    required this.pattern,
    required this.lastWritten,
    required this.onTap,
  });

  final SentencePatternAssetView pattern;
  final PersonalExpressionAttemptView? lastWritten;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final version = pattern.currentVersion;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: ListenPadding.card,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      version.name,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap4),
                    Text(
                      cleanLearningText(
                        version.patternText,
                        language: pattern.language,
                      ),
                      style: textTheme.titleMedium,
                    ),
                    if (lastWritten != null) ...[
                      const SizedBox(height: ListenSpacing.gap6),
                      Text(
                        l
                            .text('expressionLastWrote')
                            .replaceAll('{text}', lastWritten!.responseText),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: ListenSpacing.gap6),
                    Text(
                      l
                          .text('expressionSourceLine')
                          .replaceAll(
                            '{text}',
                            cleanLearningText(
                              pattern.source.text,
                              language: pattern.language,
                            ),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatternDetail extends StatefulWidget {
  const _PatternDetail({
    required this.repository,
    required this.pattern,
    required this.onEdit,
    this.onPlaySource,
    this.onStartSpeaking,
  });
  final PersonalExpressionRepository repository;
  final SentencePatternAssetView pattern;
  final Future<void> Function() onEdit;
  final Future<void> Function(PersonalExpressionSourceView source)?
  onPlaySource;
  final Future<void> Function(SentencePatternAssetView pattern)?
  onStartSpeaking;
  @override
  State<_PatternDetail> createState() => _PatternDetailState();
}

class _PatternDetailState extends State<_PatternDetail> {
  late final PersonalExpressionDetailViewModel _viewModel =
      PersonalExpressionDetailViewModel(
        widget.repository,
        pattern: widget.pattern,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_viewModel.load());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// 弹窗死刑: the writing flow is a page (the writing desk), not a dialog.
  Future<void> _write() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _WritingDeskPage(
          viewModel: _viewModel,
          pattern: widget.pattern,
          attempts: _viewModel.attempts,
        ),
      ),
    );
    if (saved == true) await _viewModel.load();
  }

  /// E1: deletion states its blast radius (N versions + M usage records) before
  /// anything is destroyed, matching the coach graduation flow spec.
  Future<void> _confirmDelete() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('expressionDeleteTitle')),
        content: Text(
          l
              .text('expressionDeleteBody')
              .replaceAll('{versions}', '${_viewModel.versions.length}')
              .replaceAll('{attempts}', '${_viewModel.attempts.length}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.text('expressionDelete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _viewModel.delete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pattern.currentVersion.name),
        actions: [
          IconButton(
            onPressed: () => unawaited(widget.onEdit()),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.loading) {
            return const Center(child: ListenLoading());
          }
          if (_viewModel.failure != null) {
            final reference = _viewModel.failure?.correlationId;
            final message = reference == null
                ? l.text('expressionListFailed')
                : '${l.text('expressionListFailed')} '
                      '${l.text('failureReference').replaceAll('{id}', reference)}';
            return ListenErrorState(
              message: message,
              action: TextButton.icon(
                key: const ValueKey('personal-expression-detail-retry'),
                onPressed: () => unawaited(_viewModel.load()),
                icon: const Icon(Icons.refresh),
                label: Text(l.text('retry')),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ListenBreakpoints.contentColumnMax,
              ),
              child: ListView(
                padding: ListenPadding.pageCompact,
                children: [
                  Text(
                    cleanLearningText(
                      widget.pattern.currentVersion.patternText,
                      language: widget.pattern.language,
                    ),
                    // The page title lives in the AppBar's name, so the pattern
                    // itself is this page's hero (titleLarge = ListenType.hero);
                    // `headlineSmall` was an unmapped Material slot at 24px w400,
                    // a size the ladder never defined.
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: ListenSpacing.gap8),
                  Text(
                    l
                        .text('expressionSourceSnapshot')
                        .replaceAll(
                          '{text}',
                          cleanLearningText(
                            widget.pattern.source.text,
                            language: widget.pattern.language,
                          ),
                        ),
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.pattern.currentVersion.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: ListenSpacing.gap4),
                      child: Text(
                        l
                            .text('expressionNoteLine')
                            .replaceAll(
                              '{text}',
                              '${widget.pattern.currentVersion.note}',
                            ),
                      ),
                    ),
                  const SizedBox(height: ListenSpacing.gap8),
                  Wrap(
                    spacing: ListenSpacing.gap8,
                    children: [
                      for (final slot in widget.pattern.currentVersion.slots)
                        Chip(label: Text(slot.name)),
                    ],
                  ),
                  const SizedBox(height: ListenSpacing.gap16),
                  Wrap(
                    spacing: ListenSpacing.gap8,
                    runSpacing: ListenSpacing.gap8,
                    children: [
                      FilledButton.icon(
                        onPressed: _write,
                        icon: const Icon(Icons.edit_note),
                        label: Text(l.text('expressionWriteYourOwn')),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onStartSpeaking == null
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await widget.onStartSpeaking!(widget.pattern);
                              },
                        icon: const Icon(Icons.mic_none),
                        label: Text(l.text('expressionSpeakUnscripted')),
                      ),
                      if (widget.onPlaySource != null)
                        OutlinedButton.icon(
                          onPressed:
                              widget.pattern.source.mediaId == null ||
                                  widget.pattern.source.mediaFingerprint == null
                              ? null
                              : () =>
                                    widget.onPlaySource!(widget.pattern.source),
                          icon: const Icon(Icons.volume_up_outlined),
                          label: Text(l.text('expressionPlaySource')),
                        ),
                    ],
                  ),
                  const Divider(height: 40),
                  // A section title inside the page, not a second hero.
                  Text(
                    l.text('expressionUsageHistory'),
                    style: textTheme.titleMedium,
                  ),
                  if (_viewModel.attempts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: ListenSpacing.gap16,
                      ),
                      child: Text(l.text('expressionNoUsageYet')),
                    ),
                  for (final attempt in _viewModel.attempts)
                    _HistoryRow(attempt: attempt),
                  const Divider(height: 40),
                  ExpansionTile(
                    title: Text(
                      l
                          .text('expressionVersionHistory')
                          .replaceAll(
                            '{count}',
                            '${_viewModel.versions.length}',
                          ),
                    ),
                    children: [
                      for (final version in _viewModel.versions)
                        ListTile(
                          title: Text(
                            l
                                .text('expressionVersionLine')
                                .replaceAll('{version}', '${version.version}')
                                .replaceAll('{name}', version.name),
                          ),
                          subtitle: Text(
                            cleanLearningText(
                              version.patternText,
                              language: widget.pattern.language,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: ListenSpacing.gap24),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    onPressed: () => unawaited(_confirmDelete()),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.text('expressionDeleteAction')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// E4: a usage-history row shows the ladder mix bar for the assistance rung the
/// learner stood on, plus 人话 (rung name + self-assessment) and relative time,
/// instead of raw `template_visible · partly_expressed`.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.attempt});

  final PersonalExpressionAttemptView attempt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rung = _rungFor(attempt.assistance);
    final channelLabel = l.text(
      attempt.channel == 'speaking'
          ? 'expressionChannelSpoken'
          : 'expressionChannelWritten',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: ListenSpacing.gap4),
            child: _LightMixBar(
              moonFlex: rung.moonFlex,
              signalFlex: rung.signalFlex,
              width: 44,
              height: 7,
            ),
          ),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attempt.responseText, style: textTheme.bodyMedium),
                const SizedBox(height: ListenSpacing.gap2),
                Text(
                  '$channelLabel · ${rung.label(l)} · '
                  '${_assessmentLabel(attempt.selfAssessment, l)} · '
                  '${_relativeTime(attempt.completedAtMs, l)}',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The in-page writing desk (弹窗死刑). The ladder is on top, the template area
/// appears/recedes with the chosen rung, and your sentence is written below in
/// signal teal. Saving records a `writing` attempt — no new backend semantics.
class _WritingDeskPage extends StatefulWidget {
  const _WritingDeskPage({
    required this.viewModel,
    required this.pattern,
    required this.attempts,
  });

  final PersonalExpressionDetailViewModel viewModel;
  final SentencePatternAssetView pattern;
  final List<PersonalExpressionAttemptView> attempts;

  @override
  State<_WritingDeskPage> createState() => _WritingDeskPageState();
}

class _WritingDeskPageState extends State<_WritingDeskPage> {
  final _response = TextEditingController();
  late final Map<String, TextEditingController> _slotValues = {
    for (final slot in widget.pattern.currentVersion.slots)
      slot.name: TextEditingController(),
  };
  String _assistance = 'template_visible';
  String _assessment = 'partly_expressed';
  bool _hintDismissed = false;
  bool _saving = false;

  @override
  void dispose() {
    _response.dispose();
    for (final controller in _slotValues.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// A gentle downshift suggestion (P3 建议≠判定): only when the most recent
  /// writing attempt felt "表达自然" and the learner was not already on the
  /// bottom rung. It never auto-downshifts and is dismissible; within a desk
  /// session it is shown once. (No cross-session preference store exists yet, so
  /// "只提一次" is scoped to this session — no new backend is invented.)
  _LadderRung? get _downshiftTarget {
    if (_hintDismissed) return null;
    final last = _lastWriting(widget.attempts);
    if (last == null || last.selfAssessment != 'expressed') return null;
    final index = _ladderIndex(last.assistance);
    if (index >= _ladderRungs.length - 1) return null;
    return _ladderRungs[index + 1];
  }

  void _generateDraft() {
    var draft = cleanLearningText(
      widget.pattern.currentVersion.patternText,
      language: widget.pattern.language,
    );
    for (final entry in _slotValues.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) {
        draft = draft.replaceAll('{${entry.key}}', value);
      }
    }
    _response.text = draft;
  }

  Future<void> _save() async {
    if (_response.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.viewModel.recordWritingAttempt(
        assistance: _assistance,
        responseText: _response.text.trim(),
        selfAssessment: _assessment,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      // A named state, not the exception. `describeApiFailure` keeps the
      // transport text on an `ApiFailure` that is never rendered; only the
      // reference id travels, and only when the backend supplied one.
      final l = AppLocalizations.of(context);
      final reference = describeApiFailure(error).correlationId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reference == null
                ? l.text('expressionAttemptSaveFailed')
                : '${l.text('expressionAttemptSaveFailed')} '
                      '${l.text('failureReference').replaceAll('{id}', reference)}',
          ),
        ),
      );
    }
  }

  Widget _templateArea(
    ColorScheme scheme,
    TextTheme textTheme,
    AppLocalizations l,
  ) {
    final version = widget.pattern.currentVersion;
    final mutedStyle = textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    switch (_assistance) {
      case 'template_visible':
        return Column(
          key: const ValueKey('template_visible'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cleanLearningText(
                version.patternText,
                language: widget.pattern.language,
              ),
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            for (final slot in version.slots)
              Padding(
                padding: const EdgeInsets.only(top: ListenSpacing.gap8),
                child: TextField(
                  controller: _slotValues[slot.name],
                  decoration: InputDecoration(
                    labelText:
                        slot.prompt ??
                        l
                            .text('expressionSlotFallbackLabel')
                            .replaceAll('{slot}', slot.name),
                    hintText: slot.exampleValue,
                  ),
                ),
              ),
            if (_slotValues.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _generateDraft,
                  child: Text(l.text('expressionGenerateDraft')),
                ),
              ),
          ],
        );
      case 'slot_hints':
        return Column(
          key: const ValueKey('slot_hints'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.text('expressionSlotOnlyIntro'), style: mutedStyle),
            for (final slot in version.slots)
              Padding(
                padding: const EdgeInsets.only(top: ListenSpacing.gap8),
                child: TextField(
                  controller: _slotValues[slot.name],
                  decoration: InputDecoration(
                    labelText: slot.prompt ?? slot.name,
                    hintText: slot.exampleValue,
                  ),
                ),
              ),
          ],
        );
      case 'keywords':
        return Text(
          key: const ValueKey('keywords'),
          version.slots.isEmpty
              ? l.text('expressionNoKeywords')
              : l
                    .text('expressionKeywordsLine')
                    .replaceAll(
                      '{list}',
                      version.slots.map((slot) => slot.name).join(' · '),
                    ),
          style: mutedStyle,
        );
      default:
        return Text(
          key: const ValueKey('no_text'),
          l.text('expressionNoTemplateHint'),
          style: mutedStyle,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final usage = _writingUsage(widget.attempts);
    final target = _downshiftTarget;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l
              .text('expressionWriteTitle')
              .replaceAll('{name}', widget.pattern.currentVersion.name),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.contentColumnMax,
          ),
          child: ListView(
            padding: ListenPadding.pageCompact,
            children: [
              if (target != null)
                Container(
                  margin: const EdgeInsets.only(bottom: ListenSpacing.gap16),
                  padding: const EdgeInsets.all(ListenSpacing.gap12),
                  decoration: BoxDecoration(
                    borderRadius: ListenRadii.surfaceBorder,
                    color: scheme.secondaryContainer,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l
                              .text('expressionDownshiftHint')
                              .replaceAll('{rung}', target.label(l)),
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _hintDismissed = true),
                        child: Text(l.text('expressionDownshiftDismiss')),
                      ),
                    ],
                  ),
                ),
              Text(
                l.text('expressionLadderTitle'),
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              _AssistanceLadder(
                current: _assistance,
                usage: usage.isEmpty ? null : usage,
                onSelect: (value) => setState(() => _assistance = value),
              ),
              const SizedBox(height: ListenSpacing.gap16),
              AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : ListenMotion.base,
                switchInCurve: ListenMotion.enter,
                switchOutCurve: ListenMotion.exit,
                child: _templateArea(scheme, textTheme, l),
              ),
              const SizedBox(height: ListenSpacing.gap16),
              Text(
                l.text('expressionYourSentence'),
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              TextField(
                controller: _response,
                minLines: 3,
                maxLines: 8,
                style: textTheme.bodyLarge?.copyWith(color: scheme.primary),
                decoration: InputDecoration(
                  hintText: l.text('expressionYourSentenceHint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: ListenSpacing.gap16),
              Text(
                l.text('expressionHowItFelt'),
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Wrap(
                spacing: ListenSpacing.gap8,
                children: [
                  for (final entry in _assessments)
                    ChoiceChip(
                      label: Text(l.text(entry.$2)),
                      selected: _assessment == entry.$1,
                      onSelected: (_) => setState(() => _assessment = entry.$1),
                    ),
                ],
              ),
              const SizedBox(height: ListenSpacing.gap24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(l.text('expressionSaveAttempt')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
