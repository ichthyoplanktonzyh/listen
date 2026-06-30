import 'dart:math' as math;

import 'package:flutter/material.dart';

class SoundPatternModeToggle extends StatelessWidget {
  const SoundPatternModeToggle({
    super.key,
    required this.mode,
    required this.rhythmTooltip,
    required this.phonesTooltip,
    required this.semanticsLabel,
    this.size = 28,
    this.onChanged,
  });

  final String mode;
  final String rhythmTooltip;
  final String phonesTooltip;
  final String semanticsLabel;
  final double size;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final itemSize = math.max(22.0, size - 4);
    final current = mode == 'phones' ? 'phones' : 'rhythm';
    final content = Container(
      height: math.max(24.0, size),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withAlpha(205),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            value: 'rhythm',
            selected: current == 'rhythm',
            tooltip: rhythmTooltip,
            icon: Icons.multiline_chart,
            itemSize: itemSize,
            onChanged: onChanged,
          ),
          const SizedBox(width: 2),
          _ModeButton(
            value: 'phones',
            selected: current == 'phones',
            tooltip: phonesTooltip,
            icon: Icons.graphic_eq,
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
    required this.itemSize,
    required this.onChanged,
  });

  final String value;
  final bool selected;
  final String tooltip;
  final IconData icon;
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
                  ? const Color(0xFFFFD166).withAlpha(230)
                  : Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: selected
                    ? Colors.white.withAlpha(155)
                    : Colors.white.withAlpha(30),
              ),
            ),
            child: Icon(
              icon,
              size: math.max(13.0, itemSize * 0.58),
              color: selected
                  ? Colors.black.withAlpha(220)
                  : Colors.white.withAlpha(170),
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: button);
  }
}
