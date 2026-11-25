// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../runtime/runtime_models.dart';
import '../../state/hosts_state.dart';
import '../../state/pet_state.dart';
import '../../state/phone_state.dart';
import '../../state/runtime_state.dart';
import '../../state/settings_state.dart';
import '../../state/system_state.dart';
import '../../state/voice_state.dart';
import '../../state/workspaces_state.dart';
import '../common/brief_notice.dart';
import '../common/overview_card.dart';
import '../common/pressable.dart';
import '../common/settings_widgets.dart';
import '../common/status_chip.dart';
import '../engine/engine_screen.dart';
import '../pet/starling_pet.dart';
import '../phone/phone_control_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../share/share_screen.dart';
import '../shell/brand_mark.dart';
import '../shell/page_frame.dart';
import '../system/keep_alive_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';

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
/// Overview card (Auth + live engine footer), then six hue-grouped sections.
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
    final wsCount = ref.watch(workspacesProvider.select((w) => w.workspaces.length));
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

    return AppPage.list(
      title: '设置',
      children: [
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
              icon: AppIcons.permissions,
              tint: SettingsHues.ai,
              title: '命令与工具权限',
              value: Text(
                settings.autoApproveCommands ? '自动批准' : '标准审批',
                style: settings.autoApproveCommands
                    ? TextStyle(color: colors.warning)
                    : null,
              ),
              onTap: () => _push(context, const PermissionPage()),
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
              title: '外观与配色',
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

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(
        ref.read(localRuntimeProvider.notifier).refreshStorage(),
      ),
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
            '开启后本机原生 Bionic 与 PRoot Ubuntu 都会同步创建「~/手机存储」快捷入口，并在「工作区管理」中允许直接浏览和挂载任意子目录。如引擎正在运行，请重启引擎以刷新 PRoot 绑定。',
          ),
          children: [
            SettingsSwitchTile(
              icon: AppIcons.fileAccess,
              tint: SettingsHues.ai,
              title: '允许 agy 访问手机文件',
              subtitle: '挂载 /storage/emulated/0 与 ~/手机存储',
              value: settings.phoneStorage,
              onChanged: (enabled) async {
                if (enabled && !storage.granted) {
                  final updated = await ref
                      .read(localRuntimeProvider.notifier)
                      .requestStorage();
                  if (!updated.granted) {
                    if (context.mounted) {
                      showBriefNotice(context, '请先授予存储权限');
                    }
                    return;
                  }
                }
                await ref
                    .read(localRuntimeProvider.notifier)
                    .setPhoneStorage(enabled);
                if (context.mounted) {
                  showBriefNotice(
                    context,
                    enabled ? '已开启手机存储挂载' : '已关闭手机存储挂载',
                  );
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
          title: '视觉与性能',
          children: [
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoApprove = ref.watch(
      settingsProvider.select((s) => s.autoApproveCommands),
    );
    return AppPage.list(
      title: '命令与工具权限',
      subtitle: const Text('控制 Antigravity CLI 执行命令与文件改动前的确认策略'),
      children: [
        SettingsSection(
          title: '默认审批策略',
          footer: const Text(
            '标准审批会在运行命令、删除或写文件前弹出确认卡，保障手机与工作区安全；开启自动批准后，所有常规 ACP 权限请求将自动放行（手机操控的高风险拦截闸门始终独立生效）。',
          ),
          children: [
            SettingsSwitchTile(
              icon: autoApprove
                  ? AppIcons.permissionRisky
                  : AppIcons.permissions,
              tint: autoApprove ? 3 : SettingsHues.ai,
              title: '自动批准命令与工具调用',
              subtitle: autoApprove ? '已开启：无需逐次确认（注意安全）' : '已关闭：高危操作前逐次确认',
              value: autoApprove,
              onChanged: (v) => unawaited(
                ref.read(settingsProvider.notifier).setAutoApproveCommands(v),
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
              subtitle: '查看保活引导与 GitHub 更新',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const KeepAliveScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
