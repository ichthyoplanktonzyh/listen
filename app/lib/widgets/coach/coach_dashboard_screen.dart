import 'package:flutter/material.dart';

import '../../controllers/coach_dashboard_controller.dart';
import '../../localization.dart';
import '../../models/coach_dashboard.dart';
import '../../models/named_failure.dart';
import '../../services/api_service.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/capability_viz.dart';
import '../common/listen_error_state.dart';
import '../common/listen_loading.dart';

/// Chapter order (S2 · #81): portrait → next steps → channel evidence →
/// material shelf, with the starter states inserted after the next steps only
/// while the backend still emits them. "See yourself, then the road, then the
/// evidence, then the shelf."
const _channelOrder = ['listening', 'speaking', 'reading', 'writing'];

/// The echo bars' two modality columns, as channel pairs. The production side
/// is the gap source: the unlit part of the reception ghost is drawn there.
const _echoPairs = <String, (List<String>, String)>{
  'sound': (['listening', 'speaking'], 'speaking'),
  'text': (['reading', 'writing'], 'writing'),
};

/// Where each starter state's entry button leads. The states themselves are
/// the backend's judgment; these are only the doors to go do the thing.
const _starterDestinations = <String, String>{
  'complete_extensive_listening': 'content_home',
  'complete_active_practice': 'content_home',
  'review_due_items': 'review_queue',
};

/// How many source facts one inline drill-down shows before "More".
const _evidencePageSize = 5;

/// What the portrait last pointed at. Presentation-only: highlighting a
/// channel changes nothing about the judgment behind it.
class _PortraitFocus {
  const _PortraitFocus(this.channels, {this.gapSource});

  final List<String> channels;

  /// The production channel of an echo pair — where the gap comes from.
  final String? gapSource;
}

/// One metric's inline evidence feed (K2: the drill-down is an expansion, not
/// a dialog). Paged so opening a metric never pulls a whole period at once.
class _EvidenceFeed {
  const _EvidenceFeed({
    this.items = const [],
    this.loading = false,
    this.failure,
    this.exhausted = false,
  });

  final List<CoachEvidenceItem> items;
  final bool loading;

  /// Why the page could not be fetched, as a *key* plus typed detail.
  ///
  /// This was `String? error` filled with `'$error'` and rendered as the
  /// panel's only line, so opening a metric on a bad connection printed the
  /// whole `HttpException` — envelope, `correlation_id`, loopback URI and all
  /// — inside the evidence drill-down.
  final NamedFailure? failure;
  final bool exhausted;
}

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onNavigate,
  });
  final LocalApi api;
  final String language;
  final Future<void> Function(
    CoachSuggestionDestination destination,
    CoachReturnContext returnContext,
  )
  onNavigate;
  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  final controller = CoachDashboardController();
  final scrollController = ScrollController();
  final _channelKeys = {
    for (final channel in _channelOrder) channel: GlobalKey(),
  };
  final _evidence = <String, _EvidenceFeed>{};
  _PortraitFocus? _focus;
  String? _openMetric;

  @override
  void initState() {
    super.initState();
    controller.load(widget.api, language: widget.language);
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).text('coachDashboard')),
    ),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        if (state.loading) {
          return const Center(child: ListenLoading());
        }
        if (state.error != null) {
          return ListenErrorState(
            message: state.error!,
            action: OutlinedButton(
              onPressed: () =>
                  controller.load(widget.api, language: widget.language),
              child: Text(AppLocalizations.of(context).text('retry')),
            ),
          );
        }
        return _dashboard(context, state.dashboard!);
      },
    ),
  );

  // A single scroll view (not a lazy list) so a portrait hotspot can always
  // reach its channel section: an unbuilt section has no context to scroll to.
  Widget _dashboard(BuildContext context, CoachDashboard dashboard) =>
      SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(ListenSpacing.gap24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._portrait(context, dashboard),
            const SizedBox(height: ListenSpacing.gap24),
            ..._nextSteps(context, dashboard),
            ..._starter(context, dashboard),
            ..._channelEvidence(context, dashboard),
            ..._materials(context, dashboard),
            ..._tools(context, dashboard),
          ],
        ),
      );

  List<Widget> _portrait(BuildContext context, CoachDashboard dashboard) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final gapCount = crossModalGapCount(dashboard);
    return [
      Text(
        l.text('capabilityPortraitTitle'),
        style: theme.textTheme.headlineSmall,
      ),
      Tooltip(
        message: _absoluteTime(dashboard.generatedAtMs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l
                .text('coachGeneratedAt')
                .replaceFirst(
                  '{time}',
                  _relativeTime(l, dashboard.generatedAtMs),
                ),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
      const SizedBox(height: ListenSpacing.gap16),
      // The portrait is this page's navigation (#70 audit K4): quadrants and
      // echo bars move focus inside the page, the gap figure is the one
      // hotspot that leaves — to the vocabulary gap pane, via the existing
      // cross_modal_review destination.
      //
      // The three hotspots carry their own affordances (hover highlight, click
      // cursor, button semantics), so there is no caption explaining how to
      // use the picture: a graphic that needs a manual is a failed graphic.
      Card(
        margin: const EdgeInsets.only(bottom: ListenSpacing.gap12),
        child: Padding(
          padding: const EdgeInsets.all(ListenSpacing.gap16),
          child: CapabilityPortrait(
            channels: dashboard.channels,
            gapCount: gapCount,
            onChannelTap: (channel) => _focusChannels([channel]),
            onPairTap: _focusPair,
            onGapTap: gapCount == null ? null : _openGap,
          ),
        ),
      ),
    ];
  }

  List<Widget> _nextSteps(BuildContext context, CoachDashboard dashboard) {
    final l = AppLocalizations.of(context);
    return [
      Text(l.text('coachNextSteps'), style: _sectionStyle(context)),
      const SizedBox(height: ListenSpacing.gap8),
      if (dashboard.suggestions.isEmpty) Text(l.text('coachNoSuggestions')),
      ...dashboard.suggestions.map(
        (suggestion) => _SuggestionRow(
          suggestion: suggestion,
          onGo: () => _openSuggestion(suggestion),
        ),
      ),
    ];
  }

  List<Widget> _starter(BuildContext context, CoachDashboard dashboard) {
    if (dashboard.starterChecklist.isEmpty) return const [];
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      const SizedBox(height: ListenSpacing.gap24),
      Text(l.text('coachStarter'), style: _sectionStyle(context)),
      Text(
        l.text('coachStarterNote'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: ListenSpacing.gap8),
      // K1: the backend emits the states it has *not* observed, so every row
      // here is honestly "not yet" — a dimmed dot plus a door, never a radio
      // button the user could think they may tick.
      ...dashboard.starterChecklist.map(
        (item) => _StarterRow(
          item: item,
          onGo: _starterDestinations.containsKey(item)
              ? () => _openStarter(item)
              : null,
        ),
      ),
    ];
  }

  List<Widget> _channelEvidence(
    BuildContext context,
    CoachDashboard dashboard,
  ) {
    final l = AppLocalizations.of(context);
    // Restraint inherited from #47: a channel with no facts renders nothing.
    final sections = <Widget>[];
    for (final channel in _channelOrder) {
      final summary = _channel(dashboard, channel);
      if (summary == null) continue;
      final metrics = summary.metrics
          .where((metric) => metric.value > 0)
          .toList(growable: false);
      if (metrics.isEmpty) continue;
      sections.add(
        _ChannelSection(
          key: _channelKeys[channel],
          channel: summary,
          metrics: metrics,
          focused: _focus?.channels.contains(channel) ?? false,
          gapSource: _focus?.gapSource == channel,
          openMetric: _openMetric,
          feeds: _evidence,
          onToggleMetric: _toggleEvidence,
          onMore: (metric) => _loadEvidencePage(metric.key),
        ),
      );
    }
    // A hotspot that pointed at a channel with nothing to show says so
    // instead of silently doing nothing.
    final silent = (_focus?.channels ?? const <String>[])
        .where(
          (channel) =>
              !(_channel(
                    dashboard,
                    channel,
                  )?.metrics.any((metric) => metric.value > 0) ??
                  false),
        )
        .toList(growable: false);
    if (sections.isEmpty && silent.isEmpty) return const [];
    return [
      const SizedBox(height: ListenSpacing.gap24),
      Text(l.text('coachChannelEvidence'), style: _sectionStyle(context)),
      const SizedBox(height: ListenSpacing.gap8),
      ...silent.map(
        (channel) => Padding(
          padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
          child: Text(
            l
                .text('coachChannelNoEvidence')
                .replaceFirst('{channel}', l.text('coachChannel_$channel')),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      ...sections,
    ];
  }

  List<Widget> _materials(BuildContext context, CoachDashboard dashboard) {
    if (dashboard.materials.isEmpty) return const [];
    final l = AppLocalizations.of(context);
    return [
      const SizedBox(height: ListenSpacing.gap24),
      Text(l.text('coachMaterials'), style: _sectionStyle(context)),
      const SizedBox(height: ListenSpacing.gap8),
      ...dashboard.materials.map(
        (material) => Card(
          child: ListTile(
            title: Text(material.title),
            subtitle: _MaterialTrajectory(material: material),
            trailing: _materialAction(context, material),
          ),
        ),
      ),
    ];
  }

  Widget? _materialAction(BuildContext context, CoachMaterialInsight material) {
    final l = AppLocalizations.of(context);
    if (material.graduationCandidate) {
      return FilledButton.tonal(
        onPressed: () => _graduate(material),
        child: Text(l.text('coachGraduate')),
      );
    }
    final recommended = material.recommendedIntent;
    if (recommended == null || recommended == material.triageIntent) {
      return null;
    }
    return OutlinedButton(
      onPressed: () => _setIntent(material),
      child: Text(l.text('coachIntent_$recommended')),
    );
  }

  // The feature rows are pure status ("LLM feedback: not configured"), so
  // they sit at the tools/about level instead of on the learning line
  // (owner decision 5, 2026-07-24).
  List<Widget> _tools(BuildContext context, CoachDashboard dashboard) {
    if (dashboard.features.isEmpty) return const [];
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      const SizedBox(height: ListenSpacing.gap24),
      Text(
        l.text('coachTools'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      ...dashboard.features.map(
        (feature) => Padding(
          padding: const EdgeInsets.only(top: ListenSpacing.gap4),
          child: Text(
            '${l.text('coachFeature_${feature.feature}')} · '
            '${l.text('coachFeatureStatus_${feature.status}')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ];
  }

  TextStyle? _sectionStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge;

  CoachChannelSummary? _channel(CoachDashboard dashboard, String channel) {
    for (final summary in dashboard.channels) {
      if (summary.channel == channel) return summary;
    }
    return null;
  }

  String _absoluteTime(int ms) => DateTime.fromMillisecondsSinceEpoch(
    ms,
  ).toLocal().toString().substring(0, 16);

  void _focusChannels(List<String> channels, {String? gapSource}) {
    setState(() => _focus = _PortraitFocus(channels, gapSource: gapSource));
    // The highlight has to build before there is anything to scroll to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      for (final channel in channels) {
        final target = _channelKeys[channel]?.currentContext;
        if (target == null) continue;
        Scrollable.ensureVisible(
          target,
          alignment: 0.05,
          duration: reduceMotion ? Duration.zero : ListenMotion.base,
          curve: ListenMotion.move,
        );
        return;
      }
    });
  }

  void _focusPair(String pair) {
    final entry = _echoPairs[pair];
    if (entry == null) return;
    _focusChannels(entry.$1, gapSource: entry.$2);
  }

  /// The one hotspot that leaves the page: the gap figure opens the
  /// vocabulary gap pane through the existing `cross_modal_review`
  /// destination — the "overview → list" hop of the gap's three-layer home.
  Future<void> _openGap() => _navigate(
    CoachSuggestionDestination(
      kind: 'cross_modal_review',
      language: widget.language,
    ),
    suggestionId: 'cross-modal-review',
  );

  Future<void> _openStarter(String item) => _navigate(
    CoachSuggestionDestination(
      kind: _starterDestinations[item]!,
      language: widget.language,
    ),
  );

  Future<void> _openSuggestion(CoachSuggestion suggestion) =>
      _navigate(suggestion.destination, suggestionId: suggestion.id);

  Future<void> _navigate(
    CoachSuggestionDestination destination, {
    String? suggestionId,
  }) async {
    if (destination.kind == 'content_home') {
      Navigator.pop(context);
      return;
    }
    final offset = scrollController.hasClients ? scrollController.offset : 0.0;
    await widget.onNavigate(
      destination,
      CoachReturnContext(
        days: 7,
        language: widget.language,
        scrollOffset: offset,
        suggestionId: suggestionId,
      ),
    );
    if (!mounted) return;
    await controller.load(widget.api, language: widget.language);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scrollController.hasClients) {
        scrollController.jumpTo(
          offset.clamp(0, scrollController.position.maxScrollExtent),
        );
      }
    });
  }

  Future<void> _graduate(CoachMaterialInsight material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).text('coachGraduateConfirmTitle'),
        ),
        content: Text(
          AppLocalizations.of(context).text('coachGraduateConfirmBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).text('coachGraduate')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.graduateCoachMaterial(material.mediaId);
    if (mounted) {
      await controller.load(widget.api, language: widget.language);
    }
  }

  Future<void> _setIntent(CoachMaterialInsight material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).text('coachMaterialAdjustTitle'),
        ),
        content: Text(
          AppLocalizations.of(context).text('coachMaterialAdjustBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).text('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.setMediaTriageIntent(
      material.mediaId,
      material.recommendedIntent,
    );
    if (mounted) {
      await controller.load(widget.api, language: widget.language);
    }
  }

  Future<void> _toggleEvidence(CoachMetric metric) async {
    if (_openMetric == metric.key) {
      setState(() => _openMetric = null);
      return;
    }
    setState(() => _openMetric = metric.key);
    // Already fetched once this visit: reopening must not re-hit the core.
    if (_evidence.containsKey(metric.key)) return;
    await _loadEvidencePage(metric.key);
  }

  Future<void> _loadEvidencePage(String metricKey) async {
    final current = _evidence[metricKey] ?? const _EvidenceFeed();
    if (current.loading) return;
    setState(
      () => _evidence[metricKey] = _EvidenceFeed(
        items: current.items,
        loading: true,
      ),
    );
    try {
      final page = await widget.api.coachEvidence(
        metricKey,
        limit: _evidencePageSize,
        offset: current.items.length,
      );
      if (!mounted) return;
      setState(
        () => _evidence[metricKey] = _EvidenceFeed(
          items: [...current.items, ...page],
          exhausted: page.length < _evidencePageSize,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _evidence[metricKey] = _EvidenceFeed(
          items: current.items,
          failure: NamedFailure(
            'coachEvidenceFailed',
            detail: describeApiFailure(error),
          ),
        ),
      );
    }
  }
}

/// "Do this next" as one verb-first sentence plus one door — the evidence
/// count is folded into the sentence instead of the old
/// reason · count · source concatenation (#70 audit).
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onGo});

  final CoachSuggestion suggestion;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    // A gap is a practice target (amber); everything else is ready light.
    final gap = suggestion.kind == 'cross_modal_review';
    return Card(
      child: ListTile(
        leading: _StateDot(color: gap ? colors.secondary : colors.primary),
        title: Text(l.text(suggestion.titleKey)),
        subtitle: Text(_countSentence(l)),
        trailing: FilledButton.tonal(
          onPressed: onGo,
          child: Text(l.text('coachGo')),
        ),
        onTap: onGo,
      ),
    );
  }

  String _countSentence(AppLocalizations l) {
    final key = 'coachSuggestionCount_${suggestion.kind}';
    final sentence = l.text(key);
    // No dedicated sentence for a suggestion kind we do not know yet: fall
    // back to the neutral count rather than inventing a claim about it.
    return (sentence == key ? l.text('coachSuggestionCount') : sentence)
        .replaceFirst('{n}', '${suggestion.evidenceCount}');
  }
}

/// A starter state: dimmed dot, the state in words, and the door to go do it.
class _StarterRow extends StatelessWidget {
  const _StarterRow({required this.item, required this.onGo});

  final String item;
  final VoidCallback? onGo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final actionKey = 'coachStarterAction_$item';
    final action = l.text(actionKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap4),
      child: Row(
        children: [
          _StateDot(color: theme.colorScheme.outlineVariant),
          const SizedBox(width: ListenSpacing.gap8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.text('coachStarter_$item'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  l.text('coachStarterPending'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onGo != null)
            OutlinedButton(
              onPressed: onGo,
              child: Text(action == actionKey ? l.text('coachGo') : action),
            ),
        ],
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: ListenSpacing.gap8,
    height: ListenSpacing.gap8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// One channel's evidence: a plain table of metric rows (K3 — no 210px cards
/// nested inside a card inside a list), each of which drills down in place.
class _ChannelSection extends StatelessWidget {
  const _ChannelSection({
    super.key,
    required this.channel,
    required this.metrics,
    required this.focused,
    required this.gapSource,
    required this.openMetric,
    required this.feeds,
    required this.onToggleMetric,
    required this.onMore,
  });

  final CoachChannelSummary channel;
  final List<CoachMetric> metrics;
  final bool focused;
  final bool gapSource;
  final String? openMetric;
  final Map<String, _EvidenceFeed> feeds;
  final Future<void> Function(CoachMetric metric) onToggleMetric;
  final void Function(CoachMetric metric) onMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = gapSource
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: ListenSpacing.gap12),
      shape: focused
          ? RoundedRectangleBorder(
              borderRadius: ListenRadii.surfaceBorder,
              side: BorderSide(color: accent),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(ListenSpacing.gap16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text('coachChannel_${channel.channel}'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: focused ? accent : null,
              ),
            ),
            if (gapSource)
              Padding(
                padding: const EdgeInsets.only(top: ListenSpacing.gap4),
                child: Text(
                  l.text('coachGapSourceHint'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            const SizedBox(height: ListenSpacing.gap8),
            ...metrics.map(
              (metric) => _MetricRow(
                metric: metric,
                expanded: openMetric == metric.key,
                feed: feeds[metric.key],
                onToggle: () => onToggleMetric(metric),
                onMore: () => onMore(metric),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// name · reading · source, with the evidence opening underneath it.
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.metric,
    required this.expanded,
    required this.feed,
    required this.onToggle,
    required this.onMore,
  });

  final CoachMetric metric;
  final bool expanded;
  final _EvidenceFeed? feed;
  final VoidCallback onToggle;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = metric.key == 'extensive_listening_ms'
        ? '${(metric.value / 60000).round()} min'
        : '${metric.value}';
    final sourceKey = 'coachMetricSource_${metric.source}';
    final source = l.text(sourceKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: ListenRadii.controlBorder,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ListenSpacing.gap8,
              horizontal: ListenSpacing.gap4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.text('coachMetric_${metric.key}')),
                      // A raw table name is not a source the reader can use;
                      // only say where it came from when we can say it in
                      // words.
                      if (source != sourceKey)
                        Text(
                          source,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Text(value, style: theme.textTheme.titleMedium),
                const SizedBox(width: ListenSpacing.gap8),
                Tooltip(
                  message: l.text(
                    expanded ? 'coachEvidenceHide' : 'coachEvidenceShow',
                  ),
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : ListenMotion.base,
          curve: ListenMotion.enter,
          alignment: Alignment.topCenter,
          child: expanded
              ? _EvidencePanel(feed: feed, onMore: onMore)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// The drill-down itself: snapshots in the learner's own material, relative
/// time, and the source in words. The fact's UUID never reaches the screen.
class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({required this.feed, required this.onMore});

  final _EvidenceFeed? feed;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = feed;
    if (current == null || (current.loading && current.items.isEmpty)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: ListenSpacing.gap8),
        child: ListenLoading.inline(),
      );
    }
    final failure = current.failure;
    if (failure != null && current.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap8),
        child: ApiFailureNotice(
          message: l.text(failure.messageKey),
          failure: failure.detail,
        ),
      );
    }
    if (current.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap8),
        child: Text(
          l.text('coachEvidenceEmpty'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...current.items.map((item) => _EvidenceRow(item: item)),
          if (current.loading)
            const Padding(
              padding: EdgeInsets.only(top: ListenSpacing.gap4),
              child: ListenLoading.inline(),
            )
          else if (current.exhausted)
            Text(
              l.text('coachEvidenceAllShown'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            TextButton(
              onPressed: onMore,
              child: Text(l.text('coachEvidenceMore')),
            ),
        ],
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item});

  final CoachEvidenceItem item;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = <String>[
      _relativeTime(l, item.occurredAtMs),
      ..._sourceWords(l, item),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: ListenSpacing.gap4),
      padding: const EdgeInsets.all(ListenSpacing.gap8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: ListenRadii.controlBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The snapshot is the evidence; an unavailable source dims the row
          // but never deletes what was recorded.
          Text(
            _snapshot(l, item.snapshot),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: item.sourceAvailable
                  ? null
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Tooltip(
            message: DateTime.fromMillisecondsSinceEpoch(
              item.occurredAtMs,
            ).toLocal().toString().substring(0, 16),
            child: Text(
              meta.join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _sourceWords(AppLocalizations l, CoachEvidenceItem item) {
    final words = <String>[];
    final kindKey = 'coachEvidenceFrom_${item.sourceKind}';
    final kind = l.text(kindKey);
    if (kind != kindKey) words.add(kind);
    if (item.sourceAvailable) return words;
    final reasonKey =
        'coachEvidenceUnavailable_${item.unavailableReason ?? 'unknown'}';
    final reason = l.text(reasonKey);
    words.add(reason == reasonKey ? l.text('coachSourceUnavailable') : reason);
    return words;
  }
}

/// The material's comprehension trajectory as two points on a line —
/// first report → latest report — with both states in words.
class _MaterialTrajectory extends StatelessWidget {
  const _MaterialTrajectory({required this.material});

  final CoachMaterialInsight material;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        _dot(context, material.firstReport),
        Container(
          width: ListenSpacing.gap16,
          height: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        _dot(context, material.latestReport),
        const SizedBox(width: ListenSpacing.gap8),
        Expanded(
          child: Text(
            '${_label(l, material.firstReport)} → '
            '${_label(l, material.latestReport)} · '
            '${l.text('coachMaterialReports').replaceFirst('{n}', '${material.reportCount}')}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  String _label(AppLocalizations l, String? report) =>
      l.text('coachReport_${report ?? 'unknown'}');

  // The report states borrow the portrait's colors: understood is the light,
  // unclear is the practice target, anything between stays neutral.
  Widget _dot(BuildContext context, String? report) {
    final colors = Theme.of(context).colorScheme;
    return _StateDot(
      color: switch (report) {
        'understood_all' => colors.primary,
        'unclear' => colors.secondary,
        'got_the_gist' => colors.onSurfaceVariant,
        _ => colors.outlineVariant,
      },
    );
  }
}

/// Human relative time, so evidence reads "3 days ago" instead of a raw
/// stamp; the absolute time stays one hover away.
String _relativeTime(AppLocalizations l, int ms) {
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60000) return l.text('coachTimeJustNow');
  final minutes = diff ~/ 60000;
  if (minutes < 60) {
    return l.text('coachTimeMinutesAgo').replaceFirst('{n}', '$minutes');
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return l.text('coachTimeHoursAgo').replaceFirst('{n}', '$hours');
  }
  final days = hours ~/ 24;
  if (days < 30) {
    return l.text('coachTimeDaysAgo').replaceFirst('{n}', '$days');
  }
  final months = days ~/ 30;
  if (months < 12) {
    return l.text('coachTimeMonthsAgo').replaceFirst('{n}', '$months');
  }
  return l.text('coachTimeYearsAgo').replaceFirst('{n}', '${days ~/ 365}');
}

/// Snapshots arrive either as the learner's own transcript (show it as it is)
/// or, for count metrics, as the stored result token — which is JSON-quoted
/// on the wire. Unquote it and say the known ones in words; anything else is
/// shown as recorded rather than guessed at.
String _snapshot(AppLocalizations l, String snapshot) {
  final text =
      snapshot.length >= 2 && snapshot.startsWith('"') && snapshot.endsWith('"')
      ? snapshot.substring(1, snapshot.length - 1)
      : snapshot;
  final key = 'coachEvidenceSnapshot_$text';
  final localized = l.text(key);
  return localized == key ? text : localized;
}
