import 'package:flutter/material.dart';

import '../../theme/listen_theme.dart';

/// A compact horizontal sentence lane that follows the active item and can
/// expand into a wrapped, full-sentence view. The children remain the source of
/// truth; this widget only owns navigation and overflow affordances.
class FollowingStructureViewport extends StatefulWidget {
  const FollowingStructureViewport({
    super.key,
    required this.children,
    this.activeIndex,
    this.spacing = 6,
    this.runSpacing = 6,
    this.maxExpandedHeight = 180,
    this.expandTooltip = 'Show full sentence',
    this.collapseTooltip = 'Collapse sentence',
  });

  final List<Widget> children;
  final int? activeIndex;
  final double spacing;
  final double runSpacing;
  final double maxExpandedHeight;
  final String expandTooltip;
  final String collapseTooltip;

  @override
  State<FollowingStructureViewport> createState() =>
      _FollowingStructureViewportState();
}

class _FollowingStructureViewportState
    extends State<FollowingStructureViewport> {
  final _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = [];
  bool _expanded = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _syncKeys();
    _scrollController.addListener(_updateEdges);
    _afterLayout(follow: true);
  }

  @override
  void didUpdateWidget(FollowingStructureViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    _afterLayout(follow: oldWidget.activeIndex != widget.activeIndex);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateEdges)
      ..dispose();
    super.dispose();
  }

  void _syncKeys() {
    while (_itemKeys.length < widget.children.length) {
      _itemKeys.add(GlobalKey());
    }
    if (_itemKeys.length > widget.children.length) {
      _itemKeys.removeRange(widget.children.length, _itemKeys.length);
    }
  }

  void _afterLayout({required bool follow}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateEdges();
      if (follow && !_expanded) _followActive();
    });
  }

  void _updateEdges() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final left = position.pixels > position.minScrollExtent + 1;
    final right = position.pixels < position.maxScrollExtent - 1;
    if (left == _canScrollLeft && right == _canScrollRight) return;
    if (mounted) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _followActive() {
    final index = widget.activeIndex;
    if (index == null || index < 0 || index >= _itemKeys.length) return;
    final context = _itemKeys[index].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.42,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  List<Widget> _keyedChildren() => [
    for (var index = 0; index < widget.children.length; index += 1)
      KeyedSubtree(key: _itemKeys[index], child: widget.children[index]),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final toggle = Tooltip(
      message: _expanded ? widget.collapseTooltip : widget.expandTooltip,
      child: IconButton(
        key: const ValueKey('structure-viewport-toggle'),
        onPressed: () {
          setState(() => _expanded = !_expanded);
          _afterLayout(follow: true);
        },
        icon: Icon(_expanded ? Icons.unfold_less : Icons.unfold_more),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        iconSize: 17,
        color: ListenColors.overlayTextMuted,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _expanded ? _expandedLane() : _compactLane()),
        const SizedBox(width: 3),
        toggle,
      ],
    );
  }

  Widget _compactLane() => Stack(
    alignment: Alignment.center,
    children: [
      SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var index = 0; index < widget.children.length; index += 1) ...[
              if (index > 0) SizedBox(width: widget.spacing),
              KeyedSubtree(
                key: _itemKeys[index],
                child: widget.children[index],
              ),
            ],
          ],
        ),
      ),
      if (_canScrollLeft) const _EdgeFade(left: true),
      if (_canScrollRight) const _EdgeFade(left: false),
    ],
  );

  Widget _expandedLane() => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: widget.maxExpandedHeight),
    child: SingleChildScrollView(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: widget.spacing,
          runSpacing: widget.runSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _keyedChildren(),
        ),
      ),
    ),
  );
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left ? 0 : null,
    right: left ? null : 0,
    top: 0,
    bottom: 0,
    child: IgnorePointer(
      child: Container(
        key: ValueKey(left ? 'structure-edge-left' : 'structure-edge-right'),
        width: 24,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [ListenColors.overlaySurface, Colors.transparent],
          ),
        ),
      ),
    ),
  );
}
