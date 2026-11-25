import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_strings.dart';
import '../../state/settings_state.dart';
import '../pet/starling_pet.dart';
import '../phone/phone_control_screen.dart';
import '../share/share_screen.dart';
import '../shell/page_frame.dart';
import '../system/keep_alive_screen.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';
import '../workspace/workspace_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);
    final s = AppStrings.of(context);

    return AgyPage(
      title: s.t('设置与外观', 'Settings & Appearance'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('外观与主题', 'Appearance'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(s.t('跟随系统', 'System')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(s.t('浅色', 'Light')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(s.t('深色', 'Dark')),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (set) =>
                      ref.read(settingsProvider.notifier).setThemeMode(set.first),
                ),
                const SizedBox(height: 16),
                Text(
                  s.t('主题配色', 'Accent Color'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final spec in AccentSpec.all)
                      _AccentSwatch(
                        spec: spec,
                        selected: spec.id == settings.accent,
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setAccent(spec.id),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  s.t('界面语言', 'Language'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('跟随系统')),
                    ButtonSegment(value: 'zh', label: Text('简体中文')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {settings.localeCode},
                  onSelectionChanged: (set) => ref
                      .read(settingsProvider.notifier)
                      .setLocaleCode(set.first),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('毛玻璃实时模糊效果', 'Frosted Glass Blur')),
                  subtitle: Text(
                    s.t(
                      '关闭后改为高透明纯色填充，降低低端机 GPU 开销',
                      'Disable real-time blur for lower GPU usage on older devices',
                    ),
                  ),
                  value: settings.glassBlur,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setGlassBlur(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('本机引擎行为', 'Local Engine'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('打开 App 自动启动本机引擎', 'Auto-start local engine')),
                  subtitle: Text(
                    s.t(
                      '检测到已安装 agy 二进制时自动在后台拉起 ACP 服务',
                      'Automatically start on-device agy acp when installed',
                    ),
                  ),
                  value: settings.autoStartLocalEngine,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setAutoStartLocalEngine(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('全部功能模块', 'Capabilities & Tools'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _SettingLink(
                  icon: Icons.folder_open_rounded,
                  title: s.t('工作区文件管理', 'Workspace Files'),
                  subtitle: s.t('浏览与编辑本机或 SSH SFTP 文件', 'Local & SSH SFTP browser/editor'),
                  onTap: () => _open(context, const WorkspaceScreen()),
                ),
                _SettingLink(
                  icon: Icons.touch_app_rounded,
                  title: s.t('MCP 手机操控与安全门', 'MCP Phone Control & SafetyGate'),
                  subtitle: s.t('无障碍读屏点按、三档确认与紧急停止', 'Accessibility tools, 3-tier confirmations, emergency stop'),
                  onTap: () => _open(context, const PhoneControlScreen()),
                ),
                _SettingLink(
                  icon: Icons.auto_awesome_rounded,
                  title: s.t('桌宠与伙伴（星灵）', 'Starling Pet & Overlay'),
                  subtitle: s.t('App 内悬浮伴侣与系统桌面悬浮球', 'In-app & system overlay companion'),
                  onTap: () => _open(context, const PetSettingsScreen()),
                ),
                _SettingLink(
                  icon: Icons.ios_share_rounded,
                  title: s.t('分享卡、导出与对话回放', 'Share Cards, Export & Replay'),
                  subtitle: s.t('自动脱敏 PNG 卡片、Markdown 与 JSON 回放', 'Redacted PNG cards, Markdown & JSON replay'),
                  onTap: () => _open(context, const ShareScreen()),
                ),
                _SettingLink(
                  icon: Icons.shield_moon_outlined,
                  title: s.t('后台保活与 App 自更新', 'Keep-Alive & Self-Update'),
                  subtitle: s.t('国产 ROM 省电豁免与 GitHub Release APK 更新', 'OEM autostart helper & GitHub APK updater'),
                  onTap: () => _open(context, const KeepAliveAndUpdateScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final AccentSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? spec.darkPrimary
        : spec.lightPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : AgySurfaces.of(context).hairline,
            width: selected ? 1.5 : 0.75,
          ),
          color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(spec.label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _SettingLink extends StatelessWidget {
  const _SettingLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 21),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: surfaces.subtleText,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}
