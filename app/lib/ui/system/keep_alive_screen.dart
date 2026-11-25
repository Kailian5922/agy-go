import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/system_state.dart';
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Chinese ROM background keep-alive assistant & GitHub Release APK self-updater.
class KeepAliveAndUpdateScreen extends ConsumerWidget {
  const KeepAliveAndUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sys = ref.watch(systemToolsProvider);
    final dev = sys.device;
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return AgyPage(
      title: '后台保活与更新',
      actions: [
        IconButton(
          tooltip: '刷新状态',
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () =>
              ref.read(systemToolsProvider.notifier).refreshDeviceInfo(),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          // ROM Background Protection Card
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '后台保活与省电豁免',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    StatusPill(
                      label: dev.ignoringBatteryOptimizations
                          ? '已忽略电池优化'
                          : '受省电策略限制',
                      dotColor: dev.ignoringBatteryOptimizations
                          ? surfaces.success
                          : surfaces.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '设备：${dev.manufacturer} ${dev.model} (Android API ${dev.sdkInt})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _vendorHint(dev.manufacturer),
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(systemToolsProvider.notifier)
                          .requestIgnoreBatteryOptimization(),
                      icon: const Icon(Icons.battery_saver_rounded, size: 18),
                      label: const Text('申请无限制后台'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(systemToolsProvider.notifier)
                          .openVendorBackgroundSettings(),
                      icon: const Icon(Icons.settings_applications_rounded, size: 18),
                      label: const Text('打开厂商自启动设置'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Self-update card
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AGY Go 应用自更新',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前版本：v${dev.versionName} (build ${dev.versionCode})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
                if (sys.latestRelease != null) ...[
                  const SizedBox(height: 10),
                  HairlineCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sys.latestRelease!.isNewer
                              ? '发现新版本：${sys.latestRelease!.tagName}'
                              : '已是最新版本 (${sys.latestRelease!.tagName})',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: sys.latestRelease!.isNewer
                                ? theme.colorScheme.primary
                                : surfaces.success,
                          ),
                        ),
                        if (sys.latestRelease!.releaseNotes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            sys.latestRelease!.releaseNotes,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: surfaces.subtleText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (sys.updateError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sys.updateError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: surfaces.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: sys.checkingUpdate
                          ? null
                          : () => ref
                              .read(systemToolsProvider.notifier)
                              .checkAppUpdate(),
                      icon: const Icon(Icons.system_update_rounded, size: 18),
                      label: Text(sys.checkingUpdate ? '检查中…' : '检查 GitHub 更新'),
                    ),
                    if (sys.latestRelease?.isNewer == true &&
                        sys.latestRelease?.apkUrl != null)
                      FilledButton.icon(
                        onPressed: sys.installingUpdate
                            ? null
                            : () => ref
                                .read(systemToolsProvider.notifier)
                                .downloadAndInstallUpdate(),
                        icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                        label: Text(
                          sys.installingUpdate ? '正在下载 APK…' : '下载并安装更新',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _vendorHint(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return '小米 / HyperOS 建议：开启「自启动」，并在省电策略中选择「无限制」，最近任务卡片下拉加锁。';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return '华为 / 荣耀建议：在「应用启动管理」关闭自动管理，手动允许自启动、关联启动与后台活动。';
    }
    if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme')) {
      return 'OPPO / 一加 / ColorOS 建议：允许「自启动」并开启「允许完全后台行为」，在多任务界面锁定卡片。';
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return 'vivo / iQOO 建议：在「后台耗电管理」设为「允许后台高耗电」，并开启应用自启动。';
    }
    return '建议在系统电池设置中将 AGY Go 设为「不受限制」，避免切后台时系统中断正在运行的本机 agy 任务。';
  }
}
