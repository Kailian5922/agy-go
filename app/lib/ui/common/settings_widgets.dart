// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import 'app_sheet.dart';
import 'list_page_row.dart' show ListPageRow;
import 'overview_card.dart' show OverviewChevron;
import 'segmented_pill.dart';

export 'segmented_pill.dart' show PillSegment, SegmentedPill;

const kSettingsGroupMargin = EdgeInsets.fromLTRB(16, 0, 16, 24);

abstract final class SettingsMetrics {
  static const inset = 16.0;
  static const trailingPad = ListPageRow.trailingPad;
  static const icon = 32.0;
  static const iconGlyph = 18.0;
  static const lineGlyph = 20.0;
  static const iconGap = 12.0;
  static const textStart = inset + icon + iconGap;
  static const rowHeight = 52.0;
  static const rowHeightTwoLine = 64.0;
}

TextStyle? settingsTitleStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.4);

class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key, this.tint = 0, this.danger = false});

  final IconData icon;
  final int tint;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = DshColors.of(context);
    final bg = danger
        ? colors.dangerContainer
        : colors.identity[tint % colors.identity.length];
    final fg = danger
        ? colors.onDangerContainer
        : colors.onIdentity[tint % colors.onIdentity.length];
    return DecoratedBox(
      decoration: ShapeDecoration(color: bg, shape: const CircleBorder()),
      child: SizedBox.square(
        dimension: SettingsMetrics.icon,
        child: Icon(icon, size: SettingsMetrics.iconGlyph, color: fg),
      ),
    );
  }
}

class SettingsLineIcon extends StatelessWidget {
  const SettingsLineIcon(this.icon, {super.key, this.danger = false});

  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = DshColors.of(context);
    return SizedBox.square(
      dimension: SettingsMetrics.icon,
      child: Icon(
        icon,
        size: SettingsMetrics.lineGlyph,
        color: danger
            ? colors.danger
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.tint = 0,
    this.danger = false,
    this.chevron,
    this.tinted = true,
    this.titleMaxLines,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int tint;
  final bool danger;
  final bool? chevron;
  final bool tinted;
  final int? titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DshColors.of(context);
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final endsInGlyph = showChevron || trailing != null;
    final icon = this.icon;
    return InkWell(
      onTap: onTap,
      splashFactory: rowSplash(context),
      highlightColor: scheme.onSurface.withValues(alpha: 0.05),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: subtitle == null
              ? SettingsMetrics.rowHeight
              : SettingsMetrics.rowHeightTwoLine,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            SettingsMetrics.inset,
            6,
            endsInGlyph ? SettingsMetrics.trailingPad : SettingsMetrics.inset,
            6,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                tinted
                    ? SettingsIcon(icon, tint: tint, danger: danger)
                    : SettingsLineIcon(icon, danger: danger),
                const SizedBox(width: SettingsMetrics.iconGap),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: titleMaxLines,
                      overflow: titleMaxLines == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: settingsTitleStyle(context)?.copyWith(
                        color: danger ? colors.danger : scheme.onSurface,
                      ),
                    ),
                    if (subtitle case final sub?) ...[
                      const SizedBox(height: 1),
                      Text(
                        sub,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value case final value?) ...[
                const SizedBox(width: 12),
                DefaultTextStyle.merge(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  child: value,
                ),
              ],
              if (trailing case final trailing?) ...[
                const SizedBox(width: 8),
                SwitchTheme(
                  data: SwitchTheme.of(context).copyWith(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: trailing,
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
  }
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.tint = 0,
    this.tinted = true,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final int tint;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final fluid = AppMotion.fluid(context);
    void change(bool next) {
      if (fluid) HapticFeedback.selectionClick();
      onChanged!(next);
    }

    return MergeSemantics(
      child: SettingsTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        tint: tint,
        tinted: tinted,
        onTap: onChanged == null ? null : () => change(!value),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged == null ? null : change,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SettingsMetrics.rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SettingsMetrics.inset,
          vertical: 6,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: settingsTitleStyle(
                  context,
                )?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: mono
                      ? AppType.monoLabel(
                          color: scheme.onSurfaceVariant,
                        ).copyWith(height: 1.6)
                      : AppType.tabular(
                          theme.textTheme.bodyMedium!.copyWith(
                            color: scheme.onSurfaceVariant,
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

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    required this.children,
    this.footer,
    this.margin = kSettingsGroupMargin,
  });

  final String? title;
  final List<Widget> children;
  final Widget? footer;
  final EdgeInsetsGeometry margin;

  static TextStyle? titleStyle(BuildContext context) =>
      groupTitleStyle(context);

  static const footerGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                child: Text(title, style: titleStyle(context)),
              ),
            ),
          SheetGroup(margin: EdgeInsets.zero, children: children),
          if (footer case final footer?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, footerGap, 8, 0),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DshColors.of(context).textTertiary,
                  height: 1.55,
                ),
                child: footer,
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsSegmentTile<T> extends StatelessWidget {
  const SettingsSegmentTile({
    super.key,
    this.icon,
    this.tint = 0,
    required this.title,
    this.subtitle,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.tinted = true,
  });

  final IconData? icon;
  final int tint;
  final String title;
  final String? subtitle;
  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final titleStyle = settingsTitleStyle(context);
    final icon = this.icon;
    const iconWidth = SettingsMetrics.icon + SettingsMetrics.iconGap;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SettingsMetrics.inset,
        8,
        SettingsMetrics.inset,
        8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = SegmentedPill.naturalWidth(context, [
            for (final s in segments) s.label,
          ]);
          final titlePainter = TextPainter(
            text: TextSpan(text: title, style: titleStyle),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();
          final titleWidth = titlePainter.width;
          titlePainter.dispose();
          final lead = icon == null ? 0.0 : iconWidth;
          final inline = lead + titleWidth + 16 + pillWidth <= constraints.maxWidth;
          final heading = [
            if (icon != null) ...[
              tinted
                  ? SettingsIcon(icon, tint: tint)
                  : SettingsLineIcon(icon),
              const SizedBox(width: SettingsMetrics.iconGap),
            ],
          ];
          final pill = SegmentedPill<T>(
            segments: segments,
            selected: selected,
            onChanged: onChanged,
            expand: !inline,
          );
          final note = switch (subtitle) {
            final sub? => Padding(
              padding: EdgeInsets.only(left: lead, top: 6, bottom: 2),
              child: Text(
                sub,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DshColors.of(context).textTertiary,
                ),
              ),
            ),
            null => null,
          };
          if (inline) {
            final row = ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SettingsMetrics.rowHeight - 16,
              ),
              child: Row(
                children: [
                  ...heading,
                  Text(title, style: titleStyle),
                  const Spacer(),
                  pill,
                ],
              ),
            );
            if (note == null) return row;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [row, note],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: SettingsMetrics.icon,
                ),
                child: Row(
                  children: [
                    ...heading,
                    Expanded(child: Text(title, style: titleStyle)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(padding: EdgeInsets.only(left: lead), child: pill),
              const SizedBox(height: 4),
              ?note,
            ],
          );
        },
      ),
    );
  }
}
