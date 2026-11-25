import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/workspace_state.dart';
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Local & SSH SFTP workspace file explorer with inline text viewer/editor.
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return AgyPage(
      title: ws.isRemote ? '远程工作区 (SFTP)' : '本机工作区',
      actions: [
        IconButton(
          tooltip: '新建文件',
          icon: const Icon(Icons.note_add_outlined, size: 20),
          onPressed: () => _promptCreate(context, ref, isDir: false),
        ),
        IconButton(
          tooltip: '新建文件夹',
          icon: const Icon(Icons.create_new_folder_outlined, size: 20),
          onPressed: () => _promptCreate(context, ref, isDir: true),
        ),
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () => ref.read(workspaceProvider.notifier).refresh(),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: HairlineCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  if (ws.canGoUp)
                    IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: '上一级',
                      onPressed: () =>
                          ref.read(workspaceProvider.notifier).goUp(),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.folder_special_outlined, size: 18),
                    ),
                  Expanded(
                    child: SelectableText(
                      ws.currentPath,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: '复制路径',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: ws.currentPath));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制目录路径')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          if (ws.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: HairlineCard(
                padding: const EdgeInsets.all(10),
                borderColor: surfaces.danger.withValues(alpha: 0.45),
                child: Text(
                  ws.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: surfaces.danger,
                  ),
                ),
              ),
            ),
          Expanded(
            child: ws.loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ws.entries.isEmpty
                ? Center(
                    child: Text(
                      '目录为空\n点击右上角新建文件或文件夹',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: surfaces.subtleText,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
                    itemCount: ws.entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = ws.entries[index];
                      return HairlineCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          if (entry.isDirectory) {
                            ref
                                .read(workspaceProvider.notifier)
                                .openDirectory(entry.path);
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _FileEditorScreen(entry: entry),
                              ),
                            );
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              entry.isDirectory
                                  ? Icons.folder_rounded
                                  : Icons.description_outlined,
                              size: 20,
                              color: entry.isDirectory
                                  ? theme.colorScheme.primary
                                  : surfaces.subtleText,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (!entry.isDirectory)
                                    Text(
                                      _formatBytes(entry.sizeBytes),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: surfaces.subtleText,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: surfaces.subtleText,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _confirmDelete(context, ref, entry),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptCreate(
    BuildContext context,
    WidgetRef ref, {
    required bool isDir,
  }) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDir ? '新建文件夹' : '新建文件'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isDir ? '例如：src' : '例如：main.py',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    if (isDir) {
      await ref.read(workspaceProvider.notifier).createDirectory(name);
    } else {
      await ref.read(workspaceProvider.notifier).createFile(name);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WorkspaceEntry entry,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除「${entry.name}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(workspaceProvider.notifier).deleteEntry(entry);
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _FileEditorScreen extends ConsumerStatefulWidget {
  const _FileEditorScreen({required this.entry});

  final WorkspaceEntry entry;

  @override
  ConsumerState<_FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends ConsumerState<_FileEditorScreen> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await ref
          .read(workspaceProvider.notifier)
          .readTextFile(widget.entry.path);
      if (!mounted) return;
      _ctrl.text = text;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(workspaceProvider.notifier)
          .writeTextFile(widget.entry.path, _ctrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存文件')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgyPage(
      title: widget.entry.name,
      actions: [
        IconButton(
          tooltip: '保存',
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded, size: 20),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('读取失败: $_error'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: HairlineCard(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
            ),
    );
  }
}
