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
  const PermissionStatusPill({super.key});

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
    final isNonStandardMode = effectiveMode != AgyAgentMode.standard;
    final isStrict = effectivePerm == AgyToolPermission.strict;
    final isSandbox = effectivePerm == AgyToolPermission.proceedInSandbox;

    if (!isYolo &&
        !isAllowAllChat &&
        !isNonStandardMode &&
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

    if (isYolo) {
      icon = AppIcons.permissionRisky;
      label = '完全放行 (YOLO)';
      tint = dsh.danger;
    } else if (isAllowAllChat) {
      icon = AppIcons.autoApprove;
      label = '本对话已自动放行';
      tint = dsh.warning;
      quickReset = () =>
          ref.read(chatProvider.notifier).allowAllForCurrentSession(false);
    } else if (isPlan) {
      icon = AppIcons.planMode;
      label = '计划模式 · 只读规划';
      tint = scheme.primary;
      quickReset = () => unawaited(
        ref.read(chatProvider.notifier).setExecutionMode(AgyAgentMode.standard),
      );
    } else if (effectiveMode == AgyAgentMode.auto) {
      icon = AppIcons.running;
      label = '智能自动模式';
      tint = dsh.warning;
    } else if (effectiveMode == AgyAgentMode.acceptEdits) {
      icon = AppIcons.edit;
      label = '自动改写模式';
      tint = scheme.primary;
    } else if (isStrict) {
      icon = AppIcons.safeMode;
      label = '严格逐次审批';
      tint = scheme.onSurfaceVariant;
    } else if (isSandbox) {
      icon = AppIcons.verified;
      label = '沙箱内放行';
      tint = dsh.success;
    } else {
      icon = AppIcons.folder;
      label = '额外挂载 ${chat.extraDirs} 个目录';
      tint = scheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.floatInset, 0, AppSpace.floatInset, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpace.floatingWidth),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              child: GlassSurface(
                tier: GlassTier.chrome,
                stadium: true,
                style: DshSurfaces.of(context).chrome.copyWith(
                  hairline: tint.withValues(alpha: 0.4),
                ),
                onTap: () => unawaited(showApprovalModeSheet(context, ref)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 5, 8, 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: tint),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (chat.extraDirs > 0 &&
                          (isYolo ||
                              isAllowAllChat ||
                              isNonStandardMode ||
                              isStrict ||
                              isSandbox)) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· +${chat.extraDirs} 目录',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: dsh.textTertiary),
                        ),
                      ],
                      const SizedBox(width: 4),
                      if (quickReset != null)
                        GestureDetector(
                          onTap: quickReset,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(AppIcons.close, size: 13, color: tint),
                          ),
                        )
                      else
                        Icon(AppIcons.disclosure, size: 13, color: tint),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the Antigravity CLI Approval & Execution Mode bottom sheet.
Future<void> showApprovalModeSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => const ApprovalModeSheetBody(),
  );
}

/// Body of the Approval & Execution Mode picker.
///
/// Works both standalone inside [showApprovalModeSheet] and pushed inline inside
/// a [SheetNavigator] (e.g., from the `+` composer panel).
class ApprovalModeSheetBody extends ConsumerWidget {
  const ApprovalModeSheetBody({super.key, this.onCloseSheet});

  final VoidCallback? onCloseSheet;

  IconData _modeIcon(AgyAgentMode mode) => switch (mode) {
    AgyAgentMode.standard => AppIcons.permissions,
    AgyAgentMode.acceptEdits => AppIcons.edit,
    AgyAgentMode.auto => AppIcons.running,
    AgyAgentMode.plan => AppIcons.planMode,
  };

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
            const SheetHeader('审批与执行模式'),
            SheetGroup(
              title: 'Antigravity 执行模式 (agentMode)',
              children: [
                for (final mode in AgyAgentMode.values)
                  ListPageRow(
                    icon: _modeIcon(mode),
                    iconColor: mode == activeMode ? scheme.primary : null,
                    title: mode.label,
                    subtitle: mode.description,
                    subtitleMaxLines: 2,
                    trailing: mode == activeMode
                        ? Icon(
                            AppIcons.radioOn,
                            size: 20,
                            color: scheme.primary,
                          )
                        : Icon(
                            AppIcons.radioOff,
                            size: 20,
                            color: dsh.textTertiary,
                          ),
                    chevron: false,
                    onTap: () async {
                      await ref
                          .read(chatProvider.notifier)
                          .setExecutionMode(mode);
                      if (context.mounted) {
                        showBriefNotice(context, '本对话已切换为「${mode.label}」');
                      }
                    },
                  ),
              ],
            ),
            SheetGroup(
              title: '工具权限预设 (toolPermission)',
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
                          title: '开启「完全放行 (YOLO)」？',
                          body:
                              '开启后 Antigravity CLI 将跳过命令执行、文件修改与工具调用的逐次确认（等同 --dangerously-skip-permissions）。仅建议在受控测试工作区内开启；手机操控的支付/银行安全闸门仍会独立拦截。',
                          confirmLabel: '确认放行',
                        );
                        if (!confirmed) return;
                      }
                      await ref
                          .read(chatProvider.notifier)
                          .setSessionToolPermission(perm);
                      if (context.mounted) {
                        showBriefNotice(context, '工具权限已设为「${perm.label}」');
                      }
                    },
                  ),
              ],
            ),
            SheetGroup(
              title: '默认与细粒度规则',
              children: [
                ListPageRow(
                  icon: AppIcons.setDefault,
                  title: '将当前组合设为所有新对话默认',
                  subtitle:
                      '同步写入 settings.json（${activeMode.label} · ${activePerm.label}）',
                  chevron: false,
                  onTap: () async {
                    if (activePerm.isHighRisk &&
                        settings.toolPermission !=
                            AgyToolPermission.alwaysProceed) {
                      final confirmed = await confirmHighRiskAction(
                        context,
                        title: '将「完全放行 (YOLO)」设为全局默认？',
                        body:
                            '这会写入 ~/.gemini/antigravity-cli/settings.json，之后每次新建会话与重启本机引擎都会自动放行工具调用。',
                        confirmLabel: '设为默认',
                      );
                      if (!confirmed) return;
                    }
                    await ref
                        .read(settingsProvider.notifier)
                        .setAgentMode(activeMode);
                    await ref
                        .read(settingsProvider.notifier)
                        .setToolPermission(activePerm);
                    if (context.mounted) {
                      showBriefNotice(context, '已保存为新对话默认策略');
                      doneOrPop();
                    }
                  },
                ),
                ListPageRow(
                  icon: AppIcons.configure,
                  title: '配置 allow / ask / deny 规则与 settings.json',
                  subtitle: '按命令、路径与 MCP 服务器精细放行或禁止',
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
