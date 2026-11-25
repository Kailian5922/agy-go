// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import 'app_sheet.dart' show groupTitleStyle;
import 'overview_card.dart' show OverviewChevron;

/// Standard list-page row mirroring DSH Go's ListPageRow geometry.
class ListPageRow extends StatelessWidget {
  const ListPageRow({
    super.key,
    this.icon,
    this.leading,
    this.leadingWidth = glyphSlot,
    required this.title,
    this.titleStyle,
    this.titleNote,
    this.titleMaxLines = 1,
    this.subtitle,
    this.subtitleColor,
    this.subtitleMaxLines = 1,
    this.badge,
    this.value,
    this.meta,
    this.metaColor,
    this.trailing,
    this.trailingSemanticLabel,
    this.onTap,
    this.onLongPress,
    this.chevron,
    this.danger = false,
    this.iconColor,
  });

  final IconData? icon;
  final Widget? leading;
  final double leadingWidth;
  final String title;
  final TextStyle? titleStyle;
  final String? titleNote;
  final int titleMaxLines;
  final String? subtitle;
  final Color? subtitleColor;
  final int subtitleMaxLines;
  final Widget? badge;
  final String? value;
  final String? meta;
  final Color? metaColor;
  final Widget? trailing;
  final String? trailingSemanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool? chevron;
  final bool danger;
  final Color? iconColor;

  static const glyphSlot = 32.0;
  static const gap = 12.0;
  static const horizontal = 16.0;
  static const trailingPad = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DshColors.of(context);
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final two = subtitle != null && subtitle!.isNotEmpty;
    final glyph =
        leading ??
        (icon == null
            ? null
            : Icon(
                icon,
                size: 20,
                color: iconColor ??
                    (danger ? colors.danger : scheme.onSurfaceVariant),
              ));
    final resolvedTitleStyle =
        titleStyle ??
        theme.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          height: 1.4,
          color: danger ? colors.danger : scheme.onSurface,
        );
    final note = titleNote;
    final titleText = note == null || note.isEmpty
        ? Text(
            title,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: resolvedTitleStyle,
          )
        : Text.rich(
            TextSpan(
              text: title,
              children: [
                TextSpan(
                  text: ' · $note',
                  style: TextStyle(color: colors.textTertiary),
                ),
              ],
            ),
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: resolvedTitleStyle,
          );
    Widget row(double maxValueWidth) => InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: two ? 64 : 52),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            10,
            showChevron || trailing is Switch ? trailingPad : horizontal,
            10,
          ),
          child: Row(
            children: [
              if (glyph != null) ...[
                SizedBox(
                  width: leadingWidth,
                  child: Center(child: glyph),
                ),
                const SizedBox(width: gap),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badge case final badge?)
                      Row(
                        children: [
                          Flexible(child: titleText),
                          const SizedBox(width: 8),
                          badge,
                        ],
                      )
                    else
                      titleText,
                    if (two) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: subtitleColor ?? colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value case final value? when value.isNotEmpty) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxValueWidth),
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppType.tabular(
                      theme.textTheme.bodyMedium!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
              if (meta case final meta? when meta.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  meta,
                  style: AppType.tabular(
                    theme.textTheme.bodySmall!.copyWith(
                      color: metaColor ?? colors.textTertiary,
                    ),
                  ),
                ),
              ],
              if (trailing case final trailing?) ...[
                const SizedBox(width: 12),
                SwitchTheme(
                  data: SwitchTheme.of(context).copyWith(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: trailingSemanticLabel == null
                      ? trailing
                      : Semantics(label: trailingSemanticLabel, child: trailing),
                ),
              ],
              if (showChevron) ...[
                const SizedBox(width: 4),
                const OverviewChevron(),
              ],
            ],
          ),
        ),
      ),
    );
    if (value == null || value!.isEmpty) return row(double.infinity);
    return LayoutBuilder(builder: (context, c) => row(c.maxWidth * 0.45));
  }
}

/// Card container of ListPageRows: card-tier glass, radius 20, zero dividers.
class ListPageCard extends StatelessWidget {
  const ListPageCard({
    super.key,
    required this.children,
    this.title,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 0),
  });

  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Semantics(
                header: true,
                child: Text(title, style: groupTitleStyle(context)),
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
