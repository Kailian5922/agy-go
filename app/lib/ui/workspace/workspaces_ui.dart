// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/settings_state.dart';
import '../../state/workspace_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/breadcrumb_row.dart';
import '../common/brief_notice.dart';
import '../common/empty_view.dart';
import '../common/fade_in.dart';
import '../common/list_page_row.dart';
import '../common/row_marks.dart';
import '../common/sheet_navigator.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';
import 'workspace_screen.dart';

/// Prompts the user for a single line of text (rename workspace, new folder, manual path).
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  String? caption,
  String initial = '',
  String? hint,
  String confirmLabel = '确定',
  bool mono = false,
  String? Function(String)? validate,
}) async {
  final ctrl = TextEditingController(text: initial);
  String? error;
  final result = await showAppDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (caption != null) ...[
              Text(
                caption,
                style: Theme.of(dialog).textTheme.bodySmall?.copyWith(
                  color: DshColors.of(dialog).textTertiary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: ctrl,
              autofocus: true,
              style: mono ? AppType.mono(size: 13.5) : null,
              decoration: InputDecoration(hintText: hint, errorText: error),
              onSubmitted: (_) {
                final v = ctrl.text.trim();
                final err = validate?.call(v);
                if (err != null) {
                  setState(() => error = err);
                  return;
                }
                Navigator.pop(dialog, v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              final err = validate?.call(v);
              if (err != null) {
                setState(() => error = err);
                return;
              }
              Navigator.pop(dialog, v);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return result;
}

IconData _iconForStoragePreset(PhoneStoragePreset preset) => switch (preset.id) {
  'phone-storage' => AppIcons.phoneStorage,
  'phone-download' => AppIcons.downloads,
  'phone-documents' => AppIcons.document,
  'phone-dcim' => AppIcons.camera,
  'phone-pictures' => AppIcons.gallery,
  _ => AppIcons.folder,
};

/// Ensures Android shared storage permission is granted and phone storage mounting is on.
///
/// Mirrors DSH Go's permission flow: requests classic READ/WRITE_EXTERNAL_STORAGE first
/// (honoured under targetSdk 28 legacy mode), and falls back to Android 11+ "All files
/// access" settings if the OEM restricts legacy storage.
Future<bool> ensurePhoneStorageMounted(
  BuildContext context,
  WidgetRef ref,
) async {
  final runtimeNotifier = ref.read(localRuntimeProvider.notifier);
  await runtimeNotifier.refreshStorage();
  var storage = ref.read(localRuntimeProvider).storage;
  if (!storage.granted) {
    storage = await runtimeNotifier.requestStorage();
  }
  if (!storage.granted &&
      (storage.needsAllFilesFallback || storage.supportsAllFilesAccess)) {
    final opened = await runtimeNotifier.openAllFilesAccess();
    if (context.mounted) {
      showBriefNotice(
        context,
        opened
            ? '请在系统设置开启「所有文件访问权限」后返回，将自动完成挂载'
            : '请先在系统设置中授予手机存储访问权限',
      );
    }
    return false;
  }
  if (!storage.granted) {
    if (context.mounted) {
      showBriefNotice(context, '未获取手机存储权限，无法挂载本机目录');
    }
    return false;
  }
  if (!ref.read(settingsProvider).phoneStorage) {
    await runtimeNotifier.setPhoneStorage(true);
  }
  return true;
}

/// Opens the DSH Go-style 2-step folder picker (Locations sheet -> Directory browser)
/// and registers the chosen folder as a mounted workspace on the active host.
Future<WorkspaceItem?> addWorkspaceFlow(BuildContext context, WidgetRef ref) async {
  final path = await showDirectoryPicker(
    context,
    title: '添加工作区',
    confirmLabel: '添加',
  );
  if (path == null || !context.mounted) return null;
  final ws = await ref.read(workspacesProvider.notifier).add(path);
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showBriefNotice('已添加工作区「${ws.displayTitle}」');
  }
  return ws;
}

Future<String?> showDirectoryPicker(
  BuildContext context, {
  String title = '选择文件夹',
  String confirmLabel = '选择',
}) {
  return showAppSheet<String>(
    context,
    isScrollControlled: true,
    builder: (_) => _DirectoryLocationsSheet(
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

class _DirectoryLocationsSheet extends ConsumerStatefulWidget {
  const _DirectoryLocationsSheet({
    required this.title,
    required this.confirmLabel,
  });

  final String title;
  final String confirmLabel;

  @override
  ConsumerState<_DirectoryLocationsSheet> createState() =>
      _DirectoryLocationsSheetState();
}

class _DirectoryLocationsSheetState
    extends ConsumerState<_DirectoryLocationsSheet> {
  late final AppLifecycleListener _lifecycle;
  String? _pendingBrowsePath;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_handleResume()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(localRuntimeProvider.notifier).refreshStorage());
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _handleResume() async {
    await ref.read(localRuntimeProvider.notifier).refreshStorage();
    if (!mounted) return;
    final pending = _pendingBrowsePath;
    if (pending != null && ref.read(localRuntimeProvider).storage.granted) {
      _pendingBrowsePath = null;
      if (!ref.read(settingsProvider).phoneStorage) {
        await ref.read(localRuntimeProvider.notifier).setPhoneStorage(true);
      }
      if (mounted) await _browse(pending);
    }
  }

  Future<void> _browse(String startPath) async {
    final navigator = Navigator.of(context);
    final picked = await navigator.push<String>(
      MaterialPageRoute<String>(
        builder: (_) => DirectoryBrowserPage(
          startPath: startPath,
          confirmLabel: widget.confirmLabel,
        ),
      ),
    );
    if (picked != null && navigator.mounted) {
      navigator.pop(picked);
    }
  }

  Future<void> _openPhoneStoragePath(String path) async {
    final phoneStorage = ref.read(settingsProvider).phoneStorage;
    final granted = ref.read(localRuntimeProvider).storage.granted ||
        ref.read(localRuntimeProvider).status.phoneStorageGranted;
    if (phoneStorage && granted) {
      await _browse(path);
      return;
    }
    _pendingBrowsePath = path;
    final ok = await ensurePhoneStorageMounted(context, ref);
    if (!mounted) return;
    if (ok) {
      _pendingBrowsePath = null;
      await _browse(path);
    }
  }

  Future<void> _enterPath(String defaultDir) async {
    final typed = await showTextPromptDialog(
      context,
      title: '输入文件夹路径',
      hint: defaultDir,
      confirmLabel: '前往',
      mono: true,
      validate: (v) => v.startsWith('/') ? null : '请输入以 / 开头的绝对路径',
    );
    if (typed == null || !mounted) return;
    await _browse(typed);
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostsProvider.select((h) => h.active));
    final local = host.isLocal;
    final runtimeState = ref.watch(localRuntimeProvider);
    final runtime = runtimeState.status;
    final conn = ref.watch(activeConnectionProvider).value;
    final phoneStorage = ref.watch(settingsProvider.select((s) => s.phoneStorage));
    final recent = ref.watch(workspacesProvider.select((w) => w.recentPaths));
    final storageRoot = runtime.phoneStoragePath;
    final storageGranted =
        runtimeState.storage.granted || runtime.phoneStorageGranted;
    final storageReady = phoneStorage && storageGranted;
    final homePath = runtime.homePath;
    final defaultDir = local
        ? (runtime.workspacePath ?? conn?.defaultCwd ?? '/data/local/tmp')
        : (conn?.defaultCwd ?? '/root');

    final baseShortcuts = <(IconData, String, String, String?)>[
      if (local) ...[
        (AppIcons.defaultFolder, '默认工作区', defaultDir, '~/workspace'),
        if (homePath != null) (AppIcons.home, '主目录', homePath, '~'),
      ] else ...[
        (AppIcons.defaultFolder, '远程默认目录', defaultDir, defaultDir),
        (AppIcons.home, '根目录 /', '/', '/'),
      ],
    ];

    const margin = EdgeInsets.fromLTRB(
      SheetTitleBar.inset,
      0,
      SheetTitleBar.inset,
      12,
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(widget.title),
              SheetGroup(
                title: '位置',
                margin: margin,
                children: [
                  for (final (icon, label, path, sub) in baseShortcuts)
                    ListPageRow(
                      icon: icon,
                      title: label,
                      subtitle: sub,
                      onTap: () => unawaited(_browse(path)),
                    ),
                ],
              ),
              if (local)
                SheetGroup(
                  title: storageReady ? '手机存储（已挂载）' : '手机存储（点击授权挂载）',
                  margin: margin,
                  children: [
                    for (final preset in phoneStoragePresets)
                      ListPageRow(
                        icon: _iconForStoragePreset(preset),
                        title: preset.relativePath.isEmpty
                            ? preset.title
                            : '${preset.title} (${preset.relativePath})',
                        subtitle: storageReady
                            ? preset.subtitle
                            : '${preset.subtitle} · 需授予手机文件访问权限',
                        onTap: () => unawaited(
                          _openPhoneStoragePath(preset.pathFor(storageRoot)),
                        ),
                      ),
                  ],
                ),
              if (recent.isNotEmpty)
                SheetGroup(
                  title: '最近访问',
                  margin: margin,
                  children: [
                    for (final p in recent)
                      ListPageRow(
                        icon: AppIcons.history,
                        title: p.split('/').where((s) => s.isNotEmpty).lastOrNull ?? p,
                        subtitle: displayWorkspacePath(
                          p,
                          local: local,
                          homePath: homePath,
                          storageRoot: storageRoot,
                        ),
                        onTap: () => unawaited(_browse(p)),
                      ),
                  ],
                ),
              SheetGroup(
                margin: margin,
                children: [
                  ListPageRow(
                    icon: AppIcons.enterPath,
                    title: '手动输入路径',
                    chevron: false,
                    onTap: () => unawaited(_enterPath(defaultDir)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-page directory browser mirroring DSH Go's DirectoryBrowserPage.
class DirectoryBrowserPage extends ConsumerStatefulWidget {
  const DirectoryBrowserPage({
    super.key,
    required this.startPath,
    this.confirmLabel = '选择',
  });

  final String startPath;
  final String confirmLabel;

  @override
  ConsumerState<DirectoryBrowserPage> createState() =>
      _DirectoryBrowserPageState();
}

class _DirectoryBrowserPageState extends ConsumerState<DirectoryBrowserPage> {
  late String _currentPath = widget.startPath;
  List<WorkspaceEntry> _dirs = const [];
  Object? _error;
  bool _loading = true;
  bool _showHidden = false;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load(_currentPath, recordHistory: false));
  }

  Future<void> _load(String path, {bool recordHistory = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(workspaceProvider.notifier)
          .listSubdirectories(path);
      if (!mounted) return;
      setState(() {
        if (recordHistory && _currentPath != path) _history.add(_currentPath);
        _currentPath = path;
        _dirs = list;
        _loading = false;
        _showHidden = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _newFolder() async {
    final name = await showTextPromptDialog(
      context,
      title: '新建文件夹',
      caption: '位于 $_currentPath',
      hint: '文件夹名称',
      confirmLabel: '创建',
      validate: (v) {
        if (v.isEmpty) return '请输入名称';
        if (v.contains('/')) return '名称不能包含 /';
        return null;
      },
    );
    if (name == null || !mounted) return;
    try {
      final created = await ref
          .read(workspaceProvider.notifier)
          .createSubdirectoryAt(_currentPath, name);
      if (!mounted) return;
      await _load(created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    }
  }

  List<({String label, String path})> _crumbs(bool local, String storageRoot) {
    final parts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final raw = <({String label, String path})>[
      (label: '/', path: '/'),
    ];
    var acc = '';
    for (final p in parts) {
      acc = '$acc/$p';
      raw.add((label: p, path: acc));
    }
    if (local) {
      final storageIdx = raw.indexWhere((c) => c.path == storageRoot);
      if (storageIdx >= 0) {
        return [
          (label: '手机存储', path: storageRoot),
          ...raw.sublist(storageIdx + 1),
        ];
      }
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(hostsProvider.select((h) => h.active.isLocal));
    final storageRoot = ref.watch(
      localRuntimeProvider.select((s) => s.status.phoneStoragePath),
    );
    final crumbs = _crumbs(local, storageRoot);
    final title = crumbs.isEmpty ? _currentPath : crumbs.last.label;
    final hiddenCount = _dirs.where((d) => d.hidden).length;
    final shown = [
      for (final d in _dirs)
        if (_showHidden || !d.hidden) d,
    ];
    final colors = DshColors.of(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _history.isNotEmpty) {
          unawaited(_load(_history.removeLast(), recordHistory: false));
        }
      },
      child: Stack(
        children: [
          AppPage(
            key: ValueKey(_currentPath),
            title: title,
            actions: [
              GlassIconButton(
                icon: AppIcons.newFolder,
                tooltip: '新建文件夹',
                onPressed: _loading ? null : _newFolder,
              ),
            ],
            slivers: [
              SliverList.list(
                children: [
                  BreadcrumbRow(
                    crumbs: crumbs,
                    onTap: (p) {
                      if (p != _currentPath) unawaited(_load(p));
                    },
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    EmptyView(
                      icon: AppIcons.noFolder,
                      title: '无法读取目录',
                      message: '$_error',
                      actionLabel: '重试',
                      onAction: () => unawaited(_load(_currentPath, recordHistory: false)),
                    )
                  else if (shown.isEmpty)
                    const EmptyView(
                      icon: AppIcons.folderOpen,
                      title: '没有子文件夹',
                      message: '可以直接选择当前目录作为工作区，或点击右上角新建文件夹。',
                    )
                  else
                    ListPageCard(
                      children: [
                        for (final (i, dir) in shown.indexed)
                          FadeSlideIn(
                            index: i,
                            child: ListPageRow(
                              icon: AppIcons.folder,
                              iconColor: dir.hidden ? colors.textTertiary : null,
                              title: dir.name,
                              onTap: () => unawaited(_load(dir.path)),
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
                                ? '隐藏点文件夹'
                                : '显示 $hiddenCount 个隐藏文件夹',
                          ),
                        ),
                      ),
                    ),
                  SizedBox(height: bottomPad + 92),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 16,
            child: GlassSurface(
              tier: GlassTier.chrome,
              borderRadius: AppShape.radiusLg,
              padding: const EdgeInsets.all(10),
              child: FilledButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).pop(_currentPath),
                child: Text(
                  '${widget.confirmLabel}「$title」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawer workspace switcher row + sheet mirroring DSH Go's WorkspaceSwitcher.
class WorkspaceSwitcher extends ConsumerWidget {
  const WorkspaceSwitcher({super.key, required this.onManage});

  final VoidCallback onManage;
  static const height = 36.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedWorkspaceProvider);
    final theme = Theme.of(context);
    final tertiary = DshColors.of(context).textTertiary;
    final label = selected == null ? '全部工作区' : selected.displayTitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => showWorkspaceSheet(context, ref, onManage: onManage),
          customBorder: Squircle.border(AppShape.md),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected == null ? AppIcons.workspaceGroup : AppIcons.workspace,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(AppIcons.expand, size: 18, color: tertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _WsSheetAction { add, manage }

Future<void> showWorkspaceSheet(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onManage,
}) async {
  final action = await showAppSheet<_WsSheetAction>(
    context,
    isScrollControlled: true,
    builder: (_) => const _WorkspaceSheet(),
  );
  if (!context.mounted) return;
  switch (action) {
    case _WsSheetAction.add:
      await addWorkspaceFlow(context, ref);
    case _WsSheetAction.manage:
      if (onManage != null) {
        onManage();
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const WorkspacesPage()),
        );
      }
    case null:
      break;
  }
}

class _WorkspaceSheet extends ConsumerWidget {
  const _WorkspaceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wsState = ref.watch(workspacesProvider);
    final local = ref.watch(hostsProvider.select((h) => h.active.isLocal));
    final runtime = ref.watch(localRuntimeProvider).status;

    void pick(String? id) {
      unawaited(ref.read(workspacesProvider.notifier).select(id));
      Navigator.of(context).pop();
    }

    const margin = EdgeInsets.fromLTRB(
      SheetTitleBar.inset,
      0,
      SheetTitleBar.inset,
      12,
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetTitleBar('工作区'),
              SheetGroup(
                margin: margin,
                children: [
                  ListPageRow(
                    icon: AppIcons.workspaceGroup,
                    title: '全部工作区',
                    trailing: RowCheck(visible: wsState.selectedId == null),
                    onTap: () => pick(null),
                  ),
                ],
              ),
              for (final section in wsState.sections)
                SheetGroup(
                  title: section.title,
                  margin: margin,
                  children: [
                    for (final w in section.items)
                      ListPageRow(
                        icon: AppIcons.workspace,
                        title: w.displayTitle,
                        subtitle: displayWorkspacePath(
                          w.path,
                          local: local,
                          homePath: runtime.homePath,
                          storageRoot: runtime.phoneStoragePath,
                        ),
                        trailing: RowCheck(visible: wsState.selectedId == w.id),
                        onTap: () => pick(w.id),
                        onLongPress: () => showWorkspaceActionsSheet(context, ref, w),
                      ),
                  ],
                ),
              SheetGroup(
                margin: margin,
                children: [
                  ListPageRow(
                    icon: AppIcons.newFolder,
                    title: '添加工作区',
                    chevron: false,
                    onTap: () => Navigator.of(context).pop(_WsSheetAction.add),
                  ),
                  ListPageRow(
                    icon: AppIcons.configure,
                    title: '管理工作区',
                    onTap: () =>
                        Navigator.of(context).pop(_WsSheetAction.manage),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-workspace action sheet (new chat here, browse files, rename, pin, group, remove).
Future<void> showWorkspaceActionsSheet(
  BuildContext context,
  WidgetRef ref,
  WorkspaceItem workspace, {
  VoidCallback? onNewChat,
}) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => SheetNavigator(
      root: (_) => _WorkspaceActionsBody(
        workspaceId: workspace.id,
        onClose: () => Navigator.of(sheet).pop(),
        onNewChat: onNewChat,
      ),
    ),
  );
}

class _WorkspaceActionsBody extends ConsumerWidget {
  const _WorkspaceActionsBody({
    required this.workspaceId,
    required this.onClose,
    this.onNewChat,
  });

  final String workspaceId;
  final VoidCallback onClose;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wsState = ref.watch(workspacesProvider);
    final w = wsState.byId(workspaceId);
    final local = ref.watch(hostsProvider.select((h) => h.active.isLocal));
    final runtime = ref.watch(localRuntimeProvider).status;
    if (w == null) {
      return const SafeArea(top: false, child: SheetTitleBar('工作区'));
    }
    final pinned = wsState.pinnedIds.contains(w.id);
    final group = wsState.groups[w.id];
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
            SheetTitleBar(w.displayTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SheetTitleBar.inset,
                0,
                SheetTitleBar.inset,
                14,
              ),
              child: Text(
                displayWorkspacePath(
                  w.path,
                  local: local,
                  homePath: runtime.homePath,
                  storageRoot: runtime.phoneStoragePath,
                ),
                style: AppType.monoLabel(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SheetGroup(
              margin: margin,
              children: [
                ListPageRow(
                  icon: AppIcons.newChat,
                  title: '在此开始新对话',
                  chevron: false,
                  onTap: () {
                    unawaited(ref.read(workspacesProvider.notifier).select(w.id));
                    onClose();
                    onNewChat?.call();
                  },
                ),
                ListPageRow(
                  icon: AppIcons.files,
                  title: '浏览工作区文件',
                  chevron: false,
                  onTap: () {
                    unawaited(ref.read(workspacesProvider.notifier).select(w.id));
                    onClose();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const WorkspaceScreen(),
                      ),
                    );
                  },
                ),
                ListPageRow(
                  icon: AppIcons.rename,
                  title: '重命名',
                  chevron: false,
                  onTap: () async {
                    onClose();
                    final next = await showTextPromptDialog(
                      context,
                      title: '重命名工作区',
                      initial: w.displayTitle,
                      hint: '工作区名称',
                      validate: (v) => v.isEmpty ? '请输入名称' : null,
                    );
                    if (next != null && next.isNotEmpty) {
                      await ref
                          .read(workspacesProvider.notifier)
                          .rename(w.id, next);
                    }
                  },
                ),
                ListPageRow(
                  icon: pinned ? AppIcons.pinActive : AppIcons.pin,
                  title: pinned ? '取消置顶' : '置顶',
                  chevron: false,
                  onTap: () => unawaited(
                    ref.read(workspacesProvider.notifier).setPinned(w.id, !pinned),
                  ),
                ),
                ListPageRow(
                  icon: AppIcons.workspaceGroup,
                  title: '分组',
                  value: group ?? '未分组',
                  onTap: () => SheetNavigator.of(context).push(
                    (_) => _WorkspaceGroupPicker(workspaceId: w.id),
                  ),
                ),
              ],
            ),
            if (!w.isDefault)
              SheetGroup(
                margin: margin,
                children: [
                  ListPageRow(
                    icon: AppIcons.remove,
                    title: '移出工作区列表',
                    subtitle: '不会删除手机或服务器上的原文件',
                    danger: true,
                    chevron: false,
                    onTap: () async {
                      onClose();
                      await ref.read(workspacesProvider.notifier).remove(w.id);
                    },
                  ),
                ],
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceGroupPicker extends ConsumerWidget {
  const _WorkspaceGroupPicker({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wsState = ref.watch(workspacesProvider);
    final groups = wsState.groupNames;
    final current = wsState.groups[workspaceId];
    final sheet = SheetNavigator.of(context);
    const margin = EdgeInsets.fromLTRB(
      SheetTitleBar.inset,
      0,
      SheetTitleBar.inset,
      12,
    );

    Future<void> pick(String? name) async {
      await ref.read(workspacesProvider.notifier).setGroup(workspaceId, name);
      sheet.pop();
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitleBar('分组'),
            SheetGroup(
              margin: margin,
              children: [
                ListPageRow(
                  icon: AppIcons.workspace,
                  title: '未分组',
                  trailing: RowCheck(visible: current == null),
                  onTap: () => unawaited(pick(null)),
                ),
                for (final g in groups)
                  ListPageRow(
                    icon: AppIcons.workspaceGroup,
                    title: g,
                    trailing: RowCheck(visible: current == g),
                    onTap: () => unawaited(pick(g)),
                  ),
              ],
            ),
            SheetGroup(
              margin: margin,
              children: [
                ListPageRow(
                  icon: AppIcons.add,
                  title: '新建分组',
                  chevron: false,
                  onTap: () async {
                    final name = await showTextPromptDialog(
                      context,
                      title: '新建分组',
                      hint: '例如：工作项目 / 学习',
                      confirmLabel: '创建',
                      validate: (v) => v.isEmpty ? '请输入分组名' : null,
                    );
                    if (name != null && name.isNotEmpty) {
                      await pick(name);
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
  }
}

/// Workspaces management page mirroring DSH Go's WorkspacesPage, with direct
/// Android shared-storage authorization and one-tap quick mounting (手机存储 / 下载 / 文档 / 相册 / 图片).
class WorkspacesPage extends ConsumerStatefulWidget {
  const WorkspacesPage({super.key});

  @override
  ConsumerState<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends ConsumerState<WorkspacesPage> {
  late final AppLifecycleListener _lifecycle;
  PhoneStoragePreset? _pendingMountPreset;
  bool _pendingBrowseStorage = false;
  bool _pendingEnableStorage = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_handleResume()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(localRuntimeProvider.notifier).refreshStorage());
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _handleResume() async {
    await ref.read(localRuntimeProvider.notifier).refreshStorage();
    if (!mounted) return;
    final granted = ref.read(localRuntimeProvider).storage.granted ||
        ref.read(localRuntimeProvider).status.phoneStorageGranted;
    if (!granted) return;

    if (_pendingEnableStorage ||
        _pendingMountPreset != null ||
        _pendingBrowseStorage) {
      if (!ref.read(settingsProvider).phoneStorage) {
        await ref.read(localRuntimeProvider.notifier).setPhoneStorage(true);
      }
    }
    if (!mounted) return;

    final preset = _pendingMountPreset;
    final browse = _pendingBrowseStorage;
    final enableOnly = _pendingEnableStorage;
    _pendingMountPreset = null;
    _pendingBrowseStorage = false;
    _pendingEnableStorage = false;

    if (preset != null) {
      await _mountPresetDirect(preset);
    } else if (browse) {
      await _browsePhoneStorageDirect();
    } else if (enableOnly) {
      showBriefNotice(context, '已授权并开启手机存储挂载');
    }
  }

  Future<void> _togglePhoneStorage(bool enabled) async {
    if (!enabled) {
      _pendingEnableStorage = false;
      await ref.read(localRuntimeProvider.notifier).setPhoneStorage(false);
      if (mounted) showBriefNotice(context, '已关闭手机存储挂载');
      return;
    }
    _pendingEnableStorage = true;
    final ok = await ensurePhoneStorageMounted(context, ref);
    if (!mounted) return;
    if (ok) {
      _pendingEnableStorage = false;
      showBriefNotice(context, '已开启手机存储挂载（~/手机存储）');
    }
  }

  Future<void> _mountPresetDirect(PhoneStoragePreset preset) async {
    final storageRoot = ref.read(localRuntimeProvider).status.phoneStoragePath;
    final path = preset.pathFor(storageRoot);
    final ws = await ref
        .read(workspacesProvider.notifier)
        .add(path, title: preset.title);
    if (mounted) {
      showBriefNotice(context, '已挂载工作区「${ws.displayTitle}」');
    }
  }

  Future<void> _onTapPreset(
    PhoneStoragePreset preset,
    WorkspaceItem? existing,
  ) async {
    if (existing != null) {
      await showWorkspaceActionsSheet(
        context,
        ref,
        existing,
        onNewChat: () =>
            Navigator.of(context).popUntil((route) => route.isFirst),
      );
      return;
    }
    final phoneStorage = ref.read(settingsProvider).phoneStorage;
    final granted = ref.read(localRuntimeProvider).storage.granted ||
        ref.read(localRuntimeProvider).status.phoneStorageGranted;
    if (phoneStorage && granted) {
      await _mountPresetDirect(preset);
      return;
    }
    _pendingMountPreset = preset;
    final ok = await ensurePhoneStorageMounted(context, ref);
    if (!mounted) return;
    if (ok) {
      _pendingMountPreset = null;
      await _mountPresetDirect(preset);
    }
  }

  Future<void> _browsePhoneStorageDirect() async {
    final storageRoot = ref.read(localRuntimeProvider).status.phoneStoragePath;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => DirectoryBrowserPage(
          startPath: storageRoot,
          confirmLabel: '挂载',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final ws = await ref.read(workspacesProvider.notifier).add(picked);
    if (mounted) {
      showBriefNotice(context, '已挂载工作区「${ws.displayTitle}」');
    }
  }

  Future<void> _onTapBrowsePhoneStorage() async {
    final phoneStorage = ref.read(settingsProvider).phoneStorage;
    final granted = ref.read(localRuntimeProvider).storage.granted ||
        ref.read(localRuntimeProvider).status.phoneStorageGranted;
    if (phoneStorage && granted) {
      await _browsePhoneStorageDirect();
      return;
    }
    _pendingBrowseStorage = true;
    final ok = await ensurePhoneStorageMounted(context, ref);
    if (!mounted) return;
    if (ok) {
      _pendingBrowseStorage = false;
      await _browsePhoneStorageDirect();
    }
  }

  WorkspaceItem? _findMountedPreset(
    WorkspacesState wsState,
    PhoneStoragePreset preset,
    String storageRoot,
  ) {
    final target = preset.pathFor(storageRoot);
    final guestTarget = preset.pathFor('/sdcard');
    for (final w in wsState.workspaces) {
      if (w.path == target || w.path == guestTarget) return w;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(workspacesProvider);
    final local = ref.watch(hostsProvider.select((h) => h.active.isLocal));
    final runtimeState = ref.watch(localRuntimeProvider);
    final runtime = runtimeState.status;
    final phoneStorage = ref.watch(
      settingsProvider.select((s) => s.phoneStorage),
    );
    final storageRoot = runtime.phoneStoragePath;
    final storageGranted =
        runtimeState.storage.granted || runtime.phoneStorageGranted;
    final storageMounted = phoneStorage && storageGranted;
    final sections = wsState.sections;

    return AppPage.list(
      title: '工作区',
      subtitle: Text(
        '${wsState.workspaces.length} 个已挂载目录 · 新对话将自动进入所选工作区',
      ),
      actions: [
        GlassIconButton(
          icon: AppIcons.add,
          tooltip: '添加工作区',
          onPressed: () => unawaited(addWorkspaceFlow(context, ref)),
        ),
      ],
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: ListPageCard(
              title: section.title,
              children: [
                for (final (idx, w) in section.items.indexed)
                  FadeSlideIn(
                    index: idx,
                    child: ListPageRow(
                      icon: AppIcons.workspace,
                      title: w.displayTitle,
                      subtitle: displayWorkspacePath(
                        w.path,
                        local: local,
                        homePath: runtime.homePath,
                        storageRoot: storageRoot,
                      ),
                      trailing: wsState.selectedId == w.id
                          ? const RowCheck(visible: true)
                          : null,
                      onTap: () => showWorkspaceActionsSheet(
                        context,
                        ref,
                        w,
                        onNewChat: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (local)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: ListPageCard(
              title: '手机存储与快捷挂载',
              children: [
                ListPageRow(
                  icon: AppIcons.fileAccess,
                  title: '允许 agy 访问手机存储',
                  subtitle: storageMounted
                      ? '已挂载 $storageRoot · 快捷入口 ~/手机存储'
                      : storageGranted
                      ? '系统权限已就绪，开启即可挂载本机存储与下载目录'
                      : '点击授权挂载手机存储、下载、文档与相册',
                  chevron: false,
                  trailing: Switch.adaptive(
                    value: storageMounted,
                    onChanged: (v) => unawaited(_togglePhoneStorage(v)),
                  ),
                  onTap: () => unawaited(_togglePhoneStorage(!storageMounted)),
                ),
                for (final preset in phoneStoragePresets)
                  Builder(
                    builder: (context) {
                      final mountedItem = _findMountedPreset(
                        wsState,
                        preset,
                        storageRoot,
                      );
                      final isMounted = mountedItem != null;
                      return ListPageRow(
                        icon: _iconForStoragePreset(preset),
                        title: preset.relativePath.isEmpty
                            ? preset.title
                            : '${preset.title} (${preset.relativePath})',
                        subtitle: preset.subtitle,
                        value: isMounted
                            ? '已挂载'
                            : (storageMounted ? '点击挂载' : '授权并挂载'),
                        trailing: isMounted
                            ? const RowCheck(visible: true)
                            : null,
                        chevron: !isMounted,
                        onTap: () =>
                            unawaited(_onTapPreset(preset, mountedItem)),
                      );
                    },
                  ),
                ListPageRow(
                  icon: AppIcons.folderOpen,
                  title: '浏览手机存储选择其他目录',
                  subtitle: '进入 $storageRoot 浏览并挂载任意子文件夹',
                  onTap: () => unawaited(_onTapBrowsePhoneStorage()),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
