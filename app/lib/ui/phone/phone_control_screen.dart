// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/pet_state.dart';
import '../../state/phone_state.dart';
import '../../state/runtime_state.dart';
import '../common/brief_notice.dart';
import '../common/overview_card.dart';
import '../common/settings_widgets.dart';
import '../common/status_dot.dart';
import '../pet/starling_pet.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

/// Inline SafetyGate approval card matching DSH Go's ApprovalCard visual hierarchy.
class PhoneApprovalCard extends StatelessWidget {
  const PhoneApprovalCard({
    super.key,
    required this.prompt,
    required this.onApprove,
    required this.onDeny,
  });

  final PhoneApprovalPrompt prompt;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final surfaces = DshSurfaces.of(context);
    final accent = prompt.isHighRisk ? dsh.danger : dsh.warning;

    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: AppShape.radiusLg,
      style: surfaces.card.copyWith(
        hairline: accent.withValues(alpha: 0.6),
        hairlineWidth: 1.0,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  prompt.isHighRisk
                      ? AppIcons.securityWarning
                      : AppIcons.phoneControl,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prompt.isHighRisk ? '高风险手机操作确认' : '手机操控确认',
                    style: theme.textTheme.titleSmall?.copyWith(color: accent),
                  ),
                ),
                Text(
                  prompt.tool,
                  style: AppType.monoLabel(color: dsh.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              prompt.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              prompt.reason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: dsh.textTertiary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: dsh.danger,
                      side: BorderSide(color: dsh.danger.withValues(alpha: 0.5)),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onDeny();
                    },
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onApprove();
                    },
                    child: const Text('允许执行'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PhoneControlScreen extends ConsumerWidget {
  const PhoneControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(phoneControlProvider);
    final pet = ref.watch(petSettingsProvider);
    final runtime = ref.watch(localRuntimeProvider).status;
    final hasActiveChat = ref.watch(
      chatProvider.select((c) => c.hasAnyRunningSession),
    );
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);

    final fullyReady = phone.enabled && phone.accessibilityConnected;

    final String overviewTitle;
    if (fullyReady && phone.mcpClientConnected) {
      overviewTitle = '手机操控已完全就绪';
    } else if (fullyReady) {
      overviewTitle = '手机操控已就绪';
    } else if (phone.enabled && phone.accessibilityStuckInSettings) {
      overviewTitle = '无障碍服务未绑定，请重开一次';
    } else if (phone.enabled && phone.likelyBlockedByRestrictedSettings) {
      overviewTitle = '需先解除「受限设置」再开无障碍';
    } else if (phone.enabled) {
      overviewTitle = '还差一步：开启无障碍服务';
    } else {
      overviewTitle = '手机操控未开启';
    }

    final String overviewSubtitle;
    if (phone.mcpUrl != null) {
      final clientPart = phone.mcpClientConnected
          ? 'agy 已接入'
          : (runtime.isRunning ? '已写入 mcp_config.json · 等待新会话或重载引擎接入' : '已写入 mcp_config.json');
      overviewSubtitle = '${phone.mcpUrl}（$clientPart）';
    } else {
      overviewSubtitle = '开启后将自动写入 ~/.gemini/config/mcp_config.json 并挂载给本机 agy';
    }

    final String a11yStatusText;
    if (phone.accessibilityConnected) {
      a11yStatusText = '无障碍服务：已连接';
    } else if (phone.accessibilityStuckInSettings) {
      a11yStatusText = '无障碍服务：系统已勾选但挂起（请关闭再重开）';
    } else if (phone.likelyBlockedByRestrictedSettings) {
      a11yStatusText = '无障碍服务：未开启（可能受 Android 受限设置拦截）';
    } else {
      a11yStatusText = '无障碍服务：未开启';
    }

    final selfCheck = phone.lastSelfCheck;

    return AppPage.list(
      title: '手机操控',
      subtitle: const Text('通过无障碍服务与本机 Streamable HTTP MCP 让 agy 安全操作手机'),
      actions: [
        GlassIconButton(
          icon: AppIcons.refresh,
          tooltip: '刷新状态',
          onPressed: () => ref.read(phoneControlProvider.notifier).refresh(),
        ),
      ],
      children: [
        OverviewCard(
          leading: OverviewGlyph(
            AppIcons.phoneControl,
            tint: fullyReady ? 4 : 3,
          ),
          title: Text(overviewTitle),
          subtitle: Text(overviewSubtitle),
          footer: OverviewFooter(
            tone: fullyReady
                ? StatusTone.ok
                : phone.enabled
                ? StatusTone.warn
                : StatusTone.idle,
            text: a11yStatusText,
          ),
        ),
        if (phone.pendingApprovals.isNotEmpty)
          for (final prompt in phone.pendingApprovals)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PhoneApprovalCard(
                prompt: prompt,
                onApprove: () => ref
                    .read(phoneControlProvider.notifier)
                    .resolveApproval(prompt.id, approved: true),
                onDeny: () => ref
                    .read(phoneControlProvider.notifier)
                    .resolveApproval(prompt.id, approved: false),
              ),
            ),
        SettingsSection(
          title: '开关与无障碍连接',
          footer: phone.likelyBlockedByRestrictedSettings
              ? const Text(
                  'Android 13+ 侧载安装包若在无障碍页看到灰色开关：先点一次灰色开关触发系统提示，再点上方「打开应用信息」→ 右上角 ⋮ → 允许受限设置，即可开启。',
                )
              : null,
          children: [
            SettingsSwitchTile(
              icon: AppIcons.phoneControl,
              tint: 3,
              title: '启用 MCP 手机操控',
              subtitle: '启动常驻本机 HTTP MCP（写入 ~/.gemini/config/mcp_config.json）',
              value: phone.enabled,
              onChanged: (v) async {
                await ref.read(phoneControlProvider.notifier).setEnabled(v);
                if (!context.mounted) return;
                if (v && runtime.isRunning && hasActiveChat) {
                  showBriefNotice(context, '已启用；当前对话完成后点击「重载本机引擎」即可接入');
                }
              },
            ),
            SettingsTile(
              icon: AppIcons.accessibility,
              tint: 4,
              title: '系统无障碍设置',
              subtitle: phone.accessibilityStuckInSettings
                  ? '系统已启用但未绑定，请关闭后再重新打开「AGY Go 手机操控」'
                  : '在已下载的应用中找到「AGY Go 手机操控」并开启',
              value: Text(
                phone.accessibilityConnected
                    ? '已连接'
                    : phone.accessibilityStuckInSettings
                    ? '需重开'
                    : '去开启',
                style: TextStyle(
                  color: phone.accessibilityConnected
                      ? dsh.success
                      : dsh.warning,
                ),
              ),
              onTap: () => ref
                  .read(phoneControlProvider.notifier)
                  .openAccessibilitySettings(),
            ),
            if (!phone.accessibilityConnected)
              SettingsTile(
                icon: AppIcons.securityWarning,
                tint: 3,
                title: '打开应用信息（解除受限设置）',
                subtitle: '解决 Android 13+/MIUI/HyperOS 无障碍开关灰显无法开启',
                onTap: () =>
                    ref.read(phoneControlProvider.notifier).openAppDetails(),
              ),
            SettingsTile(
              icon: AppIcons.done,
              tint: 1,
              title: phone.isChecking ? '正在自检连接…' : '一键自检手机操控连接',
              subtitle: selfCheck != null
                  ? selfCheck.summary
                  : '实测本地 MCP 环回通信、mcp_config.json 与无障碍读屏',
              onTap: phone.isChecking
                  ? null
                  : () async {
                      final report = await ref
                          .read(phoneControlProvider.notifier)
                          .runSelfCheck();
                      if (report != null && context.mounted) {
                        showBriefNotice(context, report.summary);
                      }
                    },
            ),
            if (phone.enabled && runtime.isRunning && !phone.mcpClientConnected)
              SettingsTile(
                icon: AppIcons.refresh,
                tint: 0,
                title: '重载本机引擎立即接入 MCP',
                subtitle: hasActiveChat
                    ? '当前有运行中的对话，请等完成后再重载'
                    : '让正在运行的 agy acp 立即重新加载最新 phone MCP',
                onTap: hasActiveChat
                    ? () => showBriefNotice(context, '当前有对话运行中，完成后可重载')
                    : () {
                        unawaited(
                          ref.read(localRuntimeProvider.notifier).restart(),
                        );
                        showBriefNotice(context, '正在重载本机引擎以接入手机操控 MCP…');
                      },
              ),
            if (phone.enabled)
              SettingsTile(
                icon: AppIcons.stop,
                title: '紧急停止并撤销所有待确认操作',
                danger: true,
                chevron: false,
                onTap: () =>
                    ref.read(phoneControlProvider.notifier).emergencyStop(),
              ),
          ],
        ),
        if (selfCheck != null)
          SettingsSection(
            title: '自检结果明细',
            children: [
              SettingsTile(
                icon: selfCheck.mcpProbeOk ? AppIcons.done : AppIcons.warning,
                tinted: false,
                title: '本地 MCP 环回服务',
                subtitle: selfCheck.mcpProbeDetail,
                chevron: false,
              ),
              SettingsTile(
                icon: selfCheck.mcpConfigOk ? AppIcons.done : AppIcons.warning,
                tinted: false,
                title: 'Antigravity MCP 配置文件',
                subtitle: selfCheck.mcpConfigOk
                    ? '~/.gemini/config/mcp_config.json 已同步 serverUrl'
                    : '未检测到有效 serverUrl 配置',
                chevron: false,
              ),
              SettingsTile(
                icon: selfCheck.accessibilityConnected
                    ? AppIcons.done
                    : AppIcons.warning,
                tinted: false,
                title: '无障碍服务与读屏',
                subtitle: selfCheck.accessibilityConnected
                    ? (selfCheck.screenReadOk ? '已绑定，读屏正常' : '已绑定')
                    : '未绑定到系统无障碍服务',
                chevron: false,
              ),
              SettingsTile(
                icon: selfCheck.mcpClientConnected
                    ? AppIcons.done
                    : AppIcons.askAi,
                tinted: false,
                title: 'agy 引擎 MCP 握手状态',
                subtitle: selfCheck.mcpClientConnected
                    ? 'agy 已完成 initialize 握手，可直接调用 phone_* 工具'
                    : '尚未收到 agy 握手请求（可点上方「重载本机引擎立即接入 MCP」）',
                chevron: false,
              ),
            ],
          ),
        SettingsSection(
          title: '应用外悬浮输入与快捷审批（DSH Go 方案）',
          footer: const Text(
            '开启后切出 AGY Go 到微信、浏览器等其他应用时，靠边悬浮球可单击直接弹出悬浮输入框「问一句」，操控确认也会以悬浮卡片弹出，无需切回应用。',
          ),
          children: [
            SettingsSwitchTile(
              icon: AppIcons.overlayBall,
              tint: 1,
              title: '启用应用外悬浮输入球',
              subtitle: pet.canDrawOverlays
                  ? '已获悬浮窗权限，切到其他应用时自动显示'
                  : pet.canUseAccessibilityOverlay
                  ? '通过无障碍悬浮显示（免额外悬浮窗权限）'
                  : '开启无障碍服务或授予「显示在其他应用上层」权限后可用',
              value: pet.showSystemOverlay,
              onChanged: (v) async {
                final ok = await ref
                    .read(petSettingsProvider.notifier)
                    .setShowSystemOverlay(v);
                if (v && !ok && context.mounted) {
                  showBriefNotice(context, '请授予悬浮窗权限或先开启无障碍服务后返回开启');
                }
              },
            ),
            SettingsTile(
              icon: AppIcons.pet,
              tint: 2,
              title: '更多悬浮球与输入条设置',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PetSettingsPage(),
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: '安全确认档位（SafetyGate）',
          footer: const Text(
            '无论选择何种档位，银行、支付、密码管理器以及包含「支付、转账、验证码、卸载、删除」等关键词的修改操作均强制拦截确认。',
          ),
          children: [
            for (final mode in PhoneSafetyMode.values)
              SettingsTile(
                icon: switch (mode) {
                  PhoneSafetyMode.confirmAll => AppIcons.askFirst,
                  PhoneSafetyMode.confirmSensitive => AppIcons.askPerTask,
                  PhoneSafetyMode.autoNonFinancial => AppIcons.noConfirm,
                },
                tint: 3,
                title: mode.label,
                subtitle: mode.description,
                chevron: false,
                trailing: Icon(
                  phone.safetyMode == mode
                      ? AppIcons.radioOn
                      : AppIcons.radioOff,
                  size: 20,
                  color: phone.safetyMode == mode
                      ? theme.colorScheme.primary
                      : dsh.textTertiary,
                ),
                onTap: () =>
                    ref.read(phoneControlProvider.notifier).setSafetyMode(mode),
              ),
          ],
        ),
        SettingsSection(
          title: '近期操控审计日志',
          children: [
            if (phone.auditLog.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '暂无操控记录。开启后在对话中调用 phone_* 工具即可实时看到操作审计。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dsh.textTertiary,
                  ),
                ),
              )
            else
              for (final item in phone.auditLog.take(25))
                SettingsTile(
                  icon: item.outcome == 'ok' ? AppIcons.done : AppIcons.warning,
                  tinted: false,
                  title: '${item.tool} · ${item.summary}',
                  subtitle:
                      '${item.at.hour.toString().padLeft(2, '0')}:${item.at.minute.toString().padLeft(2, '0')}:${item.at.second.toString().padLeft(2, '0')} · ${item.outcome}',
                  chevron: false,
                ),
          ],
        ),
      ],
    );
  }
}
