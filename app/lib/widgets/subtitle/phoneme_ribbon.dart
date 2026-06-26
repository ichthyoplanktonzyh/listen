import 'package:flutter/material.dart';

import '../../models/timeline.dart';

class PhonemeRibbon extends StatelessWidget {
  const PhonemeRibbon({
    super.key,
    required this.phones,
    required this.position,
    this.fontSize = 12.0,
    this.height = 28.0,
    this.gap = 1.0,
  });

  final List<DetectedPhone> phones;
  final Duration position;
  final double fontSize;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (phones.isEmpty) return const SizedBox.shrink();

    final totalMs = _totalDuration();
    if (totalMs <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - gap * (phones.length - 1).clamp(0, 999);
        if (availableWidth <= 0) return const SizedBox.shrink();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < phones.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              _PhoneCell(
                phone: phones[i],
                width: _cellWidth(phones[i], totalMs, availableWidth),
                height: height,
                fontSize: fontSize,
                isCurrent: _isCurrent(phones[i]),
              ),
            ],
          ],
        );
      },
    );
  }

  double _totalDuration() {
    if (phones.isEmpty) return 0;
    final first = phones.first.start.inMilliseconds;
    final last = phones.last.end.inMilliseconds;
    return (last - first).toDouble();
  }

  double _cellWidth(DetectedPhone phone, double totalMs, double available) {
    final durationMs =
        (phone.end.inMilliseconds - phone.start.inMilliseconds).toDouble();
    final ratio = durationMs / totalMs;
    return (ratio * available).clamp(4.0, available);
  }

  bool _isCurrent(DetectedPhone phone) =>
      position >= phone.start && position < phone.end;
}

class _PhoneCell extends StatelessWidget {
  const _PhoneCell({
    required this.phone,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.isCurrent,
  });

  final DetectedPhone phone;
  final double width;
  final double height;
  final double fontSize;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final color = _phoneColor(phone.symbol);
    final confidence = phone.confidence ?? 0.8;
    final alpha = isCurrent ? 1.0 : (0.4 + confidence * 0.4).clamp(0.3, 0.8);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: width,
      height: isCurrent ? height * 1.12 : height,
      decoration: BoxDecoration(
        color: color.withAlpha((alpha * 255).round()),
        borderRadius: BorderRadius.circular(3),
        border: isCurrent
            ? Border.all(color: Colors.white.withAlpha(200), width: 1.5)
            : null,
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: color.withAlpha(120),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: width >= 14
          ? Text(
              phone.displayIpa,
              style: TextStyle(
                fontSize: fontSize.clamp(8.0, width * 0.7),
                color: isCurrent ? Colors.white : Colors.white70,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                height: 1.0,
              ),
              overflow: TextOverflow.clip,
              maxLines: 1,
            )
          : null,
    );
  }

  static Color _phoneColor(String symbol) {
    final s = symbol.toUpperCase();
    if (_vowels.contains(s)) return const Color(0xFF5B8DEF);
    if (_approximants.contains(s)) return const Color(0xFF7BC47F);
    return const Color(0xFFE8935A);
  }

  static const _vowels = {
    'AA', 'AE', 'AH', 'AO', 'AW', 'AX', 'AY',
    'EH', 'ER', 'EY',
    'IH', 'IY',
    'OW', 'OY',
    'UH', 'UW',
  };

  static const _approximants = {
    'W', 'Y', 'R', 'L', 'HH',
  };
}
