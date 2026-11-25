// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';

class PillSegment<T> {
  const PillSegment(this.value, this.label);
  final T value;
  final String label;
}

/// Capsule segmented control with sliding thumb, drag support, and single-line CJK safety.
class SegmentedPill<T> extends StatefulWidget {
  const SegmentedPill({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = true,
    this.height = 36,
    this.onReselect,
  }) : assert(segments.length >= 2);

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;
  final ValueChanged<T>? onReselect;
  final bool expand;
  final double height;

  static const inset = 3.0;
  static const _labelPadding = 14.0;

  static TextStyle labelStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelLarge!
      .copyWith(fontSize: 13.5, height: 1.2, letterSpacing: 0.1);

  static double naturalWidth(BuildContext context, List<String> labels) {
    final style = labelStyle(context).copyWith(fontWeight: FontWeight.w600);
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textScaler: scaler,
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return labels.length * (widest + 2 * _labelPadding) + 2 * inset;
  }

  @override
  State<SegmentedPill<T>> createState() => _SegmentedPillState<T>();
}

class _SegmentedPillState<T> extends State<SegmentedPill<T>> {
  double? _drag;

  int get _index {
    final i = widget.segments.indexWhere((s) => s.value == widget.selected);
    return i < 0 ? 0 : i;
  }

  void _pick(int index, {bool tick = true}) {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    final value = widget.segments[index].value;
    if (value != widget.selected) {
      if (tick) HapticFeedback.selectionClick();
      onChanged(value);
    }
  }

  void _tap(int index) {
    final value = widget.segments[index].value;
    if (value == widget.selected && widget.onReselect != null) {
      return widget.onReselect!(value);
    }
    _pick(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final enabled = widget.onChanged != null;
    final n = widget.segments.length;
    final track = dark
        ? Colors.white.withValues(alpha: 0.07)
        : colors.onSurface.withValues(alpha: 0.06);
    final thumb = dark ? Colors.white.withValues(alpha: 0.2) : Colors.white;
    final style = SegmentedPill.labelStyle(context);
    final height = math.max(
      widget.height,
      MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height! +
          2 * SegmentedPill.inset +
          14,
    );
    final fluid = AppMotion.fluid(context);

    Widget pill(double width) {
      final segment = (width - 2 * SegmentedPill.inset) / n;
      final rest = SegmentedPill.inset + _index * segment;
      final left = (_drag ?? rest).clamp(
        SegmentedPill.inset,
        SegmentedPill.inset + (n - 1) * segment,
      );
      final current = _drag == null
          ? _index
          : ((left - SegmentedPill.inset) / segment).round().clamp(0, n - 1);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart:
            enabled ? (_) => setState(() => _drag = rest) : null,
        onHorizontalDragUpdate: enabled
            ? (d) {
                final next = ((_drag ?? rest) + d.delta.dx).clamp(
                  SegmentedPill.inset,
                  SegmentedPill.inset + (n - 1) * segment,
                );
                final under = ((next - SegmentedPill.inset) / segment).round();
                if (fluid && under != current) HapticFeedback.selectionClick();
                setState(() => _drag = (_drag ?? rest) + d.delta.dx);
              }
            : null,
        onHorizontalDragEnd: enabled
            ? (_) {
                final target = current;
                setState(() => _drag = null);
                _pick(target, tick: !fluid);
              }
            : null,
        onHorizontalDragCancel: () => setState(() => _drag = null),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: width,
            height: height,
            decoration: ShapeDecoration(
              color: track,
              shape: const StadiumBorder(),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: _drag != null
                      ? Duration.zero
                      : (fluid
                            ? AppMotion.thumbCurve.duration
                            : AppMotion.of(context, AppMotion.standard)),
                  curve: fluid ? AppMotion.thumbCurve : AppMotion.std,
                  left: left,
                  top: SegmentedPill.inset,
                  bottom: SegmentedPill.inset,
                  width: segment,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: thumb,
                      shape: const StadiumBorder(),
                      shadows: dark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          enabled: enabled,
                          onTap: enabled ? () => _tap(i) : null,
                          selected: i == _index,
                          inMutuallyExclusiveGroup: true,
                          label: widget.segments[i].label,
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: enabled ? () => _tap(i) : null,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: AnimatedDefaultTextStyle(
                                    duration: AppMotion.of(
                                      context,
                                      AppMotion.quick,
                                    ),
                                    style: style.copyWith(
                                      fontWeight: i == current
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: i == current
                                          ? colors.onSurface
                                          : colors.onSurfaceVariant,
                                    ),
                                    child: Text(
                                      widget.segments[i].label,
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!widget.expand) {
      return pill(
        SegmentedPill.naturalWidth(context, [
          for (final s in widget.segments) s.label,
        ]),
      );
    }
    return LayoutBuilder(builder: (context, c) => pill(c.maxWidth));
  }
}
