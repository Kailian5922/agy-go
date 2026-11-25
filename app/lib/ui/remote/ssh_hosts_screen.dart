import 'package:agy_remote/agy_remote.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/hosts_state.dart';
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

class SshHostsScreen extends ConsumerWidget {
  const SshHostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostsProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return AgyPage(
      title: 'SSH 远程主机',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加主机'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
        children: [
          HairlineCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              '通过 SSH exec 通道直接启动远端电脑/服务器上的 `agy acp`，无需在远端开放额外端口。密码和私钥仅保存在系统安全存储中。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: surfaces.subtleText,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (hosts.sshHosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  '尚未添加 SSH 主机\n点击右下角「添加主机」配置电脑或服务器',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: surfaces.subtleText,
                  ),
                ),
              ),
            )
          else
            for (final h in hosts.sshHosts) ...[
              _SshHostTile(
                config: h,
                isActive: !hosts.active.isLocal && hosts.active.id == h.id,
                onActivate: () async {
                  await ref
                      .read(hostsProvider.notifier)
                      .selectHost(HostRef.ssh(h.id));
                  if (context.mounted) Navigator.of(context).pop();
                },
                onEdit: () => _openEditor(context, ref, existing: h),
                onDelete: () =>
                    ref.read(hostsProvider.notifier).deleteSshHost(h.id),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    SshHostConfig? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SshHostEditorSheet(existing: existing),
    );
  }
}

class _SshHostTile extends StatelessWidget {
  const _SshHostTile({
    required this.config,
    required this.isActive,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  final SshHostConfig config;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return HairlineCard(
      onTap: onActivate,
      borderColor: isActive
          ? theme.colorScheme.primary.withValues(alpha: 0.55)
          : null,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.dns_rounded,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        config.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      StatusPill(label: '当前', dotColor: surfaces.success),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${config.authority} · ${config.agyCommand} acp',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.subtleText,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 19),
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 19, color: surfaces.danger),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _SshHostEditorSheet extends ConsumerStatefulWidget {
  const _SshHostEditorSheet({this.existing});

  final SshHostConfig? existing;

  @override
  ConsumerState<_SshHostEditorSheet> createState() =>
      _SshHostEditorSheetState();
}

class _SshHostEditorSheetState extends ConsumerState<_SshHostEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController();
  final _cwdCtrl = TextEditingController();
  final _agyCmdCtrl = TextEditingController(text: 'agy');
  final _passwordCtrl = TextEditingController();
  final _privateKeyCtrl = TextEditingController();
  final _passphraseCtrl = TextEditingController();
  SshAuthMethod _authMethod = SshAuthMethod.password;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _hostCtrl.text = e.host;
      _portCtrl.text = '${e.port}';
      _userCtrl.text = e.username;
      _cwdCtrl.text = e.workingDirectory ?? '';
      _agyCmdCtrl.text = e.agyCommand;
      _authMethod = e.authMethod;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _cwdCtrl.dispose();
    _agyCmdCtrl.dispose();
    _passwordCtrl.dispose();
    _privateKeyCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? '添加 SSH 主机' : '编辑 SSH 主机',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：家里 Mac / 实验室 GPU 服务器',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: '主机地址',
                        hintText: '192.168.1.10 或域名',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '端口'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<SshAuthMethod>(
                segments: const [
                  ButtonSegment(
                    value: SshAuthMethod.password,
                    label: Text('密码'),
                  ),
                  ButtonSegment(
                    value: SshAuthMethod.privateKey,
                    label: Text('私钥 PEM'),
                  ),
                ],
                selected: {_authMethod},
                onSelectionChanged: (s) => setState(() => _authMethod = s.first),
              ),
              const SizedBox(height: 10),
              if (_authMethod == SshAuthMethod.password)
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.existing == null ? '密码' : '密码（留空保持不变）',
                  ),
                )
              else ...[
                TextField(
                  controller: _privateKeyCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'SSH 私钥 (OpenSSH / PEM)',
                    hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passphraseCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '私钥口令（可选）'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _cwdCtrl,
                decoration: const InputDecoration(
                  labelText: '默认工作目录（可选）',
                  hintText: '留空自动使用远端 \$HOME',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _agyCmdCtrl,
                decoration: const InputDecoration(
                  labelText: 'agy 命令路径',
                  hintText: 'agy',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _save,
                child: const Text('保存主机'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final host = _hostCtrl.text.trim();
    final user = _userCtrl.text.trim();
    if (host.isEmpty || user.isEmpty) return;

    final id = widget.existing?.id ??
        'ssh_${DateTime.now().microsecondsSinceEpoch}';
    final config = SshHostConfig(
      id: id,
      name: _nameCtrl.text.trim().isEmpty ? host : _nameCtrl.text.trim(),
      host: host,
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      username: user,
      authMethod: _authMethod,
      workingDirectory: _cwdCtrl.text.trim().isEmpty ? null : _cwdCtrl.text.trim(),
      agyCommand: _agyCmdCtrl.text.trim().isEmpty ? 'agy' : _agyCmdCtrl.text.trim(),
      pinnedHostKeySha256: widget.existing?.pinnedHostKeySha256,
    );

    final secrets = SshHostSecrets(
      password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
      privateKeyPem: _privateKeyCtrl.text.trim().isEmpty
          ? null
          : _privateKeyCtrl.text.trim(),
      passphrase: _passphraseCtrl.text.isEmpty ? null : _passphraseCtrl.text,
    );

    await ref.read(hostsProvider.notifier).saveSshHost(config, secrets: secrets);
    if (mounted) Navigator.of(context).pop();
  }
}
