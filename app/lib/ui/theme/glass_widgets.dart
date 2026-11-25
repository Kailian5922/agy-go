import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// Ambient vertical gradient canvas behind every page (depth via material, not shadows).
class AgyBackdrop extends StatelessWidget {
  const AgyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surfaces.bgTop, surfaces.bgBottom],
        ),
      ),
      child: child,
    );
  }
}

/// Frosted glass container with hairline border and automatic blur fallback.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.blurSigma = 18,
    this.fillColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fillColor ?? surfaces.glassFill,
        borderRadius: borderRadius,
        border: Border.all(color: surfaces.hairline, width: 0.75),
      ),
      child: child,
    );

    if (!surfaces.blurEnabled) {
      return ClipRRect(borderRadius: borderRadius, child: inner);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: inner,
      ),
    );
  }
}

/// Semi-transparent hairline card resting cleanly on the ambient gradient.
class HairlineCard extends StatelessWidget {
  const HairlineCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.onTap,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? surfaces.cardFill,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? surfaces.hairline,
          width: 0.75,
        ),
      ),
      child: child,
    );

    if (onTap == null) return box;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: box,
      ),
    );
  }
}

/// Compact pill with status dot + concise label.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.dotColor,
    this.onTap,
    this.trailing,
  });

  final String label;
  final Color dotColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: surfaces.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: surfaces.hairline, width: 0.75),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: content,
      ),
    );
  }
}
