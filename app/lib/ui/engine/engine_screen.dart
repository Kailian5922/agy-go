// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../runtime/runtime_models.dart';
import '../../state/runtime_state.dart';
import '../../state/settings_state.dart';
import '../common/brief_notice.dart';
import '../common/overview_card.dart';
import '../common/settings_widgets.dart';
import '../common/status_dot.dart';
import '../settings/settings_screen.dart' show PhoneStoragePage;
import '../shell/page_frame.dart';
import '../system/keep_alive_screen.dart';
import '../theme/theme.dart';

/// Manages the on-device Android Antigravity CLI runtime, installation, auth,
/// storage mounting link, and live redacted logs in DSH Go's Mist Glass design.
class EngineScreen extends ConsumerStatefulWidget {
  const EngineScreen({super.key});

  @override
  ConsumerState<EngineScreen> createState() => _EngineScreenState();
}

class _EngineScreenState extends ConsumerState<EngineScreen> {
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _oauthCodeCtrl = TextEditingController();
  LocalAuthMode _draftAuthMode = LocalAuthMode.oauth;
  bool _initialized = false;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _oauthCodeCtrl.dispose();
    super.dispose();
  }

  void _syncFromSettings(AppSettings settings) {
    if (_initialized || !settings.loaded) return;
    _initialized = true;
    _draftAuthMode = settings.authMode;
    _apiKeyCtrl.text = settings.apiKey;
    _baseUrlCtrl.text = settings.customBaseUrl;
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(localRuntimeProvider);
    final settings = ref.watch(settingsProvider);
    _syncFromSettings(settings);

    final st = runtime.status;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);

    final tone = switch (st.phase) {
      RuntimePhase.running => StatusTone.ok,
      RuntimePhase.installing || RuntimePhase.starting => StatusTone.busy,
      RuntimePhase.error => StatusTone.error,
      RuntimePhase.notInstalled => StatusTone.warn,
      _ => StatusTone.idle,
    };

    final phaseText = switch (st.phase) {
      RuntimePhase.notInstalled => '未安装官方 agy',
      RuntimePhase.installing => '正在安装本机引擎…',
      RuntimePhase.installed => '已安装（未运行）',
      RuntimePhase.starting => '正在启动本机引擎…',
      RuntimePhase.running => '运行中 (127.0.0.1:${st.port ?? '-'})',
      RuntimePhase.stopping => '正在停止…',
      RuntimePhase.error => st.error ?? '引擎启动异常',
    };

    return AppPage.list(
      title: '本机引擎',
      subtitle: const Text('直接在本机运行官方 Google Antigravity CLI（免 Root）'),
      actions: [
        GlassIconButton(
          icon: AppIcons.refresh,
          tooltip: '检查 agy 更新',
          onPressed: runtime.checkingUpdate
              ? null
              : () => ref.read(localRuntimeProvider.notifier).checkUpdate(),
        ),
      ],
      children: [
        OverviewCard(
          leading: OverviewGlyph(
            AppIcons.engine,
            tint: st.phase == RuntimePhase.running ? 4 : 0,
          ),
          title: const Text('Antigravity CLI'),
          subtitle: Text(
            phaseText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: st.phase == RuntimePhase.error
                ? TextStyle(color: dsh.danger)
                : null,
          ),
          footer: OverviewFooter(
            tone: tone,
            text: [
              st.abi,
              st.executionMode == 'proot' ? 'PRoot Ubuntu' : '原生 Bionic',
              if (st.installedVersion != null) 'v${st.installedVersion}',
            ].join(' · '),
          ),
        ),

        if (st.phase == RuntimePhase.installing && runtime.progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: runtime.progress!.fraction.clamp(0.0, 1.0),
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 6),
                Text(
                  runtime.progress!.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dsh.textTertiary,
                  ),
                ),
              ],
            ),
          ),

        // Equal-width action capsules matching DSH Go's EngineActions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: st.phase == RuntimePhase.running
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () =>
                            ref.read(localRuntimeProvider.notifier).stop(),
                        icon: const Icon(AppIcons.stop, size: 17),
                        label: const Text('停止'),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: st.phase.isBusy
                            ? null
                            : () {
                                if (st.installedVersion == null) {
                                  ref
                                      .read(localRuntimeProvider.notifier)
                                      .installOrUpdate();
                                } else {
                                  ref
                                      .read(localRuntimeProvider.notifier)
                                      .start();
                                }
                              },
                        icon: Icon(
                          st.installedVersion == null
                              ? AppIcons.download
                              : AppIcons.play,
                          size: 17,
                        ),
                        label: Text(
                          st.installedVersion == null ? '安装 agy' : '启动',
                        ),
                      ),
              ),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: st.phase.isBusy
                      ? null
                      : () => ref
                            .read(localRuntimeProvider.notifier)
                            .installOrUpdate(),
                  icon: const Icon(AppIcons.download, size: 17),
                  label: Text(st.installedVersion == null ? '检查源' : '更新/重装'),
                ),
              ),
              if (st.installedVersion != null)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: st.phase.isBusy
                        ? null
                        : () => ref
                              .read(localRuntimeProvider.notifier)
                              .reset(keepHome: true),
                    icon: const Icon(AppIcons.restart, size: 17),
                    label: const Text('重置'),
                  ),
                ),
            ],
          ),
        ),

        SettingsSection(
          title: '启动与挂载',
          children: [
            SettingsSwitchTile(
              icon: AppIcons.running,
              tint: 0,
              title: '打开 App 时自动启动本机引擎',
              value: settings.autoStartLocalEngine,
              onChanged: (v) => unawaited(
                ref.read(settingsProvider.notifier).setAutoStartLocalEngine(v),
              ),
            ),
            if (st.prootAvailable)
              SettingsSwitchTile(
                icon: AppIcons.terminal,
                tint: 5,
                title: '优先使用 PRoot Ubuntu Linux 容器',
                subtitle: '需要 apt/git/python 完整用户态时开启',
                value: st.preferProot,
                onChanged: (v) => unawaited(
                  ref.read(localRuntimeProvider.notifier).setPreferProot(v),
                ),
              ),
            SettingsTile(
              icon: AppIcons.phoneStorage,
              tint: 4,
              title: '手机存储挂载',
              value: Text(
                settings.phoneStorage && runtime.storage.granted ? '已挂载' : '未挂载',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PhoneStoragePage(),
                ),
              ),
            ),
            SettingsTile(
              icon: AppIcons.keepAlive,
              tint: 5,
              title: '后台保活引导',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const KeepAliveScreen(),
                ),
              ),
            ),
          ],
        ),

        // Authentication section
        SettingsSection(
          title: '账号与认证',
          children: [
            SettingsSegmentTile<LocalAuthMode>(
              icon: AppIcons.apiKey,
              tint: 0,
              title: '认证方式',
              segments: const [
                PillSegment(LocalAuthMode.oauth, 'Google 账号'),
                PillSegment(LocalAuthMode.geminiApiKey, 'API Key'),
              ],
              selected: _draftAuthMode,
              onChanged: (mode) => setState(() => _draftAuthMode = mode),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: _draftAuthMode == LocalAuthMode.oauth
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '调用官方 `agy acp --login` 在系统浏览器完成 Google 账号授权，凭据仅存于本机应用私有目录。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.textTertiary,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: st.installedVersion == null
                              ? null
                              : () async {
                                  await ref
                                      .read(settingsProvider.notifier)
                                      .setAuthConfig(
                                        mode: LocalAuthMode.oauth,
                                        apiKey: _apiKeyCtrl.text,
                                        customBaseUrl: _baseUrlCtrl.text,
                                      );
                                  await ref
                                      .read(localRuntimeProvider.notifier)
                                      .startOAuthLogin();
                                },
                          icon: const Icon(AppIcons.openLink, size: 17),
                          label: const Text('开始 Google 登录'),
                        ),
                        if (runtime.pendingOAuthUrl != null) ...[
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () => launchUrl(
                              Uri.parse(runtime.pendingOAuthUrl!),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(AppIcons.openExternal, size: 17),
                            label: const Text('在浏览器打开登录页'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _oauthCodeCtrl,
                            decoration: const InputDecoration(
                              labelText: '粘贴浏览器显示的授权码',
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: () async {
                              final code = _oauthCodeCtrl.text.trim();
                              if (code.isEmpty) return;
                              await ref
                                  .read(localRuntimeProvider.notifier)
                                  .submitOAuthCode(code);
                              _oauthCodeCtrl.clear();
                              if (context.mounted) {
                                showBriefNotice(context, '已提交授权码');
                              }
                            },
                            child: const Text('提交授权码'),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _apiKeyCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'GEMINI_API_KEY',
                            hintText: 'AIza...',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _baseUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: '自定义端点（可选）',
                            hintText: '留空使用官方默认地址',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(settingsProvider.notifier)
                                .setAuthConfig(
                                  mode: LocalAuthMode.geminiApiKey,
                                  apiKey: _apiKeyCtrl.text,
                                  customBaseUrl: _baseUrlCtrl.text,
                                );
                            if (context.mounted) {
                              showBriefNotice(context, '已保存，重启引擎后生效');
                            }
                          },
                          icon: const Icon(AppIcons.done, size: 17),
                          label: const Text('保存 API Key 配置'),
                        ),
                      ],
                    ),
            ),
          ],
        ),

        // Runtime info
        SettingsSection(
          title: '运行环境',
          children: [
            InfoRow(
              label: '已装版本',
              value: st.installedVersion ?? '未安装',
              mono: true,
            ),
            if (runtime.updateCheck != null)
              InfoRow(
                label: '官方最新',
                value:
                    '${runtime.updateCheck!.latestVersion}${runtime.updateCheck!.updateAvailable ? '（可更新）' : '（最新）'}',
              ),
            InfoRow(label: '设备架构', value: st.abi, mono: true),
            if (st.workspacePath != null)
              InfoRow(label: '默认工作区', value: st.workspacePath!, mono: true),
          ],
        ),

        // Terminal log card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    Text(
                      '引擎日志（已脱敏）',
                      style: SettingsSection.titleStyle(context),
                    ),
                    const Spacer(),
                    if (runtime.logs.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: runtime.logs.join('\n')),
                          );
                          showBriefNotice(context, '已复制日志');
                        },
                        child: Text(
                          '复制',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: dsh.codeWellBg,
                  shape: AppShape.outlined(dsh.codeWellBorder, radius: 16),
                ),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 140,
                    maxHeight: 280,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: runtime.logs.isEmpty
                      ? Text(
                          '暂无日志输出。',
                          style: AppType.monoSmall(color: dsh.textTertiary),
                        )
                      : SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            runtime.logs.join('\n'),
                            style: AppType.monoSmall(
                              color: dsh.codeWellFg,
                            ).copyWith(fontSize: 11.5),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
