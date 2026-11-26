// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/settings_state.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/sheet_navigator.dart';
import '../features/agy_extensions_pages.dart';
import '../theme/theme.dart';

/// Shared risk-confirmation dialog before enabling YOLO / unrestricted permissions.
Future<bool> confirmHighRiskAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = '确认开启',
}) async {
  final dsh = DshColors.of(context);
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      icon: Icon(AppIcons.riskWarning, color: dsh.danger, size: 28),
      title: Text(title),
      content: Text(
        body,
        style: Theme.of(dialog).textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: dsh.danger,
            foregroundColor: Theme.of(dialog).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Floating compact status pill above [ComposerBar] showing active non-standard
/// execution mode or elevated tool permission (mirroring DSH Go's PermissionPill).
class PermissionStatusPill extends ConsumerWidget {
  const PermissionStatusPill({super.key, this.inline = false});

  /// When true, renders only the stadium pill without outer full-width padding
  /// so it can share one horizontal row with [ActivityStrip].
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final chat = ref.watch(
      chatProvider.select(
        (c) => (
          mode: c.sessionAgentMode,
          perm: c.sessionToolPermission,
          allowAll: c.allowAllForSession,
          extraDirs: c.additionalDirectories.length,
        ),
      ),
    );
    final effectiveMode = chat.mode ?? settings.agentMode;
    final effectivePerm = chat.perm ?? settings.toolPermission;

    final isYolo = effectivePerm == AgyToolPermission.alwaysProceed;
    final isAllowAllChat = chat.allowAll && !isYolo;
    final isPlan = effectiveMode == AgyAgentMode.plan;
    final isStrict = effectivePerm == AgyToolPermission.strict;
    final isSandbox = effectivePerm == AgyToolPermission.proceedInSandbox;

    if (!isYolo &&
        !isAllowAllChat &&
        !isPlan &&
        !isStrict &&
        !isSandbox &&
        chat.extraDirs == 0) {
      return const SizedBox.shrink();
    }

    final dsh = DshColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    late final IconData icon;
    late final String label;
    late final Color tint;
    VoidCallback? quickReset;

    if (isPlan) {
      icon = AppIcons.planMode;
      label = '计划模式';
      tint = scheme.primary;
      quickReset = () => unawaited(
        ref.read(chatProvider.notifier).setExecutionMode(AgyAgentMode.standard),
      );
    } else if (isYolo) {
      icon = AppIcons.permissionRisky;
      label = '完全放行';
      tint = dsh.danger;
    } else if (isAllowAllChat) {
      icon = AppIcons.autoApprove;
      label = '本对话放行';
      tint = dsh.warning;
      quickReset = () =>
          ref.read(chatProvider.notifier).allowAllForCurrentSession(false);
    } else if (isStrict) {
      icon = AppIcons.safeMode;
      label = '严格确认';
      tint = scheme.onSurfaceVariant;
    } else if (isSandbox) {
      icon = AppIcons.verified;
      label = '沙箱放行';
      tint = dsh.success;
    } else {
      icon = AppIcons.folder;
      label = '+${chat.extraDirs} 目录';
      tint = scheme.primary;
    }

    final pill = Pressable(
      child: GlassSurface(
        tier: GlassTier.chrome,
        stadium: true,
        style: DshSurfaces.of(context).chrome.copyWith(
          hairline: tint.withValues(alpha: 0.4),
        ),
        onTap: () => unawaited(showApprovalModeSheet(context, ref)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!inline &&
                  chat.extraDirs > 0 &&
                  (isYolo || isAllowAllChat || isPlan || isStrict || isSandbox)) ...[
                const SizedBox(width: 5),
                Text(
                  '· +${chat.extraDirs} 目录',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: dsh.textTertiary),
                ),
              ],
              const SizedBox(width: 3),
              if (quickReset != null)
                GestureDetector(
                  onTap: quickReset,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: Icon(AppIcons.close, size: 13, color: tint),
                  ),
                )
              else
                Icon(AppIcons.disclosure, size: 13, color: tint),
            ],
          ),
        ),
      ),
    );

    if (inline) return pill;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.floatInset,
        0,
        AppSpace.floatInset,
        6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpace.floatingWidth),
          child: Align(alignment: Alignment.centerLeft, child: pill),
        ),
      ),
    );
  }
}

/// Opens the official Antigravity Permission Preset picker bottom sheet.
Future<void> showApprovalModeSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => const ApprovalModeSheetBody(),
  );
}

/// Official Antigravity 4-tier permission picker (`strict` / `request-review` /
/// `proceed-in-sandbox` / `always-proceed`) + a simple `/plan` read-only toggle.
class ApprovalModeSheetBody extends ConsumerWidget {
  const ApprovalModeSheetBody({super.key, this.onCloseSheet});

  final VoidCallback? onCloseSheet;

  IconData _permIcon(AgyToolPermission perm) => switch (perm) {
    AgyToolPermission.strict => AppIcons.safeMode,
    AgyToolPermission.requestReview => AppIcons.permissions,
    AgyToolPermission.proceedInSandbox => AppIcons.verified,
    AgyToolPermission.alwaysProceed => AppIcons.permissionRisky,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final chat = ref.watch(chatProvider);
    final activeMode = chat.sessionAgentMode ?? settings.agentMode;
    final activePerm = chat.sessionToolPermission ?? settings.toolPermission;
    final isPlan = activeMode == AgyAgentMode.plan;
    final dsh = DshColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final insideNested = SheetNavigator.maybeOf(context)?.canPop ?? false;

    void doneOrPop() {
      if (insideNested) {
        SheetNavigator.of(context).pop();
      } else {
        onCloseSheet?.call();
      }
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader('权限层级'),
            SheetGroup(
              title: 'Antigravity 官方权限预设',
              children: [
                for (final perm in AgyToolPermission.values)
                  ListPageRow(
                    icon: _permIcon(perm),
                    iconColor: perm.isHighRisk
                        ? dsh.danger
                        : (perm == activePerm ? scheme.primary : null),
                    title: perm.label,
                    subtitle: perm.description,
                    subtitleMaxLines: 2,
                    danger: perm.isHighRisk && perm == activePerm,
                    trailing: perm == activePerm
                        ? Icon(
                            AppIcons.radioOn,
                            size: 20,
                            color: perm.isHighRisk ? dsh.danger : scheme.primary,
                          )
                        : Icon(
                            AppIcons.radioOff,
                            size: 20,
                            color: dsh.textTertiary,
                          ),
                    chevron: false,
                    onTap: () async {
                      if (perm.isHighRisk && activePerm != perm) {
                        final confirmed = await confirmHighRiskAction(
                          context,
                          title: '开启「完全放行」？',
                          body:
                              '开启后 Antigravity CLI 将跳过命令执行、文件修改与工具调用的逐次确认（等同 --dangerously-skip-permissions）。仅建议在受控工作区内使用；手机操控的支付安全闸门仍独立拦截。',
                          confirmLabel: '确认放行',
                        );
                        if (!confirmed) return;
                      }
                      await ref
                          .read(chatProvider.notifier)
                          .setSessionToolPermission(perm);
                      if (context.mounted) {
                        showBriefNotice(context, '权限已切换为「${perm.label}」');
                      }
                    },
                  ),
              ],
            ),
            SheetGroup(
              title: '快捷选项',
              children: [
                ListPageRow(
                  icon: AppIcons.planMode,
                  iconColor: isPlan ? scheme.primary : null,
                  title: '计划模式（/plan）',
                  subtitle: '只读调研并先输出方案，经你同意后再修改代码',
                  trailing: Switch.adaptive(
                    value: isPlan,
                    onChanged: (v) async {
                      await ref
                          .read(chatProvider.notifier)
                          .setExecutionMode(
                            v ? AgyAgentMode.plan : AgyAgentMode.standard,
                          );
                    },
                  ),
                  chevron: false,
                  onTap: () async {
                    await ref
                        .read(chatProvider.notifier)
                        .setExecutionMode(
                          isPlan ? AgyAgentMode.standard : AgyAgentMode.plan,
                        );
                  },
                ),
                ListPageRow(
                  icon: AppIcons.setDefault,
                  title: '将「${activePerm.label}」设为全局默认',
                  subtitle: '同步写入 ~/.gemini/antigravity-cli/settings.json',
                  chevron: false,
                  onTap: () async {
                    if (activePerm.isHighRisk &&
                        settings.toolPermission !=
                            AgyToolPermission.alwaysProceed) {
                      final confirmed = await confirmHighRiskAction(
                        context,
                        title: '将「完全放行」设为全局默认？',
                        body:
                            '这会写入 settings.json，之后每次新建会话与重启引擎都会自动放行工具调用。',
                        confirmLabel: '设为默认',
                      );
                      if (!confirmed) return;
                    }
                    await ref
                        .read(settingsProvider.notifier)
                        .setToolPermission(activePerm);
                    if (context.mounted) {
                      showBriefNotice(context, '已保存为新对话默认权限');
                      doneOrPop();
                    }
                  },
                ),
                ListPageRow(
                  icon: AppIcons.configure,
                  title: '高级规则（allow / ask / deny）',
                  subtitle: '按命令、路径与 MCP 服务器精细配置 settings.json',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AgyEngineParamsPage(),
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
