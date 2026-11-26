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
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/empty_view.dart';
import '../common/expand_reveal.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/row_marks.dart';
import '../common/search_capsule.dart';
import '../common/status_dot.dart';
import '../remote/ssh_hosts_screen.dart';
import '../share/share_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';
import 'brand_mark.dart';
import 'drawer_destination.dart';
import 'session_search_page.dart';

Color sessionSelectionColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.primary.withValues(
    alpha: scheme.brightness == Brightness.dark ? 0.18 : 0.09,
  );
}

/// Left sessions drawer mirroring DSH Go's exact anatomy:
/// Brand lockup + solid "新对话" pill -> Search capsule -> Workspace switcher ->
/// Filter & custom folder pills -> Edge-faded grouped sessions list (with multi-select) ->
/// Bottom IdentityBar or batch-action toolbar.
class SessionsDrawer extends ConsumerStatefulWidget {
  const SessionsDrawer({
    super.key,
    required this.onClose,
    required this.onOpen,
    this.drawerMotion,
  });

  final VoidCallback onClose;
  final ValueChanged<DrawerDestination> onOpen;
  final Animation<double>? drawerMotion;

  static const contentEdge = 10.0;

  @override
  ConsumerState<SessionsDrawer> createState() => _SessionsDrawerState();
}

class _SessionsDrawerState extends ConsumerState<SessionsDrawer> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  void _enterSelectMode([String? initialId]) {
    setState(() {
      _selecting = true;
      _selectedIds.clear();
      if (initialId != null) _selectedIds.add(initialId);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _pickFolderFor(Set<String> ids) async {
    final folders = ref.read(sessionsProvider).folders;
    final choice = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                ids.length == 1 ? '移动到文件夹' : '批量移动 ${ids.length} 个对话',
              ),
              SheetGroup(
                children: [
                  ListPageRow(
                    icon: AppIcons.noFolder,
                    title: '未分组（移出文件夹）',
                    chevron: false,
                    onTap: () => Navigator.of(sheet).pop(''),
                  ),
                  for (final f in folders)
                    ListPageRow(
                      icon: AppIcons.folderMark,
                      title: f,
                      chevron: false,
                      onTap: () => Navigator.of(sheet).pop(f),
                    ),
                  ListPageRow(
                    icon: AppIcons.newFolder,
                    title: '新建文件夹并移入…',
                    chevron: false,
                    onTap: () => Navigator.of(sheet).pop('__new__'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    String? target = choice;
    if (choice == '__new__') {
      final created = await showTextPromptDialog(
        context,
        title: '新建会话文件夹',
        hint: '例如 工作项目 / 调试 / 学习',
        confirmLabel: '创建',
      );
      if (created == null || created.trim().isEmpty) return;
      target = created.trim();
    }
    await ref
        .read(sessionsProvider.notifier)
        .batchMoveToFolder(ids, target.isEmpty ? null : target);
    if (mounted) {
      showBriefNotice(
        context,
        target.isEmpty ? '已移出文件夹' : '已移至「$target」',
      );
      if (_selecting) _exitSelectMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    void newChat() {
      ref.read(chatProvider.notifier).startNewChat();
      widget.onClose();
    }

    Future<void> openSearch() async {
      final id = await showSessionSearch(context);
      if (id != null && context.mounted) {
        ref.read(sessionsProvider.notifier).selectSession(id);
        widget.onClose();
      }
    }

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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
              child: Row(
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
                  if (_selecting)
                    TextButton(
                      onPressed: _exitSelectMode,
                      child: const Text('完成'),
                    )
                  else
                    NewChatButton(onTap: newChat),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SearchCapsuleButton(
                hint: '搜索对话…',
                onTap: () => unawaited(openSearch()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 10, 2),
              child: Row(
                children: [
                  Icon(
                    AppIcons.workspaceGroup,
                    size: 16,
                    color: DshColors.of(context).textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '工作区',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: DshColors.of(context).textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: '添加工作区',
                    child: InkWell(
                      onTap: () => unawaited(addWorkspaceFlow(context, ref)),
                      customBorder: Squircle.border(AppShape.md),
                      child: SizedBox.square(
                        dimension: 32,
                        child: Icon(
                          AppIcons.newFolder,
                          size: 17,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Tooltip(
                    message: '管理工作区',
                    child: InkWell(
                      onTap: () => widget.onOpen(DrawerDestination.workspaces),
                      customBorder: Squircle.border(AppShape.md),
                      child: SizedBox.square(
                        dimension: 32,
                        child: Icon(
                          AppIcons.configure,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _FilterChipsRow(
              selecting: _selecting,
              onToggleSelectMode: () =>
                  _selecting ? _exitSelectMode() : _enterSelectMode(),
            ),
            Expanded(
              child: _EdgeFade(
                child: _SessionList(
                  onClose: widget.onClose,
                  onOpen: widget.onOpen,
                  selecting: _selecting,
                  selectedIds: _selectedIds,
                  onToggleSelect: _toggleSelected,
                  onStartMultiSelect: _enterSelectMode,
                  onMoveToFolder: (id) => unawaited(_pickFolderFor({id})),
                ),
              ),
            ),
            if (_selecting)
              _BatchBar(
                count: _selectedIds.length,
                onMove: _selectedIds.isEmpty
                    ? null
                    : () => unawaited(_pickFolderFor(Set.from(_selectedIds))),
                onArchive: _selectedIds.isEmpty
                    ? null
                    : () async {
                        final isArchivedView =
                            ref.read(sessionsProvider).filter ==
                            DrawerSessionFilter.archived;
                        await ref
                            .read(sessionsProvider.notifier)
                            .batchArchive(
                              Set.from(_selectedIds),
                              !isArchivedView,
                            );
                        if (context.mounted) {
                          showBriefNotice(
                            context,
                            isArchivedView ? '已批量移出归档' : '已批量归档',
                          );
                          _exitSelectMode();
                        }
                      },
                onDelete: _selectedIds.isEmpty
                    ? null
                    : () async {
                        final count = _selectedIds.length;
                        final ok = await showAppDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: Text('批量删除 $count 个对话？'),
                            content: const Text('删除后所选会话记录将从列表移除。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: DshColors.of(d).danger,
                                  foregroundColor: DshColors.of(d).onDanger,
                                ),
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ref
                              .read(sessionsProvider.notifier)
                              .batchDelete(Set.from(_selectedIds));
                          if (context.mounted) {
                            showBriefNotice(context, '已删除 $count 个对话');
                            _exitSelectMode();
                          }
                        }
                      },
                onCancel: _exitSelectMode,
              )
            else
              IdentityBar(
                onHost: () => showHostSwitcherSheet(
                  context,
                  ref,
                  onManage: () => widget.onOpen(DrawerDestination.remote),
                ),
                onLocalDetails: () => widget.onOpen(DrawerDestination.engine),
                onFeatures: () => widget.onOpen(DrawerDestination.features),
                onSettings: () => widget.onOpen(DrawerDestination.settings),
              ),
          ],
        ),
      ),
    );

    final motion = widget.drawerMotion;
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

class _BatchBar extends StatelessWidget {
  const _BatchBar({
    required this.count,
    required this.onMove,
    required this.onArchive,
    required this.onDelete,
    required this.onCancel,
  });

  final int count;
  final VoidCallback? onMove;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: AppShape.radiusLg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已选 $count 项',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(AppIcons.moveToFolder, size: 19),
              tooltip: '移至文件夹',
              onPressed: onMove,
            ),
            IconButton(
              icon: const Icon(AppIcons.archive, size: 19),
              tooltip: '归档 / 恢复',
              onPressed: onArchive,
            ),
            IconButton(
              icon: Icon(
                AppIcons.delete,
                size: 19,
                color: onDelete == null ? dsh.textDisabled : dsh.danger,
              ),
              tooltip: '删除',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class NewChatButton extends StatelessWidget {
  const NewChatButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      child: Material(
        color: scheme.primary,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 15, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.newChat, size: 19, color: scheme.onPrimary),
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
    );
  }
}

class _FilterChipsRow extends ConsumerWidget {
  const _FilterChipsRow({
    required this.selecting,
    required this.onToggleSelectMode,
  });

  final bool selecting;
  final VoidCallback onToggleSelectMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(sessionsProvider);
    final current = st.filter;
    final activeFolder = st.activeFolder;
    final archivedCount = st.archivedIds.length;
    final pinnedCount = st.pinnedIds.length;
    final folders = st.folders;
    final hasAnySessions = st.sessions.isNotEmpty;

    if (!hasAnySessions && folders.isEmpty) {
      return const SizedBox(height: 4);
    }

    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
      IconData? icon,
    }) {
      final bg = selected
          ? scheme.primaryContainer
          : (dark
                ? Colors.white.withValues(alpha: 0.06)
                : scheme.onSurface.withValues(alpha: 0.05));
      final fg = selected
          ? scheme.onPrimaryContainer
          : scheme.onSurfaceVariant;
      return Material(
        color: bg,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        children: [
          chip(
            label: '全部',
            selected: activeFolder == null && current == DrawerSessionFilter.all,
            onTap: () => ref
                .read(sessionsProvider.notifier)
                .setFilter(DrawerSessionFilter.all),
          ),
          if (pinnedCount > 0) ...[
            const SizedBox(width: 6),
            chip(
              label: '置顶',
              selected:
                  activeFolder == null && current == DrawerSessionFilter.pinned,
              onTap: () => ref
                  .read(sessionsProvider.notifier)
                  .setFilter(DrawerSessionFilter.pinned),
            ),
          ],
          if (archivedCount > 0) ...[
            const SizedBox(width: 6),
            chip(
              label: '归档',
              selected:
                  activeFolder == null &&
                  current == DrawerSessionFilter.archived,
              onTap: () => ref
                  .read(sessionsProvider.notifier)
                  .setFilter(DrawerSessionFilter.archived),
            ),
          ],
          for (final folder in folders) ...[
            const SizedBox(width: 6),
            chip(
              icon: AppIcons.folderMark,
              label: folder,
              selected: activeFolder == folder,
              onTap: () =>
                  ref.read(sessionsProvider.notifier).selectFolder(folder),
              onLongPress: () async {
                final ok = await showAppDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text('删除文件夹「$folder」？'),
                    content: const Text('文件夹内的对话不会被删除，仅回到未分组状态。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref
                      .read(sessionsProvider.notifier)
                      .deleteFolder(folder);
                }
              },
            ),
          ],
          const SizedBox(width: 6),
          chip(
            icon: AppIcons.newFolder,
            label: '文件夹',
            selected: false,
            onTap: () async {
              final name = await showTextPromptDialog(
                context,
                title: '新建会话文件夹',
                hint: '例如 工作 / 调试 / 日常',
                confirmLabel: '创建',
              );
              if (name != null && name.trim().isNotEmpty) {
                await ref
                    .read(sessionsProvider.notifier)
                    .createFolder(name.trim());
              }
            },
          ),
          if (hasAnySessions) ...[
            const SizedBox(width: 6),
            chip(
              icon: AppIcons.multiSelect,
              label: selecting ? '退出多选' : '多选',
              selected: selecting,
              onTap: onToggleSelectMode,
            ),
          ],
        ],
      ),
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.child});

  final Widget child;

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
            (10.0 / h).clamp(0.0, 0.5),
            (1 - 16.0 / h).clamp(0.5, 1.0),
            1,
          ],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

class _SessionList extends ConsumerWidget {
  const _SessionList({
    required this.onClose,
    required this.onOpen,
    required this.selecting,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onStartMultiSelect,
    required this.onMoveToFolder,
  });

  final VoidCallback onClose;
  final ValueChanged<DrawerDestination> onOpen;
  final bool selecting;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<String> onStartMultiSelect;
  final ValueChanged<String> onMoveToFolder;

  Future<void> _startChatInWorkspace(
    WidgetRef ref,
    WorkspaceSessionGroup group,
  ) async {
    if (group.workspace != null) {
      await ref.read(workspacesProvider.notifier).select(group.workspace!.id);
    } else if (group.path.isNotEmpty) {
      await ref
          .read(workspacesProvider.notifier)
          .add(group.path, title: group.title);
    }
    ref.read(chatProvider.notifier).startNewChat();
    onClose();
  }

  void _openSession(
    WidgetRef ref,
    WorkspaceSessionGroup group,
    AcpSessionInfo s,
  ) {
    ref.read(sessionsProvider.notifier).selectSession(s.sessionId);
    final ws = group.workspace;
    if (ws != null && ref.read(workspacesProvider).selectedId != ws.id) {
      unawaited(ref.read(workspacesProvider.notifier).select(ws.id));
    }
    onClose();
  }

  Future<void> _showWorkspaceQuickActions(
    BuildContext context,
    WidgetRef ref,
    WorkspaceSessionGroup group,
  ) async {
    final action = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(group.title),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: AppIcons.newChat,
                  title: '在此工作区新建对话',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'new'),
                ),
                ListPageRow(
                  icon: AppIcons.files,
                  title: '浏览工作区文件',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'files'),
                ),
                ListPageRow(
                  icon: AppIcons.configure,
                  title: '管理全部工作区',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'manage'),
                ),
                if (!group.isDefault)
                  ListPageRow(
                    icon: AppIcons.remove,
                    title: '移出工作区',
                    subtitle: '移出列表并清理该工作区会话，不删除手机原文件',
                    danger: true,
                    chevron: false,
                    onTap: () => Navigator.pop(sheet, 'remove'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'new':
        await _startChatInWorkspace(ref, group);
      case 'files':
        if (group.workspace != null) {
          await ref.read(workspacesProvider.notifier).select(group.workspace!.id);
        }
        onOpen(DrawerDestination.files);
      case 'manage':
        onOpen(DrawerDestination.workspaces);
      case 'remove':
        final wsCtrl = ref.read(workspacesProvider.notifier);
        final sessCtrl = ref.read(sessionsProvider.notifier);
        if (group.workspace != null) {
          await wsCtrl.remove(group.workspace!.id);
        } else if (group.path.isNotEmpty) {
          await wsCtrl.hidePath(group.path);
        }
        if (group.path.isNotEmpty) {
          await sessCtrl.removeWorkspaceSessions(group.path);
        }
        if (context.mounted) {
          showBriefNotice(context, '已移出工作区「${group.title}」');
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsState = ref.watch(sessionsProvider);
    final groups = ref.watch(workspaceSessionGroupsProvider);
    final conn = ref.watch(activeConnectionProvider);
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider).status;

    if (sessionsState.loading && sessionsState.sessions.isEmpty) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (sessionsState.sessions.isEmpty) {
      if (hosts.active.isLocal && !runtime.isRunning) {
        final installed = runtime.phase == RuntimePhase.installed;
        return Center(
          child: EmptyView(
            compact: true,
            icon: installed ? AppIcons.power : AppIcons.thisPhone,
            title: installed ? '本机引擎未启动' : '尚未安装官方 agy',
            message: installed
                ? '启动引擎后即可开始对话并同步历史会话。'
                : '前往本机引擎一键拉取 Google 官方 Android 原生客户端。',
            actionLabel: installed ? '启动引擎' : '前往安装',
            onAction: installed
                ? () =>
                      unawaited(ref.read(localRuntimeProvider.notifier).start())
                : () => onOpen(DrawerDestination.engine),
          ),
        );
      }
      if (!hosts.active.isLocal && conn.hasError) {
        return Center(
          child: EmptyView(
            compact: true,
            icon: AppIcons.disconnected,
            title: '远程主机未连接',
            message: '${conn.error}',
            actionLabel: '重试连接',
            onAction: () =>
                ref.read(activeConnectionProvider.notifier).reconnect(),
          ),
        );
      }
    }

    if (groups.isEmpty) {
      return Center(
        child: EmptyView(
          compact: true,
          icon: sessionsState.activeFolder != null
              ? AppIcons.folder
              : AppIcons.chat,
          title: sessionsState.activeFolder != null
              ? '「${sessionsState.activeFolder}」内暂无对话'
              : sessionsState.filter == DrawerSessionFilter.pinned
              ? '暂无置顶对话'
              : sessionsState.filter == DrawerSessionFilter.archived
              ? '暂无归档对话'
              : '还没有对话',
          message: sessionsState.activeFolder != null
              ? '长按任意对话即可移入此文件夹。'
              : '点击右上角「新对话」开始第一次交流。',
        ),
      );
    }

    final colors = DshColors.of(context);
    final theme = Theme.of(context);
    final chatBusy = ref.watch(chatProvider.select((c) => c.isBusy));

    return RefreshIndicator(
      onRefresh: () => ref.read(sessionsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
        children: [
          for (final group in groups) ...[
            Builder(
              key: ValueKey('ws-group-${group.key}'),
              builder: (ctx) {
                final open = !sessionsState.isWorkspaceCollapsed(group.key);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WorkspaceHeaderRow(
                      group: group,
                      open: open,
                      selecting: selecting,
                      onToggle: () => unawaited(
                        ref
                            .read(sessionsProvider.notifier)
                            .toggleWorkspaceCollapsed(group.key),
                      ),
                      onNewChat: () =>
                          unawaited(_startChatInWorkspace(ref, group)),
                      onLongPress: () => unawaited(
                        _showWorkspaceQuickActions(context, ref, group),
                      ),
                    ),
                    ExpandReveal(
                      open: open,
                      child: Container(
                        margin: const EdgeInsets.only(left: 19, bottom: 6),
                        padding: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: DshSurfaces.of(context).card.hairline,
                            ),
                          ),
                        ),
                        child: group.sessions.isEmpty
                            ? Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  onTap: () => unawaited(
                                    _startChatInWorkspace(ref, group),
                                  ),
                                  customBorder: Squircle.border(AppShape.md),
                                  child: SizedBox(
                                    height: 36,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '暂无对话 · 点此新建',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.textTertiary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final s in group.sessions)
                                    _SessionRow(
                                      title: sessionsState.displayTitle(s),
                                      folderTag:
                                          sessionsState.activeFolder == null
                                          ? sessionsState.folderOf(s.sessionId)
                                          : null,
                                      selected:
                                          s.sessionId ==
                                          sessionsState.currentSessionId,
                                      selecting: selecting,
                                      checked: selectedIds.contains(
                                        s.sessionId,
                                      ),
                                      pinned: sessionsState.isPinned(
                                        s.sessionId,
                                      ),
                                      busy:
                                          chatBusy &&
                                          s.sessionId ==
                                              sessionsState.currentSessionId,
                                      onTap: () {
                                        if (selecting) {
                                          onToggleSelect(s.sessionId);
                                        } else {
                                          _openSession(ref, group, s);
                                        }
                                      },
                                      onLongPress: () => selecting
                                          ? onToggleSelect(s.sessionId)
                                          : unawaited(
                                              _showSessionActions(
                                                context,
                                                ref,
                                                s,
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showSessionActions(
    BuildContext context,
    WidgetRef ref,
    AcpSessionInfo s,
  ) async {
    final st = ref.read(sessionsProvider);
    final title = st.displayTitle(s);
    final pinned = st.isPinned(s.sessionId);
    final archived = st.isArchived(s.sessionId);
    final action = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: pinned ? AppIcons.pinActive : AppIcons.pin,
                  title: pinned ? '取消置顶' : '置顶对话',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'pin'),
                ),
                ListPageRow(
                  icon: AppIcons.rename,
                  title: '重命名',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'rename'),
                ),
                ListPageRow(
                  icon: AppIcons.moveToFolder,
                  title: '移动到文件夹',
                  value: st.folderOf(s.sessionId),
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'folder'),
                ),
                ListPageRow(
                  icon: AppIcons.multiSelect,
                  title: '多选批量管理',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'multi'),
                ),
                ListPageRow(
                  icon: AppIcons.share,
                  title: '分享 / 导出 / 回放',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'share'),
                ),
                ListPageRow(
                  icon: archived ? AppIcons.unarchive : AppIcons.archive,
                  title: archived ? '移出归档' : '归档对话',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'archive'),
                ),
                ListPageRow(
                  icon: AppIcons.delete,
                  title: '删除对话',
                  danger: true,
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'delete'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    final ctrl = ref.read(sessionsProvider.notifier);
    switch (action) {
      case 'pin':
        await ctrl.togglePin(s.sessionId);
      case 'rename':
        final next = await showTextPromptDialog(
          context,
          title: '重命名对话',
          initial: title,
          hint: '对话标题',
          validate: (v) => v.isEmpty ? '请输入标题' : null,
        );
        if (next != null && next.isNotEmpty) {
          await ctrl.renameSession(s.sessionId, next);
        }
      case 'folder':
        onMoveToFolder(s.sessionId);
      case 'multi':
        onStartMultiSelect(s.sessionId);
      case 'share':
        ctrl.selectSession(s.sessionId);
        onClose();
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ShareScreen()),
        );
      case 'archive':
        await ctrl.setArchived(s.sessionId, !archived);
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showBriefNotice(
            archived ? '已移出归档' : '已归档「$title」',
          );
        }
      case 'delete':
        final ok = await showAppDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('删除「$title」？'),
            content: const Text('删除后该会话记录将从当前列表移除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: DshColors.of(d).danger,
                  foregroundColor: DshColors.of(d).onDanger,
                ),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await ctrl.deleteSession(s.sessionId);
        }
    }
  }
}

class _WorkspaceHeaderRow extends StatelessWidget {
  const _WorkspaceHeaderRow({
    required this.group,
    required this.open,
    required this.selecting,
    required this.onToggle,
    required this.onNewChat,
    required this.onLongPress,
  });

  final WorkspaceSessionGroup group;
  final bool open;
  final bool selecting;
  final VoidCallback onToggle;
  final VoidCallback onNewChat;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DshColors.of(context);
    final shape = Squircle.border(AppShape.md);
    final iconColor = group.isSelected
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          onLongPress: () {
            unawaited(HapticFeedback.mediumImpact());
            onLongPress();
          },
          customBorder: shape,
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
              child: Row(
                children: [
                  Icon(
                    group.isDefault
                        ? AppIcons.defaultFolder
                        : (open ? AppIcons.folderOpen : AppIcons.workspace),
                    size: 18,
                    color: iconColor,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      group.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: group.isSelected
                            ? scheme.primary
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${group.sessions.length}',
                    style: AppType.tabular(
                      theme.textTheme.bodySmall!.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  if (!selecting) ...[
                    const SizedBox(width: 2),
                    Tooltip(
                      message: '在「${group.title}」新建对话',
                      child: InkWell(
                        onTap: onNewChat,
                        customBorder: const CircleBorder(),
                        child: SizedBox.square(
                          dimension: 30,
                          child: Icon(
                            AppIcons.newChat,
                            size: 16,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  AnimatedRotation(
                    turns: open ? 0 : -0.25,
                    duration: AppMotion.of(context, AppMotion.quick),
                    curve: AppMotion.std,
                    child: Icon(
                      AppIcons.expand,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.title,
    required this.selected,
    required this.selecting,
    required this.checked,
    required this.pinned,
    required this.busy,
    required this.onTap,
    required this.onLongPress,
    this.folderTag,
  });

  final String title;
  final String? folderTag;
  final bool selected;
  final bool selecting;
  final bool checked;
  final bool pinned;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DshColors.of(context);
    final shape = Squircle.border(AppShape.md);
    return Material(
      color: (selecting ? checked : selected)
          ? sessionSelectionColor(context)
          : Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () {
          unawaited(HapticFeedback.mediumImpact());
          onLongPress();
        },
        customBorder: shape,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (selecting) ...[
                  Icon(
                    checked ? AppIcons.checkboxOn : AppIcons.checkboxOff,
                    size: 18,
                    color: checked ? scheme.primary : colors.textTertiary,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                if (folderTag != null && folderTag!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    folderTag!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
                if (busy) ...[
                  const SizedBox(width: 8),
                  const StatusDot(tone: StatusTone.busy, size: 7),
                ] else if (pinned) ...[
                  const SizedBox(width: 8),
                  Icon(AppIcons.pinActive, size: 14, color: colors.textTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drawer footer mirroring DSH Go's IdentityBar:
/// [Host Avatar] [Host Name / ● Status ⌄]   [All Features 44] [Settings 44]
class IdentityBar extends ConsumerWidget {
  const IdentityBar({
    super.key,
    required this.onHost,
    required this.onFeatures,
    required this.onSettings,
    this.onLocalDetails,
  });

  final VoidCallback onHost;
  final VoidCallback? onLocalDetails;
  final VoidCallback onFeatures;
  final VoidCallback onSettings;

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
              children: [
                const SizedBox(width: 6),
                IconButton(
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
                  child: InkWell(
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
                                        child: Text(
                                          statusLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppType.tabular(
                                            theme.textTheme.bodySmall!.copyWith(
                                              color: colors.textTertiary,
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
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
