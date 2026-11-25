// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/workspaces_state.dart';
import '../common/status_dot.dart';
import '../theme/theme.dart';
import 'drawer_destination.dart';

/// Right-edge quick panel pulled over chat by a leftward swipe, mirroring DSH Go's QuickPanel.
class QuickPanel extends ConsumerWidget {
  const QuickPanel({
    super.key,
    required this.motion,
    required this.onOpen,
    this.sessionId,
  });

  final Animation<double> motion;
  final ValueChanged<DrawerDestination> onOpen;
  final String? sessionId;

  static const width = 264.0;
  static const conversationWidth = 304.0;

  static const _radius = BorderRadius.only(
    topLeft: Radius.circular(AppShape.xl),
    bottomLeft: Radius.circular(AppShape.xl),
  );

  static const _defaultItems = <DrawerDestination>[
    DrawerDestination.engine,
    DrawerDestination.workspaces,
    DrawerDestination.files,
    DrawerDestination.remote,
    DrawerDestination.terminal,
    DrawerDestination.phone,
    DrawerDestination.pet,
    DrawerDestination.share,
    DrawerDestination.keepAlive,
    DrawerDestination.features,
    DrawerDestination.settings,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final chat = ref.watch(chatProvider);
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider).status;
    final cwd = ref.watch(effectiveWorkingDirProvider);
    final hasSession = sessionId != null;

    final content = Material(
      type: MaterialType.transparency,
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Semantics(
                header: true,
                child: Text(
                  hasSession ? '当前对话与快捷入口' : '快捷入口',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            if (hasSession)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: GlassSurface(
                  tier: GlassTier.card,
                  borderRadius: AppShape.radiusMd,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusDot(
                            tone: chat.isBusy ? StatusTone.busy : StatusTone.ok,
                            size: 7,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hosts.activeLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayWorkspacePath(
                          chat.sessionCwd ?? cwd,
                          local: hosts.active.isLocal,
                          homePath: runtime.homePath,
                          storageRoot: runtime.phoneStoragePath,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.monoLabel(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final destination in _defaultItems)
                    _QuickRow(
                      destination: destination,
                      onTap: () => onOpen(destination),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 13),
              child: Text(
                '右滑打开会话抽屉 · 左滑打开快捷入口',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return SlidingGlass(
      motion: motion,
      tier: GlassTier.sheet,
      borderRadius: _radius,
      child: content,
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.destination, required this.onTap});

  final DrawerDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('quick-panel-${destination.name}'),
      onTap: onTap,
      customBorder: Squircle.border(AppShape.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(
                destination.icon,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
