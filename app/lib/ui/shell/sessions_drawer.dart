import 'package:agy_remote/agy_remote.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../runtime/runtime_models.dart';
import '../../state/chat_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../engine/engine_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../settings/settings_screen.dart';
import '../terminal/terminal_screen.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Left sessions & navigation drawer, usable both as a swipe overlay and docked tablet sidebar.
class SessionsDrawer extends ConsumerWidget {
  const SessionsDrawer({
    super.key,
    this.onClose,
    this.docked = false,
  });

  final VoidCallback? onClose;
  final bool docked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider);
    final sessions = ref.watch(sessionsProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    final body = SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.65),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AGY Go',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        hosts.activeLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: surfaces.subtleText,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '新建对话',
                  icon: const Icon(Icons.edit_square, size: 20),
                  onPressed: () {
                    ref.read(chatProvider.notifier).startNewChat();
                    onClose?.call();
                  },
                ),
              ],
            ),
          ),

          // Quick host switcher strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: HairlineCard(
              padding: const EdgeInsets.all(6),
              borderRadius: BorderRadius.circular(14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _HostChip(
                      label: '本机引擎',
                      selected: hosts.active.isLocal,
                      dotColor: runtime.status.isRunning
                          ? surfaces.success
                          : surfaces.warning,
                      onTap: () => ref
                          .read(hostsProvider.notifier)
                          .selectHost(const HostRef.local()),
                    ),
                    for (final ssh in hosts.sshHosts) ...[
                      const SizedBox(width: 6),
                      _HostChip(
                        label: ssh.name,
                        selected: !hosts.active.isLocal && hosts.active.id == ssh.id,
                        dotColor: theme.colorScheme.primary,
                        onTap: () => ref
                            .read(hostsProvider.notifier)
                            .selectHost(HostRef.ssh(ssh.id)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Sessions list
          Expanded(
            child: sessions.loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : sessions.sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '暂无历史对话\n发送一条消息即可创建新会话',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: surfaces.subtleText,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: sessions.sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = sessions.sessions[index];
                      final selected = item.sessionId == sessions.currentSessionId;
                      return HairlineCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        backgroundColor: selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.14)
                            : null,
                        borderColor: selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.45)
                            : null,
                        onTap: () {
                          ref
                              .read(sessionsProvider.notifier)
                              .selectSession(item.sessionId);
                          onClose?.call();
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title?.isNotEmpty == true
                                        ? item.title!
                                        : '会话 ${item.sessionId.substring(0, item.sessionId.length.clamp(0, 8))}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.cwd,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: surfaces.subtleText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 17,
                                color: surfaces.subtleText,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ref
                                  .read(sessionsProvider.notifier)
                                  .deleteSession(item.sessionId),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              children: [
                _NavTile(
                  icon: Icons.memory_rounded,
                  title: '本机引擎',
                  trailingText: switch (runtime.status.phase) {
                    RuntimePhase.running => '运行中',
                    RuntimePhase.installing => '安装中',
                    RuntimePhase.installed => '就绪',
                    RuntimePhase.starting => '启动中',
                    RuntimePhase.notInstalled => '未安装',
                    _ => '异常',
                  },
                  onTap: () => _push(context, const EngineScreen()),
                ),
                _NavTile(
                  icon: Icons.dns_rounded,
                  title: 'SSH 远程主机',
                  trailingText: '${hosts.sshHosts.length} 台',
                  onTap: () => _push(context, const SshHostsScreen()),
                ),
                _NavTile(
                  icon: Icons.terminal_rounded,
                  title: '终端',
                  onTap: () => _push(context, const TerminalScreen()),
                ),
                _NavTile(
                  icon: Icons.tune_rounded,
                  title: '设置与外观',
                  onTap: () => _push(context, const SettingsScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (docked) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: surfaces.hairline, width: 0.75),
          ),
        ),
        child: body,
      );
    }

    return GlassSurface(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
      child: body,
    );
  }

  void _push(BuildContext context, Widget page) {
    onClose?.call();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _HostChip extends StatelessWidget {
  const _HostChip({
    required this.label,
    required this.selected,
    required this.dotColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color dotColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: surfaces.subtleText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
