import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/personal_expression.dart';
import '../services/api_service.dart';
import '../theme/breakpoints.dart';
import '../theme/listen_theme.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/common/listen_empty_state.dart';
import '../widgets/common/listen_error_state.dart';
import '../widgets/common/listen_loading.dart';

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
    label: '看完整模板',
    hint: '模板 + 槽位全给',
    moonFlex: 3,
    signalFlex: 1,
  ),
  _LadderRung(
    value: 'slot_hints',
    label: '只看槽位',
    hint: '只规划内容，不给结构',
    moonFlex: 2,
    signalFlex: 2,
  ),
  _LadderRung(
    value: 'keywords',
    label: '只看关键词',
    hint: '只剩词，句子归你',
    moonFlex: 1,
    signalFlex: 3,
  ),
  _LadderRung(
    value: 'no_text',
    label: '不看模板',
    hint: '全是你的语言',
    moonFlex: 0,
    signalFlex: 4,
  ),
];

class _LadderRung {
  const _LadderRung({
    required this.value,
    required this.label,
    required this.hint,
    required this.moonFlex,
    required this.signalFlex,
  });

  final String value;
  final String label;
  final String hint;
  final int moonFlex;
  final int signalFlex;
}

int _ladderIndex(String value) {
  final index = _ladderRungs.indexWhere((rung) => rung.value == value);
  return index < 0 ? 0 : index;
}

_LadderRung _rungFor(String value) => _ladderRungs[_ladderIndex(value)];

const _assessments = <(String, String)>[
  ('needs_work', '还需要练习'),
  ('partly_expressed', '基本表达出来'),
  ('expressed', '表达自然'),
];

String _assessmentLabel(String value) {
  for (final entry in _assessments) {
    if (entry.$1 == value) return entry.$2;
  }
  return value;
}

/// Human relative time for a `completed_at_ms` epoch, so history rows show
/// "3 天前" instead of a raw millisecond stamp.
String _relativeTime(int ms) {
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60000) return '刚刚';
  final minutes = diff ~/ 60000;
  if (minutes < 60) return '$minutes 分钟前';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours 小时前';
  final days = hours ~/ 24;
  if (days < 30) return '$days 天前';
  final months = days ~/ 30;
  if (months < 12) return '$months 个月前';
  return '${days ~/ 365} 年前';
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
/// highlighted, each tail-labelled 你在这 / 用过 N 次 / 还没试过.
///
/// When [usage] is null (no writing history) only the current rung is marked
/// "你在这" — the other rungs stay silent rather than claim "还没试过", so an
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

  String? _tail(_LadderRung rung) {
    if (rung.value == current) return '你在这';
    if (usage == null) return null;
    final count = usage![rung.value] ?? 0;
    return count > 0 ? '用过 $count 次' : '还没试过';
  }

  @override
  Widget build(BuildContext context) {
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
            label: '${rung.label}，${rung.hint}',
            child: InkWell(
              borderRadius: ListenRadii.controlBorder,
              onTap: () => onSelect(rung.value),
              child: AnimatedContainer(
                duration: reduceMotion ? Duration.zero : ListenMotion.base,
                curve: ListenMotion.move,
                padding: const EdgeInsets.symmetric(
                  horizontal: ListenSpacing.gap12,
                  vertical: ListenSpacing.gap8,
                ),
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
                          Text(rung.label, style: textTheme.labelLarge),
                          Text(
                            rung.hint,
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
                        _tail(rung) ?? '',
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
    required this.api,
    required this.language,
    this.initialSource,
    this.onPlaySource,
    this.onStartSpeaking,
  });

  final LocalApi api;
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
  List<SentencePatternAssetView> _patterns = const [];

  /// The most recent `writing` sentence per pattern, for the E3 list card
  /// ("↳ 你上次写：…"). Populated lazily after patterns load; a pattern with no
  /// writing history simply stays absent.
  Map<String, PersonalExpressionAttemptView> _lastWritten = const {};
  String _query = '';
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      _refresh().then((_) {
        if (mounted && widget.initialSource != null) {
          unawaited(_edit(source: widget.initialSource));
        }
      }),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = await widget.api.sentencePatterns(
        language: widget.language,
        query: _query,
      );
      if (!mounted) return;
      setState(() => _patterns = values);
      await _loadLastWritten(values);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reads existing attempts per pattern (no new backend semantics) to surface
  /// the learner's last written sentence on each list card.
  Future<void> _loadLastWritten(
    List<SentencePatternAssetView> patterns,
  ) async {
    final entries = await Future.wait(
      patterns.map((pattern) async {
        try {
          final attempts = await widget.api.personalExpressionAttempts(
            pattern.id,
          );
          return MapEntry(pattern.id, _lastWriting(attempts));
        } catch (_) {
          return MapEntry(pattern.id, null);
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _lastWritten = {
        for (final entry in entries)
          if (entry.value != null) entry.key: entry.value!,
      };
    });
  }

  Future<void> _export() async {
    try {
      final bundle = await widget.api.exportPersonalExpression(
        language: widget.language,
      );
      final location = await getSaveLocation(
        suggestedName: 'llplayer-personal-expression.json',
      );
      if (location == null) return;
      await File(location.path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundle.toJson()),
      );
      if (mounted) {
        _notify('已导出 ${bundle.patternCount} 条到 ${location.path}');
      }
    } catch (error) {
      if (mounted) _notify('导出失败：$error', isError: true);
    }
  }

  void _notify(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isError ? scheme.onError : scheme.onInverseSurface),
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
    final patternText = TextEditingController(
      text: current?.patternText ?? effectiveSource.text,
    );
    final slotNames = TextEditingController(
      text: current?.slots.map((slot) => slot.name).join(', ') ?? '',
    );
    final note = TextEditingController(text: current?.note ?? '');
    final sourceText = TextEditingController(text: effectiveSource.text);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pattern == null ? '保存到我的表达' : '编辑个人表达'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: sourceText,
                  enabled: pattern == null && source == null,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '不可变来源快照'),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: patternText,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '我的模板',
                    hintText: 'I ended up {result}.',
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: slotNames,
                  decoration: const InputDecoration(
                    labelText: '槽位名称（逗号分隔）',
                    hintText: 'result, reason',
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '我的说明'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty ||
                  patternText.text.trim().isEmpty ||
                  sourceText.text.trim().isEmpty) {
                return;
              }
              if (pattern == null) {
                await widget.api.createSentencePattern(
                  language: widget.language,
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
                await widget.api.reviseSentencePattern(
                  id: pattern.id,
                  name: name.text.trim(),
                  patternText: patternText.text.trim(),
                  slots: _slots(slotNames.text),
                  note: note.text.trim().isEmpty ? null : note.text.trim(),
                  systemConstructionId: current?.systemConstructionId,
                );
              }
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    name.dispose();
    patternText.dispose();
    slotNames.dispose();
    note.dispose();
    sourceText.dispose();
    if (saved == true) await _refresh();
  }

  Future<void> _open(SentencePatternAssetView pattern) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PatternDetail(
          api: widget.api,
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
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的表达'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '导出个人表达',
            onPressed: () => unawaited(_export()),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建个人表达',
            onPressed: () => unawaited(_edit()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.text('search'),
              ),
              onChanged: (value) {
                _query = value;
                unawaited(_refresh());
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ListenErrorNotice(message: _error!),
            ),
          Expanded(
            child: _busy
                ? const Center(child: ListenLoading())
                : _patterns.isEmpty
                ? const ListenEmptyState(
                    icon: Icons.edit_note,
                    message: '还没有个人表达。可从阅读句子收藏，或在这里手动创建。',
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: ListenBreakpoints.contentColumnMax,
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _patterns.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: ListenSpacing.gap8),
                        itemBuilder: (context, index) {
                          final pattern = _patterns[index];
                          return _PatternCard(
                            pattern: pattern,
                            lastWritten: _lastWritten[pattern.id],
                            onTap: () => unawaited(_open(pattern)),
                          );
                        },
                      ),
                    ),
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final version = pattern.currentVersion;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    Text(version.patternText, style: textTheme.titleMedium),
                    if (lastWritten != null) ...[
                      const SizedBox(height: ListenSpacing.gap6),
                      Text(
                        '↳ 你上次写：${lastWritten!.responseText}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: ListenSpacing.gap6),
                    Text(
                      '来源：${pattern.source.text}',
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
    required this.api,
    required this.pattern,
    required this.onEdit,
    this.onPlaySource,
    this.onStartSpeaking,
  });
  final LocalApi api;
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
  List<PersonalExpressionAttemptView> attempts = const [];
  List<SentencePatternVersionView> versions = const [];
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final values = await Future.wait([
      widget.api.personalExpressionAttempts(widget.pattern.id),
      widget.api.sentencePatternVersions(widget.pattern.id),
    ]);
    if (mounted) {
      setState(() {
        attempts = values[0] as List<PersonalExpressionAttemptView>;
        versions = values[1] as List<SentencePatternVersionView>;
      });
    }
  }

  /// 弹窗死刑: the writing flow is a page (the writing desk), not a dialog.
  Future<void> _write() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _WritingDeskPage(
          api: widget.api,
          pattern: widget.pattern,
          attempts: attempts,
        ),
      ),
    );
    if (saved == true) await _refresh();
  }

  /// E1: deletion states its blast radius (N versions + M usage records) before
  /// anything is destroyed, matching the coach graduation flow spec.
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个表达？'),
        content: Text(
          '会一起删掉它的 ${versions.length} 个版本'
          '与 ${attempts.length} 条使用记录，无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.deleteSentencePattern(widget.pattern.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.contentColumnMax,
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.pattern.currentVersion.patternText,
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                '来源快照：${widget.pattern.source.text}',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (widget.pattern.currentVersion.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: ListenSpacing.gap4),
                  child: Text('说明：${widget.pattern.currentVersion.note}'),
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
                    label: const Text('写自己的句子'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onStartSpeaking == null
                        ? null
                        : () async {
                            Navigator.pop(context);
                            await widget.onStartSpeaking!(widget.pattern);
                          },
                    icon: const Icon(Icons.mic_none),
                    label: const Text('脱稿说一遍'),
                  ),
                  if (widget.onPlaySource != null)
                    OutlinedButton.icon(
                      onPressed:
                          widget.pattern.source.mediaId == null ||
                              widget.pattern.source.mediaFingerprint == null
                          ? null
                          : () => widget.onPlaySource!(widget.pattern.source),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('回听来源'),
                    ),
                ],
              ),
              const Divider(height: 40),
              Text('使用历史', style: textTheme.titleLarge),
              if (attempts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('还没有使用记录。'),
                ),
              for (final attempt in attempts)
                _HistoryRow(attempt: attempt),
              const Divider(height: 40),
              ExpansionTile(
                title: Text('版本历史（${versions.length}）'),
                children: [
                  for (final version in versions)
                    ListTile(
                      title: Text('v${version.version} · ${version.name}'),
                      subtitle: Text(version.patternText),
                    ),
                ],
              ),
              const SizedBox(height: ListenSpacing.gap24),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () => unawaited(_confirmDelete()),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除这个表达'),
              ),
            ],
          ),
        ),
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rung = _rungFor(attempt.assistance);
    final channelLabel = attempt.channel == 'speaking' ? '口头' : '书面';
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
                  '$channelLabel · ${rung.label} · '
                  '${_assessmentLabel(attempt.selfAssessment)} · '
                  '${_relativeTime(attempt.completedAtMs)}',
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
    required this.api,
    required this.pattern,
    required this.attempts,
  });

  final LocalApi api;
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
    var draft = widget.pattern.currentVersion.patternText;
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
      await widget.api.recordPersonalExpressionAttempt(
        patternId: widget.pattern.id,
        patternVersionId: widget.pattern.currentVersion.id,
        channel: 'writing',
        assistance: _assistance,
        responseText: _response.text.trim(),
        selfAssessment: _assessment,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$error')),
        );
      }
    }
  }

  Widget _templateArea(ColorScheme scheme, TextTheme textTheme) {
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
              version.patternText,
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
                    labelText: slot.prompt ?? '填入 ${slot.name}',
                    hintText: slot.exampleValue,
                  ),
                ),
              ),
            if (_slotValues.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _generateDraft,
                  child: const Text('用我的槽位生成草稿'),
                ),
              ),
          ],
        );
      case 'slot_hints':
        return Column(
          key: const ValueKey('slot_hints'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('只规划要表达的内容，不显示模板结构：', style: mutedStyle),
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
              ? '没有保存关键词提示。'
              : '关键词：${version.slots.map((slot) => slot.name).join(' · ')}',
          style: mutedStyle,
        );
      default:
        return Text(
          key: const ValueKey('no_text'),
          '模板与槽位提示已隐藏，请直接写出自己的表达。',
          style: mutedStyle,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final usage = _writingUsage(widget.attempts);
    final target = _downshiftTarget;
    return Scaffold(
      appBar: AppBar(title: Text('写出：${widget.pattern.currentVersion.name}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.contentColumnMax,
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
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
                          '上次你写得很自然，要不要试试更少的帮助（${target.label}）？',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _hintDismissed = true),
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                ),
              Text(
                '帮助梯子 · 撤一阶，光多归你一分',
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
                child: _templateArea(scheme, textTheme),
              ),
              const SizedBox(height: ListenSpacing.gap16),
              Text(
                '你的句子',
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
                decoration: const InputDecoration(
                  hintText: '写出自己的真实内容',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: ListenSpacing.gap16),
              Text(
                '写完感觉',
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
                      label: Text(entry.$2),
                      selected: _assessment == entry.$1,
                      onSelected: (_) =>
                          setState(() => _assessment = entry.$1),
                    ),
                ],
              ),
              const SizedBox(height: ListenSpacing.gap24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('保存使用记录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
