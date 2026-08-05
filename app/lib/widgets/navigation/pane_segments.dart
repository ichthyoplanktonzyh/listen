import 'package:flutter/material.dart';

import '../../theme/breakpoints.dart';
import '../../theme/spacing.dart';

/// Segments of the "listen" destination: where material comes from, and what
/// is already here. Both ends are the same media library (three entry points,
/// one destination), so they are two views of one page rather than two
/// sidebar rows.
enum ListenSegment { discover, library }

/// Segments of the "my language" destination. Vocabulary, expressions and
/// review share one identity — the language the learner has collected, and
/// the practice on it — so review is an action on the collection rather than
/// its neighbour in the rail.
enum LanguageSegment { vocabulary, expressions, review }

/// One segment of a [SegmentedPane]: its label and the body it shows.
class PaneSegment<T> {
  const PaneSegment({
    required this.value,
    required this.label,
    required this.builder,
  });

  final T value;

  /// Already-localized label — the pane never looks strings up itself.
  final String label;

  /// Built only while this segment is selected.
  final WidgetBuilder builder;
}

/// A destination that holds several surfaces under one identity: a segment
/// row on top, the selected surface below.
///
/// Controlled, not stateful: the shell owns the selection so it can be set
/// from outside — the coach's suggestions have to land on a *specific*
/// segment, and a pane that hid its selection could only ever be opened at
/// its first one.
///
/// Only the selected segment is built. Switching therefore disposes the
/// previous body, which is what the route-scoped controller hosts already
/// expect (build on entry, dispose on leave). The segments are independent
/// read surfaces with no uncommitted state between them, so nothing is lost;
/// a review *session* is pushed above this pane and is not on the stack while
/// a switch is possible.
class SegmentedPane<T> extends StatelessWidget {
  const SegmentedPane({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  final List<PaneSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final current = segments.firstWhere(
      (segment) => segment.value == selected,
      orElse: () => segments.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ListenSpacing.gap24,
            ListenSpacing.gap16,
            ListenSpacing.gap24,
            ListenSpacing.gap12,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ListenBreakpoints.wideColumnMax,
                ),
                child: SegmentedButton<T>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final segment in segments)
                      ButtonSegment<T>(
                        value: segment.value,
                        label: Text(segment.label),
                      ),
                  ],
                  selected: {current.value},
                  onSelectionChanged: (selection) =>
                      onSelected(selection.first),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: current.builder(context)),
      ],
    );
  }
}
