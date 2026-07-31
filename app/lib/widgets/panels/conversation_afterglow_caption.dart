import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../models/realtime_conversation.dart';
import '../../theme/breakpoints.dart';
import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';

/// The one line of text the stage is allowed to carry (#70 Phase 2 · S8).
///
/// [text] is always the *other person's* provider caption. [settled] means the
/// provider stopped extending that line — the point the 2.6s afterglow starts
/// counting from.
@immutable
class ConversationCaptionLine {
  const ConversationCaptionLine({required this.text, required this.settled});

  final String text;
  final bool settled;

  @override
  bool operator ==(Object other) =>
      other is ConversationCaptionLine &&
      other.text == text &&
      other.settled == settled;

  @override
  int get hashCode => Object.hash(text, settled);
}

/// Derives the afterglow line from controller state — presentation only.
///
/// **Honest layering is the whole point of this function** (charter · 诚实分层,
/// audit D3). Two different things were being drawn with the same weight
/// before:
///
/// - the provider's caption of the *assistant* — the only thing eligible here.
///   It is guidance: something to lean on while listening, then let go of;
/// - the provider's caption of the *learner* — never eligible, at any status.
///   Showing your own words back to you live turns speaking into reading them
///   aloud, and the provider's version of your speech is not your output
///   anyway. Your output is the local Whisper transcript, and it appears once,
///   in the debrief (S9 · #86), labelled as learner output.
///
/// So the filter below is deliberately `role == 'assistant'` rather than
/// "the newest item": a learner turn arriving on top must leave the stage
/// silent, not promote a learner caption. Nothing here reinterprets what the
/// backend decided — it only picks which decided thing may be seen.
ConversationCaptionLine? conversationAfterglowLineOf(
  RealtimeConversationState state,
) {
  RealtimeConversationItem? newest;
  for (final item in state.items) {
    if (item.role != 'assistant') continue;
    if (item.providerText.trim().isEmpty) continue;
    if (newest == null || item.sequence >= newest.sequence) newest = item;
  }
  if (newest == null) return null;
  return ConversationCaptionLine(
    text: newest.providerText.trim(),
    // 'streaming' is the assembler's "still being spoken" status; every other
    // status (finalized / interrupted / failed) means the line is done.
    settled: newest.status != 'streaming',
  );
}

/// One low-luminance line under the shape: what the other person is saying
/// right now, gone 2.6s after they stop.
///
/// 「字幕的克制」(design note `listen-live-conversation.html`): no history, no
/// scrolling, no second line. Reading a growing transcript while talking is
/// the fatigue source audit D3 named; the full read-through belongs to the
/// debrief. The widget keeps a fixed height so the shape above it never
/// shifts when the line comes and goes.
///
/// Motion: the line arrives on [ListenMotion.base]/[ListenMotion.enter] and
/// leaves on [ListenMotion.slow]/[ListenMotion.exit] after one
/// [ListenMotion.ambient] (2.6s) hold. No bounce; under reduce motion the
/// cross-fades collapse to zero duration and the line simply appears and
/// disappears at the same moments.
class ConversationAfterglowCaption extends StatefulWidget {
  const ConversationAfterglowCaption({super.key, required this.line});

  /// Null means the other person has not said anything yet — the stage stays
  /// silent rather than borrowing the learner's words.
  final ConversationCaptionLine? line;

  @override
  State<ConversationAfterglowCaption> createState() =>
      _ConversationAfterglowCaptionState();
}

class _ConversationAfterglowCaptionState
    extends State<ConversationAfterglowCaption> {
  /// The last line shown. Held while it fades so the text does not vanish a
  /// frame before the opacity does.
  String _shown = '';
  bool _visible = false;
  Timer? _afterglow;

  @override
  void initState() {
    super.initState();
    _apply(widget.line);
  }

  @override
  void didUpdateWidget(covariant ConversationAfterglowCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line != oldWidget.line) _apply(widget.line);
  }

  @override
  void dispose() {
    _afterglow?.cancel();
    super.dispose();
  }

  void _apply(ConversationCaptionLine? line) {
    _afterglow?.cancel();
    _afterglow = null;
    if (line == null || line.text.isEmpty) {
      _visible = false;
      return;
    }
    _shown = line.text;
    _visible = true;
    // While the provider keeps extending the line there is nothing to count
    // down from; the hold only starts once the line is done.
    if (!line.settled) return;
    _afterglow = Timer(ListenMotion.ambient, () {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: _captionSlotHeight,
      child: Center(
        child: AnimatedOpacity(
          key: const ValueKey('conversation-afterglow-caption'),
          opacity: _visible ? 1 : 0,
          duration: reduceMotion
              ? Duration.zero
              : (_visible ? ListenMotion.base : ListenMotion.slow),
          curve: _visible ? ListenMotion.enter : ListenMotion.exit,
          child: ConstrainedBox(
            // The stage's own column measure, shared with the lobby it grew
            // out of: the caption may not be wider than the room it is spoken
            // in, and the cap is where the sentence gets trimmed.
            constraints: const BoxConstraints(
              maxWidth: ListenBreakpoints.formColumnMax,
            ),
            child: Text(
              _shown,
              // One line, always. An overlong sentence is trimmed rather than
              // wrapped: the stage never grows a second line of text.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                // 月白 at low luminance: the other person's voice, dim enough
                // to be glanced at rather than read.
                color: ListenColors.moonWhite.withValues(alpha: 0.62),
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed so the shape above never moves as the line comes and goes.
const double _captionSlotHeight = 26;
