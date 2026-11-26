// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../common/side_insets.dart';
import '../theme/theme.dart';

/// Standard frame for every secondary page in AGY Go (exact DSH Go AppPage).
///
/// No solid AppBar slab: floating 44dp circular chrome-glass back button top-left,
/// large scrolling headline that continuously fades into a compact centered bar title,
/// and a feathered BackdropVeil behind the top chrome once content scrolls underneath.
class AppPage extends StatefulWidget {
  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.hero,
    this.slivers = const [],
    this.actions = const [],
    this.showLargeTitle = true,
    this.padBottom = true,
    this.solidBar = true,
    this.leading,
  });

  final String title;
  final Widget? subtitle;
  final Widget? hero;
  final List<Widget> slivers;
  final List<Widget> actions;
  final bool showLargeTitle;
  final bool padBottom;
  final bool solidBar;
  final Widget? leading;

  static const contentWidth = AppSpace.readingWidth;

  static double sideFor(double width, {double inset = 0}) =>
      math.max(inset, (width - contentWidth) / 2).floorToDouble();

  static Widget list({
    Key? key,
    required String title,
    Widget? subtitle,
    Widget? hero,
    required List<Widget> children,
    List<Widget> actions = const [],
    bool solidBar = true,
    bool padBottom = true,
  }) => AppPage(
    key: key,
    title: title,
    subtitle: subtitle,
    hero: hero,
    actions: actions,
    solidBar: solidBar,
    padBottom: padBottom,
    slivers: [SliverList.list(children: children)],
  );

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  static const _maxHeaderHeight = 400.0;
  final _controller = ScrollController();
  final _offset = ValueNotifier(0.0);
  final _headerKey = GlobalKey();
  double _headerHeight = 56;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      _offset.value = _controller.hasClients
          ? math.min(_controller.offset, _maxHeaderHeight)
          : 0.0;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _offset.dispose();
    super.dispose();
  }

  bool get _hasHeader => widget.hero != null || widget.showLargeTitle;

  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _headerHeight = box.size.height.clamp(40.0, _maxHeaderHeight);
    }
  }

  double _headerOpacity(double offset) =>
      (1 - offset / (_headerHeight * 0.6)).clamp(0.0, 1.0);

  double _barTitle(double offset) {
    if (!_hasHeader) return 1;
    return ((offset - _headerHeight * 0.4) / 20).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureHeader();
    });
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context);
    final topInset = math.max(padding.top, 8.0);
    const barHeight = 56.0;
    final top = topInset + barHeight;
    final inset = sideInsetFor(padding);
    final side = EdgeInsets.symmetric(
      horizontal: AppPage.sideFor(MediaQuery.sizeOf(context).width, inset: inset),
    );
    Widget? header;
    if (widget.hero case final hero?) {
      header = hero;
    } else if (widget.showLargeTitle) {
      header = Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              namesRoute: true,
              child: Text(widget.title, style: theme.textTheme.headlineLarge),
            ),
            if (widget.subtitle case final subtitle?) ...[
              const SizedBox(height: 4),
              DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                child: subtitle,
              ),
            ],
          ],
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(theme.brightness),
      child: AppBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              CustomScrollView(
                controller: _controller,
                physics: AppMotion.scrollPhysics(context),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: top)),
                  if (header != null)
                    SliverPadding(
                      padding: side,
                      sliver: SliverToBoxAdapter(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _offset,
                          builder: (context, offset, child) => Opacity(
                            opacity: _headerOpacity(offset),
                            alwaysIncludeSemantics: true,
                            child: TickerMode(
                              enabled: _headerOpacity(offset) > 0,
                              child: Transform.scale(
                                scale: 1 + (-offset / 900).clamp(0.0, 0.1),
                                alignment: AlignmentDirectional.topStart,
                                child: child,
                              ),
                            ),
                          ),
                          child: KeyedSubtree(key: _headerKey, child: header),
                        ),
                      ),
                    ),
                  for (final sliver in widget.slivers)
                    SliverPadding(padding: side, sliver: sliver),
                  if (widget.padBottom)
                    SliverToBoxAdapter(
                      child: SizedBox(height: padding.bottom + 32),
                    ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: widget.solidBar ? 0 : null,
                child: ValueListenableBuilder<double>(
                  valueListenable: _offset,
                  builder: (context, offset, child) => Opacity(
                    opacity: (offset / 24).clamp(0.0, 1.0),
                    child: child,
                  ),
                  child: widget.solidBar
                      ? BackdropVeil.top(height: top, feather: 12)
                      : TopFade(height: top + 12),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: topInset,
                height: barHeight,
                child: BackdropGroup(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12 + inset),
                    child: NavigationToolbar(
                      centerMiddle: true,
                      middleSpacing: 8,
                      leading: Center(
                        widthFactor: 1,
                        child: widget.leading ??
                            GlassIconButton(
                              icon: AppIcons.back,
                              tooltip: '返回',
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                      ),
                      middle: ValueListenableBuilder<double>(
                        valueListenable: _offset,
                        builder: (context, offset, child) {
                          final t = _barTitle(offset);
                          return Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, 6 * (1 - t)),
                              child: child,
                            ),
                          );
                        },
                        child: Semantics(
                          header: !_hasHeader,
                          child: Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ),
                      trailing: widget.actions.isEmpty
                          ? const SizedBox(width: 44)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 8,
                              children: widget.actions,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 44dp round chrome-glass button used across top bars and drawers.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.grouped = true,
    this.tier = GlassTier.chrome,
    this.size = 44,
    this.iconSize = 22,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool grouped;
  final GlassTier tier;
  final double size;
  final double iconSize;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    Widget button = SizedBox.square(
      dimension: size,
      child: GlassSurface(
        tier: tier,
        circle: true,
        grouped: grouped,
        onTap: onPressed,
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: enabled ? scheme.onSurface : DshColors.of(context).textDisabled,
          ),
        ),
      ),
    );
    if (badge case final badge?) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(top: 4, right: 4, child: badge),
        ],
      );
    }
    if (tooltip case final tip?) button = Tooltip(message: tip, child: button);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: button,
    );
  }
}

class PageSectionLabel extends StatelessWidget {
  const PageSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
