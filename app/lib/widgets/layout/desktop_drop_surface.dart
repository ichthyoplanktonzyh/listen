import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// Desktop plugin adapter that exposes dropped paths to the app shell.
class DesktopDropSurface extends StatefulWidget {
  const DesktopDropSurface({
    super.key,
    required this.onDropped,
    required this.child,
  });

  final FutureOr<void> Function(List<String> paths) onDropped;
  final Widget child;

  @override
  State<DesktopDropSurface> createState() => _DesktopDropSurfaceState();
}

class _DesktopDropSurfaceState extends State<DesktopDropSurface> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _dragging = true),
    onDragExited: (_) => setState(() => _dragging = false),
    onDragDone: (details) {
      setState(() => _dragging = false);
      unawaited(
        Future<void>.sync(
          () => widget.onDropped(
            details.files.map((file) => file.path).toList(growable: false),
          ),
        ),
      );
    },
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: _dragging
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 4)
            : null,
      ),
      child: widget.child,
    ),
  );
}
