// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass.dart';
import '../theme/motion.dart';
import '../theme/semantic_colors.dart';
import '../theme/shapes.dart';
import '../theme/sheet_recede.dart';
import '../theme/surfaces.dart';
import 'sheet_dismissal.dart';
import 'sheet_title_bar.dart';

export 'sheet_dismissal.dart'
    show SheetDismissal, SheetDismissScope, SheetDragHolds;
export 'sheet_title_bar.dart'
    show SheetIconButton, SheetSectionLabel, SheetTitleBar;

const double kSheetGutter = SheetTitleBar.inset;

TextStyle? groupTitleStyle(BuildContext context) => Theme.of(
  context,
).textTheme.labelLarge?.copyWith(color: DshColors.of(context).textTertiary);

class _InAppSheet extends InheritedWidget {
  const _InAppSheet({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InAppSheet>() != null;

  @override
  bool updateShouldNotify(_InAppSheet oldWidget) => false;
}

/// Unified frosted-glass bottom sheet entry mirroring DSH Go.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double? heightFactor,
  bool isScrollControlled = false,
  bool glass = true,
  SheetDismissal? dismissal,
  void Function(ModalRoute<Object?> route, Route<dynamic>? nextRoute)?
  onRouteChanged,
}) {
  final policy =
      dismissal ??
      (heightFactor == null ? SheetDismissal.drag : SheetDismissal.button);
  final draggable = policy == SheetDismissal.drag;
  final holds = draggable ? SheetDragHolds() : null;
  Widget scoped(Widget child) => SheetDismissScope(
    dismissal: policy,
    holds: holds,
    child: _InAppSheet(child: child),
  );
  WidgetBuilder sized(WidgetBuilder inner) => heightFactor == null
      ? (context) => scoped(Builder(builder: inner))
      : (context) => scoped(
          SizedBox(
            height: MediaQuery.sizeOf(context).height * heightFactor,
            width: double.infinity,
            child: Builder(builder: inner),
          ),
        );

  final short = MediaQuery.sizeOf(context).height < 480;
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final route = _AppSheetRoute<T>(
    onRouteChanged: onRouteChanged,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    useSafeArea: true,
    isScrollControlled: isScrollControlled || heightFactor != null,
    scrollControlDisabledMaxHeightRatio: short ? 1 : 9 / 16,
    showDragHandle: false,
    enableDrag: draggable,
    isDismissible: draggable,
    backgroundColor: glass ? Colors.transparent : null,
    elevation: 0,
    sheetAnimationStyle: AppMotion.reduced(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: AppMotion.sheetIn,
            reverseDuration: AppMotion.sheetOut,
            curve: AppMotion.sheetRise,
            reverseCurve: AppMotion.sheetFall,
          ),
    builder: sized((context) {
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (draggable)
            SheetDragHandle(onDismiss: () => Navigator.of(context).maybePop()),
          Flexible(child: builder(context)),
        ],
      );
      Widget surface([Animation<double>? held]) => glass
          ? _SheetGlass(
              held: held,
              child: Material(type: MaterialType.transparency, child: content),
            )
          : content;
      return SheetRecedeSheet(
        child: holds == null
            ? surface()
            : _HeldSheetDrag(holds: holds, builder: surface),
      );
    }),
  );
  onRouteChanged?.call(route, null);
  return navigator
      .push(route)
      .whenComplete(() => onRouteChanged?.call(route, null));
}

class _AppSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AppSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.useSafeArea,
    super.scrollControlDisabledMaxHeightRatio,
    super.showDragHandle,
    super.enableDrag,
    super.isDismissible,
    super.backgroundColor,
    super.elevation,
    super.sheetAnimationStyle,
    this.onRouteChanged,
  });
  final void Function(ModalRoute<Object?> route, Route<dynamic>? nextRoute)?
  onRouteChanged;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    onRouteChanged?.call(this, nextRoute);
  }
}

class _SheetGlass extends StatefulWidget {
  const _SheetGlass({this.held, required this.child});

  final Animation<double>? held;
  final Widget child;

  @override
  State<_SheetGlass> createState() => _SheetGlassState();
}

class _SheetGlassState extends State<_SheetGlass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settled = AnimationController(
    vsync: this,
    duration: AppMotion.glassIn,
  );
  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_route != null) return;
    _route = ModalRoute.of(context)!.animation!..addStatusListener(_onRoute);
    widget.held?.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRoute);
    widget.held?.removeListener(_sync);
    _settled.dispose();
    super.dispose();
  }

  void _onRoute(AnimationStatus _) => _sync();

  void _sync() {
    if (!_route!.isCompleted || (widget.held?.value ?? 0) != 0) {
      if (_settled.value != 0) _settled.value = 0;
    } else if (AppMotion.reduced(context)) {
      _settled.value = 1;
    } else if (!_settled.isForwardOrCompleted) {
      unawaited(_settled.forward());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _settled,
    builder: (context, child) => GlassSurface(
      tier: GlassTier.sheet,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppShape.xl),
      ),
      settled: _settled.value,
      child: child,
    ),
    child: widget.child,
  );
}

class _HeldSheetDrag extends StatefulWidget {
  const _HeldSheetDrag({required this.holds, required this.builder});

  final SheetDragHolds holds;
  final Widget Function(Animation<double> offset) builder;

  @override
  State<_HeldSheetDrag> createState() => _HeldSheetDragState();
}

class _HeldSheetDragState extends State<_HeldSheetDrag>
    with SingleTickerProviderStateMixin {
  static const _flingVelocity = 700.0;
  static const _closeFraction = 0.5;

  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _dragged = 0;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    if (_offset.isAnimating) {
      _offset.stop();
      _dragged = _offset.value;
    }
    _dragged += details.delta.dy;
    _offset.value = math.max(0, _dragged);
  }

  void _settle([double velocity = 0]) {
    _dragged = 0;
    if (AppMotion.reduced(context) || _offset.value == 0) {
      _offset.value = 0;
      return;
    }
    final height = context.size?.height ?? MediaQuery.sizeOf(context).height;
    unawaited(
      _offset.animateWith(
        AppMotion.settle(
          AppMotion.sheetSpring,
          _offset.value,
          0,
          velocity,
          extent: height,
        ),
      ),
    );
  }

  void _end(DragEndDetails details) {
    final height = context.size?.height ?? double.infinity;
    final velocity = details.primaryVelocity ?? 0;
    final closing =
        velocity > _flingVelocity || _dragged > height * _closeFraction;
    _settle(velocity);
    if (closing) unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      _HeldDragRecognizer:
          GestureRecognizerFactoryWithHandlers<_HeldDragRecognizer>(
            () => _HeldDragRecognizer(holds: widget.holds, debugOwner: this),
            (recognizer) => recognizer
              ..holds = widget.holds
              ..onlyAcceptDragOnThreshold = true
              ..onUpdate = _update
              ..onEnd = _end
              ..onCancel = _settle,
          ),
    },
    child: AnimatedBuilder(
      animation: _offset,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _offset.value), child: child),
      child: widget.builder(_offset),
    ),
  );
}

class _HeldDragRecognizer extends VerticalDragGestureRecognizer {
  _HeldDragRecognizer({required this.holds, super.debugOwner});

  SheetDragHolds holds;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      holds.held && super.isPointerAllowed(event);
}

class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
    final mark = Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Container(
        width: 36,
        height: 4,
        decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      ),
    );
    if (onDismiss == null) return mark;
    return Semantics(
      button: true,
      label: '关闭',
      onTap: onDismiss,
      onDismiss: onDismiss,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: Center(child: mark),
        ),
      ),
    );
  }
}

class SheetHeader extends StatelessWidget {
  const SheetHeader(
    this.title, {
    super.key,
    this.actions = const [],
    this.maxLines = 1,
  });

  final String title;
  final List<Widget> actions;
  final int? maxLines;
  static const buttonSize = SheetTitleBar.keySize;

  @override
  Widget build(BuildContext context) =>
      SheetTitleBar(title, actions: actions, maxLines: maxLines);
}

class SheetGroup extends StatelessWidget {
  const SheetGroup({
    super.key,
    required this.children,
    this.title,
    this.margin,
  });

  final List<Widget> children;
  final String? title;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final horizontal = _InAppSheet.of(context) ? kSheetGutter : 16.0;
    return Padding(
      padding:
          margin ?? EdgeInsets.symmetric(horizontal: horizontal, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title case final label?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Semantics(
                header: true,
                child: Text(label, style: groupTitleStyle(context)),
              ),
            ),
          GlassSurface(
            tier: GlassTier.card,
            borderRadius: AppShape.radiusLg,
            child: Material(
              type: MaterialType.transparency,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedSuperellipseBorder(
                borderRadius: AppShape.radiusLg,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, child) in children.indexed) ...[
                      if (index > 0) const SizedBox(height: 2),
                      child,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
