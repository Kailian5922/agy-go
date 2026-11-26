// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../common/smooth_size.dart';
import '../common/status_dot.dart';
import '../theme/theme.dart';

export 'model_sheet.dart'
    show ModelModeChip, formatModelName, showModelModeSheet, thoughtLevelLabel;

/// Header status row: colored dot + concise human label.
class HeaderStatus {
  const HeaderStatus(this.tone, this.label);

  final StatusTone tone;
  final String label;
}

/// Floating chrome-glass chat top bar mirroring DSH Go's ChatHeader:
///
/// `(≡)  ( Title / ● Status · Workspace )    ( ✦ Model · Effort ⌄ )  (+)`
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.title,
    required this.status,
    this.detail,
    this.trailing,
    this.onOpenDrawer,
    this.onTitleTap,
    this.onNewChat,
    this.scrolledUnder,
  });

  final String title;
  final HeaderStatus status;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onTitleTap;
  final VoidCallback? onNewChat;
  final ValueListenable<double>? scrolledUnder;

  static const barHeight = 56.0;

  static double pillHeightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(
      44.0,
      scaler.scale(15) * 1.3 + scaler.scale(11) * 1.25 + 8,
    );
  }

  static double barHeightOf(BuildContext context) =>
      math.max(barHeight, pillHeightOf(context) + 12);

  static double topInsetOf(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).top, 8.0);

  static double heightOf(BuildContext context) =>
      topInsetOf(context) + barHeightOf(context) + 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);
    final top = topInsetOf(context);
    final barH = barHeightOf(context);
    final pillH = pillHeightOf(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontSize: 15,
      height: 1.3,
    );
    final statusStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 11,
      height: 1.25,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (scrolledUnder != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: scrolledUnder!,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: TopFade(height: top + barH + 12),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, top, 12, 0),
          child: BackdropGroup(
            child: SizedBox(
              key: const ValueKey('chat-header-bar'),
              height: barH,
              child: Row(
                children: [
                  SizedBox.square(
                    key: const ValueKey('chat-menu'),
                    dimension: 44,
                    child: GlassSurface(
                      tier: GlassTier.chrome,
                      circle: true,
                      grouped: true,
                      onTap: onOpenDrawer,
                      child: Tooltip(
                        message: '对话与导航',
                        child: Center(
                          child: Icon(
                            AppIcons.menu,
                            size: 22,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GlassSurface(
                        tier: GlassTier.chrome,
                        stadium: true,
                        grouped: true,
                        onTap: onTitleTap,
                        child: ConstrainedBox(
                          key: const ValueKey('chat-title-pill'),
                          constraints: BoxConstraints(minHeight: pillH),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 4,
                            ),
                            child: SmoothSize(
                              duration: AppMotion.of(
                                context,
                                AppMotion.standard,
                              ),
                              curve: AppMotion.std,
                              alignment: Alignment.centerLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle,
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      StatusDot(tone: status.tone, size: 6),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          detail != null && detail!.isNotEmpty
                                              ? '${status.label} · $detail'
                                              : status.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: statusStyle?.copyWith(
                                            color: status.tone == StatusTone.warn
                                                ? dsh.warning
                                                : status.tone == StatusTone.error
                                                ? dsh.danger
                                                : dsh.textTertiary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (trailing case final chip?) ...[
                    const SizedBox(width: 8),
                    chip,
                  ],
                  SmoothSize(
                    duration: AppMotion.of(context, AppMotion.quick),
                    child: onNewChat == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: SizedBox.square(
                              key: const ValueKey('chat-new-chat'),
                              dimension: 44,
                              child: GlassSurface(
                                tier: GlassTier.chrome,
                                circle: true,
                                grouped: true,
                                onTap: onNewChat,
                                child: Tooltip(
                                  message: '新对话',
                                  child: Center(
                                    child: Icon(
                                      AppIcons.newChat,
                                      size: 22,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
