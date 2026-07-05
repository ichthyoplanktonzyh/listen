import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/listen_theme.dart';

class RhythmReferenceToggle extends StatelessWidget {
  const RhythmReferenceToggle({
    super.key,
    required this.mode,
    required this.citationTooltip,
    required this.connectedTooltip,
    required this.actualTooltip,
    required this.semanticsLabel,
    this.size = 28,
    this.onChanged,
  });

  final String mode;
  final String citationTooltip;
  final String connectedTooltip;
  final String actualTooltip;
  final String semanticsLabel;
  final double size;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final itemSize = math.max(22.0, size - 4);
    final current = switch (mode) {
      'citation' || 'connected' => mode,
      _ => 'actual',
    };
    final content = Container(
      height: math.max(24.0, size),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ListenColors.overlaySurface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: ListenColors.overlayBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            value: 'citation',
            selected: current == 'citation',
            tooltip: citationTooltip,
            icon: Icons.menu_book_outlined,
            selectedColor: ListenColors.soundCitation,
            itemSize: itemSize,
            onChanged: onChanged,
          ),
          const SizedBox(width: 2),
          _ModeButton(
            value: 'connected',
            selected: current == 'connected',
            tooltip: connectedTooltip,
            icon: Icons.route_outlined,
            selectedColor: ListenColors.soundConnected,
            itemSize: itemSize,
            onChanged: onChanged,
          ),
          const SizedBox(width: 2),
          _ModeButton(
            value: 'actual',
            selected: current == 'actual',
            tooltip: actualTooltip,
            icon: Icons.multiline_chart,
            selectedColor: ListenColors.soundActual,
            itemSize: itemSize,
            onChanged: onChanged,
          ),
        ],
      ),
    );
    return Semantics(label: semanticsLabel, child: content);
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.value,
    required this.selected,
    required this.tooltip,
    required this.icon,
    required this.selectedColor,
    required this.itemSize,
    required this.onChanged,
  });

  final String value;
  final bool selected;
  final String tooltip;
  final IconData icon;
  final Color selectedColor;
  final double itemSize;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null && !selected;
    final button = Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            width: itemSize,
            height: itemSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? selectedColor.withAlpha(230)
                  : ListenColors.overlayText.withAlpha(20),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: selected
                    ? ListenColors.overlayText.withAlpha(155)
                    : ListenColors.overlayText.withAlpha(30),
              ),
            ),
            child: Icon(
              icon,
              size: math.max(13.0, itemSize * 0.58),
              color: selected
                  ? ListenColors.overlayInk
                  : ListenColors.overlayTextMuted,
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: button);
  }
}
