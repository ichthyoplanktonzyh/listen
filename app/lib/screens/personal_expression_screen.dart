import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/personal_expression.dart';
import '../services/api_service.dart';

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
      if (mounted) setState(() => _patterns = values);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
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
                const SizedBox(height: 12),
                TextField(
                  controller: sourceText,
                  enabled: pattern == null && source == null,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '不可变来源快照'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: patternText,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '我的模板',
                    hintText: 'I ended up {result}.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: slotNames,
                  decoration: const InputDecoration(
                    labelText: '槽位名称（逗号分隔）',
                    hintText: 'result, reason',
                  ),
                ),
                const SizedBox(height: 12),
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
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _patterns.isEmpty
                ? const Center(child: Text('还没有个人表达。可从阅读句子收藏，或在这里手动创建。'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _patterns.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final pattern = _patterns[index];
                      return Card(
                        child: ListTile(
                          title: Text(pattern.currentVersion.name),
                          subtitle: Text(
                            '${pattern.currentVersion.patternText}\n来源：${pattern.source.text}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => unawaited(_open(pattern)),
                        ),
                      );
                    },
                  ),
          ),
        ],
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

  Future<void> _write() async {
    final response = TextEditingController();
    final slotValues = {
      for (final slot in widget.pattern.currentVersion.slots)
        slot.name: TextEditingController(),
    };
    var assistance = 'template_visible';
    var assessment = 'partly_expressed';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('写出我的句子'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (assistance == 'template_visible') ...[
                  Text(
                    widget.pattern.currentVersion.patternText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final slot in widget.pattern.currentVersion.slots)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: slotValues[slot.name],
                        decoration: InputDecoration(
                          labelText: slot.prompt ?? '填入 ${slot.name}',
                          hintText: slot.exampleValue,
                        ),
                      ),
                    ),
                  if (slotValues.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          var draft = widget.pattern.currentVersion.patternText;
                          for (final entry in slotValues.entries) {
                            final value = entry.value.text.trim();
                            if (value.isNotEmpty) {
                              draft = draft.replaceAll('{${entry.key}}', value);
                            }
                          }
                          response.text = draft;
                        },
                        child: const Text('用我的槽位生成草稿'),
                      ),
                    ),
                ] else if (assistance == 'slot_hints') ...[
                  const Text('只规划要表达的内容，不显示模板结构：'),
                  for (final slot in widget.pattern.currentVersion.slots)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: slotValues[slot.name],
                        decoration: InputDecoration(
                          labelText: slot.prompt ?? slot.name,
                          hintText: slot.exampleValue,
                        ),
                      ),
                    ),
                ] else if (assistance == 'keywords')
                  Text(
                    widget.pattern.currentVersion.slots.isEmpty
                        ? '没有保存关键词提示。'
                        : '关键词：${widget.pattern.currentVersion.slots.map((slot) => slot.name).join(' · ')}',
                  )
                else
                  const Text('模板与槽位提示已隐藏，请直接写出自己的表达。'),
                const SizedBox(height: 12),
                TextField(
                  controller: response,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(labelText: '我的真实内容'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: assistance,
                  decoration: const InputDecoration(labelText: '使用的帮助'),
                  items: const [
                    DropdownMenuItem(
                      value: 'template_visible',
                      child: Text('看完整模板'),
                    ),
                    DropdownMenuItem(
                      value: 'slot_hints',
                      child: Text('只看槽位提示'),
                    ),
                    DropdownMenuItem(value: 'keywords', child: Text('只看关键词')),
                    DropdownMenuItem(value: 'no_text', child: Text('隐藏模板')),
                  ],
                  onChanged: (value) => setState(() => assistance = value!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: assessment,
                  decoration: const InputDecoration(labelText: '自评'),
                  items: const [
                    DropdownMenuItem(value: 'needs_work', child: Text('还需要练习')),
                    DropdownMenuItem(
                      value: 'partly_expressed',
                      child: Text('基本表达出来'),
                    ),
                    DropdownMenuItem(value: 'expressed', child: Text('表达自然')),
                  ],
                  onChanged: (value) => setState(() => assessment = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (response.text.trim().isEmpty) return;
                await widget.api.recordPersonalExpressionAttempt(
                  patternId: widget.pattern.id,
                  patternVersionId: widget.pattern.currentVersion.id,
                  channel: 'writing',
                  assistance: assistance,
                  responseText: response.text.trim(),
                  selfAssessment: assessment,
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('保存使用记录'),
            ),
          ],
        ),
      ),
    );
    response.dispose();
    for (final controller in slotValues.values) {
      controller.dispose();
    }
    if (saved == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.pattern.currentVersion.name),
      actions: [
        IconButton(
          onPressed: () => unawaited(widget.onEdit()),
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.pattern.currentVersion.patternText,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text('来源快照：${widget.pattern.source.text}'),
        if (widget.pattern.currentVersion.note != null)
          Text('说明：${widget.pattern.currentVersion.note}'),
        Wrap(
          spacing: 8,
          children: [
            for (final slot in widget.pattern.currentVersion.slots)
              Chip(label: Text(slot.name)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
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
        Text('使用历史', style: Theme.of(context).textTheme.titleLarge),
        if (attempts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('还没有使用记录。'),
          ),
        for (final attempt in attempts)
          ListTile(
            leading: Icon(
              attempt.channel == 'speaking' ? Icons.mic : Icons.edit,
            ),
            title: Text(attempt.responseText),
            subtitle: Text(
              '${attempt.channel == 'speaking' ? '口头' : '书面'} · ${attempt.assistance} · ${attempt.selfAssessment}',
            ),
          ),
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
        const SizedBox(height: 24),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            await widget.api.deleteSentencePattern(widget.pattern.id);
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除这个表达'),
        ),
      ],
    ),
  );
}
