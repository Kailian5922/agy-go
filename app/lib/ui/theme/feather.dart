import 'package:flutter/widgets.dart';

import 'backdrop.dart';
import 'surfaces.dart';

/// A feathered top fade: fully [color] down to [solidUntil], then eases out to
/// transparent at [height] along an ease-in-out curve, so neither end of the
/// transition shows a crease (a linear ramp reads as a hard edge).
///
/// Used behind floating chrome (chat header, web controls) instead of a divider.
LinearGradient featherFade({
  required Color color,
  required double height,
  required double solidUntil,
  int samples = 12,
}) {
  final solid = (solidUntil / height).clamp(0.0, 1.0);
  final colors = <Color>[color, color];
  final stops = <double>[0, solid];
  for (var i = 1; i <= samples; i++) {
    final t = i / samples;
    final keep = 1 - Curves.easeInOutCubic.transform(t);
    colors.add(color.withValues(alpha: color.a * keep));
    stops.add(solid + (1 - solid) * t);
  }
  return LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: stops);
}

/// Page-coloured fade under the status bar and floating top buttons.
///
/// Shared by every top bar (secondary pages, chat) so they read the same: no
/// slab, no divider; the page's own backdrop, solid behind the buttons and
/// feathered out over the last 16dp.
/// Callers fade it in only once content has scrolled under the bar, so at rest
/// the page is one uninterrupted surface.
class TopFade extends StatelessWidget {
  const TopFade({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: BackdropVeil.top(height: height - 16, feather: 16),
  );
}

/// Page-coloured feathered bottom fade behind the floating composer dock.
class BottomFade extends StatelessWidget {
  const BottomFade({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final bottom = DshSurfaces.of(context).backdropBottom;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  bottom,
                  bottom.withValues(alpha: bottom.a * 0.85),
                  bottom.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
