// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agy_remote/agy_remote.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_state.dart';
import 'hosts_state.dart';
import 'runtime_state.dart';
import 'settings_state.dart';

/// A registered workspace directory mounted for sessions on the active host.
class WorkspaceItem {
  const WorkspaceItem({
    required this.id,
    required this.path,
    required this.title,
    this.isDefault = false,
    this.createdAt,
  });

  factory WorkspaceItem.fromJson(Map<String, Object?> json) => WorkspaceItem(
    id: json['id'] as String? ?? '',
    path: json['path'] as String? ?? '',
    title: json['title'] as String? ?? '',
    isDefault: json['isDefault'] == true,
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
  );

  final String id;
  final String path;
  final String title;
  final bool isDefault;
  final DateTime? createdAt;

  String get displayTitle {
    final t = title.trim();
    if (isDefault && (t.isEmpty || t == 'default-workspace')) {
      return '默认工作区';
    }
    if (t.isNotEmpty) return t;
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'isDefault': isDefault,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  WorkspaceItem copyWith({String? title, String? path}) => WorkspaceItem(
    id: id,
    path: path ?? this.path,
    title: title ?? this.title,
    isDefault: isDefault,
    createdAt: createdAt,
  );
}

enum WorkspaceSectionKind { pinned, group, rest }

class WorkspaceSection {
  const WorkspaceSection(this.kind, this.title, this.items);

  final WorkspaceSectionKind kind;
  final String? title;
  final List<WorkspaceItem> items;
}

class WorkspacesState {
  const WorkspacesState({
    this.loaded = false,
    this.workspaces = const [],
    this.selectedId,
    this.pinnedIds = const [],
    this.groups = const {},
    this.recentPaths = const [],
  });

  final bool loaded;
  final List<WorkspaceItem> workspaces;
  final String? selectedId;
  final List<String> pinnedIds;
  final Map<String, String> groups;
  final List<String> recentPaths;

  WorkspaceItem? byId(String? id) {
    if (id == null) return null;
    for (final w in workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  WorkspaceItem? get selected => byId(selectedId);

  List<WorkspaceSection> get sections {
    final pinSet = pinnedIds.toSet();
    final pinned = [
      for (final w in workspaces)
        if (pinSet.contains(w.id)) w,
    ];
    final grouped = <String, List<WorkspaceItem>>{};
    final rest = <WorkspaceItem>[];
    for (final w in workspaces) {
      if (pinSet.contains(w.id)) continue;
      final g = groups[w.id];
      if (g == null || g.isEmpty) {
        rest.add(w);
      } else {
        grouped.putIfAbsent(g, () => []).add(w);
      }
    }
    final titled = pinned.isNotEmpty || grouped.isNotEmpty;
    return [
      if (pinned.isNotEmpty)
        WorkspaceSection(WorkspaceSectionKind.pinned, '置顶', pinned),
      for (final entry in grouped.entries)
        WorkspaceSection(WorkspaceSectionKind.group, entry.key, entry.value),
      if (rest.isNotEmpty)
        WorkspaceSection(
          WorkspaceSectionKind.rest,
          titled ? '其他' : null,
          rest,
        ),
    ];
  }

  List<String> get groupNames {
    final names = <String>{};
    for (final w in workspaces) {
      if (groups[w.id] case final g? when g.isNotEmpty) names.add(g);
    }
    return names.toList();
  }

  WorkspacesState copyWith({
    bool? loaded,
    List<WorkspaceItem>? workspaces,
    String? Function()? selectedId,
    List<String>? pinnedIds,
    Map<String, String>? groups,
    List<String>? recentPaths,
  }) => WorkspacesState(
    loaded: loaded ?? this.loaded,
    workspaces: workspaces ?? this.workspaces,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    pinnedIds: pinnedIds ?? this.pinnedIds,
    groups: groups ?? this.groups,
    recentPaths: recentPaths ?? this.recentPaths,
  );
}

/// Manages per-host registered workspaces, selection, pinning, grouping, and
/// Android PRoot/native bind synchronization.
class WorkspacesController extends Notifier<WorkspacesState> {
  static const _maxRecent = 4;
  String _storageKey = '';
  int _gen = 0;
  final Map<String, WorkspacesState> _cache = {};

  static String keyFor(HostRef host) =>
      'agy.workspaces.${host.kind.name}.${host.id}';

  @override
  WorkspacesState build() {
    final host = ref.watch(hostsProvider.select((h) => h.active));
    final connCwd = ref.watch(
      activeConnectionProvider.select((a) => a.value?.defaultCwd),
    );
    final runtimePaths = ref.watch(
      localRuntimeProvider.select(
        (s) => (
          workspacePath: s.status.workspacePath,
          storagePath: s.status.phoneStoragePath,
          storageGranted: s.status.phoneStorageGranted,
        ),
      ),
    );
    final phoneStorage = ref.watch(
      settingsProvider.select((s) => s.phoneStorage),
    );

    final defaultPath = host.isLocal
        ? (runtimePaths.workspacePath ?? connCwd ?? Directory.current.path)
        : (connCwd ?? '/root');
    final storageRoot = runtimePaths.storagePath;

    _storageKey = keyFor(host);
    final gen = ++_gen;
    unawaited(
      _load(
        _storageKey,
        gen: gen,
        host: host,
        defaultPath: defaultPath,
        includeStoragePreset:
            host.isLocal && phoneStorage && runtimePaths.storageGranted,
        storageRoot: storageRoot,
      ),
    );
    final cached = _cache[_storageKey];
    if (cached != null) {
      return cached;
    }
    return WorkspacesState(
      workspaces: [
        WorkspaceItem(
          id: 'default',
          path: defaultPath,
          title: 'default-workspace',
          isDefault: true,
        ),
      ],
    );
  }

  Future<void> _load(
    String key, {
    required int gen,
    required HostRef host,
    required String defaultPath,
    required bool includeStoragePreset,
    required String storageRoot,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      var workspaces = <WorkspaceItem>[];
      String? selectedId;
      var pinnedIds = <String>[];
      var groups = <String, String>{};
      var recent = <String>[];

      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, Object?>;
        if (map['workspaces'] is List) {
          for (final item in (map['workspaces'] as List).whereType<Map>()) {
            final parsed = WorkspaceItem.fromJson(
              Map<String, Object?>.from(item),
            );
            if (parsed.id.isNotEmpty && parsed.path.isNotEmpty) {
              workspaces.add(parsed);
            }
          }
        }
        selectedId = map['selectedId'] as String?;
        if (map['pinnedIds'] is List) {
          pinnedIds = (map['pinnedIds'] as List).whereType<String>().toList();
        }
        if (map['groups'] is Map) {
          groups = {
            for (final e in (map['groups'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
          };
        }
        if (map['recentPaths'] is List) {
          recent = (map['recentPaths'] as List).whereType<String>().toList();
        }
      }

      // Always keep the default workspace entry synchronized with the active runtime path.
      final defaultIdx = workspaces.indexWhere((w) => w.id == 'default');
      if (defaultIdx >= 0) {
        workspaces[defaultIdx] = workspaces[defaultIdx].copyWith(path: defaultPath);
      } else {
        workspaces.insert(
          0,
          WorkspaceItem(
            id: 'default',
            path: defaultPath,
            title: 'default-workspace',
            isDefault: true,
            createdAt: DateTime.now(),
          ),
        );
      }

      // Convenience entry when phone storage is newly authorized & mounted.
      if (includeStoragePreset &&
          !workspaces.any((w) => w.path == storageRoot)) {
        workspaces.add(
          WorkspaceItem(
            id: 'phone-storage',
            path: storageRoot,
            title: '手机存储',
            createdAt: DateTime.now(),
          ),
        );
      }

      if (selectedId != null && !workspaces.any((w) => w.id == selectedId)) {
        selectedId = null;
      }

      if (!ref.mounted || _storageKey != key || _gen != gen) return;
      final loadedState = WorkspacesState(
        loaded: true,
        workspaces: workspaces,
        selectedId: selectedId,
        pinnedIds: pinnedIds,
        groups: groups,
        recentPaths: recent,
      );
      _cache[key] = loadedState;
      state = loadedState;
      if (host.isLocal) {
        unawaited(_syncLocalBinds(workspaces));
      }
    } catch (_) {
      if (!ref.mounted || _storageKey != key || _gen != gen) return;
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> _save(WorkspacesState next) async {
    _gen++;
    final key = _storageKey;
    _cache[key] = next;
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'workspaces': [for (final w in next.workspaces) w.toJson()],
          'selectedId': next.selectedId,
          'pinnedIds': next.pinnedIds,
          'groups': next.groups,
          'recentPaths': next.recentPaths,
        }),
      );
    } catch (_) {}
    if (ref.mounted && ref.read(hostsProvider).active.isLocal) {
      unawaited(_syncLocalBinds(next.workspaces));
    }
  }

  Future<void> _syncLocalBinds(List<WorkspaceItem> workspaces) async {
    final paths = [
      for (final w in workspaces)
        if (!w.isDefault && w.path.startsWith('/')) w.path,
    ];
    await ref.read(runtimeChannelProvider).setWorkspaceBinds(paths);
  }

  Future<WorkspaceItem> add(String rawPath, {String? title}) async {
    final clean = _normalizePath(rawPath);
    for (final existing in state.workspaces) {
      if (existing.path == clean) {
        await select(existing.id);
        return existing;
      }
    }
    final name = (title?.trim().isNotEmpty ?? false)
        ? title!.trim()
        : _folderName(clean);
    final item = WorkspaceItem(
      id: 'ws_${DateTime.now().microsecondsSinceEpoch}',
      path: clean,
      title: name,
      createdAt: DateTime.now(),
    );
    final parent = _parentFolder(clean);
    final nextRecent = parent == null
        ? state.recentPaths
        : [
            parent,
            for (final p in state.recentPaths)
              if (p != parent) p,
          ].take(_maxRecent).toList();
    final next = state.copyWith(
      workspaces: [...state.workspaces, item],
      selectedId: () => item.id,
      recentPaths: nextRecent,
    );
    await _save(next);
    return item;
  }

  Future<void> select(String? workspaceId) async {
    await _save(state.copyWith(selectedId: () => workspaceId));
  }

  Future<void> rename(String workspaceId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    final next = [
      for (final w in state.workspaces)
        if (w.id == workspaceId) w.copyWith(title: clean) else w,
    ];
    await _save(state.copyWith(workspaces: next));
  }

  Future<void> setPinned(String workspaceId, bool pinned) async {
    final next = [
      if (pinned) workspaceId,
      for (final id in state.pinnedIds)
        if (id != workspaceId) id,
    ];
    await _save(state.copyWith(pinnedIds: next));
  }

  Future<void> setGroup(String workspaceId, String? group) async {
    final clean = group?.trim() ?? '';
    final next = Map<String, String>.from(state.groups)..remove(workspaceId);
    if (clean.isNotEmpty) next[workspaceId] = clean;
    await _save(state.copyWith(groups: next));
  }

  Future<void> remove(String workspaceId) async {
    if (workspaceId == 'default') return;
    final nextList = state.workspaces.where((w) => w.id != workspaceId).toList();
    final nextGroups = Map<String, String>.from(state.groups)..remove(workspaceId);
    final nextPins = state.pinnedIds.where((id) => id != workspaceId).toList();
    await _save(
      state.copyWith(
        workspaces: nextList,
        selectedId: () =>
            state.selectedId == workspaceId ? null : state.selectedId,
        pinnedIds: nextPins,
        groups: nextGroups,
      ),
    );
  }

  static String _normalizePath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length > 1 && trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _folderName(String path) {
    for (final preset in phoneStoragePresets) {
      if (path == preset.pathFor('/storage/emulated/0') ||
          path == preset.pathFor('/sdcard')) {
        return preset.title;
      }
    }
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  static String? _parentFolder(String path) {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return null;
    return path.substring(0, idx);
  }
}

/// Standard Android shared-storage directories that can be mounted directly as
/// workspaces or browsed from the 2-step directory picker (mirroring DSH Go).
class PhoneStoragePreset {
  const PhoneStoragePreset({
    required this.id,
    required this.title,
    required this.relativePath,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String relativePath;
  final String subtitle;

  String pathFor(String storageRoot) {
    final base = storageRoot.endsWith('/') && storageRoot.length > 1
        ? storageRoot.substring(0, storageRoot.length - 1)
        : storageRoot;
    return relativePath.isEmpty ? base : '$base/$relativePath';
  }
}

const phoneStoragePresets = <PhoneStoragePreset>[
  PhoneStoragePreset(
    id: 'phone-storage',
    title: '手机存储',
    relativePath: '',
    subtitle: '手机内部存储根目录',
  ),
  PhoneStoragePreset(
    id: 'phone-download',
    title: '下载',
    relativePath: 'Download',
    subtitle: '手机存储/Download',
  ),
  PhoneStoragePreset(
    id: 'phone-documents',
    title: '文档',
    relativePath: 'Documents',
    subtitle: '手机存储/Documents',
  ),
  PhoneStoragePreset(
    id: 'phone-dcim',
    title: '相册',
    relativePath: 'DCIM',
    subtitle: '手机存储/DCIM',
  ),
  PhoneStoragePreset(
    id: 'phone-pictures',
    title: '图片',
    relativePath: 'Pictures',
    subtitle: '手机存储/Pictures',
  ),
];

final workspacesProvider =
    NotifierProvider<WorkspacesController, WorkspacesState>(
      WorkspacesController.new,
    );

final selectedWorkspaceProvider = Provider<WorkspaceItem?>(
  (ref) => ref.watch(workspacesProvider).selected,
);

/// The real filesystem path passed to `agy acp` as `cwd` for new sessions and
/// opened by default in the Workspace Files browser.
final effectiveWorkingDirProvider = Provider<String>((ref) {
  final selected = ref.watch(selectedWorkspaceProvider);
  if (selected != null && selected.path.isNotEmpty) return selected.path;
  final conn = ref.watch(activeConnectionProvider).value;
  if (conn != null && conn.defaultCwd.isNotEmpty) return conn.defaultCwd;
  final runtime = ref.watch(localRuntimeProvider).status;
  return runtime.workspacePath ?? Directory.current.path;
});

/// Human-readable short display path (mirrors DSH Go's workspace_format).
String displayWorkspacePath(
  String path, {
  required bool local,
  String? homePath,
  String storageRoot = '/storage/emulated/0',
}) {
  if (local) {
    if (path == storageRoot || path == '/sdcard') return '手机存储';
    if (path.startsWith('$storageRoot/')) {
      return '手机存储/${path.substring(storageRoot.length + 1)}';
    }
    if (path.startsWith('/sdcard/')) {
      return '手机存储/${path.substring('/sdcard/'.length)}';
    }
    if (homePath != null && homePath.isNotEmpty) {
      if (path == '$homePath/workspace') return '~/workspace';
      if (path == homePath) return '~';
      if (path.startsWith('$homePath/')) {
        return '~/${path.substring(homePath.length + 1)}';
      }
    }
  }
  return path;
}

/// Canonicalizes workspace/session paths (trims trailing `/` and unifies Android
/// `/sdcard` with `/storage/emulated/0`) so sessions reliably match their workspace.
String normalizeWorkspacePath(String raw) {
  var p = raw.trim();
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  if (p == '/sdcard') return '/storage/emulated/0';
  if (p.startsWith('/sdcard/')) {
    return '/storage/emulated/0/${p.substring('/sdcard/'.length)}';
  }
  return p;
}

/// Finds the registered [WorkspaceItem] owning [cwd] via longest-prefix match.
WorkspaceItem? matchWorkspaceForCwd(
  String cwd,
  List<WorkspaceItem> workspaces,
) {
  final norm = normalizeWorkspacePath(cwd);
  if (norm.isEmpty) return null;
  WorkspaceItem? best;
  var bestLen = -1;
  for (final ws in workspaces) {
    final wsNorm = normalizeWorkspacePath(ws.path);
    if (wsNorm.isEmpty) continue;
    final exact = norm == wsNorm;
    final inside = wsNorm == '/'
        ? norm.startsWith('/')
        : norm.startsWith('$wsNorm/');
    if ((exact || inside) && wsNorm.length > bestLen) {
      best = ws;
      bestLen = wsNorm.length;
    }
  }
  return best;
}
