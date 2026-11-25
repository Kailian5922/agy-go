import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../engine/engine_screen.dart';
import '../remote/ssh_hosts_screen.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';
import 'chat_list.dart';
import 'composer_bar.dart';
import 'permission_card.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({
    super.key,
    required this.showDrawerButton,
    required this.onOpenDrawer,
    required this.onOpenQuickPanel,
  });

  final bool showDrawerButton;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenQuickPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostsProvider);
    final connAsync = ref.watch(activeConnectionProvider);
    final chat = ref.watch(
      chatProvider.select(
        (s) => (
          title: s.transcript.title,
          isBusy: s.isBusy,
          permissions: s.pendingPermissions,
          error: s.error,
          authRequired: s.authRequired,
        ),
      ),
    );

    final surfaces = AgySurfaces.of(context);
    final connected = connAsync.value != null;
    final dotColor = connected
        ? surfaces.success
        : connAsync.isLoading
        ? surfaces.warning
        : connAsync.hasError
        ? surfaces.danger
        : surfaces.subtleText;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: ChatList(
                onPickSuggestion: (text) =>
                    ref.read(chatProvider.notifier).send(text),
              ),
            ),
            if (chat.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: HairlineCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  borderColor: surfaces.danger.withValues(alpha: 0.45),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: surfaces.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          chat.error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: surfaces.danger),
                        ),
                      ),
                      if (chat.authRequired)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const EngineScreen(),
                            ),
                          ),
                          child: const Text('去认证'),
                        ),
                    ],
                  ),
                ),
              ),
            for (final perm in chat.permissions)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: PermissionCard(
                  pending: perm,
                  onSelect: (optId) => ref
                      .read(chatProvider.notifier)
                      .respondPermission(perm, optId),
                  onCancel: () => ref
                      .read(chatProvider.notifier)
                      .respondPermission(perm, null),
                ),
              ),
            ComposerBar(
              enabled: connected,
              isBusy: chat.isBusy,
              onSend: (text) => ref.read(chatProvider.notifier).send(text),
              onCancel: () => ref.read(chatProvider.notifier).cancel(),
            ),
          ],
        ),

        // Floating frosted-glass top header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    if (showDrawerButton)
                      IconButton(
                        icon: const Icon(Icons.menu_rounded, size: 22),
                        tooltip: '会话与导航',
                        onPressed: onOpenDrawer,
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Center(
                        child: StatusPill(
                          label: chat.title?.isNotEmpty == true
                              ? '${hosts.activeLabel()} · ${chat.title}'
                              : hosts.activeLabel(),
                          dotColor: dotColor,
                          trailing: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: surfaces.subtleText,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => hosts.active.isLocal
                                  ? const EngineScreen()
                                  : const SshHostsScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, size: 21),
                      tooltip: '会话控制',
                      onPressed: onOpenQuickPanel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
