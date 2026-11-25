import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../runtime/runtime_models.dart';
import '../../state/runtime_state.dart';
import '../../state/settings_state.dart';
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Manages the on-device Android Antigravity CLI runtime, installation, auth, and live logs.
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
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    final phaseColor = switch (st.phase) {
      RuntimePhase.running => surfaces.success,
      RuntimePhase.installing || RuntimePhase.starting => surfaces.warning,
      RuntimePhase.error => surfaces.danger,
      _ => surfaces.subtleText,
    };

    final phaseText = switch (st.phase) {
      RuntimePhase.notInstalled => '未安装',
      RuntimePhase.installing => '安装中',
      RuntimePhase.installed => '已安装（未运行）',
      RuntimePhase.starting => '启动中',
      RuntimePhase.running => '运行中 (:${st.port ?? '-'})',
      RuntimePhase.stopping => '停止中',
      RuntimePhase.error => '异常',
    };

    return AgyPage(
      title: '本机引擎（Android）',
      actions: [
        IconButton(
          tooltip: '检查 agy 更新',
          onPressed: runtime.checkingUpdate
              ? null
              : () => ref.read(localRuntimeProvider.notifier).checkUpdate(),
          icon: runtime.checkingUpdate
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          // Runtime overview & lifecycle controls
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '运行状态',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    StatusPill(label: phaseText, dotColor: phaseColor),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoRow(label: '设备架构', value: st.abi),
                _InfoRow(
                  label: '运行模式',
                  value: st.executionMode == 'proot'
                      ? 'PRoot Ubuntu Linux'
                      : 'Android 原生 Bionic（免 PRoot）',
                ),
                _InfoRow(
                  label: '已装版本',
                  value: st.installedVersion ?? '未安装',
                ),
                if (runtime.updateCheck != null)
                  _InfoRow(
                    label: '官方最新',
                    value:
                        '${runtime.updateCheck!.latestVersion}${runtime.updateCheck!.updateAvailable ? '（可更新）' : '（最新）'}',
                  ),
                if (st.workspacePath != null)
                  _InfoRow(label: '工作区', value: st.workspacePath!),
                if (st.phase == RuntimePhase.installing &&
                    runtime.progress != null) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: runtime.progress!.fraction.clamp(0.0, 1.0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    runtime.progress!.detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: surfaces.subtleText,
                    ),
                  ),
                ],
                if (st.error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    st.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: surfaces.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (st.phase == RuntimePhase.running)
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            ref.read(localRuntimeProvider.notifier).stop(),
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: const Text('停止引擎'),
                      )
                    else if (st.installedVersion != null)
                      FilledButton.icon(
                        onPressed: st.phase.isBusy
                            ? null
                            : () =>
                                ref.read(localRuntimeProvider.notifier).start(),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('启动引擎'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: st.phase.isBusy
                          ? null
                          : () => ref
                              .read(localRuntimeProvider.notifier)
                              .installOrUpdate(),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        st.installedVersion == null ? '安装官方 agy' : '更新 / 重装',
                      ),
                    ),
                    if (st.installedVersion != null)
                      OutlinedButton.icon(
                        onPressed: st.phase.isBusy
                            ? null
                            : () => ref
                                .read(localRuntimeProvider.notifier)
                                .reset(keepHome: true),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('重置二进制'),
                      ),
                  ],
                ),
                if (st.prootAvailable) ...[
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('优先使用 PRoot Ubuntu Linux 容器'),
                    subtitle: const Text('需要运行完整 apt/git/python 环境时开启'),
                    value: st.preferProot,
                    onChanged: (v) => ref
                        .read(localRuntimeProvider.notifier)
                        .setPreferProot(v),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Authentication configuration card
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '认证方式',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<LocalAuthMode>(
                  segments: const [
                    ButtonSegment(
                      value: LocalAuthMode.oauth,
                      label: Text('Google 账号'),
                      icon: Icon(Icons.account_circle_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: LocalAuthMode.geminiApiKey,
                      label: Text('Gemini API Key'),
                      icon: Icon(Icons.key_rounded, size: 18),
                    ),
                  ],
                  selected: {_draftAuthMode},
                  onSelectionChanged: (set) {
                    setState(() => _draftAuthMode = set.first);
                  },
                ),
                const SizedBox(height: 14),
                if (_draftAuthMode == LocalAuthMode.oauth) ...[
                  Text(
                    '通过官方 `agy acp --login` 在系统浏览器中完成 Google 账号授权，凭据保存在本机私密目录。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: surfaces.subtleText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
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
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('开始 Google 登录'),
                      ),
                    ],
                  ),
                  if (runtime.pendingOAuthUrl != null) ...[
                    const SizedBox(height: 12),
                    HairlineCard(
                      padding: const EdgeInsets.all(12),
                      borderColor: theme.colorScheme.primary.withValues(alpha: 0.45),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '已获取 Google 授权链接',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () => launchUrl(
                              Uri.parse(runtime.pendingOAuthUrl!),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                            label: const Text('在浏览器打开登录页'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _oauthCodeCtrl,
                            decoration: const InputDecoration(
                              labelText: '粘贴浏览器显示的授权码',
                              hintText: '完成登录后复制授权码粘贴于此',
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
                            },
                            child: const Text('提交授权码'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
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
                      labelText: '自定义端点（可选 GOOGLE_GEMINI_BASE_URL）',
                      hintText: '留空使用官方默认地址',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      await ref.read(settingsProvider.notifier).setAuthConfig(
                        mode: LocalAuthMode.geminiApiKey,
                        apiKey: _apiKeyCtrl.text,
                        customBaseUrl: _baseUrlCtrl.text,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已保存认证配置；如引擎正在运行请重启生效。'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存 API Key 配置'),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Live runtime log panel
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '引擎日志（已自动脱敏）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 120, maxHeight: 280),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E17),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: surfaces.hairline),
                  ),
                  child: runtime.logs.isEmpty
                      ? const Text(
                          '暂无日志输出。',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        )
                      : SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            runtime.logs.join('\n'),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.45,
                              color: Color(0xFFD6E2F5),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: surfaces.subtleText,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
