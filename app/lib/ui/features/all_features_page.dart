// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/sessions_state.dart';
import '../chat/session_detail_page.dart';
import '../common/app_sheet.dart' show groupTitleStyle;
import '../common/list_page_row.dart';
import '../common/overview_card.dart';
import '../common/tile_grid.dart';
import '../engine/engine_screen.dart';
import '../pet/starling_pet.dart';
import '../phone/phone_control_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../settings/settings_screen.dart';
import '../share/share_screen.dart';
import '../shell/page_frame.dart';
import '../shell/session_search_page.dart';
import '../system/keep_alive_screen.dart';
import '../terminal/terminal_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspace_screen.dart';
import '../workspace/workspaces_ui.dart';

/// All Features hub mirroring DSH Go's AllFeaturesPage (2-column FeatureCard TileGrid).
class AllFeaturesPage extends ConsumerWidget {
  const AllFeaturesPage({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final chat = ref.watch(chatProvider);
    final current = sessions.currentSession;
    final hasSession = chat.sessionId != null;

    return AppPage.list(
      title: '全部功能',
      subtitle: const Text('所有本机引擎、工作区、远程与辅助能力'),
      children: [
        OverviewCard(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          leading: OverviewGlyph(
            hasSession ? AppIcons.chat : AppIcons.conversations,
            tint: hasSession ? 0 : 7,
          ),
          title: Text(
            hasSession
                ? (current != null ? sessions.displayTitle(current) : '当前对话')
                : '尚未打开对话',
          ),
          subtitle: Text(
            hasSession
                ? '点击返回对话，或查看下方对话详情、文件与导出'
                : '从首页开始新对话，或直接进入下方工具',
          ),
          onTap: hasSession
              ? () => Navigator.of(context).popUntil((r) => r.isFirst)
              : null,
        ),
        const _SectionLabel('当前对话'),
        TileGrid(
          children: [
            FeatureCard(
              icon: AppIcons.sessionDetails,
              tint: 0,
              title: '对话详情',
              subtitle: '工具轨迹、目录与用量',
              enabled: hasSession,
              onTap: () => _push(context, const SessionDetailPage()),
            ),
            FeatureCard(
              icon: AppIcons.files,
              tint: 5,
              title: '工作区文件',
              subtitle: '浏览、编辑与创建文件',
              onTap: () => _push(context, const WorkspaceScreen()),
            ),
            FeatureCard(
              icon: AppIcons.terminal,
              tint: 6,
              title: '远程终端',
              subtitle: 'SSH PTY 交互终端',
              onTap: () => _push(context, const TerminalScreen()),
            ),
            FeatureCard(
              icon: AppIcons.share,
              tint: 2,
              title: '分享与回放',
              subtitle: '长图卡片、脱敏导出与回放',
              onTap: () => _push(context, const ShareScreen()),
            ),
          ],
        ),
        const _SectionLabel('工作区与主机'),
        TileGrid(
          children: [
            FeatureCard(
              icon: AppIcons.workspace,
              tint: 4,
              title: '工作区管理',
              subtitle: '挂载本机目录、手机存储与分组',
              onTap: () => _push(context, const WorkspacesPage()),
            ),
            FeatureCard(
              icon: AppIcons.search,
              tint: 7,
              title: '搜索对话',
              subtitle: '按标题或工作区路径检索',
              onTap: () async {
                final id = await showSessionSearch(context);
                if (id != null && context.mounted) {
                  ref.read(sessionsProvider.notifier).selectSession(id);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),
            FeatureCard(
              icon: AppIcons.engine,
              tint: 0,
              title: '本机引擎',
              subtitle: '安装、启停官方 agy 与认证',
              onTap: () => _push(context, const EngineScreen()),
            ),
            FeatureCard(
              icon: AppIcons.remoteHosts,
              tint: 1,
              title: 'SSH 远程主机',
              subtitle: '连接 Linux/macOS 远程 agy',
              onTap: () => _push(context, const SshHostsScreen()),
            ),
          ],
        ),
        const _SectionLabel('能力与体验'),
        TileGrid(
          children: [
            FeatureCard(
              icon: AppIcons.phoneControl,
              tint: 3,
              title: '手机操控',
              subtitle: '无障碍 MCP 服务与安全闸门',
              onTap: () => _push(context, const PhoneControlScreen()),
            ),
            FeatureCard(
              icon: AppIcons.pet,
              tint: 2,
              title: '星灵桌宠',
              subtitle: '状态联动宠物与系统悬浮窗',
              onTap: () => _push(context, const PetSettingsPage()),
            ),
            FeatureCard(
              icon: AppIcons.keepAlive,
              tint: 5,
              title: '保活与更新',
              subtitle: '国产 ROM 保活引导与检查更新',
              onTap: () => _push(context, const KeepAliveScreen()),
            ),
            FeatureCard(
              icon: AppIcons.phoneStorage,
              tint: 4,
              title: '手机存储挂载',
              subtitle: '授权挂载 /storage/emulated/0',
              onTap: () => _push(context, const PhoneStoragePage()),
            ),
          ],
        ),
        const _SectionLabel('设置'),
        ListPageCard(
          children: [
            ListPageRow(
              icon: AppIcons.settings,
              title: '全部设置',
              subtitle: '认证、外观、权限、系统权限与诊断',
              onTap: () => _push(context, const SettingsScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Semantics(
      header: true,
      child: Text(text, style: groupTitleStyle(context)),
    ),
  );
}
