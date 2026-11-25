// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/phone_state.dart';
import '../common/overview_card.dart';
import '../common/settings_widgets.dart';
import '../common/status_dot.dart';
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
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);

    final ready = phone.enabled && phone.accessibilityConnected;

    return AppPage.list(
      title: '手机操控',
      subtitle: const Text('通过无障碍服务与本地受保护 MCP 协议让 agy 安全操作手机'),
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
            tint: ready ? 4 : 3,
          ),
          title: Text(
            ready
                ? '手机操控已就绪'
                : phone.enabled
                ? '还差一步：开启无障碍服务'
                : '手机操控未开启',
          ),
          subtitle: Text(
            phone.mcpUrl != null
                ? 'MCP 端点：${phone.mcpUrl}（Bearer 鉴权）'
                : '开启后将自动把本地 phone MCP 挂载到新会话',
          ),
          footer: OverviewFooter(
            tone: ready
                ? StatusTone.ok
                : phone.enabled
                ? StatusTone.warn
                : StatusTone.idle,
            text: phone.accessibilityConnected ? '无障碍服务：已连接' : '无障碍服务：未开启',
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
          title: '开关与无障碍',
          children: [
            SettingsSwitchTile(
              icon: AppIcons.phoneControl,
              tint: 3,
              title: '启用 MCP 手机操控',
              subtitle: '启动本地受保护 HTTP MCP 并挂载给本机 agy',
              value: phone.enabled,
              onChanged: (v) =>
                  ref.read(phoneControlProvider.notifier).setEnabled(v),
            ),
            SettingsTile(
              icon: AppIcons.accessibility,
              tint: 4,
              title: '系统无障碍设置',
              value: Text(
                phone.accessibilityConnected ? '已开启' : '去开启',
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
