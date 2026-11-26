// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../runtime/runtime_models.dart';
import '../../state/agy_config_state.dart';
import '../../state/hosts_state.dart';
import '../../state/live_activity_state.dart';
import '../../state/pet_state.dart';
import '../../state/phone_state.dart';
import '../../state/runtime_state.dart';
import '../../state/settings_state.dart';
import '../../state/system_state.dart';
import '../../state/voice_state.dart';
import '../../state/workspaces_state.dart';
import '../chat/permission_controls.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/list_page_row.dart';
import '../common/overview_card.dart';
import '../common/pressable.dart';
import '../common/search_capsule.dart';
import '../common/settings_widgets.dart';
import '../common/status_chip.dart';
import '../engine/engine_screen.dart';
import '../features/agy_extensions_pages.dart';
import '../pet/starling_pet.dart';
import '../phone/phone_control_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../share/share_screen.dart';
import '../shell/brand_mark.dart';
import '../shell/page_frame.dart';
import '../system/keep_alive_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';
import 'settings_search_page.dart';

/// One hue per group on the settings hub (exact DSH Go SettingsHues).
abstract final class SettingsHues {
  static const ai = 0;
  static const abilities = 4;
  static const appearance = 1;
  static const general = 5;
  static const hosts = 6;
  static const help = 7;
}

const _chatTextScales = <(double, String)>[
  (0.9, '小'),
  (1.0, '标准'),
  (1.1, '大'),
  (1.2, '特大'),
];

String _maskKey(String key) {
  final t = key.trim();
  if (t.length <= 8) return '••••••••';
  return '${t.substring(0, 4)}••••${t.substring(t.length - 4)}';
}

(StatusTone, String) _engineBadge(RuntimeStatus status) => switch (status.phase) {
  RuntimePhase.running => (StatusTone.ok, '运行中'),
  RuntimePhase.starting || RuntimePhase.installing => (StatusTone.busy, '准备中'),
  RuntimePhase.error => (StatusTone.error, '异常'),
  RuntimePhase.installed => (StatusTone.idle, '已停止'),
  RuntimePhase.stopping => (StatusTone.idle, '停止中'),
  RuntimePhase.notInstalled => (StatusTone.warn, '未安装'),
};

/// Settings hub mirroring DSH Go's exact information architecture:
/// Search capsule + Overview card (Auth + live engine footer), then six hue-grouped sections.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final runtime = ref.watch(localRuntimeProvider);
    final phone = ref.watch(phoneControlProvider);
    final pet = ref.watch(petSettingsProvider);
    final hosts = ref.watch(hostsProvider);
    final sys = ref.watch(systemToolsProvider);
    final agyConfig = ref.watch(agyConfigProvider);
    final wsCount = ref.watch(
      workspacesProvider.select((w) => w.workspaces.length),
    );
    final colors = DshColors.of(context);
    final notifier = ref.read(settingsProvider.notifier);

    final (engineTone, engineLabel) = _engineBadge(runtime.status);
    final phoneValue = !phone.enabled
        ? '已关闭'
        : phone.accessibilityConnected
        ? '已开启'
        : '还差一步';
    final storageValue = settings.phoneStorage
        ? (runtime.storage.granted ? '已挂载' : '需授权')
        : '未开启';
    final permSummary = settings.agentMode == AgyAgentMode.plan
        ? '计划模式 · ${settings.toolPermission.label}'
        : settings.toolPermission.label;

    return AppPage.list(
      title: '设置',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SearchCapsuleButton(
            hint: '搜索设置、审批、MCP、壁纸…',
            onTap: () => _push(context, const SettingsSearchPage()),
          ),
        ),
        const SettingsOverview(),
        SettingsSection(
          title: 'AI 与工作区',
          children: [
            SettingsTile(
              icon: AppIcons.providers,
              tint: SettingsHues.ai,
              title: '认证与本机引擎',
              value: Text(
                settings.authMode == LocalAuthMode.geminiApiKey
                    ? 'Gemini API Key'
                    : 'Google 账号',
              ),
              onTap: () => _push(context, const EngineScreen()),
            ),
            SettingsTile(
              icon: settings.toolPermission.isHighRisk
                  ? AppIcons.permissionRisky
                  : AppIcons.permissions,
              tint: settings.toolPermission.isHighRisk ? 3 : SettingsHues.ai,
              title: '权限层级',
              value: Text(
                permSummary,
                style: settings.toolPermission.isHighRisk
                    ? TextStyle(color: colors.danger)
                    : null,
              ),
              onTap: () => _push(context, const PermissionPage()),
            ),
            SettingsTile(
              icon: AppIcons.plugin,
              tint: SettingsHues.ai,
              title: 'MCP 服务管理',
              value: Text('${agyConfig.mcpServers.length} 个配置'),
              onTap: () => _push(context, const McpServersPage()),
            ),
            SettingsTile(
              icon: AppIcons.skill,
              tint: SettingsHues.ai,
              title: 'Skills 与记忆规则',
              value: Text('${agyConfig.skills.length} 个技能'),
              onTap: () => _push(context, const SkillsAndRulesPage()),
            ),
            SettingsTile(
              icon: AppIcons.configure,
              tint: SettingsHues.ai,
              title: '引擎参数与规则 (settings.json)',
              onTap: () => _push(context, const AgyEngineParamsPage()),
            ),
            SettingsTile(
              icon: AppIcons.workspace,
              tint: SettingsHues.ai,
              title: '工作区管理',
              value: Text('$wsCount 个目录'),
              onTap: () => _push(context, const WorkspacesPage()),
            ),
            SettingsTile(
              icon: AppIcons.phoneStorage,
              tint: SettingsHues.ai,
              title: '手机存储挂载',
              value: Text(
                storageValue,
                style: settings.phoneStorage && !runtime.storage.granted
                    ? TextStyle(color: colors.warning)
                    : null,
              ),
              onTap: () => _push(context, const PhoneStoragePage()),
            ),
          ],
        ),
        SettingsSection(
          title: '能力',
          children: [
            SettingsTile(
              icon: AppIcons.phoneControl,
              tint: SettingsHues.abilities,
              title: '手机操控（MCP）',
              value: Text(
                phoneValue,
                style: phoneValue == '还差一步'
                    ? TextStyle(color: colors.warning)
                    : null,
              ),
              onTap: () => _push(context, const PhoneControlScreen()),
            ),
            SettingsTile(
              icon: AppIcons.voice,
              tint: SettingsHues.abilities,
              title: '语音与朗读',
              onTap: () => _push(context, const VoiceSettingsPage()),
            ),
            SettingsTile(
              icon: AppIcons.share,
              tint: SettingsHues.abilities,
              title: '分享与对话回放',
              onTap: () => _push(context, const ShareScreen()),
            ),
          ],
        ),
        SettingsSection(
          title: '外观',
          children: [
            SettingsTile(
              icon: AppIcons.theme,
              tint: SettingsHues.appearance,
              title: '外观、配色与壁纸',
              value: Text(AppAccent.fromId(settings.accent).label),
              onTap: () => _push(context, const AppearancePage()),
            ),
            SettingsSegmentTile<double>(
              icon: AppIcons.textSize,
              tint: SettingsHues.appearance,
              title: '聊天字号',
              segments: [
                for (final (scale, label) in _chatTextScales)
                  PillSegment(scale, label),
              ],
              selected: settings.chatTextScale,
              onChanged: (scale) => unawaited(notifier.setChatTextScale(scale)),
            ),
            SettingsSwitchTile(
              icon: AppIcons.foldTurns,
              tint: SettingsHues.appearance,
              title: '完成后折叠思考与工具步骤',
              subtitle: '一轮回答结束后将过程收成单行摘要',
              value: settings.foldCompletedTurns,
              onChanged: (v) => unawaited(notifier.setFoldCompletedTurns(v)),
            ),
            SettingsTile(
              icon: AppIcons.pet,
              tint: SettingsHues.appearance,
              title: '星灵桌宠',
              value: Text(pet.showInApp ? '已显示' : '已隐藏'),
              onTap: () => _push(context, const PetSettingsPage()),
            ),
          ],
        ),
        SettingsSection(
          title: '通用',
          children: [
            SettingsSegmentTile<String>(
              icon: AppIcons.translate,
              tint: SettingsHues.general,
              title: '界面语言',
              segments: const [
                PillSegment('system', '跟随系统'),
                PillSegment('zh', '中文'),
                PillSegment('en', 'English'),
              ],
              selected: settings.localeCode,
              onChanged: (code) => unawaited(notifier.setLocaleCode(code)),
            ),
            SettingsTile(
              icon: AppIcons.notifications,
              tint: SettingsHues.general,
              title: '通知与胶囊提醒',
              value: Text(
                settings.liveActivityEnabled ||
                        settings.notifyOnApproval ||
                        settings.notifyOnTurnComplete
                    ? '已开启'
                    : '已关闭',
              ),
              onTap: () => _push(context, const NotificationSettingsPage()),
            ),
            SettingsSwitchTile(
              icon: AppIcons.tip,
              tint: SettingsHues.general,
              title: '模型运行时保持屏幕常亮',
              subtitle: '停留在 App 页面且模型思考/执行期间不自动熄屏，结束后恢复正常',
              value: settings.keepScreenOnWhileRunning,
              onChanged: (v) =>
                  unawaited(notifier.setKeepScreenOnWhileRunning(v)),
            ),
            SettingsSwitchTile(
              icon: AppIcons.sidebar,
              tint: SettingsHues.general,
              title: '右侧左滑快捷面板',
              subtitle: '在对话页向左轻滑打开快捷导航与会话控制',
              value: settings.quickPanelSwipe,
              onChanged: (v) => unawaited(notifier.setQuickPanelSwipe(v)),
            ),
            SettingsTile(
              icon: AppIcons.keepAlive,
              tint: SettingsHues.general,
              title: '后台保活与更新',
              value: Text(
                sys.device.ignoringBatteryOptimizations ? '已放行' : '建议设置',
                style: !sys.device.ignoringBatteryOptimizations
                    ? TextStyle(color: colors.warning)
                    : null,
              ),
              onTap: () => _push(context, const KeepAliveScreen()),
            ),
            SettingsTile(
              icon: AppIcons.systemAccess,
              tint: SettingsHues.general,
              title: '系统权限',
              subtitle: '存储、无障碍、悬浮窗与省电策略',
              onTap: () => _push(context, const SystemAccessPage()),
            ),
          ],
        ),
        SettingsSection(
          title: '主机',
          children: [
            SettingsTile(
              icon: AppIcons.engine,
              tint: SettingsHues.hosts,
              title: '本机引擎',
              value: StatusChip(tone: engineTone, label: engineLabel),
              onTap: () => _push(context, const EngineScreen()),
            ),
            SettingsTile(
              icon: AppIcons.remoteHosts,
              tint: SettingsHues.hosts,
              title: 'SSH 远程主机',
              value: hosts.sshHosts.isEmpty
                  ? null
                  : Text('${hosts.sshHosts.length} 台主机'),
              onTap: () => _push(context, const SshHostsScreen()),
            ),
          ],
        ),
        SettingsSection(
          title: '帮助与关于',
          children: [
            SettingsTile(
              icon: AppIcons.diagnostics,
              tint: SettingsHues.help,
              title: '诊断与日志',
              onTap: () => _push(context, const DiagnosticsPage()),
            ),
            SettingsTile(
              icon: AppIcons.info,
              tint: SettingsHues.help,
              title: '关于 AGY Go',
              value: Text(
                'v${sys.device.versionName}',
                style: AppType.tabular(Theme.of(context).textTheme.bodyMedium!),
              ),
              onTap: () => _push(context, const AboutPage()),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: AgyBrandMark(size: 18, color: colors.textDisabled),
          ),
        ),
      ],
    );
  }
}

/// Top overview card mirroring DSH Go's SettingsOverview (Auth + Live Engine footer).
class SettingsOverview extends ConsumerWidget {
  const SettingsOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final runtime = ref.watch(localRuntimeProvider);
    final hosts = ref.watch(hostsProvider);
    final st = runtime.status;
    final (tone, label) = _engineBadge(st);

    final isKey = settings.authMode == LocalAuthMode.geminiApiKey;
    final title = isKey
        ? (settings.hasApiKey ? 'Gemini API Key' : '未配置 API Key')
        : 'Google 账号登录';
    final subtitle = isKey
        ? (settings.hasApiKey ? _maskKey(settings.apiKey) : '点击配置 Gemini API Key 或切回 OAuth')
        : '通过官方 agy acp --login 在本机安全授权';

    return OverviewCard(
      leading: OverviewGlyph(
        isKey ? AppIcons.apiKey : AppIcons.account,
        tint: isKey ? 4 : 0,
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: isKey && settings.hasApiKey
            ? AppType.monoLabel(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ).copyWith(fontSize: 13)
            : null,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const EngineScreen()),
      ),
      footer: OverviewFooter(
        tone: tone,
        text: [
          hosts.active.isLocal ? '本机引擎' : hosts.activeLabel(),
          label,
          if (st.installedVersion != null) 'agy ${st.installedVersion}',
        ].join(' · '),
      ),
      onFooterTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const EngineScreen()),
      ),
    );
  }
}

/// Phone storage & workspace mounting page mirroring DSH Go's PhoneStorage mounting flow.
class PhoneStoragePage extends ConsumerStatefulWidget {
  const PhoneStoragePage({super.key});

  @override
  ConsumerState<PhoneStoragePage> createState() => _PhoneStoragePageState();
}

class _PhoneStoragePageState extends ConsumerState<PhoneStoragePage> {
  late final AppLifecycleListener _lifecycle;
  bool _pendingEnable = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_handleResume()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(localRuntimeProvider.notifier).refreshStorage());
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _handleResume() async {
    await ref.read(localRuntimeProvider.notifier).refreshStorage();
    if (!mounted) return;
    final granted = ref.read(localRuntimeProvider).storage.granted ||
        ref.read(localRuntimeProvider).status.phoneStorageGranted;
    if (_pendingEnable && granted) {
      _pendingEnable = false;
      await ref.read(localRuntimeProvider.notifier).setPhoneStorage(true);
      if (mounted) showBriefNotice(context, '已授权并开启手机存储挂载');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final runtime = ref.watch(localRuntimeProvider);
    final storage = runtime.storage;
    final st = runtime.status;
    final dsh = DshColors.of(context);

    final mountedNow = settings.phoneStorage && storage.granted;

    return AppPage.list(
      title: '手机存储挂载',
      subtitle: const Text('把手机共享存储挂载给本机 Antigravity CLI，参考 DSH Go 挂载机制'),
      children: [
        OverviewCard(
          leading: OverviewGlyph(
            AppIcons.phoneStorage,
            tint: mountedNow ? 4 : 7,
          ),
          title: Text(mountedNow ? '手机存储已挂载' : '手机存储未挂载'),
          subtitle: Text(
            mountedNow
                ? 'agy 可直接访问 /storage/emulated/0 与 ~/手机存储'
                : storage.granted
                ? '已获系统文件权限，开启下方开关即可挂载'
                : '需先向系统申请读写手机文件的权限',
          ),
          footer: OverviewFooter(
            tone: mountedNow
                ? StatusTone.ok
                : storage.granted
                ? StatusTone.idle
                : StatusTone.warn,
            text: storage.granted ? '系统文件权限：已授权' : '系统文件权限：未授权',
          ),
        ),
        SettingsSection(
          title: '挂载开关',
          footer: const Text(
            '开启后本机原生 Bionic 与 PRoot Ubuntu 都会同步创建「~/手机存储」快捷入口，并在「工作区管理」中允许直接挂载手机存储、下载、文档、相册等目录。',
          ),
          children: [
            SettingsSwitchTile(
              icon: AppIcons.fileAccess,
              tint: SettingsHues.ai,
              title: '允许 agy 访问手机文件',
              subtitle: '挂载 /storage/emulated/0 与 ~/手机存储',
              value: mountedNow,
              onChanged: (enabled) async {
                if (!enabled) {
                  _pendingEnable = false;
                  await ref
                      .read(localRuntimeProvider.notifier)
                      .setPhoneStorage(false);
                  if (context.mounted) {
                    showBriefNotice(context, '已关闭手机存储挂载');
                  }
                  return;
                }
                _pendingEnable = true;
                final ok = await ensurePhoneStorageMounted(context, ref);
                if (context.mounted && ok) {
                  _pendingEnable = false;
                  showBriefNotice(context, '已开启手机存储挂载');
                }
              },
            ),
            SettingsTile(
              icon: AppIcons.systemAccess,
              tint: SettingsHues.general,
              title: storage.granted ? '重新检查存储权限' : '请求系统存储权限',
              value: Text(
                storage.granted ? '已授权' : '未授权',
                style: TextStyle(
                  color: storage.granted ? dsh.success : dsh.warning,
                ),
              ),
              onTap: () async {
                final res = await ref
                    .read(localRuntimeProvider.notifier)
                    .requestStorage();
                if (context.mounted) {
                  showBriefNotice(
                    context,
                    res.granted ? '已获取手机存储权限' : '权限未授予，可尝试下方的「所有文件访问」',
                  );
                }
              },
            ),
            SettingsTile(
              icon: AppIcons.openExternal,
              tint: SettingsHues.general,
              title: 'Android 11+ 所有文件访问设置',
              subtitle: '若系统拦截非媒体文件，在此开启「所有文件访问权限」',
              onTap: () => unawaited(
                ref.read(localRuntimeProvider.notifier).openAllFilesAccess(),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: '挂载路径映射',
          children: [
            InfoRow(label: '手机共享存储', value: storage.hostPath, mono: true),
            InfoRow(
              label: '默认工作区',
              value: st.workspacePath ?? '~/workspace',
              mono: true,
            ),
            InfoRow(
              label: '运行模式',
              value: st.executionMode == 'proot'
                  ? 'PRoot (-b ${storage.hostPath}:${storage.guestPath})'
                  : 'Android 原生 Bionic (直通 + ~/手机存储)',
            ),
            SettingsTile(
              icon: AppIcons.workspace,
              tint: SettingsHues.ai,
              title: '管理已挂载的工作区目录',
              subtitle: '选择任意子文件夹作为对话工作区',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WorkspacesPage()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Appearance settings mirroring DSH Go's AppearancePage.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final brightness = Theme.of(context).brightness;

    return AppPage.list(
      title: '外观与配色',
      subtitle: const Text('雾面玻璃层次、OKLCH 主题色与动效'),
      children: [
        SettingsSection(
          title: '浅色与深色',
          children: [
            SettingsSegmentTile<ThemeMode>(
              icon: AppIcons.theme,
              tint: SettingsHues.appearance,
              title: '界面主题',
              segments: const [
                PillSegment(ThemeMode.system, '跟随系统'),
                PillSegment(ThemeMode.light, '浅色'),
                PillSegment(ThemeMode.dark, '深色'),
              ],
              selected: settings.themeMode,
              onChanged: (m) => unawaited(notifier.setThemeMode(m)),
            ),
          ],
        ),
        SettingsSection(
          title: '主题配色',
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in AppAccent.presets)
                    _AccentPill(
                      preset: preset,
                      color: preset.seedFor(brightness),
                      selected: preset.id == settings.accent.name,
                      onTap: () => unawaited(
                        notifier.setAccent(AppAccentId.parse(preset.id)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: '聊天壁纸',
          footer: const Text(
            '自定义图片会叠放在雾面玻璃底色之上，磨砂顶栏、抽屉和输入框会自动柔化背景细节。',
          ),
          children: [
            SettingsTile(
              icon: AppIcons.image,
              tint: SettingsHues.appearance,
              title: settings.wallpaperPath != null ? '更换聊天壁纸' : '选择聊天壁纸',
              subtitle: settings.wallpaperPath != null
                  ? settings.wallpaperPath!.split('/').last
                  : '从手机相册选择一张图片作为对话背景',
              onTap: () async {
                final picked = await ref
                    .read(systemToolsProvider.notifier)
                    .pickImage();
                if (picked != null && picked.path.isNotEmpty) {
                  await notifier.setWallpaperPath(picked.path);
                  if (context.mounted) {
                    showBriefNotice(context, '已应用聊天壁纸');
                  }
                }
              },
            ),
            if (settings.wallpaperPath != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '壁纸透明度',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider.adaptive(
                        value: settings.wallpaperOpacity,
                        min: 0.08,
                        max: 0.55,
                        onChanged: (v) =>
                            unawaited(notifier.setWallpaperOpacity(v)),
                      ),
                    ),
                    Text(
                      '${(settings.wallpaperOpacity * 100).round()}%',
                      style: AppType.monoLabel(
                        color: DshColors.of(context).textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              SettingsTile(
                icon: AppIcons.delete,
                tint: 3,
                title: '清除壁纸',
                onTap: () async {
                  await notifier.setWallpaperPath(null);
                  if (context.mounted) showBriefNotice(context, '已恢复默认雾面背景');
                },
              ),
            ],
          ],
        ),
        SettingsSection(
          title: '视觉与性能',
          children: [
            SettingsSwitchTile(
              icon: AppIcons.systemIsland,
              tint: SettingsHues.appearance,
              title: '隐藏顶部状态栏',
              subtitle: '沉浸隐藏顶部系统状态栏，从屏幕顶部下滑可临时呼出',
              value: settings.hideStatusBar,
              onChanged: (v) => unawaited(notifier.setHideStatusBar(v)),
            ),
            SettingsSwitchTile(
              icon: AppIcons.edgeGlow,
              tint: SettingsHues.appearance,
              title: '毛玻璃实时模糊',
              subtitle: '关闭后改用高透明纯色填充，降低低端机 GPU 负载',
              value: settings.glassBlur,
              onChanged: (v) => unawaited(notifier.setGlassBlur(v)),
            ),
            SettingsSwitchTile(
              icon: AppIcons.running,
              tint: SettingsHues.appearance,
              title: '流式灵动动效',
              subtitle: '抽屉视差、按压弹簧与页面跟随手势',
              value: settings.fluidMotion,
              onChanged: (v) => unawaited(notifier.setFluidMotion(v)),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccentPill extends StatelessWidget {
  const _AccentPill({
    required this.preset,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final AppAccent preset;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = AppShape.outlined(
      selected ? color : scheme.outlineVariant,
      radius: 14,
      width: selected ? 1.5 : 0.75,
    );
    return Pressable(
      child: Material(
        color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          AppIcons.done,
                          size: 10,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? preset.onSeedDark
                              : preset.onSeed,
                        )
                      : null,
                ),
                const SizedBox(width: 7),
                Text(
                  preset.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PermissionPage extends ConsumerWidget {
  const PermissionPage({super.key});

  IconData _permIcon(AgyToolPermission perm) => switch (perm) {
    AgyToolPermission.strict => AppIcons.safeMode,
    AgyToolPermission.requestReview => AppIcons.permissions,
    AgyToolPermission.proceedInSandbox => AppIcons.verified,
    AgyToolPermission.alwaysProceed => AppIcons.permissionRisky,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final dsh = DshColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isPlan = settings.agentMode == AgyAgentMode.plan;

    return AppPage.list(
      title: '权限层级',
      subtitle: const Text(
        '遵循 Antigravity 官方四级权限预设，同步写入 ~/.gemini/antigravity-cli/settings.json',
      ),
      children: [
        SettingsSection(
          title: 'Antigravity 官方权限预设',
          footer: const Text(
            '「完全放行」会在启动本机 agy 时附加 --dangerously-skip-permissions 并跳过常规工具审批；手机操控的银行/支付安全闸门仍独立强制生效。',
          ),
          children: [
            for (final perm in AgyToolPermission.values)
              ListPageRow(
                icon: _permIcon(perm),
                iconColor: perm.isHighRisk
                    ? dsh.danger
                    : (perm == settings.toolPermission ? scheme.primary : null),
                title: perm.label,
                subtitle: perm.description,
                subtitleMaxLines: 2,
                danger: perm.isHighRisk && perm == settings.toolPermission,
                trailing: Icon(
                  perm == settings.toolPermission
                      ? AppIcons.radioOn
                      : AppIcons.radioOff,
                  size: 20,
                  color: perm == settings.toolPermission
                      ? (perm.isHighRisk ? dsh.danger : scheme.primary)
                      : dsh.textTertiary,
                ),
                chevron: false,
                onTap: () async {
                  if (perm.isHighRisk && settings.toolPermission != perm) {
                    final confirmed = await confirmHighRiskAction(
                      context,
                      title: '将「完全放行」设为默认？',
                      body:
                          '开启后每次启动本机 Antigravity CLI 与新建对话都将跳过命令、改文件、联网和 MCP 的逐次确认。仅建议在受控工作区内启用。',
                      confirmLabel: '确认开启',
                    );
                    if (!confirmed) return;
                  }
                  await notifier.setToolPermission(perm);
                },
              ),
          ],
        ),
        SettingsSection(
          title: '工作流与细粒度规则',
          children: [
            SettingsSwitchTile(
              icon: AppIcons.planMode,
              tint: SettingsHues.ai,
              title: '默认开启计划模式（/plan）',
              subtitle: '只读调研并先输出实施方案，经你同意后再修改代码',
              value: isPlan,
              onChanged: (v) => unawaited(
                notifier.setAgentMode(
                  v ? AgyAgentMode.plan : AgyAgentMode.standard,
                ),
              ),
            ),
            SettingsSegmentTile<AgyQueuedMessageBehavior>(
              icon: AppIcons.queued,
              tint: SettingsHues.ai,
              title: '生成中再发消息',
              segments: const [
                PillSegment(AgyQueuedMessageBehavior.queue, '排队等本轮完'),
                PillSegment(AgyQueuedMessageBehavior.steer, '立即中断发送'),
              ],
              selected: settings.queuedBehavior,
              onChanged: (v) => unawaited(notifier.setQueuedBehavior(v)),
            ),
            SettingsSwitchTile(
              icon: AppIcons.folderOpen,
              tint: SettingsHues.ai,
              title: '允许访问工作区外目录',
              subtitle: '对应 settings.json 的 allowNonWorkspaceAccess',
              value: settings.allowNonWorkspaceAccess,
              onChanged: (v) => unawaited(notifier.setAllowNonWorkspaceAccess(v)),
            ),
            SettingsTile(
              icon: AppIcons.configure,
              tint: SettingsHues.ai,
              title: '高级规则（allow / ask / deny）',
              subtitle: '按命令、文件路径、域名与 MCP 工具精细控制 settings.json',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AgyEngineParamsPage(),
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: '手机操控安全闸门',
          children: [
            SettingsTile(
              icon: AppIcons.phoneControl,
              tint: SettingsHues.abilities,
              title: '手机操控 SafetyGate 三档规则',
              subtitle: '银行/支付/密码应用强制拦截设置',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PhoneControlScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Notification & Android 16+ Live Activity (capsule / island) settings, mirroring DSH Go.
class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.invalidate(liveActivityStatusProvider);
        unawaited(
          ref
              .read(liveActivityChannelProvider)
              .push(ref.read(liveActivityPushProvider)),
        );
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _openLiveSettings() async {
    final opened = await ref
        .read(liveActivityChannelProvider)
        .openLiveSettings();
    if (mounted && !opened) {
      showBriefNotice(context, '无法直接打开系统页面，请在系统设置中手动开启实时活动');
    }
  }

  Future<void> _openNotificationSettings() async {
    final opened = await ref
        .read(liveActivityChannelProvider)
        .openNotificationSettings();
    if (mounted && !opened) {
      showBriefNotice(context, '无法打开系统通知设置');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final liveAsync = ref.watch(liveActivityStatusProvider);
    final live = liveAsync.value;
    final dsh = DshColors.of(context);
    final theme = Theme.of(context);

    // Avoid flashing "不支持" before the system answers or on non-Android test hosts.
    final liveSupported = live == null || live.unknown || live.supported;
    final liveBlocked =
        settings.liveActivityEnabled &&
        live != null &&
        !live.unknown &&
        live.needsPromotionPermission;
    final systemNotifOff =
        live != null && !live.unknown && live.blockedBySystemNotifications;

    return AppPage.list(
      title: '通知与胶囊提醒',
      subtitle: const Text('实时活动胶囊、灵动岛 / 流体云进度展示，以及后台完成与审批提醒'),
      children: [
        if (systemNotifOff)
          _NotificationBanner(
            icon: AppIcons.notificationsOff,
            title: '系统通知已被关闭',
            text: '请先在系统设置中允许 AGY Go 发送通知，否则后台提醒与状态栏胶囊均无法显示。',
            actionLabel: '前往开启',
            onAction: () => unawaited(_openNotificationSettings()),
          ),
        if (liveBlocked)
          _NotificationBanner(
            icon: AppIcons.notificationsOff,
            title: '系统没有允许实时活动',
            text: '请在系统设置里为 AGY Go 打开「实时活动」（部分机型叫「在流体云中显示」或「超级岛通知」）。',
            actionLabel: '前往开启',
            onAction: () => unawaited(_openLiveSettings()),
          ),
        SettingsSection(
          title: '实时活动（胶囊通知）',
          footer: const Text(
            'Android 16 实时活动（Live Updates）：小米 HyperOS 3.1+（超级岛）、OPPO / 一加 ColorOS 16（流体云）、荣耀 MagicOS 10（灵动胶囊）和 Pixel 会自动放进状态栏胶囊或灵动岛；vivo 原子岛和三星 Now Bar 目前仅对厂商合作应用开放。',
          ),
          children: [
            SettingsSwitchTile(
              icon: AppIcons.providers,
              tint: SettingsHues.ai,
              title: '显示实时活动',
              subtitle: liveSupported
                  ? '干活、等你确认、操作手机时，显示在状态栏胶囊和锁屏上；支持的手机会自动进入灵动岛'
                  : '这台手机的系统还不支持 Android 16 实时活动（当前 API ${live.sdk}）',
              value: settings.liveActivityEnabled && liveSupported,
              onChanged: liveSupported
                  ? (v) => unawaited(notifier.setLiveActivityEnabled(v))
                  : null,
            ),
            if (live != null && !live.unknown)
              SettingsTile(
                icon: live.allowed
                    ? AppIcons.done
                    : live.supported
                    ? AppIcons.warning
                    : AppIcons.info,
                tint: live.allowed ? 4 : SettingsHues.general,
                title: '系统胶囊状态',
                value: Text(
                  live.allowed
                      ? (live.xiaomiFocus
                            ? '已就绪（HyperOS 焦点）'
                            : '已就绪（Live Updates）')
                      : live.supported
                      ? '待系统开启'
                      : '暂不支持',
                  style: TextStyle(
                    color: live.allowed
                        ? dsh.success
                        : live.supported
                        ? dsh.warning
                        : dsh.textTertiary,
                  ),
                ),
                onTap: live.supported
                    ? () => unawaited(_openLiveSettings())
                    : null,
              ),
          ],
        ),
        SettingsSection(
          title: '后台通知事件',
          footer: const Text(
            '仅在 AGY Go 退到后台或锁屏时推送常规系统提醒；前台聊天时不会打扰。',
          ),
          children: [
            SettingsSwitchTile(
              icon: AppIcons.approval,
              tint: 3,
              title: '等待审批确认时高优提醒',
              subtitle: '工具执行或命令需要你点击允许时发出高优先级通知',
              value: settings.notifyOnApproval,
              onChanged: (v) => unawaited(notifier.setNotifyOnApproval(v)),
            ),
            SettingsSwitchTile(
              icon: AppIcons.notificationsOn,
              tint: SettingsHues.general,
              title: '长任务回复完成提醒',
              subtitle: '一轮生成结束后推送完成通知',
              value: settings.notifyOnTurnComplete,
              onChanged: (v) => unawaited(notifier.setNotifyOnTurnComplete(v)),
            ),
          ],
        ),
        SettingsSection(
          title: '系统设置与调试',
          footer: Text(
            '锁屏隐藏敏感内容时，系统只显示脱敏摘要（如「AGY Go 正在干活」），不会暴露对话标题与内容。',
            style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
          ),
          children: [
            SettingsTile(
              icon: AppIcons.configure,
              tint: SettingsHues.general,
              title: '打开系统实时活动设置',
              subtitle: '在系统设置中放行「实时活动 / 流体云 / 超级岛」开关',
              onTap: () => unawaited(_openLiveSettings()),
            ),
            SettingsTile(
              icon: AppIcons.notifications,
              tint: SettingsHues.general,
              title: '打开系统通知设置',
              subtitle: '管理通知渠道、横幅和锁屏显示方式',
              onTap: () => unawaited(_openNotificationSettings()),
            ),
            SettingsTile(
              icon: AppIcons.providers,
              tint: SettingsHues.ai,
              title: '发送测试胶囊通知（10 秒）',
              subtitle: '立即在状态栏胶囊 / 灵动岛预览实时活动效果',
              onTap: () async {
                final accentColor =
                    AppAccent.fromId(settings.accent).seed.toARGB32();
                final ok = await ref
                    .read(liveActivityChannelProvider)
                    .preview(accentColor: accentColor);
                if (!context.mounted) return;
                if (ok) {
                  showBriefNotice(context, '已发送 10 秒实时活动胶囊，可下拉或切回桌面查看');
                } else {
                  showBriefNotice(
                    context,
                    live?.supported == true
                        ? '系统尚未允许实时活动，请先点击上方「前往开启」'
                        : '当前系统不支持实时活动胶囊（需 Android 16+ 或 HyperOS 焦点权限）',
                  );
                }
              },
            ),
            SettingsTile(
              icon: AppIcons.notificationsOn,
              tint: SettingsHues.general,
              title: '发送测试普通通知',
              subtitle: '检查常规通知栏提醒与权限是否正常放行',
              onTap: () async {
                await ref.read(systemToolsProvider.notifier).notifyTurnEvent(
                  title: 'AGY Go 通知测试',
                  body: '当后台任务完成或等待审批时，你将收到类似提醒。',
                  urgent: false,
                );
                if (context.mounted) showBriefNotice(context, '已发送测试通知');
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.icon,
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: AppShape.radiusLg,
        style: DshSurfaces.of(context).card.copyWith(
          hairline: dsh.warning.withValues(alpha: 0.45),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: dsh.warning),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: dsh.textTertiary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: dsh.warning,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(AppIcons.forward, size: 15),
                      onPressed: onAction,
                      label: Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceSettingsPage extends ConsumerWidget {
  const VoiceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceProvider);
    return AppPage.list(
      title: '语音与朗读',
      subtitle: const Text('调用 Android 系统语音识别听写与系统 TTS 朗读'),
      children: [
        SettingsSection(
          title: '语音测试',
          children: [
            SettingsTile(
              icon: AppIcons.readAloud,
              tint: SettingsHues.abilities,
              title: voice.isSpeaking ? '停止测试朗读' : '试听语音朗读',
              subtitle: '验证 Android 系统 TTS 引擎是否就绪',
              onTap: () {
                final ctrl = ref.read(voiceProvider.notifier);
                if (voice.isSpeaking) {
                  ctrl.stopSpeaking();
                } else {
                  ctrl.speak('你好，AGY Go 语音朗读已准备就绪。');
                }
              },
            ),
            SettingsTile(
              icon: AppIcons.voice,
              tint: SettingsHues.abilities,
              title: voice.isListening ? '停止语音听写' : '测试语音听写',
              subtitle: voice.error ?? '在聊天输入框右侧直接点击麦克风即可听写',
              onTap: () => ref.read(voiceProvider.notifier).toggleListening(),
            ),
          ],
        ),
      ],
    );
  }
}

/// Unified system permissions overview mirroring DSH Go's SystemAccessPage.
class SystemAccessPage extends ConsumerStatefulWidget {
  const SystemAccessPage({super.key});

  @override
  ConsumerState<SystemAccessPage> createState() => _SystemAccessPageState();
}

class _SystemAccessPageState extends ConsumerState<SystemAccessPage> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    unawaited(ref.read(localRuntimeProvider.notifier).refreshStorage());
    unawaited(ref.read(phoneControlProvider.notifier).refresh());
    unawaited(ref.read(petSettingsProvider.notifier).refreshPermission());
    unawaited(ref.read(systemToolsProvider.notifier).refreshDeviceInfo());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(localRuntimeProvider.select((r) => r.storage));
    final phone = ref.watch(phoneControlProvider);
    final pet = ref.watch(petSettingsProvider);
    final dev = ref.watch(systemToolsProvider.select((s) => s.device));
    final dsh = DshColors.of(context);

    Widget badge(bool ok, {String on = '已开启', String off = '未开启'}) => Text(
      ok ? on : off,
      style: TextStyle(color: ok ? dsh.success : dsh.warning),
    );

    return AppPage.list(
      title: '系统权限',
      subtitle: const Text('各项本机功能所需的 Android 系统授权状态'),
      children: [
        SettingsSection(
          title: '读写手机文件',
          children: [
            SettingsTile(
              icon: AppIcons.fileAccess,
              tint: SettingsHues.ai,
              title: '允许访问手机存储',
              subtitle: '将 /storage/emulated/0 挂载给工作区',
              value: badge(storage.granted, on: '已授权', off: '未授权'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PhoneStoragePage(),
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: '手机操控与桌宠',
          children: [
            SettingsTile(
              icon: AppIcons.accessibility,
              tint: SettingsHues.abilities,
              title: '无障碍服务',
              subtitle: '供 MCP 手机操控读屏与手势执行使用',
              value: badge(phone.accessibilityConnected),
              onTap: () => ref
                  .read(phoneControlProvider.notifier)
                  .openAccessibilitySettings(),
            ),
            SettingsTile(
              icon: AppIcons.overlayPermission,
              tint: SettingsHues.appearance,
              title: '显示在其他应用上层',
              subtitle: '供星灵桌面悬浮球使用',
              value: badge(pet.canDrawOverlays),
              onTap: () => ref
                  .read(petSettingsProvider.notifier)
                  .requestOverlayPermission(),
            ),
          ],
        ),
        SettingsSection(
          title: '后台持续运行',
          children: [
            SettingsTile(
              icon: AppIcons.keepAlive,
              tint: SettingsHues.general,
              title: '忽略电池优化',
              subtitle: '避免切到后台时系统中断本机 agy 进程',
              value: badge(dev.ignoringBatteryOptimizations, on: '已放行', off: '受限制'),
              onTap: () => ref
                  .read(systemToolsProvider.notifier)
                  .requestIgnoreBatteryOptimization(),
            ),
          ],
        ),
      ],
    );
  }
}

class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(localRuntimeProvider);
    final dsh = DshColors.of(context);
    final logs = runtime.logs.join('\n');

    return AppPage.list(
      title: '诊断与日志',
      subtitle: const Text('所有引擎输出均已自动脱敏凭据与密钥'),
      actions: [
        GlassIconButton(
          icon: AppIcons.copy,
          tooltip: '复制日志',
          onPressed: logs.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: logs));
                  showBriefNotice(context, '已复制脱敏日志');
                },
        ),
      ],
      children: [
        SettingsSection(
          title: '本机运行摘要',
          children: [
            InfoRow(label: '阶段', value: runtime.status.phase.name, mono: true),
            InfoRow(label: '架构', value: runtime.status.abi, mono: true),
            InfoRow(
              label: '模式',
              value: runtime.status.executionMode,
              mono: true,
            ),
            InfoRow(
              label: 'agy 版本',
              value: runtime.status.installedVersion ?? '未安装',
              mono: true,
            ),
            InfoRow(
              label: '存储权限',
              value: runtime.storage.granted ? 'granted' : 'denied',
              mono: true,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: dsh.codeWellBg,
              shape: AppShape.outlined(dsh.codeWellBorder, radius: 16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: logs.isEmpty
                  ? Text(
                      '暂无日志输出。启动或安装本机引擎后将在此实时显示。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: dsh.textTertiary,
                      ),
                    )
                  : SelectableText(
                      logs,
                      style: AppType.monoSmall(
                        color: dsh.codeWellFg,
                      ).copyWith(fontSize: 11.5),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sys = ref.watch(systemToolsProvider);
    final dev = sys.device;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);

    return AppPage.list(
      title: '关于 AGY Go',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              AgyBrandMark(size: 54, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('AGY Go', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'v${dev.versionName} (build ${dev.versionCode})',
                style: AppType.tabular(
                  theme.textTheme.bodySmall!.copyWith(color: dsh.textTertiary),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '面向 Google Antigravity CLI 的手机本机 & SSH 远程原生客户端。直连官方二进制与官方 ACP 协议，零反代、零转发。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dsh.textTertiary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: '开源与致谢',
          children: [
            const InfoRow(label: '开源协议', value: 'GNU AGPL-3.0'),
            const InfoRow(label: 'UI 与工作区参考', value: 'DSH Go (AGPL-3.0)'),
            const InfoRow(label: '图标与等宽字体', value: 'Phosphor (MIT) · JetBrains Mono'),
            SettingsTile(
              icon: AppIcons.openLink,
              tint: SettingsHues.help,
              title: 'GitHub 仓库',
              subtitle: 'Kailian5922/agy-go',
              onTap: () => unawaited(
                launchUrl(
                  Uri.parse('https://github.com/Kailian5922/agy-go'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
            SettingsTile(
              icon: AppIcons.checkUpdate,
              tint: SettingsHues.help,
              title: '检查应用更新',
              subtitle: '查询最新版本并在应用内下载安装',
              onTap: () => unawaited(showUpdateSheet(context, ref)),
            ),
          ],
        ),
      ],
    );
  }
}

/// In-app update sheet checking GitHub latest release & invoking Android APK installer.
Future<void> showUpdateSheet(BuildContext context, WidgetRef ref) {
  unawaited(ref.read(systemToolsProvider.notifier).checkAppUpdate());
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => const _UpdateSheetBody(),
  );
}

class _UpdateSheetBody extends ConsumerWidget {
  const _UpdateSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sys = ref.watch(systemToolsProvider);
    final rel = sys.latestRelease;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader('检查应用更新'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '当前版本：v${sys.device.versionName} (build ${sys.device.versionCode})',
                    style: AppType.monoLabel(color: dsh.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  if (sys.checkingUpdate)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    )
                  else if (sys.updateError != null)
                    Text(
                      '检查失败：${sys.updateError}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: dsh.danger,
                      ),
                    )
                  else if (rel != null) ...[
                    Text(
                      rel.isNewer ? '发现新版本 ${rel.tagName}' : '当前已是最新版本',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (rel.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        rel.releaseNotes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: dsh.textTertiary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (rel.isNewer && rel.apkUrl != null)
                      FilledButton.icon(
                        icon: sys.installingUpdate
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(AppIcons.download, size: 18),
                        label: Text(sys.installingUpdate ? '下载安装中…' : '下载并安装更新'),
                        onPressed: sys.installingUpdate
                            ? null
                            : () => unawaited(
                                ref
                                    .read(systemToolsProvider.notifier)
                                    .downloadAndInstallUpdate(),
                              ),
                      )
                    else
                      OutlinedButton.icon(
                        icon: const Icon(AppIcons.refresh, size: 17),
                        label: const Text('重新检查'),
                        onPressed: () => unawaited(
                          ref
                              .read(systemToolsProvider.notifier)
                              .checkAppUpdate(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
