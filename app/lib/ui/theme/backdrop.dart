// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:material_ui/material_ui.dart';

import 'feather.dart';
import 'surfaces.dart';

/// Full-screen Mist Glass backdrop: vertical low-chroma mist/night gradient plus
/// two subtle ambient corner glows so frosted chrome/sheet glass picks up soft colour.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.glow = true});

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final s = DshSurfaces.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BackdropPainter(
                  top: s.backdropTop,
                  bottom: s.backdropBottom,
                  glowPrimary: glow ? s.glowPrimary : null,
                  glowSecondary: glow ? s.glowSecondary : null,
                ),
              ),
            ),
          ),
        ),
        Material(type: MaterialType.transparency, child: child),
      ],
    );
  }
}

/// Paints the top strip of the page's backdrop feathered smoothly into transparent,
/// keeping scrolled content from clashing with the floating glass header or status bar.
class BackdropVeil extends StatelessWidget {
  const BackdropVeil.top({
    super.key,
    required this.height,
    this.feather = 12,
  });

  final double height;
  final double feather;

  @override
  Widget build(BuildContext context) {
    final s = DshSurfaces.of(context);
    final total = height + feather;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: total,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: featherFade(
                color: s.backdropTop,
                height: total,
                solidUntil: height,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.top,
    required this.bottom,
    this.glowPrimary,
    this.glowSecondary,
  });

  final Color top;
  final Color bottom;
  final Color? glowPrimary;
  final Color? glowSecondary;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );
    final longest = size.longestSide;
    if (glowPrimary case final color?) {
      _glow(canvas, Offset(size.width * 0.92, 0), longest * 0.62, color);
    }
    if (glowSecondary case final color?) {
      _glow(canvas, Offset(0, size.height), longest * 0.55, color);
    }
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.glowPrimary != glowPrimary ||
      old.glowSecondary != glowSecondary;
}
