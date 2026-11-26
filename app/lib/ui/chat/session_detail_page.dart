// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../../state/settings_state.dart';
import '../../state/workspaces_state.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/settings_widgets.dart';
import '../share/share_screen.dart';
import '../shell/page_frame.dart';
import '../terminal/terminal_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspace_screen.dart';
import 'diff_and_output_page.dart';
import 'permission_controls.dart';
import 'tool_format.dart';

/// Conversation details, live plan checklist, tool trajectory & diffs page.
class SessionDetailPage extends ConsumerStatefulWidget {
  const SessionDetailPage({super.key});

  @override
  ConsumerState<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends ConsumerState<SessionDetailPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final sessions = ref.watch(sessionsProvider);
    final hosts = ref.watch(hostsProvider);
    final settings = ref.watch(settingsProvider);
    final runtime = ref.watch(localRuntimeProvider).status;
    final current = sessions.currentSession;
    final title = current != null ? sessions.displayTitle(current) : '对话详情';
    final toolCalls = <AcpToolCall>[
      for (final item in chat.transcript.items)
        if (item is AssistantTranscriptItem) ...item.toolCalls,
    ];
    final plan = chat.transcript.plan;
    final diffs = collectTranscriptDiffs(
      chat.transcript,
      workspaceCwd: chat.sessionCwd,
    );
    final usage = chat.transcript.usage;
    final activeMode = chat.sessionAgentMode ?? settings.agentMode;
    final activePerm = chat.sessionToolPermission ?? settings.toolPermission;
    final scheme = Theme.of(context).colorScheme;
    final dsh = DshColors.of(context);

    return AppPage.list(
      title: '对话详情',
      subtitle: Text(title),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: SegmentedPill<int>(
            selected: _tab,
            onChanged: (v) => setState(() => _tab = v),
            segments: [
              const PillSegment(0, '概览'),
              PillSegment(1, plan.isEmpty ? '计划' : '计划(${plan.length})'),
              PillSegment(2, '轨迹(${toolCalls.length})'),
              PillSegment(3, 'Diff(${diffs.length})'),
            ],
          ),
        ),
        if (_tab == 0) ...[
          SettingsSection(
            title: '基本信息',
            children: [
              InfoRow(label: '标题', value: title),
              InfoRow(
                label: '会话 ID',
                value: chat.sessionId ?? '未创建',
                mono: true,
              ),
              InfoRow(label: '主机', value: hosts.activeLabel()),
              InfoRow(
                label: '工作区目录',
                value: displayWorkspacePath(
                  chat.sessionCwd ?? ref.read(effectiveWorkingDirProvider),
                  local: hosts.active.isLocal,
                  homePath: runtime.homePath,
                  storageRoot: runtime.phoneStoragePath,
                ),
                mono: true,
              ),
              if (chat.additionalDirectories.isNotEmpty)
                InfoRow(
                  label: '额外挂载目录',
                  value: chat.additionalDirectories.join(', '),
                  mono: true,
                ),
              InfoRow(
                label: '执行 / 审批模式',
                value: '${activeMode.label} · ${activePerm.label}',
              ),
              InfoRow(
                label: '消息 / 工具数',
                value:
                    '${chat.transcript.items.length} 条（含 ${toolCalls.length} 次工具调用）',
              ),
            ],
          ),
          if (usage != null)
            SettingsSection(
              title: '上下文与用量',
              children: [
                if (usage.usedTokens != null)
                  InfoRow(label: '已用 Token', value: '${usage.usedTokens}'),
                if (usage.sizeTokens != null)
                  InfoRow(label: '上下文上限', value: '${usage.sizeTokens}'),
                if (usage.costAmount != null)
                  InfoRow(
                    label: '估算费用',
                    value:
                        '${usage.costAmount!.toStringAsFixed(4)} ${usage.costCurrency ?? ''}'
                            .trim(),
                  ),
              ],
            ),
          ListPageCard(
            title: '对当前对话操作',
            children: [
              ListPageRow(
                icon: AppIcons.permissions,
                title: '审批与执行模式',
                subtitle: '${activeMode.label} · ${activePerm.label}',
                onTap: () => unawaited(showApprovalModeSheet(context, ref)),
              ),
              ListPageRow(
                icon: AppIcons.diagnostics,
                title: '订阅额度与上下文用量',
                subtitle: '查看 5 小时 / 周额度、窗口占比并执行 /compact',
                onTap: () => unawaited(showContextUsageSheet(context, ref)),
              ),
              ListPageRow(
                icon: AppIcons.files,
                title: '打开工作区文件',
                subtitle: '查看或编辑工作区目录内容',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkspaceScreen(),
                  ),
                ),
              ),
              ListPageRow(
                icon: AppIcons.terminal,
                title: '打开终端',
                subtitle: '本机 Shell 或 SSH PTY 交互终端',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TerminalScreen(),
                  ),
                ),
              ),
              ListPageRow(
                icon: AppIcons.share,
                title: '分享长图 / 导出 / 回放',
                subtitle: '自动脱敏密钥后生成图片或 Markdown',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ShareScreen()),
                ),
              ),
            ],
          ),
        ] else if (_tab == 1) ...[
          if (plan.isEmpty)
            const EmptyView(
              icon: AppIcons.todo,
              title: '暂无任务计划清单',
              message: '开启 /plan 计划模式或触发复杂任务后，Antigravity 输出的实时步骤清单会显示在这里。',
            )
          else
            ListPageCard(
              title:
                  '已完成 ${plan.where((p) => p.status.toLowerCase() == 'completed').length} / ${plan.length}',
              children: [
                for (final entry in plan)
                  ListPageRow(
                    icon: switch (entry.status.toLowerCase()) {
                      'completed' => AppIcons.success,
                      'in_progress' => AppIcons.inProgress,
                      'failed' => AppIcons.stepFailed,
                      _ => AppIcons.pending,
                    },
                    iconColor: switch (entry.status.toLowerCase()) {
                      'completed' => dsh.success,
                      'in_progress' => scheme.primary,
                      'failed' => dsh.danger,
                      _ => dsh.textTertiary,
                    },
                    title: entry.content,
                    titleMaxLines: 3,
                    meta: entry.priority,
                    chevron: false,
                  ),
              ],
            ),
        ] else if (_tab == 2) ...[
          if (toolCalls.isEmpty)
            const EmptyView(
              icon: AppIcons.terminal,
              title: '暂无工具调用',
              message: '本对话中的命令执行、文件读写和 MCP 调用会按时间顺序记录在这里。',
            )
          else
            ListPageCard(
              title: '共 ${toolCalls.length} 次工具调用',
              children: [
                for (final tc in toolCalls.reversed)
                  ListPageRow(
                    icon: _toolIcon(tc.kind),
                    title: formatToolSummary(
                      tc,
                      workspaceCwd: chat.sessionCwd,
                    ),
                    subtitle: tc.locations.isNotEmpty
                        ? tc.locations
                              .map(
                                (l) => displayToolPath(
                                  l.path,
                                  workspaceCwd: chat.sessionCwd,
                                ),
                              )
                              .join(', ')
                        : tc.kind.name,
                    meta: tc.status.name,
                    chevron: false,
                  ),
              ],
            ),
        ] else ...[
          if (diffs.isEmpty)
            const EmptyView(
              icon: AppIcons.diff,
              title: '暂无文件变更 Diff',
              message: '当 Antigravity 修改工作区文件后，变更汇总会显示在这里，并支持全屏审阅。',
            )
          else
            ListPageCard(
              title: '共 ${diffs.length} 处文件变更',
              children: [
                for (final d in diffs)
                  ListPageRow(
                    icon: AppIcons.diff,
                    title: d.path,
                    subtitle: '+${d.addedLines} / −${d.removedLines}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DiffViewerPage(entries: [d], title: d.path),
                      ),
                    ),
                  ),
                ListPageRow(
                  icon: AppIcons.openExternal,
                  title: '全屏查看全部变更 Diff',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DiffViewerPage.fromTranscript(
                        chat.transcript,
                        workspaceCwd: chat.sessionCwd,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  IconData _toolIcon(AcpToolKind kind) => switch (kind) {
    AcpToolKind.execute => AppIcons.terminal,
    AcpToolKind.read => AppIcons.document,
    AcpToolKind.edit => AppIcons.edit,
    AcpToolKind.search => AppIcons.search,
    AcpToolKind.fetch => AppIcons.web,
    _ => AppIcons.tool,
  };
}
