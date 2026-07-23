import 'package:flutter/animation.dart';

/// The charter's motion language (#28 / #32): content arrives by "powering
/// on / settling", the shell leaves by "receding" — never by bouncing.
///
/// Durations and curves mirror the owner-approved motion spec
/// (`design-notes/listen-motion.html`). Widgets reference these instead of
/// inventing literals so the whole app breathes at one tempo.
///
/// Forbidden by the spec: bounce / rubber-band / overshoot, celebratory
/// effects, decorative spinners, attention-grabbing motion. All animation
/// sites must respect `MediaQuery.disableAnimationsOf` (reduce motion) by
/// dropping to zero duration.
abstract final class ListenMotion {
  /// Immediate confirmation of a tap — fast enough to read as "the press
  /// itself", not an animation (spec `--dur-tap`).
  static const tap = Duration(milliseconds: 90);

  /// Hover states easing in/out — noticeable but never laggy
  /// (spec `--dur-hover`).
  static const hover = Duration(milliseconds: 160);

  /// The default tempo: content entering, the current word powering on,
  /// shell receding (spec `--dur-base`).
  static const base = Duration(milliseconds: 240);

  /// Larger surface changes — panels, dialogs (spec `--dur-slow`).
  static const slow = Duration(milliseconds: 360);

  /// Ambient breathing, e.g. the rhythm beat pulse — slow enough to feel
  /// like a heartbeat, not a blink (spec `--dur-ambient`).
  static const ambient = Duration(milliseconds: 2600);

  /// Content entering: decelerate and settle, no overshoot
  /// (spec `--ease-enter` = cubic-bezier(.2,.8,.2,1)).
  static const enter = Cubic(0.2, 0.8, 0.2, 1);

  /// Shell leaving: accelerate away (spec `--ease-exit` =
  /// cubic-bezier(.4,0,1,1)).
  static const exit = Cubic(0.4, 0, 1, 1);

  /// Positional movement: the standard curve (spec `--ease-move` =
  /// cubic-bezier(.4,0,.2,1)).
  static const move = Cubic(0.4, 0, 0.2, 1);
}
