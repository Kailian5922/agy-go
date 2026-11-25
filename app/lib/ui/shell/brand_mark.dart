import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';

/// Original geometric brand emblem for AGY Go (ascending prism + orbital arc).
/// 100% original artwork — no third-party brand or mascot glyphs.
class AgyBrandMark extends StatelessWidget {
  const AgyBrandMark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AgyMarkPainter(c)),
    );
  }
}

class _AgyMarkPainter extends CustomPainter {
  const _AgyMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);

    // Subtle ascending orbital ring
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 7);
    canvas.drawArc(
      Rect.fromCenter(center: Offset.zero, width: s * 0.92, height: s * 0.44),
      0.15,
      math.pi * 1.48,
      false,
      ringPaint,
    );
    canvas.restore();

    // Clean ascending prism chevron ("A" silhouette without sharp corners)
    final prism = Path()
      ..moveTo(center.dx, center.dy - s * 0.38)
      ..quadraticBezierTo(
        center.dx + s * 0.08,
        center.dy - s * 0.16,
        center.dx + s * 0.31,
        center.dy + s * 0.30,
      )
      ..quadraticBezierTo(
        center.dx + s * 0.10,
        center.dy + s * 0.14,
        center.dx,
        center.dy + s * 0.14,
      )
      ..quadraticBezierTo(
        center.dx - s * 0.10,
        center.dy + s * 0.14,
        center.dx - s * 0.31,
        center.dy + s * 0.30,
      )
      ..quadraticBezierTo(
        center.dx - s * 0.08,
        center.dy - s * 0.16,
        center.dx,
        center.dy - s * 0.38,
      )
      ..close();

    canvas.drawPath(prism, Paint()..color = color);

    // Floating apex spark dot
    canvas.drawCircle(
      Offset(center.dx + s * 0.28, center.dy - s * 0.25),
      s * 0.08,
      Paint()..color = color.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_AgyMarkPainter old) => old.color != color;
}

/// Brand mark + wordmark lockup matching DSH Go's drawer header proportions.
class AgyBrandLockup extends StatelessWidget {
  const AgyBrandLockup({super.key, this.height = 19});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AgyBrandMark(size: height + 3, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          'AGY Go',
          style: AppType.wordmark(size: height, color: scheme.onSurface),
        ),
      ],
    );
  }
}
