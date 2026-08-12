import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/material_capability_coordinator.dart';
import '../localization.dart';
import '../models/learning_edition.dart';
import '../services/composition_session_service.dart';
import '../services/composition_store.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/composition/composition_audio_player.dart';

/// The learner-facing view of one adopted Composition: the produced reading
/// structure (sentences), the derived audio when the composition carries one,
/// and anchor-to-time alignment. Package identity, dependency graph, recipe,
/// and provenance stay progressive detail — this surface speaks about the
/// resulting edition only.
class CompositionSessionScreen extends StatefulWidget {
  const CompositionSessionScreen({
    super.key,
    required this.materialId,
    required this.materialTitle,
    required this.session,
    required this.coordinator,
  });

  final String materialId;
  final String materialTitle;
  final CompositionSessionService session;
  final MaterialCapabilityCoordinator coordinator;

  @override
  State<CompositionSessionScreen> createState() =>
      _CompositionSessionScreenState();
}

class _CompositionSessionScreenState extends State<CompositionSessionScreen> {
  LearningEdition? _adopted;
  ResolvedComposition? _composition;
  Object? _failure;
  int _currentSentenceIndex = -1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final adopted = await widget.session.adoptedEdition(widget.materialId);
      if (!mounted) return;
      setState(() => _adopted = adopted);
      if (adopted == null) return;
      final composition = await widget.session.resolveComposition(
        widget.materialId,
        adopted.releaseId,
      );
      if (!mounted || composition == null) return;
      setState(() => _composition = composition);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  void _syncHighlight(Duration position) {
    final composition = _composition;
    if (composition == null) return;
    var best = -1;
    var bestTime = -1;
    for (var index = 0; index < composition.sentences.length; index++) {
      final mediaTime = composition.alignments[composition.sentences[index].id];
      if (mediaTime == null) continue;
      if (mediaTime <= position.inMilliseconds && mediaTime > bestTime) {
        bestTime = mediaTime;
        best = index;
      }
    }
    if (best != _currentSentenceIndex) {
      setState(() => _currentSentenceIndex = best);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.materialTitle)),
      body: ListenableBuilder(
        listenable: widget.coordinator,
        builder: (context, _) => _buildBody(l),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    if (_failure != null) {
      return Center(child: Text(l.text('compositionLoadFailed')));
    }
    if (_adopted == null) {
      return Center(child: Text(l.text('compositionNone')));
    }
    final composition = _composition;
    if (composition == null) {
      return Center(child: Text(l.text('compositionMissing')));
    }
    final mediaPath = composition.derivedMediaPath;
    return ListView(
      padding: const EdgeInsets.all(ListenSpacing.gap16),
      children: [
        if (mediaPath != null) ...[
          CompositionAudioPlayer(
            mediaPath: mediaPath,
            onPositionChanged: _syncHighlight,
          ),
          const SizedBox(height: ListenSpacing.gap16),
        ] else
          Text(
            l.text('compositionNoAudio'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: ListenSpacing.gap8),
        for (var index = 0; index < composition.sentences.length; index++)
          _SentenceTile(
            text: composition.sentences[index].text,
            highlighted: index == _currentSentenceIndex,
          ),
      ],
    );
  }
}

class _SentenceTile extends StatelessWidget {
  const _SentenceTile({required this.text, required this.highlighted});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ListenSpacing.gap8),
        decoration: BoxDecoration(
          color: highlighted
              ? colors.primaryContainer.withValues(alpha: 0.55)
              : colors.surfaceContainerLowest,
          borderRadius: ListenRadii.controlBorder,
          border: Border.all(
            color: highlighted ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: highlighted ? colors.onPrimaryContainer : null,
            fontWeight: highlighted ? FontWeight.w600 : null,
          ),
        ),
      ),
    );
  }
}
