import 'package:flutter/material.dart';

import '../theme/typography.dart';

/// The listen brand mark + wordmark (#28 direction B "mutual wave", #32).
///
/// Three bars mirrored around a midline: above it the content (bright), below
/// it your echo (dark) — one wave, two directions. The mark colors are brand
/// constants, not theme roles: a logo keeps its identity in both themes, and
/// the bright/dark relationship *is* the meaning (you listen to content, the
/// product listens to you), so it must not flip with brightness.
///
/// Reused verbatim by the app bar, and later the home/launch surfaces —
/// anything that needs the product's signature draws this widget instead of
/// improvising.
class ListenWordmark extends StatelessWidget {
  const ListenWordmark({super.key, this.size = 22, this.withText = true});

  /// Height of the square mark. The wordmark text scales with it
  /// (lockup ratio from `design-notes/listen-mark-exploration.html`:
  /// 30px mark ↔ 27px text ↔ 12px gap).
  final double size;

  /// False renders the bare mark (favicon-like contexts).
  final bool withText;

  /// Content half of the wave — the charter signal teal.
  static const markContent = Color(0xff4db8a8);

  /// Echo half — the same teal, receded. Fixed rather than derived so the
  /// mark's two halves keep their drawn relationship at any theme.
  static const markEcho = Color(0xff2f8578);

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: const _MutualWavePainter(),
    );
    if (!withText) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.4),
        Text(
          'listen',
          style: TextStyle(
            // Draft weighs the wordmark at 800; the bundled Plex family tops
            // out at SemiBold, and w600 of a real face beats a synthetic 800.
            fontWeight: FontWeight.w600,
            fontSize: size * 0.9,
            height: 1.0,
            letterSpacing: size * 0.9 * -0.02,
            fontFamily: ListenFonts.sans,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Geometry lifted from the accepted lockup SVG (viewBox 64: bars at
/// x 16/28/40, up 12/19/8, down 10/17/6, stroke 5, round caps), re-centered
/// horizontally.
class _MutualWavePainter extends CustomPainter {
  const _MutualWavePainter();

  static const _x = [0.22, 0.5, 0.78];
  static const _up = [0.19, 0.3, 0.125];
  static const _down = [0.156, 0.266, 0.094];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final mid = size.height / 2;
    final stroke = Paint()
      ..strokeWidth = s * 0.078
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final x = size.width * _x[i];
      stroke.color = ListenWordmark.markContent;
      canvas.drawLine(Offset(x, mid), Offset(x, mid - s * _up[i]), stroke);
      stroke.color = ListenWordmark.markEcho;
      canvas.drawLine(Offset(x, mid), Offset(x, mid + s * _down[i]), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MutualWavePainter oldDelegate) => false;
}
