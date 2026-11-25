import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings_state.dart';
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return AgyPage(
      title: '设置与外观',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '外观与主题',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) =>
                      ref.read(settingsProvider.notifier).setThemeMode(s.first),
                ),
                const SizedBox(height: 16),
                Text(
                  '主题配色',
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
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('毛玻璃实时模糊效果'),
                  subtitle: const Text('关闭后改为高透明纯色填充，降低低端机 GPU 开销'),
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
                  '本机引擎行为',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('打开 App 自动启动本机引擎'),
                  subtitle: const Text('检测到已安装 agy 二进制时自动在后台拉起 ACP 服务'),
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
                  '后续阶段规划（Roadmap）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const _RoadmapItem(
                  phase: 'Phase 3',
                  title: 'MCP 手机操控（无障碍 / Shizuku + SafetyGate）',
                  detail: '本地标准 MCP Server 直连 agy，支持读屏、点按、三档安全确认与敏感页拦截。',
                ),
                const SizedBox(height: 8),
                const _RoadmapItem(
                  phase: 'Phase 4',
                  title: '语音通话 · 原创桌宠 · 对话分享 · 自更新',
                  detail: '端上 VAD 语音对话、悬浮桌宠、加密对话回放链接与国产 ROM 后台保活引导。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

class _RoadmapItem extends StatelessWidget {
  const _RoadmapItem({
    required this.phase,
    required this.title,
    required this.detail,
  });

  final String phase;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$phase · $title',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: surfaces.subtleText,
          ),
        ),
      ],
    );
  }
}
