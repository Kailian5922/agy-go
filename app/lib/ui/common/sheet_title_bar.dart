// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import 'app_sheet.dart' show groupTitleStyle;
import 'sheet_dismissal.dart';
import 'sheet_navigator.dart';

class SheetTitleBar extends StatelessWidget {
  const SheetTitleBar(
    this.title, {
    super.key,
    this.onClose,
    this.actions = const [],
    this.maxLines = 1,
  });

  final String title;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final int? maxLines;

  static const inset = 20.0;
  static const keySize = 32.0;
  static const _hit = 44.0;
  static const _slack = (_hit - keySize) / 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = SheetNavigator.maybeOf(context);
    final canGoBack = sheet?.canPop ?? false;
    final close = SheetDismissScope.of(context) == SheetDismissal.button;
    final trailing = close || actions.isNotEmpty;
    final style = theme.textTheme.titleLarge;
    final wraps = maxLines != 1;
    var titleTop = 0.0;
    var keyTop = 0.0;
    if (wraps) {
      final line = _lineHeight(context, style);
      titleTop = ((_hit - line) / 2).clamp(0.0, double.infinity);
      keyTop = ((line - _hit) / 2).clamp(0.0, double.infinity);
    }
    Widget key(Widget child) => child.withTopInset(keyTop);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        canGoBack ? inset - _slack : inset,
        0,
        trailing ? inset - _slack : inset,
        8,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _hit),
        child: Row(
          crossAxisAlignment:
              wraps ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            if (canGoBack) ...[
              key(
                SheetIconButton(
                  icon: AppIcons.back,
                  tooltip: '返回',
                  onPressed: sheet!.pop,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: maxLines,
                  overflow: wraps ? null : TextOverflow.ellipsis,
                  style: style,
                ),
              ).withTopInset(titleTop),
            ),
            if (trailing) const SizedBox(width: 8),
            for (final action in actions) key(action),
            if (close)
              key(
                SheetIconButton(
                  icon: AppIcons.close,
                  tooltip: '关闭',
                  onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static double _lineHeight(BuildContext context, TextStyle? style) {
    final base = DefaultTextStyle.of(context);
    final painter = TextPainter(
      text: TextSpan(text: '国A', style: base.style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: base.textHeightBehavior,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

extension on Widget {
  Widget withTopInset(double top) => top == 0
      ? this
      : Padding(
          padding: EdgeInsets.only(top: top),
          child: this,
        );
}

class SheetIconButton extends StatelessWidget {
  const SheetIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        onTap: onPressed,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.onSurface.withValues(alpha: dark ? 0.10 : 0.06),
                  shape: const CircleBorder(),
                ),
                child: SizedBox.square(
                  dimension: SheetTitleBar.keySize,
                  child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SheetSectionLabel extends StatelessWidget {
  const SheetSectionLabel(
    this.text, {
    super.key,
    this.inset = SheetTitleBar.inset,
  });

  final String text;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(inset + 8, 4, inset + 8, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: groupTitleStyle(context),
        ),
      ),
    );
  }
}
