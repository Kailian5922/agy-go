// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:agy_remote/agy_remote.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/hosts_state.dart';
import '../common/app_sheet.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/segmented_pill.dart';
import '../common/status_chip.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

class SshHostsScreen extends ConsumerWidget {
  const SshHostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostsProvider);

    return AppPage.list(
      title: 'SSH 远程主机',
      subtitle: const Text('通过 SSH exec 通道直接连接电脑或服务器上的 agy acp'),
      actions: [
        GlassIconButton(
          icon: AppIcons.add,
          tooltip: '添加主机',
          onPressed: () => _openEditor(context),
        ),
      ],
      children: [
        if (hosts.sshHosts.isEmpty)
          EmptyView(
            icon: AppIcons.sshHost,
            title: '还没有远程主机',
            message: '添加 Mac、Linux 电脑或云服务器后，即可随时切换连接远端 Antigravity CLI',
            action: FilledButton.icon(
              onPressed: () => _openEditor(context),
              icon: const Icon(AppIcons.add, size: 18),
              label: const Text('添加 SSH 主机'),
            ),
          )
        else
          ListPageCard(
            children: [
              for (final h in hosts.sshHosts)
                ListPageRow(
                  icon: AppIcons.sshHost,
                  title: h.name,
                  subtitle: '${h.authority} · ${h.agyCommand} acp',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!hosts.active.isLocal && hosts.active.id == h.id)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: StatusChip(tone: StatusTone.ok, label: '当前'),
                        ),
                      IconButton(
                        icon: const Icon(AppIcons.edit, size: 18),
                        tooltip: '编辑',
                        onPressed: () => _openEditor(context, existing: h),
                      ),
                      IconButton(
                        icon: Icon(
                          AppIcons.delete,
                          size: 18,
                          color: DshColors.of(context).danger,
                        ),
                        tooltip: '删除',
                        onPressed: () => ref
                            .read(hostsProvider.notifier)
                            .deleteSshHost(h.id),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await ref
                        .read(hostsProvider.notifier)
                        .selectHost(HostRef.ssh(h.id));
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, {SshHostConfig? existing}) {
    return showAppSheet<void>(
      context,
      isScrollControlled: true,
      builder: (_) => _SshHostEditorSheet(existing: existing),
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(widget.existing == null ? '添加 SSH 主机' : '编辑 SSH 主机'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：家里 Mac / 实验室服务器',
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
              SegmentedPill<SshAuthMethod>(
                expand: true,
                segments: const [
                  PillSegment(SshAuthMethod.password, '密码认证'),
                  PillSegment(SshAuthMethod.privateKey, '私钥 PEM'),
                ],
                selected: _authMethod,
                onChanged: (m) => setState(() => _authMethod = m),
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
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
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
      workingDirectory: _cwdCtrl.text.trim().isEmpty
          ? null
          : _cwdCtrl.text.trim(),
      agyCommand: _agyCmdCtrl.text.trim().isEmpty
          ? 'agy'
          : _agyCmdCtrl.text.trim(),
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
