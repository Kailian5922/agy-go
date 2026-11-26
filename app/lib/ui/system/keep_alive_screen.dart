// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/settings_state.dart';
import '../../state/system_state.dart';
import '../common/overview_card.dart';
import '../common/settings_widgets.dart';
import '../common/status_dot.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

/// Chinese ROM background keep-alive assistant & GitHub Release APK updater.
class KeepAliveScreen extends ConsumerWidget {
  const KeepAliveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sys = ref.watch(systemToolsProvider);
    final keepScreenOn = ref.watch(
      settingsProvider.select((s) => s.keepScreenOnWhileRunning),
    );
    final dev = sys.device;
    final dsh = DshColors.of(context);

    return AppPage.list(
      title: '保活与更新',
      subtitle: const Text('国产 ROM 省电豁免引导与 GitHub 版本检查'),
      actions: [
        GlassIconButton(
          icon: AppIcons.refresh,
          tooltip: '刷新状态',
          onPressed: () =>
              ref.read(systemToolsProvider.notifier).refreshDeviceInfo(),
        ),
      ],
      children: [
        OverviewCard(
          leading: OverviewGlyph(
            AppIcons.keepAlive,
            tint: dev.ignoringBatteryOptimizations ? 4 : 3,
          ),
          title: Text(
            dev.ignoringBatteryOptimizations ? '已忽略电池优化' : '当前受省电策略限制',
          ),
          subtitle: Text(
            '${dev.manufacturer} ${dev.model} · Android API ${dev.sdkInt}',
          ),
          footer: OverviewFooter(
            tone: dev.ignoringBatteryOptimizations
                ? StatusTone.ok
                : StatusTone.warn,
            text: dev.ignoringBatteryOptimizations
                ? '切后台时不易被系统回收'
                : '建议放行后台运行以避免任务中断',
          ),
        ),
        SettingsSection(
          title: '前台常亮与后台保活',
          footer: Text(_vendorHint(dev.manufacturer)),
          children: [
            SettingsSwitchTile(
              icon: AppIcons.tip,
              tint: 3,
              title: '模型运行时保持屏幕常亮',
              subtitle: '停留在 App 页面且模型思考/执行期间不自动熄屏，结束后自动恢复',
              value: keepScreenOn,
              onChanged: (v) => unawaited(
                ref
                    .read(settingsProvider.notifier)
                    .setKeepScreenOnWhileRunning(v),
              ),
            ),
            SettingsTile(
              icon: AppIcons.highPower,
              tint: 4,
              title: '申请无限制后台运行',
              subtitle: '向系统请求忽略 AGY Go 的电池优化',
              onTap: () => ref
                  .read(systemToolsProvider.notifier)
                  .requestIgnoreBatteryOptimization(),
            ),
            SettingsTile(
              icon: AppIcons.autostart,
              tint: 5,
              title: '打开厂商自启动与省电设置',
              subtitle: '适配 HyperOS / 鸿蒙 / ColorOS / OriginOS',
              onTap: () => ref
                  .read(systemToolsProvider.notifier)
                  .openVendorBackgroundSettings(),
            ),
          ],
        ),
        SettingsSection(
          title: '应用更新',
          footer: sys.updateError != null
              ? Text(sys.updateError!, style: TextStyle(color: dsh.danger))
              : sys.latestRelease != null &&
                    sys.latestRelease!.releaseNotes.isNotEmpty
              ? Text(sys.latestRelease!.releaseNotes)
              : null,
          children: [
            InfoRow(
              label: '当前版本',
              value: 'v${dev.versionName} (build ${dev.versionCode})',
              mono: true,
            ),
            if (sys.latestRelease != null)
              InfoRow(
                label: '最新版本',
                value: sys.latestRelease!.isNewer
                    ? '${sys.latestRelease!.tagName}（可更新）'
                    : '${sys.latestRelease!.tagName}（最新）',
              ),
            SettingsTile(
              icon: AppIcons.checkUpdate,
              tint: 0,
              title: sys.checkingUpdate ? '正在检查…' : '检查 GitHub 更新',
              onTap: sys.checkingUpdate
                  ? null
                  : () => ref
                        .read(systemToolsProvider.notifier)
                        .checkAppUpdate(),
            ),
            if (sys.latestRelease?.isNewer == true &&
                sys.latestRelease?.apkUrl != null)
              SettingsTile(
                icon: AppIcons.download,
                tint: 4,
                title: sys.installingUpdate ? '正在下载 APK…' : '下载并安装新版本',
                onTap: sys.installingUpdate
                    ? null
                    : () => ref
                          .read(systemToolsProvider.notifier)
                          .downloadAndInstallUpdate(),
              ),
          ],
        ),
      ],
    );
  }

  String _vendorHint(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return '小米 / HyperOS 建议：开启「自启动」，省电策略选「无限制」，并在多任务界面下拉加锁。';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return '华为 / 荣耀建议：在「应用启动管理」关闭自动管理，手动允许自启动、关联启动与后台活动。';
    }
    if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme')) {
      return 'OPPO / 一加 / ColorOS 建议：允许「自启动」并开启「允许完全后台行为」，在多任务界面加锁。';
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return 'vivo / iQOO 建议：在「后台耗电管理」设为「允许后台高耗电」，并开启应用自启动。';
    }
    return '建议在系统电池设置中将 AGY Go 设为「不受限制」，避免切后台时中断正在运行的本机 agy 任务。';
  }
}

typedef KeepAliveAndUpdateScreen = KeepAliveScreen;
