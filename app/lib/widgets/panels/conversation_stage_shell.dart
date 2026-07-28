import 'package:flutter/material.dart';

import '../../controllers/realtime_conversation_controller.dart';
import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';
import '../../theme/spacing.dart';
import '../common/capability_viz.dart';

/// Which of the conversation's three rooms is on screen (#70 Phase 2 · S6).
///
/// This is **presentation only**. It is derived from the controller's phase —
/// no new state, no estimation, no reinterpretation of what the backend
/// decided. Adding a room here must never change when a conversation starts,
/// drains or finishes.
enum ConversationStageSegment {
  /// 门厅 — before the lights go down: which voice speaks with you, what the
  /// topic is, and the conversation history.
  lobby,

  /// 舞台 — the dark room. The shell recedes entirely and only the live
  /// conversation glows.
  stage,

  /// 结束页 — the stage dims and the debrief takes over. S9 (#86) owns the
  /// three-part 回流 content; S6 only builds the room it lands in.
  debrief,
}

/// Derives the on-screen room from the controller state.
///
/// Deliberately total over [RealtimeConversationPhase] so a new phase forces a
/// decision here rather than silently falling into the lobby.
ConversationStageSegment conversationStageSegmentOf(
  RealtimeConversationState state, {
  bool debriefDismissed = false,
}) => switch (state.phase) {
  RealtimeConversationPhase.connecting ||
  RealtimeConversationPhase.live ||
  RealtimeConversationPhase.draining => ConversationStageSegment.stage,
  RealtimeConversationPhase.postProcessing ||
  RealtimeConversationPhase.done ||
  RealtimeConversationPhase.failed =>
    debriefDismissed || state.items.isEmpty
        ? ConversationStageSegment.lobby
        : ConversationStageSegment.debrief,
  RealtimeConversationPhase.idle => ConversationStageSegment.lobby,
};

/// The full-bleed dark container the whole conversation lives in.
///
/// 「全暗场」(charter · 舞台态): the app shell is already gone — this route
/// covers the app bar — and the ground is compressed to `ground2`, half a stop
/// below the quiet room. The room stays dark in both themes, so the subtree is
/// pinned to the dark scheme instead of inheriting a light one.
///
/// The 门厅→舞台 two-stage entrance is a cross-fade between segments: the lobby
/// leaves on [ListenMotion.exit], the stage arrives on [ListenMotion.enter] at
/// [ListenMotion.slow]. Never a bounce; zero duration under reduce-motion.
class ConversationStageShell extends StatelessWidget {
  const ConversationStageShell({
    super.key,
    required this.segment,
    required this.child,
  });

  final ConversationStageSegment segment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Theme(
      data: ListenTheme.dark(),
      child: Material(
        color: ListenColors.stageGround,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.32),
              radius: 1.1,
              colors: [ListenColors.stageGlow, ListenColors.stageGround],
              stops: [0, 0.78],
            ),
          ),
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : ListenMotion.slow,
            switchInCurve: ListenMotion.enter,
            switchOutCurve: ListenMotion.exit,
            child: KeyedSubtree(key: ValueKey(segment), child: child),
          ),
        ),
      ),
    );
  }
}

/// The stage's slot layout: one big glowing shape in the middle, at most one
/// line of caption under it, and the controls at the bottom edge.
///
/// The slots are the seams the rest of the C wave lands in:
/// - [visualization] → S7 (#84) 回声水面, from `widgets/common/capability_viz`;
/// - [caption] → S8 (#85) 余音字幕 (one line, fades out, no history; your own
///   words never reach the stage — provider captions are guidance only);
/// - [controls] → finish / discard, owned by this slice.
class ConversationStageLayout extends StatelessWidget {
  const ConversationStageLayout({
    super.key,
    required this.visualization,
    required this.controls,
    this.caption,
    this.exitAffordance,
  });

  final Widget visualization;
  final Widget controls;

  /// S8's mount point. Null means "no caption on stage", which is also the
  /// owner-decided default (`字幕默认关`).
  final Widget? caption;

  final Widget? exitAffordance;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(ListenSpacing.gap12),
            child: exitAffordance ?? const SizedBox.shrink(),
          ),
        ),
        Expanded(child: Center(child: visualization)),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ListenSpacing.gap24,
              vertical: ListenSpacing.gap8,
            ),
            child: caption,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ListenSpacing.gap24,
            ListenSpacing.gap12,
            ListenSpacing.gap24,
            ListenSpacing.gap32,
          ),
          child: controls,
        ),
      ],
    ),
  );
}

/// Route for the conversation: the stage powers on, it does not slide in like
/// a page of chrome.
///
/// Replaces `MaterialPageRoute` (issue #83). Deliberately **not** tied to
/// macOS fullscreen — F and the system fullscreen stay with the player
/// (#25 boundary untouched); the stage is a window-sized dark room because a
/// conversation is usually accompanied by dictionary lookups.
Route<T> conversationStageRoute<T>({
  required WidgetBuilder builder,
  bool reduceMotion = false,
}) => PageRouteBuilder<T>(
  transitionDuration: reduceMotion ? Duration.zero : ListenMotion.slow,
  reverseTransitionDuration: reduceMotion ? Duration.zero : ListenMotion.base,
  pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    if (reduceMotion || MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: ListenMotion.enter,
        reverseCurve: ListenMotion.exit,
      ),
      child: child,
    );
  },
);

/// Maps the controller's activity onto the 回声水面's light levels (#84 · S7).
///
/// **Presentation only.** The state machine is reused as-is: this function
/// reads `activity` and returns light — it never estimates, smooths, or
/// re-decides who is speaking. 色的角色分配 (charter): your voice is signal
/// teal, the brightest moment of the flow; the other person's voice is 月白;
/// nothing else glows.
///
/// The four states are separated on three independent axes so they stay
/// legible without reading a label (fixes D2, 状态退化成一枚 Chip):
/// - `listening` 微澜 — your side barely stirs, the water waits for you;
/// - `learnerSpeaking` 青波升起 — your echo takes the surface, the moon is gone;
/// - `thinking` 涟漪 — no voice, one ripple spreading from the waterline;
/// - `assistantSpeaking` 月白落下 — light falls from above, and your side keeps
///   a visible resting swell: the channel is open, you may cut in (fixes D5).
EchoSurfaceLevels conversationEchoLevelsOf(
  RealtimeConversationActivity activity,
) => switch (activity) {
  RealtimeConversationActivity.inactive => EchoSurfaceLevels.still,
  RealtimeConversationActivity.listening => const EchoSurfaceLevels(
    moon: 0.1,
    learner: 0.26,
    ripple: 0,
  ),
  RealtimeConversationActivity.learnerSpeaking => const EchoSurfaceLevels(
    moon: 0,
    learner: 1,
    ripple: 0,
  ),
  RealtimeConversationActivity.thinking => const EchoSurfaceLevels(
    moon: 0.14,
    learner: 0.12,
    ripple: 1,
  ),
  RealtimeConversationActivity.assistantSpeaking => const EchoSurfaceLevels(
    moon: 1,
    learner: 0.2,
    ripple: 0,
  ),
};
