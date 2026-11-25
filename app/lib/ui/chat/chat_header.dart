// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/settings_state.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/smooth_size.dart';
import '../common/status_dot.dart';
import '../engine/engine_screen.dart';
import '../theme/theme.dart';

/// Header status row: colored dot + concise human label.
class HeaderStatus {
  const HeaderStatus(this.tone, this.label);

  final StatusTone tone;
  final String label;
}

/// Floating chrome-glass chat top bar mirroring DSH Go's ChatHeader:
///
/// `(≡)  ( Title / ● Status · Workspace )    ( ✦ Mode ⌄ )  (+)`
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

  static double heightOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top + barHeightOf(context) + 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
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

/// Right-hand chrome-glass mode / model pill in [ChatHeader], mirroring DSH Go's ModelChip.
class ModelModeChip extends ConsumerWidget {
  const ModelModeChip({super.key, this.grouped = true});

  final bool grouped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final chat = ref.watch(
      chatProvider.select(
        (c) => (
          modes: c.transcript.modes,
          configs: c.transcript.configOptions,
          hasSession: c.sessionId != null,
        ),
      ),
    );
    final settings = ref.watch(settingsProvider);

    final modelOpt = chat.configs
        .where((c) => c.id == 'model' || c.category == 'model')
        .firstOrNull;
    final activeMode = chat.modes?.availableModes
        .where((m) => m.id == chat.modes!.currentModeId)
        .firstOrNull;

    String label;
    if (modelOpt != null && modelOpt.currentValue != null) {
      final raw = '${modelOpt.currentValue}';
      label = modelOpt.options
              .where((o) => o.value == raw)
              .firstOrNull
              ?.name ??
          raw;
    } else if (activeMode != null) {
      label = activeMode.name;
    } else {
      label = settings.authMode == LocalAuthMode.geminiApiKey
          ? 'Gemini API'
          : 'Antigravity';
    }
    if (label.length > 14) {
      label = '${label.substring(0, 13)}…';
    }

    return GlassSurface(
      tier: GlassTier.chrome,
      stadium: true,
      grouped: grouped,
      onTap: () => showModelModeSheet(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.providers, size: 15, color: colors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 13,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                AppIcons.expand,
                size: 16,
                color: DshColors.of(context).textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted bottom sheet for switching ACP modes, dynamic config options, and auth.
Future<void> showModelModeSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => const _ModelModeSheetBody(),
  );
}

class _ModelModeSheetBody extends ConsumerWidget {
  const _ModelModeSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final conn = ref.watch(activeConnectionProvider).value;
    final settings = ref.watch(settingsProvider);
    final modes = chat.transcript.modes;
    final configs = chat.transcript.configOptions;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader('模型与会话模式'),
            if (modes != null && modes.availableModes.isNotEmpty)
              SheetGroup(
                title: '会话模式（ACP Modes）',
                children: [
                  for (final m in modes.availableModes)
                    ListPageRow(
                      icon: AppIcons.modes,
                      title: m.name,
                      subtitle: m.description,
                      trailing: m.id == modes.currentModeId
                          ? Icon(
                              AppIcons.selected,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        ref.read(chatProvider.notifier).setMode(m.id);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            for (final opt in configs)
              if (opt.options.isNotEmpty)
                SheetGroup(
                  title: opt.name,
                  children: [
                    for (final choice in opt.options)
                      ListPageRow(
                        icon: AppIcons.modelItem,
                        title: choice.name,
                        subtitle: choice.description,
                        trailing: '${opt.currentValue}' == choice.value
                            ? Icon(
                                AppIcons.selected,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          ref
                              .read(chatProvider.notifier)
                              .setConfigOption(opt.id, choice.value);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
            SheetGroup(
              title: '认证与连接',
              children: [
                ListPageRow(
                  icon: AppIcons.apiKey,
                  title: settings.authMode == LocalAuthMode.geminiApiKey
                      ? 'Gemini API Key'
                      : 'Google 账号 OAuth',
                  subtitle: conn != null
                      ? '当前连接：${conn.label}${conn.initResult.agentInfo != null ? ' · ${conn.initResult.agentInfo!.name} ${conn.initResult.agentInfo!.version}' : ''}'
                      : '引擎未连接，前往本机引擎配置或启动',
                  trailing: const Icon(AppIcons.disclosure, size: 16),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EngineScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
