import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/phone_state.dart';
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Inline high-visibility approval card for SafetyGate phone-control actions.
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
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);
    final accent = prompt.isHighRisk ? surfaces.danger : surfaces.warning;

    return GlassSurface(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                prompt.isHighRisk
                    ? Icons.gpp_maybe_rounded
                    : Icons.touch_app_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prompt.isHighRisk ? '高风险手机操作确认' : '手机操控操作确认',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              Text(
                prompt.tool,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: surfaces.subtleText,
                ),
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
              color: surfaces.subtleText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: onApprove,
                child: const Text('允许执行'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onDeny,
                style: OutlinedButton.styleFrom(
                  foregroundColor: surfaces.danger,
                  side: BorderSide(color: surfaces.danger.withValues(alpha: 0.5)),
                ),
                child: const Text('拒绝'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PhoneControlScreen extends ConsumerWidget {
  const PhoneControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(phoneControlProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return AgyPage(
      title: '手机操控（MCP）',
      actions: [
        IconButton(
          tooltip: '刷新状态',
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () => ref.read(phoneControlProvider.notifier).refresh(),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          // Master switch & emergency stop
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '启用 MCP 手机操控',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '开启后将启动本地受保护的 MCP HTTP 服务，并自动挂载给本机 Antigravity CLI。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: surfaces.subtleText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: phone.enabled,
                      onChanged: (v) =>
                          ref.read(phoneControlProvider.notifier).setEnabled(v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatusPill(
                      label: phone.accessibilityConnected
                          ? '无障碍服务已就绪'
                          : '无障碍服务未开启',
                      dotColor: phone.accessibilityConnected
                          ? surfaces.success
                          : surfaces.warning,
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(phoneControlProvider.notifier)
                          .openAccessibilitySettings(),
                      icon: const Icon(Icons.accessibility_new_rounded, size: 17),
                      label: const Text('无障碍设置'),
                    ),
                  ],
                ),
                if (phone.mcpUrl != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'MCP 端点：${phone.mcpUrl}（Bearer 鉴权已启用）',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: surfaces.subtleText,
                    ),
                  ),
                ],
                if (phone.enabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => ref
                          .read(phoneControlProvider.notifier)
                          .emergencyStop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: surfaces.danger,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.emergency_rounded, size: 18),
                      label: const Text('紧急停止并撤销所有待确认操作'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (phone.pendingApprovals.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final prompt in phone.pendingApprovals) ...[
              PhoneApprovalCard(
                prompt: prompt,
                onApprove: () => ref
                    .read(phoneControlProvider.notifier)
                    .resolveApproval(prompt.id, approved: true),
                onDeny: () => ref
                    .read(phoneControlProvider.notifier)
                    .resolveApproval(prompt.id, approved: false),
              ),
              const SizedBox(height: 8),
            ],
          ],

          const SizedBox(height: 14),

          // Three-tier SafetyGate mode selection
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '安全确认档位（SafetyGate）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '无论处于何种档位，银行/支付/密码管理器及包含「支付、转账、验证码、卸载、删除」等关键词的修改操作均强制拦截确认。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.subtleText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                for (final mode in PhoneSafetyMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: HairlineCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      borderColor: phone.safetyMode == mode
                          ? theme.colorScheme.primary.withValues(alpha: 0.55)
                          : null,
                      backgroundColor: phone.safetyMode == mode
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : null,
                      onTap: () => ref
                          .read(phoneControlProvider.notifier)
                          .setSafetyMode(mode),
                      child: Row(
                        children: [
                          Icon(
                            phone.safetyMode == mode
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 19,
                            color: phone.safetyMode == mode
                                ? theme.colorScheme.primary
                                : surfaces.subtleText,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mode.label,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  mode.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: surfaces.subtleText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Audit log
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '近期操控审计日志',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (phone.auditLog.isEmpty)
                  Text(
                    '暂无操控记录。开启后在对话中让 Antigravity 调用 `phone_*` 工具即可看到实时审计。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: surfaces.subtleText,
                    ),
                  )
                else
                  for (final item in phone.auditLog.take(30))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 5),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: item.outcome == 'ok'
                                  ? surfaces.success
                                  : item.outcome == 'denied' ||
                                          item.outcome == 'blocked'
                                  ? surfaces.warning
                                  : surfaces.danger,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.tool} · ${item.summary}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${item.at.hour.toString().padLeft(2, '0')}:${item.at.minute.toString().padLeft(2, '0')}:${item.at.second.toString().padLeft(2, '0')} · ${item.outcome}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: surfaces.subtleText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
