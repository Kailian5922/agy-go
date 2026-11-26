// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:agy_remote/agy_remote.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../runtime/runtime_models.dart';
import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/drawer_view_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_sheet.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/row_marks.dart';
import '../common/smooth_size.dart';
import '../common/status_dot.dart';
import '../remote/ssh_hosts_screen.dart';
import '../share/share_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';
import 'brand_mark.dart';
import 'drawer/drawer_actions.dart';
import 'drawer/drawer_filter_bar.dart';
import 'drawer/drawer_list.dart';
import 'drawer/selection_bars.dart';
import 'drawer_destination.dart';
import 'session_search_page.dart';

export '../../state/drawer_view_state.dart' show SessionDay, sessionDayOf;
export 'drawer/session_tile.dart' show SessionTile;
export 'drawer_destination.dart';

/// Soft fill behind the current conversation (drawer and search).
Color sessionSelectionColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.primary.withValues(
    alpha: scheme.brightness == Brightness.dark ? 0.18 : 0.09,
  );
}

/// 1:1 port of DSH Go's left sessions drawer:
/// - Brand lockup + sole primary-colored solid 「新对话」 pill (swaps to
///   [DrawerSelectionHeader] in multi-select)
/// - [SessionSearchBar] 40dp glass pill
/// - Single-row [WorkspaceSwitcher] (scope selector, NOT a nested tree) +
///   [DrawerViewButton] (`···` options sheet)
/// - [DrawerFilterBar] (`全部 / 运行中 / 待确认 / 未读` ink-selected chips)
/// - Edge-faded [DrawerConversationList] (`置顶 → 可折叠自定义文件夹 → 今天/昨天/本周/更早`)
/// - Footer [IdentityBar] (overlaid in-place by [SelectionActionBar] with zero height jump)
class SessionsDrawer extends ConsumerWidget {
  const SessionsDrawer({
    super.key,
    required this.onClose,
    required this.onOpen,
    this.now,
    this.drawerMotion,
  });

  final VoidCallback onClose;
  final ValueChanged<DrawerDestination> onOpen;

  /// Clock override for day-grouping in tests.
  final DateTime? now;

  /// Pull-over drawer animation (null when permanently docked).
  final Animation<double>? drawerMotion;

  /// Outer inset for search bar, row highlights, and footer controls.
  static const contentEdge = 10.0;

  static const _compactHeight = 480.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void newChat() {
      ref.read(pendingSessionFolderProvider.notifier).select(null);
      ref.read(chatProvider.notifier).startNewChat();
      onClose();
    }

    void manageWorkspaces() => onOpen(DrawerDestination.workspaces);

    final selecting = ref.watch(
      drawerSelectionProvider.select((s) => s != null),
    );
    // Keep unread tracking active while the drawer stays mounted with the shell.
    ref.listen(unreadSessionIdsProvider, (_, _) {});
    // Folders forget conversations the host no longer has once loaded.
    ref.listen(sessionsProvider, (_, next) {
      if (next.loading || next.error != null) return;
      final known = {for (final s in next.sessions) s.sessionId};
      if (known.isNotEmpty) {
        unawaited(ref.read(drawerViewProvider.notifier).forgetMissing(known));
      }
    });
    // Closing the drawer (tap outside, swipe, or back) exits multi-select.
    if (selecting && !TickerMode.valuesOf(context).enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(drawerSelectionProvider.notifier).end();
        }
      });
    }

    final quick = AppMotion.of(context, AppMotion.quick);
    final short = MediaQuery.sizeOf(context).height < _compactHeight;

    final top = <Widget>[
      AnimatedSwitcher(
        duration: quick,
        child: selecting
            ? DrawerSelectionHeader(
                key: const ValueKey('selecting'),
                now: now,
              )
            : Padding(
                key: const ValueKey('brand'),
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
                child: LayoutBuilder(
                  builder: (context, box) => Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AgyBrandLockup(height: 19),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      NewChatButton(
                        onTap: newChat,
                        compact: NewChatButton.widthOf(context) >
                            box.maxWidth - 72,
                      ),
                    ],
                  ),
                ),
              ),
      ),
      SessionSearchBar(onClose: onClose),
      SmoothSize(
        duration: AppMotion.of(context, AppMotion.standard),
        curve: AppMotion.std,
        alignment: Alignment.topCenter,
        child: Row(
          children: [
            Expanded(child: WorkspaceSwitcher(onManage: manageWorkspaces)),
            _ViewOptionsKey(onClose: onClose),
          ],
        ),
      ),
      SmoothSize(
        duration: AppMotion.of(context, AppMotion.standard),
        curve: AppMotion.std,
        alignment: Alignment.topCenter,
        child: const DrawerFilterBar(),
      ),
    ];

    final list = _EdgeFade(
      child: _SessionList(onClose: onClose, now: now),
    );

    const radius = BorderRadius.only(
      topRight: Radius.circular(AppShape.xl),
      bottomRight: Radius.circular(AppShape.xl),
    );

    final content = Material(
      type: MaterialType.transparency,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (short)
              Expanded(
                child: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: top,
                      ),
                    ),
                  ],
                  body: list,
                ),
              )
            else ...[
              ...top,
              Expanded(child: list),
            ],
            // SelectionActionBar overlays IdentityBar in place: zero height jump.
            Stack(
              children: [
                AnimatedOpacity(
                  opacity: selecting ? 0 : 1,
                  duration: quick,
                  child: IgnorePointer(
                    ignoring: selecting,
                    child: ExcludeSemantics(
                      excluding: selecting,
                      child: IdentityBar(
                        onHost: () => showHostSwitcherSheet(
                          context,
                          ref,
                          onManage: () => onOpen(DrawerDestination.remote),
                        ),
                        onLocalDetails: () => onOpen(DrawerDestination.engine),
                        onFeatures: () => onOpen(DrawerDestination.features),
                        onSettings: () => onOpen(DrawerDestination.settings),
                        onSettingsHold: () =>
                            onOpen(DrawerDestination.settingsSearch),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: quick,
                    child: selecting
                        ? SelectionActionBar(
                            key: const ValueKey('selecting'),
                            onMove: () => unawaited(
                              moveToFolderFlow(
                                context,
                                ref,
                                ref.read(drawerSelectionProvider)?.toList() ??
                                    const [],
                              ),
                            ),
                            onPin: () =>
                                unawaited(pinSelectionFlow(context, ref)),
                            onArchive: () =>
                                unawaited(archiveSelectionFlow(context, ref)),
                            onDelete: () =>
                                unawaited(deleteSelectionFlow(context, ref)),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final motion = drawerMotion;
    if (motion == null) {
      return GlassSurface(
        tier: GlassTier.sheet,
        borderRadius: radius,
        child: content,
      );
    }
    return SlidingGlass(
      motion: motion,
      tier: GlassTier.sheet,
      borderRadius: radius,
      child: content,
    );
  }
}

/// "新对话": the drawer's sole solid primary element, a 36dp stadium pill.
class NewChatButton extends StatelessWidget {
  const NewChatButton({super.key, required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  /// Width of the full pill in [context]'s text size.
  static double widthOf(BuildContext context) {
    final label = TextPainter(
      text: TextSpan(
        text: '新对话',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = 12 + 20 + 4 + label.width + 15;
    label.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '新对话',
      onTap: onTap,
      excludeSemantics: true,
      child: Pressable(
        child: Material(
          color: scheme.primary,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
              child: compact
                  ? Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Icon(
                        AppIcons.newChat,
                        size: 20,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 15, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.newChat,
                            size: 20,
                            color: scheme.onPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '新对话',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `···` options button at the right end of the workspace scope row.
class _ViewOptionsKey extends ConsumerWidget {
  const _ViewOptionsKey({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(drawerScopeProvider);
    final filtered = ref.watch(drawerFilterProvider) != DrawerFilter.all;
    final hasArchived = ref.watch(
      sessionsProvider.select((s) => s.archivedIds.isNotEmpty),
    );
    final hasFolders = ref.watch(
      drawerViewProvider.select((v) => v.folders.isNotEmpty),
    );
    if (scope.sessions.isEmpty && !filtered && !hasArchived && !hasFolders) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: DrawerViewButton(
        onTap: () => unawaited(
          openDrawerViewOptions(context, ref, onClose: onClose),
        ),
      ),
    );
  }
}

/// Soft top and bottom edges so list rows fade into header and footer.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.child});

  final Widget child;

  static const _top = 10.0;
  static const _bottom = 16.0;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final h = rect.height <= 0 ? 1.0 : rect.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [
            0,
            (_top / h).clamp(0.0, 0.5),
            (1 - _bottom / h).clamp(0.5, 1.0),
            1,
          ],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

class _SessionList extends ConsumerWidget {
  const _SessionList({required this.onClose, this.now});

  final VoidCallback onClose;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsState = ref.watch(sessionsProvider);
    final workspace = ref.watch(selectedWorkspaceProvider);
    final scope = ref.watch(drawerScopeProvider);
    final folders = ref.watch(drawerViewProvider.select((v) => v.folders));

    if (sessionsState.loading && sessionsState.sessions.isEmpty) {
      return const _SkeletonList();
    }
    if (sessionsState.error != null && sessionsState.sessions.isEmpty) {
      return _Centered(
        child: EmptyView(
          compact: true,
          icon: AppIcons.offline,
          title: '加载对话失败',
          message: sessionsState.error,
          actionLabel: '重试',
          onAction: () => unawaited(ref.read(sessionsProvider.notifier).refresh()),
        ),
      );
    }

    if (scope.sessions.isEmpty && (workspace != null || folders.isEmpty)) {
      return workspace == null
          ? const _EmptyState()
          : const _WorkspaceEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(sessionsProvider.notifier).refresh(),
      child: DrawerConversationList(
        now: now,
        onNewChat: onClose,
        onOpen: (id) {
          ref.read(sessionsProvider.notifier).selectSession(id);
          onClose();
        },
        onLongPress: (s) => unawaited(_showSessionActions(context, ref, s)),
      ),
    );
  }

  Future<void> _showSessionActions(
    BuildContext context,
    WidgetRef ref,
    AcpSessionInfo s,
  ) async {
    final sessions = ref.read(sessionsProvider);
    final title = sessions.displayTitle(s);
    final pinned = sessions.isPinned(s.sessionId);
    final inFolder =
        ref.read(drawerViewProvider).folderOf.containsKey(s.sessionId);
    final running = ref
        .read(chatProvider)
        .runningSessionIds
        .contains(s.sessionId);

    final action = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetHeader(title),
                SheetGroup(
                  children: [
                    ListTile(
                      leading: Icon(pinned ? AppIcons.pinActive : AppIcons.pin),
                      title: Text(pinned ? '取消置顶' : '置顶'),
                      onTap: () =>
                          Navigator.pop(sheet, pinned ? 'unpin' : 'pin'),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.rename),
                      title: const Text('重命名'),
                      onTap: () => Navigator.pop(sheet, 'rename'),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.moveToFolder),
                      title: Text(inFolder ? '移到其他文件夹' : '移到文件夹'),
                      onTap: () => Navigator.pop(sheet, 'folder'),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.share),
                      title: const Text('分享'),
                      onTap: () => Navigator.pop(sheet, 'share'),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.multiSelect),
                      title: const Text('多选'),
                      onTap: () => Navigator.pop(sheet, 'select'),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.archive),
                      title: const Text('归档'),
                      subtitle: Text(
                        running ? '当前仍在运行，归档后会从主列表移入「已归档」' : '归档后从主列表移入「已归档」',
                      ),
                      onTap: () => Navigator.pop(sheet, 'archive'),
                    ),
                    ListTile(
                      leading: Icon(
                        AppIcons.delete,
                        color: DshColors.of(sheet).danger,
                      ),
                      title: Text(
                        '删除',
                        style: TextStyle(color: DshColors.of(sheet).danger),
                      ),
                      onTap: () => Navigator.pop(sheet, 'delete'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'pin' || 'unpin':
        await ref.read(sessionsProvider.notifier).togglePin(s.sessionId);
      case 'rename':
        final next = await showTextPromptDialog(
          context,
          title: '重命名对话',
          initial: title == '新对话' ? '' : title,
          hint: '输入新的标题',
          confirmLabel: '保存',
        );
        if (next != null && next.trim().isNotEmpty) {
          await ref
              .read(sessionsProvider.notifier)
              .renameSession(s.sessionId, next.trim());
        }
      case 'folder':
        await moveToFolderFlow(context, ref, [s.sessionId]);
      case 'share':
        ref.read(sessionsProvider.notifier).selectSession(s.sessionId);
        onClose();
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ShareScreen()),
        );
      case 'select':
        ref.read(drawerSelectionProvider.notifier).start(s.sessionId);
      case 'archive':
        await archiveSessionsFlow(
          context,
          ref,
          [s.sessionId],
          singleTitle: title,
        );
      case 'delete':
        await deleteSessionsFlow(
          context,
          ref,
          [s.sessionId],
          singleTitle: title,
        );
    }
  }
}

/// Loading: quiet breathing placeholder rows on the exact 20dp grid.
class _SkeletonList extends StatefulWidget {
  const _SkeletonList();

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: AppMotion.breath,
  );
  late final Animation<double> _opacity = _breath.drive(
    Tween(begin: 0.55, end: 1.0).chain(CurveTween(curve: AppMotion.std)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _breath
        ..stop()
        ..value = 1;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.09 : 0.07,
    );
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
    );
    const widths = [0.72, 0.5, 0.64, 0.42, 0.58];
    return Semantics(
      label: '正在加载对话',
      child: FadeTransition(
        opacity: _opacity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final row = (constraints.maxWidth - 40).clamp(40.0, 600.0);
            return ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 19, bottom: 9),
                  child: bar(28, 8),
                ),
                for (final w in widths)
                  SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: bar(row * w, 10),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Keeps an empty view in the upper third of the list area.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Align(
            alignment: const Alignment(0, -0.4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected workspace has no conversations yet.
class _WorkspaceEmptyState extends ConsumerWidget {
  const _WorkspaceEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Centered(
      child: EmptyView(
        compact: true,
        icon: AppIcons.folderOpen,
        title: '这个工作区还没有对话',
        message: '在这里新建的对话会自动归入这个工作区。',
        actionLabel: '全部对话',
        onAction: () =>
            unawaited(ref.read(workspacesProvider.notifier).select(null)),
      ),
    );
  }
}

/// No sessions: either the engine / remote host isn't ready yet, or none exist.
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostsProvider);
    if (!hosts.active.isLocal) {
      final conn = ref.watch(activeConnectionProvider);
      final name = hosts.sshById(hosts.active.id)?.name ?? 'SSH 主机';
      final view = conn.when(
        data: (c) => c != null
            ? const EmptyView(
                compact: true,
                icon: AppIcons.chat,
                title: '还没有对话',
                message: '点击右上角「新对话」或在下方输入消息即可开始。',
              )
            : EmptyView(
                compact: true,
                icon: AppIcons.disconnected,
                title: '未连接到 $name',
                message: '点左下角主机切换或重试连接。',
                actionLabel: '重试',
                onAction: () => ref.invalidate(activeConnectionProvider),
              ),
        loading: () => EmptyView(
          compact: true,
          icon: AppIcons.reconnecting,
          title: '正在连接 $name',
          message: '连接成功后会自动拉取对话列表。',
        ),
        error: (err, _) => EmptyView(
          compact: true,
          icon: AppIcons.disconnected,
          title: '无法连接 $name',
          message: err.toString(),
          actionLabel: '重试',
          onAction: () => ref.invalidate(activeConnectionProvider),
        ),
      );
      return _Centered(child: view);
    }

    final status = ref.watch(localRuntimeProvider.select((s) => s.status));
    final view = switch (status.phase) {
      RuntimePhase.running => const EmptyView(
        compact: true,
        icon: AppIcons.chat,
        title: '还没有对话',
        message: '点击右上角「新对话」或在下方输入消息即可开始。',
      ),
      RuntimePhase.starting || RuntimePhase.installing => EmptyView(
        compact: true,
        icon: AppIcons.loading,
        title: status.phase == RuntimePhase.installing ? '正在安装本机引擎' : '正在启动本机引擎',
        message: '就绪后会自动显示你的对话记录。',
      ),
      RuntimePhase.installed || RuntimePhase.error => EmptyView(
        compact: true,
        icon: AppIcons.power,
        title: '本机引擎未运行',
        message: status.error ?? '启动后即可开始对话。',
        actionLabel: '启动引擎',
        onAction: () => unawaited(
          ref.read(localRuntimeProvider.notifier).start(),
        ),
      ),
      RuntimePhase.notInstalled => EmptyView(
        compact: true,
        icon: AppIcons.thisPhone,
        title: '尚未安装本机引擎',
        message: '前往「本机引擎」完成一键安装后即可在本机离线启动。',
        actionLabel: '安装并启动',
        onAction: () => unawaited(
          ref.read(localRuntimeProvider.notifier).installOrUpdate(),
        ),
      ),
      RuntimePhase.stopping => const EmptyView(
        compact: true,
        icon: AppIcons.power,
        title: '本机引擎正在停止',
        message: '稍候可重新启动。',
      ),
    };
    return _Centered(child: view);
  }
}

/// Drawer footer mirroring DSH Go's IdentityBar:
/// [Host Avatar] [Host Name / ● Status ↕]   [全部功能 44] [设置 44 (长按搜设置)]
class IdentityBar extends ConsumerWidget {
  const IdentityBar({
    super.key,
    required this.onHost,
    required this.onFeatures,
    required this.onSettings,
    this.onSettingsHold,
    this.onLocalDetails,
  });

  final VoidCallback onHost;
  final VoidCallback? onLocalDetails;
  final VoidCallback onFeatures;
  final VoidCallback onSettings;

  /// Long-press ⚙ jumps straight to SettingsSearchPage.
  final VoidCallback? onSettingsHold;

  static const keySize = 44.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider).status;
    final conn = ref.watch(activeConnectionProvider);
    final isLocal = hosts.active.isLocal;
    final name = isLocal
        ? '本机 Android'
        : (hosts.sshById(hosts.active.id)?.name ?? 'SSH 主机');

    final (StatusTone tone, String statusLabel) = isLocal
        ? switch (runtime.phase) {
            RuntimePhase.running => (StatusTone.ok, '运行中'),
            RuntimePhase.starting || RuntimePhase.installing => (
              StatusTone.busy,
              runtime.phase == RuntimePhase.installing ? '安装中' : '启动中',
            ),
            RuntimePhase.error => (StatusTone.error, '异常'),
            RuntimePhase.installed => (StatusTone.idle, '已停止'),
            RuntimePhase.notInstalled => (StatusTone.warn, '未安装'),
            RuntimePhase.stopping => (StatusTone.busy, '停止中'),
          }
        : conn.when(
            data: (c) => c != null
                ? (StatusTone.ok, 'SSH 已连接')
                : (StatusTone.idle, '未连接'),
            loading: () => (StatusTone.busy, '连接中…'),
            error: (_, _) => (StatusTone.error, '连接失败'),
          );

    final tint = isLocal ? 0 : 6;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 13),
      child: Row(
        children: [
          Expanded(
            child: Row(
              key: const ValueKey('identity-host-controls'),
              children: [
                const SizedBox(width: 6),
                IconButton(
                  key: const ValueKey('identity-host-details'),
                  tooltip: isLocal ? '本机引擎详情' : '管理 SSH 主机',
                  onPressed: isLocal ? onLocalDetails : onHost,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints.tightFor(
                    width: keySize,
                    height: keySize,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: colors.identity[tint],
                      shape: const CircleBorder(),
                    ),
                    child: SizedBox.square(
                      dimension: 36,
                      child: Icon(
                        isLocal ? AppIcons.thisPhone : AppIcons.sshHost,
                        size: 19,
                        color: colors.onIdentity[tint],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '$name，$statusLabel',
                    onTap: onHost,
                    excludeSemantics: true,
                    child: InkWell(
                      key: const ValueKey('identity-host-switcher'),
                      onTap: onHost,
                      customBorder: Squircle.border(AppShape.md),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: keySize),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        StatusDot(tone: tone, size: 6),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration: AppMotion.of(
                                              context,
                                              AppMotion.quick,
                                            ),
                                            layoutBuilder:
                                                (current, previous) => Stack(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  children: [
                                                    ...previous,
                                                    ?current,
                                                  ],
                                                ),
                                            child: Text(
                                              statusLabel,
                                              key: ValueKey(statusLabel),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppType.tabular(
                                                theme.textTheme.bodySmall!
                                                    .copyWith(
                                                      color:
                                                          colors.textTertiary,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                AppIcons.dropdown,
                                size: 18,
                                color: colors.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RoundButton(
            icon: AppIcons.allFeatures,
            tooltip: '全部功能',
            onTap: onFeatures,
          ),
          const SizedBox(width: 8),
          _RoundButton(
            icon: AppIcons.settings,
            tooltip: '设置',
            onTap: onSettings,
            onLongPress: onSettingsHold,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final hold = onLongPress;
    Widget button = SizedBox.square(
      dimension: IdentityBar.keySize,
      child: GlassSurface(
        tier: GlassTier.pill,
        circle: true,
        onTap: onTap,
        child: Center(
          child: Icon(
            icon,
            size: 22,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
    if (hold != null) {
      button = GestureDetector(
        onLongPress: () {
          unawaited(HapticFeedback.mediumImpact());
          hold();
        },
        child: button,
      );
    }
    return Tooltip(
      message: tooltip,
      triggerMode: hold == null ? null : TooltipTriggerMode.manual,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onTap,
        onLongPress: hold,
        excludeSemantics: true,
        child: button,
      ),
    );
  }
}

/// Host switcher frosted sheet mirroring DSH Go's showHostSheet.
Future<void> showHostSwitcherSheet(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onManage,
}) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => Consumer(
      builder: (context, ref, _) {
        final hosts = ref.watch(hostsProvider);
        final runtime = ref.watch(localRuntimeProvider).status;
        const margin = EdgeInsets.fromLTRB(
          SheetTitleBar.inset,
          0,
          SheetTitleBar.inset,
          12,
        );
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetTitleBar('切换主机'),
                SheetGroup(
                  title: '本机',
                  margin: margin,
                  children: [
                    ListPageRow(
                      icon: AppIcons.thisPhone,
                      title: '本机 Android',
                      subtitle: runtime.isRunning
                          ? '运行中 (${runtime.executionMode})'
                          : (runtime.installedVersion != null
                                ? '已安装 v${runtime.installedVersion}'
                                : '未安装官方 agy'),
                      trailing: RowCheck(visible: hosts.active.isLocal),
                      onTap: () {
                        unawaited(
                          ref
                              .read(hostsProvider.notifier)
                              .selectHost(const HostRef.local()),
                        );
                        Navigator.pop(sheet);
                      },
                    ),
                  ],
                ),
                if (hosts.sshHosts.isNotEmpty)
                  SheetGroup(
                    title: 'SSH 远程主机',
                    margin: margin,
                    children: [
                      for (final h in hosts.sshHosts)
                        ListPageRow(
                          icon: AppIcons.sshHost,
                          title: h.name,
                          subtitle: '${h.username}@${h.host}:${h.port}',
                          trailing: RowCheck(
                            visible: !hosts.active.isLocal &&
                                hosts.active.id == h.id,
                          ),
                          onTap: () {
                            unawaited(
                              ref
                                  .read(hostsProvider.notifier)
                                  .selectHost(HostRef.ssh(h.id)),
                            );
                            Navigator.pop(sheet);
                          },
                        ),
                    ],
                  ),
                SheetGroup(
                  margin: margin,
                  children: [
                    ListPageRow(
                      icon: AppIcons.remoteHosts,
                      title: '管理 SSH 远程主机',
                      onTap: () {
                        Navigator.pop(sheet);
                        if (onManage != null) {
                          onManage();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SshHostsScreen(),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    ),
  );
}
