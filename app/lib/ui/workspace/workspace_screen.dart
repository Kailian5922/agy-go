// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/workspace_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/breadcrumb_row.dart';
import '../common/brief_notice.dart';
import '../common/empty_view.dart';
import '../common/fade_in.dart';
import '../common/list_page_row.dart';
import '../common/search_capsule.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';
import 'workspaces_ui.dart';

/// Workspace files browser & inline editor mirroring DSH Go's WorkspaceFilesPage.
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _showHidden = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<({String label, String path})> _crumbs(
    WorkspaceState ws,
    bool local,
    String storageRoot,
  ) {
    final parts = ws.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final raw = <({String label, String path})>[(label: '/', path: '/')];
    var acc = '';
    for (final p in parts) {
      acc = '$acc/$p';
      raw.add((label: p, path: acc));
    }
    if (local) {
      final sIdx = raw.indexWhere((c) => c.path == storageRoot);
      if (sIdx >= 0) {
        return [(label: '手机存储', path: storageRoot), ...raw.sublist(sIdx + 1)];
      }
    }
    final rIdx = raw.indexWhere((c) => c.path == ws.rootPath);
    if (rIdx > 0) {
      return [(label: '工作区', path: ws.rootPath), ...raw.sublist(rIdx + 1)];
    }
    return raw;
  }

  Future<void> _openFile(WorkspaceEntry entry) async {
    final ctrl = ref.read(workspaceProvider.notifier);
    try {
      final content = await ctrl.readTextFile(entry.path);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _FileEditorPage(
            entry: entry,
            initialContent: content,
            onSave: (text) => ctrl.writeTextFile(entry.path, text),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('无法打开文件：$e')),
      );
    }
  }

  Future<void> _showEntryActions(WorkspaceEntry entry) async {
    final action = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(entry.name),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: AppIcons.copy,
                  title: '复制路径',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'copy'),
                ),
                if (!entry.isDirectory)
                  ListPageRow(
                    icon: AppIcons.edit,
                    title: '查看 / 编辑',
                    chevron: false,
                    onTap: () => Navigator.pop(sheet, 'edit'),
                  ),
                ListPageRow(
                  icon: AppIcons.delete,
                  title: '删除',
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
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: entry.path));
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showBriefNotice('已复制路径');
        }
      case 'edit':
        await _openFile(entry);
      case 'delete':
        final ok = await showAppDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('删除「${entry.name}」？'),
            content: Text(
              entry.isDirectory ? '将递归删除该文件夹内所有内容，无法撤销。' : '删除后无法撤销。',
            ),
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
          await ref.read(workspaceProvider.notifier).deleteEntry(entry);
        }
    }
  }

  Future<void> _showCreateSheet() async {
    final choice = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader('新建'),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: AppIcons.newFolder,
                  title: '新建文件夹',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'dir'),
                ),
                ListPageRow(
                  icon: AppIcons.file,
                  title: '新建文件',
                  chevron: false,
                  onTap: () => Navigator.pop(sheet, 'file'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final name = await showTextPromptDialog(
      context,
      title: choice == 'dir' ? '新建文件夹' : '新建文件',
      hint: choice == 'dir' ? 'folder_name' : 'notes.md',
      confirmLabel: '创建',
      validate: (v) {
        if (v.isEmpty) return '请输入名称';
        if (v.contains('/')) return '名称不能包含 /';
        return null;
      },
    );
    if (name == null || !mounted) return;
    final ctrl = ref.read(workspaceProvider.notifier);
    if (choice == 'dir') {
      await ctrl.createDirectory(name);
    } else {
      await ctrl.createFile(name);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceProvider);
    final local = ref.watch(hostsProvider.select((h) => h.active.isLocal));
    final runtime = ref.watch(localRuntimeProvider).status;
    final ctrl = ref.read(workspaceProvider.notifier);
    final colors = DshColors.of(context);
    final q = _query.trim().toLowerCase();
    final visible = [
      for (final e in ws.entries)
        if ((_showHidden || !e.hidden) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
          e,
    ];
    final hiddenCount = ws.entries.where((e) => e.hidden).length;

    return PopScope(
      canPop: !ws.canGoUp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && ws.canGoUp) unawaited(ctrl.goUp());
      },
      child: RefreshIndicator(
        onRefresh: ctrl.refresh,
        edgeOffset: MediaQuery.paddingOf(context).top + 56,
        child: AppPage(
          title: '文件',
          subtitle: Text(
            displayWorkspacePath(
              ws.currentPath,
              local: local,
              homePath: runtime.homePath,
              storageRoot: runtime.phoneStoragePath,
            ),
            style: AppType.mono(
              size: 12.5,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            GlassIconButton(
              icon: AppIcons.workspace,
              tooltip: '切换工作区',
              onPressed: () => showWorkspaceSheet(
                context,
                ref,
                onManage: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkspacesPage(),
                  ),
                ),
              ),
            ),
            GlassIconButton(
              icon: AppIcons.add,
              tooltip: '新建文件或文件夹',
              onPressed: _showCreateSheet,
            ),
          ],
          slivers: [
            SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SearchCapsule(
                    controller: _searchCtrl,
                    hint: '搜索当前目录…',
                    onChanged: (v) => setState(() => _query = v),
                    onClear: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
                ),
                BreadcrumbRow(
                  crumbs: _crumbs(ws, local, runtime.phoneStoragePath),
                  onTap: (p) {
                    if (p != ws.currentPath) unawaited(ctrl.openDirectory(p));
                  },
                ),
                if (ws.loading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (ws.error != null)
                  EmptyView(
                    icon: AppIcons.error,
                    title: '无法读取目录',
                    message: ws.error,
                    actionLabel: '重试',
                    onAction: ctrl.refresh,
                  )
                else if (visible.isEmpty)
                  EmptyView(
                    icon: AppIcons.folderOpen,
                    title: q.isNotEmpty ? '没有匹配的文件' : '目录为空',
                    message: q.isNotEmpty ? '尝试更换搜索关键词。' : '点击右上角 + 可新建文件或文件夹。',
                  )
                else
                  ListPageCard(
                    children: [
                      for (final (i, entry) in visible.indexed)
                        FadeSlideIn(
                          index: i,
                          child: ListPageRow(
                            icon: entry.isDirectory
                                ? AppIcons.folder
                                : AppIcons.file,
                            iconColor: entry.isDirectory
                                ? Theme.of(context).colorScheme.primary
                                : (entry.hidden ? colors.textTertiary : null),
                            title: entry.name,
                            meta: entry.isDirectory
                                ? null
                                : _formatSize(entry.sizeBytes),
                            chevron: entry.isDirectory,
                            onTap: () => entry.isDirectory
                                ? unawaited(ctrl.openDirectory(entry.path))
                                : unawaited(_openFile(entry)),
                            onLongPress: () => unawaited(_showEntryActions(entry)),
                          ),
                        ),
                    ],
                  ),
                if (hiddenCount > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _showHidden = !_showHidden),
                        child: Text(
                          _showHidden
                              ? '隐藏点文件'
                              : '显示 $hiddenCount 个隐藏项',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileEditorPage extends StatefulWidget {
  const _FileEditorPage({
    required this.entry,
    required this.initialContent,
    required this.onSave,
  });

  final WorkspaceEntry entry;
  final String initialContent;
  final Future<void> Function(String) onSave;

  @override
  State<_FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<_FileEditorPage> {
  late final _ctrl = TextEditingController(text: widget.initialContent);
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_ctrl.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showBriefNotice('已保存 ${widget.entry.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = DshColors.of(context);
    return AppPage(
      title: widget.entry.name,
      showLargeTitle: false,
      actions: [
        GlassIconButton(
          icon: AppIcons.copy,
          tooltip: '复制全部内容',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _ctrl.text));
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showBriefNotice('已复制');
            }
          },
        ),
        GlassIconButton(
          icon: AppIcons.save,
          tooltip: '保存',
          onPressed: (_saving || !_dirty) ? null : _save,
        ),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverToBoxAdapter(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.codeWellBg,
                shape: AppShape.outlined(colors.codeWellBorder, radius: AppShape.md),
              ),
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                minLines: 22,
                onChanged: (_) {
                  if (!_dirty) setState(() => _dirty = true);
                },
                style: AppType.mono(size: 13, color: colors.codeWellFg),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.all(14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
