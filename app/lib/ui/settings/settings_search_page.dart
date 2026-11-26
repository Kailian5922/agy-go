// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:material_ui/material_ui.dart';

import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/search_capsule.dart';
import '../engine/engine_screen.dart';
import '../features/agy_extensions_pages.dart';
import '../pet/starling_pet.dart';
import '../phone/phone_control_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../share/share_screen.dart';
import '../shell/page_frame.dart';
import '../system/keep_alive_screen.dart';
import '../terminal/terminal_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspace_screen.dart';
import '../workspace/workspaces_ui.dart';
import 'settings_screen.dart';

class _SettingSearchEntry {
  const _SettingSearchEntry({
    required this.title,
    required this.subtitle,
    required this.group,
    required this.icon,
    required this.keywords,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final String group;
  final IconData icon;
  final List<String> keywords;
  final WidgetBuilder builder;

  bool matches(String q) {
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q) ||
        group.toLowerCase().contains(q) ||
        keywords.any((k) => k.toLowerCase().contains(q));
  }
}

final _catalog = <_SettingSearchEntry>[
  _SettingSearchEntry(
    title: '认证与本机引擎',
    subtitle: '安装官方 agy、Google 账号登录或 Gemini API Key',
    group: 'AI 与工作区',
    icon: AppIcons.engine,
    keywords: ['oauth', 'api key', 'gemini', 'login', '登录', '引擎', '安装', 'agy'],
    builder: (_) => const EngineScreen(),
  ),
  _SettingSearchEntry(
    title: '权限层级',
    subtitle: '严格确认 / 询问确认 / 沙箱放行 / 完全放行 与计划模式',
    group: 'AI 与工作区',
    icon: AppIcons.permissions,
    keywords: ['permission', 'approval', 'yolo', 'plan', 'sandbox', 'strict', '权限', '审批', '放行'],
    builder: (_) => const PermissionPage(),
  ),
  _SettingSearchEntry(
    title: 'MCP 服务管理',
    subtitle: '管理 settings.json 中的 Stdio / HTTP / SSE MCP 服务器',
    group: 'AI 与工作区',
    icon: AppIcons.plugin,
    keywords: ['mcp', 'server', 'stdio', 'http', 'sse', '工具', '扩展'],
    builder: (_) => const McpServersPage(),
  ),
  _SettingSearchEntry(
    title: 'Skills 与记忆规则',
    subtitle: '管理 SKILL.md 技能与全局 / 工作区 GEMINI.md',
    group: 'AI 与工作区',
    icon: AppIcons.skill,
    keywords: ['skill', 'skills', 'memory', 'rules', 'gemini.md', '记忆', '技能', '规则'],
    builder: (_) => const SkillsAndRulesPage(),
  ),
  _SettingSearchEntry(
    title: '引擎参数与权限规则 (settings.json)',
    subtitle: '配置 allow / ask / deny 规则、队列插话行为与原始 JSON',
    group: 'AI 与工作区',
    icon: AppIcons.configure,
    keywords: ['settings.json', 'config', 'allow', 'deny', 'ask', 'steer', 'queue', '参数'],
    builder: (_) => const AgyEngineParamsPage(),
  ),
  _SettingSearchEntry(
    title: '工作区管理',
    subtitle: '挂载本机目录、手机存储与分组',
    group: 'AI 与工作区',
    icon: AppIcons.workspace,
    keywords: ['workspace', 'folder', 'storage', '目录', '挂载', '工作区'],
    builder: (_) => const WorkspacesPage(),
  ),
  _SettingSearchEntry(
    title: '手机存储挂载',
    subtitle: '授权挂载 /storage/emulated/0 与 ~/手机存储',
    group: 'AI 与工作区',
    icon: AppIcons.phoneStorage,
    keywords: ['storage', 'sdcard', 'emulated', '存储', '相册', '权限'],
    builder: (_) => const PhoneStoragePage(),
  ),
  _SettingSearchEntry(
    title: '工作区文件浏览',
    subtitle: '浏览、编辑或新建当前工作区文件',
    group: '能力',
    icon: AppIcons.files,
    keywords: ['files', 'editor', '文件', '编辑'],
    builder: (_) => const WorkspaceScreen(),
  ),
  _SettingSearchEntry(
    title: '本机与 SSH 终端',
    subtitle: '在手机内直接运行 agy 命令或连接远程 PTY',
    group: '能力',
    icon: AppIcons.terminal,
    keywords: ['terminal', 'shell', 'pty', 'bash', '终端', '命令行'],
    builder: (_) => const TerminalScreen(),
  ),
  _SettingSearchEntry(
    title: '手机操控（MCP）',
    subtitle: '无障碍读屏、手势操作与 SafetyGate 支付安全闸门',
    group: '能力',
    icon: AppIcons.phoneControl,
    keywords: ['phone', 'accessibility', 'safetygate', '无障碍', '操控', '手机'],
    builder: (_) => const PhoneControlScreen(),
  ),
  _SettingSearchEntry(
    title: '语音与朗读',
    subtitle: '系统语音听写输入与 TTS 回复朗读',
    group: '能力',
    icon: AppIcons.voice,
    keywords: ['voice', 'tts', 'stt', '语音', '朗读', '听写'],
    builder: (_) => const VoiceSettingsPage(),
  ),
  _SettingSearchEntry(
    title: '分享与对话回放',
    subtitle: '脱敏长图、Markdown 导出与步骤回放',
    group: '能力',
    icon: AppIcons.share,
    keywords: ['share', 'export', 'replay', '分享', '长图', '导出', '回放'],
    builder: (_) => const ShareScreen(),
  ),
  _SettingSearchEntry(
    title: '外观、配色与壁纸',
    subtitle: '浅色/深色主题、OKLCH 配色、隐藏状态栏、毛玻璃与聊天壁纸',
    group: '外观',
    icon: AppIcons.theme,
    keywords: ['theme', 'dark', 'light', 'blur', 'status bar', 'wallpaper', '状态栏', '壁纸', '配色', '模糊'],
    builder: (_) => const AppearancePage(),
  ),
  _SettingSearchEntry(
    title: '星灵桌宠',
    subtitle: '状态联动宠物与系统桌面悬浮球',
    group: '外观',
    icon: AppIcons.pet,
    keywords: ['pet', 'overlay', '桌宠', '悬浮球'],
    builder: (_) => const PetSettingsPage(),
  ),
  _SettingSearchEntry(
    title: '通知与胶囊提醒（实时活动）',
    subtitle: '状态栏胶囊 / 灵动岛 / 流体云 / 超级岛、审批高优与完成通知',
    group: '通用',
    icon: AppIcons.notifications,
    keywords: [
      'notification',
      'alert',
      'live',
      'capsule',
      'island',
      '通知',
      '提醒',
      '后台',
      '胶囊',
      '实时活动',
      '灵动岛',
      '流体云',
      '超级岛',
    ],
    builder: (_) => const NotificationSettingsPage(),
  ),
  _SettingSearchEntry(
    title: '模型运行时保持屏幕常亮',
    subtitle: '停留在 App 页面且模型思考/执行期间不自动熄屏，结束后恢复正常',
    group: '通用',
    icon: AppIcons.tip,
    keywords: [
      'screen',
      'awake',
      'wakelock',
      'sleep',
      '常亮',
      '不熄屏',
      '息屏',
      '熄屏',
      '屏幕',
      '亮屏',
    ],
    builder: (_) => const KeepAliveScreen(),
  ),
  _SettingSearchEntry(
    title: '后台保活与更新',
    subtitle: '国产 ROM 保活引导与忽略电池优化',
    group: '通用',
    icon: AppIcons.keepAlive,
    keywords: ['battery', 'keep alive', 'update', '保活', '电池', '更新'],
    builder: (_) => const KeepAliveScreen(),
  ),
  _SettingSearchEntry(
    title: '系统权限总览',
    subtitle: '统一查看存储、无障碍、悬浮窗与省电策略授权状态',
    group: '通用',
    icon: AppIcons.systemAccess,
    keywords: ['system', 'access', '系统权限', '授权'],
    builder: (_) => const SystemAccessPage(),
  ),
  _SettingSearchEntry(
    title: 'SSH 远程主机',
    subtitle: '添加并连接远程 Linux / macOS 上的 agy acp',
    group: '主机',
    icon: AppIcons.remoteHosts,
    keywords: ['ssh', 'remote', 'host', '远程', '服务器', '主机'],
    builder: (_) => const SshHostsScreen(),
  ),
  _SettingSearchEntry(
    title: '诊断与日志',
    subtitle: '查看并复制已自动脱敏的本机引擎日志',
    group: '帮助与关于',
    icon: AppIcons.diagnostics,
    keywords: ['log', 'debug', 'diagnostics', '日志', '诊断'],
    builder: (_) => const DiagnosticsPage(),
  ),
  _SettingSearchEntry(
    title: '关于 AGY Go 与检查更新',
    subtitle: '版本号、开源协议与检查更新',
    group: '帮助与关于',
    icon: AppIcons.info,
    keywords: ['about', 'version', 'license', '关于', '版本', '更新'],
    builder: (_) => const AboutPage(),
  ),
];

/// Full-text search over all AGY Go settings & features, mirroring DSH Go's SettingsSearchPage.
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final hits = _catalog.where((e) => e.matches(q)).toList();

    return AppPage.list(
      title: '搜索设置',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SearchCapsule(
            controller: _ctrl,
            hint: '搜索权限、MCP、壁纸、状态栏、SSH…',
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            onClear: () {
              _ctrl.clear();
              setState(() => _query = '');
            },
          ),
        ),
        if (hits.isEmpty)
          const EmptyView(
            icon: AppIcons.noResults,
            title: '没有匹配的设置项',
            message: '试试搜索「审批」「状态栏」「壁纸」「MCP」「Skills」或「存储」。',
          )
        else
          ListPageCard(
            title: q.isEmpty ? '全部设置与能力 (${hits.length})' : '匹配结果 (${hits.length})',
            children: [
              for (final entry in hits)
                ListPageRow(
                  icon: entry.icon,
                  title: entry.title,
                  titleNote: entry.group,
                  subtitle: entry.subtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: entry.builder),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
