import 'dart:async';
import 'dart:convert';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_state.dart';
import 'hosts_state.dart';
import 'workspaces_state.dart';

enum DrawerSessionFilter { all, pinned, archived }

class SessionsState {
  const SessionsState({
    this.sessions = const [],
    this.currentSessionId,
    this.loading = false,
    this.error,
    this.pinnedIds = const [],
    this.archivedIds = const [],
    this.deletedIds = const [],
    this.customTitles = const {},
    this.folders = const [],
    this.sessionFolders = const {},
    this.sessionWorkspaces = const {},
    this.collapsedWorkspaceKeys = const [],
    this.activeFolder,
    this.filter = DrawerSessionFilter.all,
  });

  final List<AcpSessionInfo> sessions;
  final String? currentSessionId;
  final bool loading;
  final String? error;
  final List<String> pinnedIds;
  final List<String> archivedIds;

  /// Persisted deleted session IDs so conversations stay deleted across restarts
  /// even when an ACP engine does not advertise `session/delete`.
  final List<String> deletedIds;
  final Map<String, String> customTitles;
  final List<String> folders;
  final Map<String, String> sessionFolders;

  /// Persisted `sessionId -> normalized workspace cwd` mapping so every
  /// conversation reliably stays grouped under its owning workspace.
  final Map<String, String> sessionWorkspaces;
  final List<String> collapsedWorkspaceKeys;
  final String? activeFolder;
  final DrawerSessionFilter filter;

  AcpSessionInfo? get currentSession {
    final id = currentSessionId;
    if (id == null) return null;
    for (final s in sessions) {
      if (s.sessionId == id) return s;
    }
    return null;
  }

  String displayTitle(AcpSessionInfo s) {
    final custom = customTitles[s.sessionId]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final raw = s.title?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return '新对话';
  }

  String effectiveCwdOf(AcpSessionInfo s) {
    final live = s.cwd.trim();
    if (live.isNotEmpty) return normalizeWorkspacePath(live);
    final saved = sessionWorkspaces[s.sessionId]?.trim() ?? '';
    return saved.isEmpty ? '' : normalizeWorkspacePath(saved);
  }

  bool isPinned(String id) => pinnedIds.contains(id);
  bool isArchived(String id) => archivedIds.contains(id);
  bool isDeleted(String id) => deletedIds.contains(id);
  String? folderOf(String id) => sessionFolders[id];
  bool isWorkspaceCollapsed(String key) => collapsedWorkspaceKeys.contains(key);

  SessionsState copyWith({
    List<AcpSessionInfo>? sessions,
    String? currentSessionId,
    bool clearCurrent = false,
    bool? loading,
    String? error,
    bool clearError = false,
    List<String>? pinnedIds,
    List<String>? archivedIds,
    List<String>? deletedIds,
    Map<String, String>? customTitles,
    List<String>? folders,
    Map<String, String>? sessionFolders,
    Map<String, String>? sessionWorkspaces,
    List<String>? collapsedWorkspaceKeys,
    String? Function()? activeFolder,
    DrawerSessionFilter? filter,
  }) => SessionsState(
    sessions: sessions ?? this.sessions,
    currentSessionId: clearCurrent
        ? null
        : (currentSessionId ?? this.currentSessionId),
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    pinnedIds: pinnedIds ?? this.pinnedIds,
    archivedIds: archivedIds ?? this.archivedIds,
    deletedIds: deletedIds ?? this.deletedIds,
    customTitles: customTitles ?? this.customTitles,
    folders: folders ?? this.folders,
    sessionFolders: sessionFolders ?? this.sessionFolders,
    sessionWorkspaces: sessionWorkspaces ?? this.sessionWorkspaces,
    collapsedWorkspaceKeys:
        collapsedWorkspaceKeys ?? this.collapsedWorkspaceKeys,
    activeFolder: activeFolder == null ? this.activeFolder : activeFolder(),
    filter: filter ?? this.filter,
  );
}

class SessionsController extends Notifier<SessionsState> {
  String _prefsKey = '';
  int _metaVersion = 0;

  @override
  SessionsState build() {
    final host = ref.watch(hostsProvider.select((h) => h.active));
    _prefsKey = 'agy.sessions.meta.${host.kind.name}.${host.id}';
    _metaVersion++;
    unawaited(_loadMeta(_prefsKey, _metaVersion));

    ref.listen<String>(
      workspacesProvider.select((w) => w.workspaces.map((e) => e.path).join('|')),
      (prev, next) {
        if (prev == null || prev == next) return;
        final conn = ref.read(activeConnectionProvider).value;
        if (conn != null) unawaited(_refreshFor(conn));
      },
    );

    final conn = ref.watch(activeConnectionProvider.select((a) => a.value));
    if (conn == null) return const SessionsState();
    unawaited(_refreshFor(conn));
    return const SessionsState(loading: true);
  }

  Future<void> _loadMeta(String key, int expectedVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null ||
          raw.isEmpty ||
          !ref.mounted ||
          _prefsKey != key ||
          _metaVersion != expectedVersion) {
        return;
      }
      final map = jsonDecode(raw) as Map<String, Object?>;
      final deleted =
          (map['deleted'] as List?)?.whereType<String>().toList() ?? const [];
      final deletedSet = deleted.toSet();
      final filteredSessions = deletedSet.isEmpty
          ? state.sessions
          : state.sessions
                .where((s) => !deletedSet.contains(s.sessionId))
                .toList();
      final clearCurrent =
          state.currentSessionId != null &&
          deletedSet.contains(state.currentSessionId);
      state = state.copyWith(
        sessions: filteredSessions,
        clearCurrent: clearCurrent,
        pinnedIds:
            (map['pinned'] as List?)?.whereType<String>().toList() ?? const [],
        archivedIds:
            (map['archived'] as List?)?.whereType<String>().toList() ?? const [],
        deletedIds: deleted,
        customTitles: {
          if (map['titles'] is Map)
            for (final e in (map['titles'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
        },
        folders:
            (map['folders'] as List?)?.whereType<String>().toList() ?? const [],
        sessionFolders: {
          if (map['sessionFolders'] is Map)
            for (final e in (map['sessionFolders'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
        },
        sessionWorkspaces: {
          if (map['sessionWorkspaces'] is Map)
            for (final e in (map['sessionWorkspaces'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: normalizeWorkspacePath(e.value as String),
        },
        collapsedWorkspaceKeys:
            (map['collapsedWorkspaces'] as List?)?.whereType<String>().toList() ??
            const [],
      );
    } catch (_) {}
  }

  Future<void> _saveMeta() async {
    _metaVersion++;
    final key = _prefsKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'pinned': state.pinnedIds,
          'archived': state.archivedIds,
          'deleted': state.deletedIds,
          'titles': state.customTitles,
          'folders': state.folders,
          'sessionFolders': state.sessionFolders,
          'sessionWorkspaces': state.sessionWorkspaces,
          'collapsedWorkspaces': state.collapsedWorkspaceKeys,
        }),
      );
    } catch (_) {}
  }

  Future<void> refresh() async {
    final conn = ref.read(activeConnectionProvider).value;
    if (conn == null) return;
    await _refreshFor(conn);
  }

  Future<void> _refreshFor(HostConnection conn) async {
    if (!conn.initResult.capabilities.canListSessions) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, clearError: true);
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final byId = <String, AcpSessionInfo>{};
      final deletedSet = state.deletedIds.toSet();
      void ingest(List<AcpSessionInfo> list, {String? fallbackCwd}) {
        for (final s in list) {
          if (deletedSet.contains(s.sessionId)) continue;
          final existing = byId[s.sessionId];
          final rawCwd = s.cwd.trim().isNotEmpty
              ? s.cwd.trim()
              : (existing?.cwd.trim().isNotEmpty == true
                    ? existing!.cwd.trim()
                    : (fallbackCwd ?? state.sessionWorkspaces[s.sessionId] ?? ''));
          final resolvedCwd = rawCwd.isEmpty
              ? ''
              : normalizeWorkspacePath(rawCwd);
          final resolvedTitle = s.title?.trim().isNotEmpty == true
              ? s.title
              : existing?.title;
          final resolvedUpdated = existing?.updatedAt == null
              ? s.updatedAt
              : (s.updatedAt == null
                    ? existing!.updatedAt
                    : (s.updatedAt!.isAfter(existing!.updatedAt!)
                          ? s.updatedAt
                          : existing.updatedAt));
          byId[s.sessionId] = AcpSessionInfo(
            sessionId: s.sessionId,
            cwd: resolvedCwd,
            title: resolvedTitle,
            updatedAt: resolvedUpdated,
          );
        }
      }

      // 1. Global session listing.
      final globalPage = await conn.client.listSessions();
      if (!ref.mounted) return;
      ingest(globalPage.sessions);

      // 2. Per-workspace session listing for every registered workspace directory,
      // ensuring sessions scoped to non-default workspaces are always discovered.
      final wsPaths = <String>{};
      for (final ws in ref.read(workspacesProvider).workspaces) {
        final norm = normalizeWorkspacePath(ws.path);
        if (norm.isNotEmpty) wsPaths.add(norm);
      }
      for (final path in wsPaths) {
        if (!ref.mounted) return;
        try {
          final wsPage = await conn.client.listSessions(cwd: path);
          ingest(wsPage.sessions, fallbackCwd: path);
        } catch (_) {
          // Ignore individual unreachable directories; keep other workspaces intact.
        }
      }

      // Re-check latest deletedIds in case _loadMeta or deleteSession ran mid-refresh.
      final latestDeleted = state.deletedIds.toSet();
      byId.removeWhere((id, _) => latestDeleted.contains(id));

      // Preserve the active just-created session if not yet flushed on disk.
      final active = state.currentSession;
      if (active != null &&
          !latestDeleted.contains(active.sessionId) &&
          !byId.containsKey(active.sessionId)) {
        byId[active.sessionId] = active;
      }

      final merged = byId.values.toList()
        ..sort((a, b) {
          final ta = a.updatedAt;
          final tb = b.updatedAt;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });

      final nextWorkspaces = Map<String, String>.from(state.sessionWorkspaces);
      var wsChanged = false;
      for (final s in merged) {
        if (s.cwd.trim().isNotEmpty) {
          final norm = normalizeWorkspacePath(s.cwd);
          if (nextWorkspaces[s.sessionId] != norm) {
            nextWorkspaces[s.sessionId] = norm;
            wsChanged = true;
          }
        }
      }

      if (!ref.mounted) return;
      state = state.copyWith(
        sessions: merged,
        sessionWorkspaces: nextWorkspaces,
        loading: false,
      );
      if (wsChanged) {
        unawaited(_saveMeta());
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void selectSession(String? sessionId) {
    state = state.copyWith(
      currentSessionId: sessionId,
      clearCurrent: sessionId == null,
    );
  }

  void setFilter(DrawerSessionFilter filter) {
    state = state.copyWith(filter: filter, activeFolder: () => null);
  }

  void selectFolder(String? folder) {
    state = state.copyWith(
      activeFolder: () => folder,
      filter: DrawerSessionFilter.all,
    );
  }

  Future<void> toggleWorkspaceCollapsed(String key) async {
    final collapsed = state.isWorkspaceCollapsed(key);
    final next = [
      if (!collapsed) key,
      for (final k in state.collapsedWorkspaceKeys)
        if (k != key) k,
    ];
    state = state.copyWith(collapsedWorkspaceKeys: next);
    await _saveMeta();
  }

  Future<void> createFolder(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || state.folders.contains(clean)) return;
    state = state.copyWith(folders: [...state.folders, clean]);
    await _saveMeta();
  }

  Future<void> deleteFolder(String name) async {
    final nextFolders = state.folders.where((f) => f != name).toList();
    final nextMap = Map<String, String>.from(state.sessionFolders)
      ..removeWhere((_, v) => v == name);
    state = state.copyWith(
      folders: nextFolders,
      sessionFolders: nextMap,
      activeFolder: () => state.activeFolder == name ? null : state.activeFolder,
    );
    await _saveMeta();
  }

  Future<void> moveToFolder(String sessionId, String? folder) =>
      batchMoveToFolder({sessionId}, folder);

  Future<void> batchMoveToFolder(Set<String> ids, String? folder) async {
    if (ids.isEmpty) return;
    final nextMap = Map<String, String>.from(state.sessionFolders);
    var nextFolders = state.folders;
    final clean = folder?.trim() ?? '';
    if (clean.isEmpty) {
      for (final id in ids) {
        nextMap.remove(id);
      }
    } else {
      if (!nextFolders.contains(clean)) {
        nextFolders = [...nextFolders, clean];
      }
      for (final id in ids) {
        nextMap[id] = clean;
      }
    }
    state = state.copyWith(folders: nextFolders, sessionFolders: nextMap);
    await _saveMeta();
  }

  Future<void> batchArchive(Set<String> ids, bool archived) async {
    if (ids.isEmpty) return;
    final remaining = state.archivedIds.where((id) => !ids.contains(id)).toList();
    final next = archived ? [...ids, ...remaining] : remaining;
    final clearCur = archived &&
        state.currentSessionId != null &&
        ids.contains(state.currentSessionId);
    state = state.copyWith(archivedIds: next, clearCurrent: clearCur);
    await _saveMeta();
  }

  Future<void> batchDelete(Set<String> ids) async {
    for (final id in ids.toList()) {
      await deleteSession(id);
    }
  }

  /// Removes/hides all sessions scoped to [workspacePath] when that workspace is removed.
  Future<void> removeWorkspaceSessions(String workspacePath) async {
    final normWs = normalizeWorkspacePath(workspacePath);
    if (normWs.isEmpty) return;
    final ids = <String>{};
    for (final s in state.sessions) {
      final cwd = state.effectiveCwdOf(s);
      final inside =
          cwd == normWs ||
          (normWs == '/' ? cwd.startsWith('/') : cwd.startsWith('$normWs/'));
      if (inside) ids.add(s.sessionId);
    }
    if (ids.isNotEmpty) {
      await batchDelete(ids);
    }
  }

  void registerCreatedSession(AcpSessionInfo info) {
    final normCwd = info.cwd.trim().isEmpty
        ? ''
        : normalizeWorkspacePath(info.cwd);
    final normalized = AcpSessionInfo(
      sessionId: info.sessionId,
      cwd: normCwd,
      title: info.title,
      updatedAt: info.updatedAt,
    );
    final next = [
      normalized,
      ...state.sessions.where((s) => s.sessionId != info.sessionId),
    ];
    final nextWorkspaces = Map<String, String>.from(state.sessionWorkspaces);
    if (normCwd.isNotEmpty) {
      nextWorkspaces[info.sessionId] = normCwd;
    }

    // Auto-expand the workspace receiving this brand-new conversation.
    var nextCollapsed = state.collapsedWorkspaceKeys;
    if (normCwd.isNotEmpty && nextCollapsed.isNotEmpty) {
      final matched = matchWorkspaceForCwd(
        normCwd,
        ref.read(workspacesProvider).workspaces,
      );
      final targetKey = matched?.id ?? 'path:$normCwd';
      if (nextCollapsed.contains(targetKey)) {
        nextCollapsed = nextCollapsed.where((k) => k != targetKey).toList();
      }
    }

    state = state.copyWith(
      sessions: next,
      currentSessionId: info.sessionId,
      deletedIds: state.deletedIds.where((id) => id != info.sessionId).toList(),
      sessionWorkspaces: nextWorkspaces,
      collapsedWorkspaceKeys: nextCollapsed,
    );
    if (normCwd.isNotEmpty) {
      unawaited(_saveMeta());
    }
  }

  void updateSessionTitle(String sessionId, String title) {
    final next = [
      for (final s in state.sessions)
        if (s.sessionId == sessionId)
          AcpSessionInfo(
            sessionId: s.sessionId,
            cwd: s.cwd,
            title: title,
            updatedAt: DateTime.now(),
          )
        else
          s,
    ];
    state = state.copyWith(sessions: next);
  }

  Future<void> renameSession(String sessionId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    final nextTitles = Map<String, String>.from(state.customTitles)
      ..[sessionId] = clean;
    state = state.copyWith(customTitles: nextTitles);
    updateSessionTitle(sessionId, clean);
    await _saveMeta();
  }

  Future<void> togglePin(String sessionId) async {
    final pinned = state.isPinned(sessionId);
    final next = [
      if (!pinned) sessionId,
      for (final id in state.pinnedIds)
        if (id != sessionId) id,
    ];
    state = state.copyWith(pinnedIds: next);
    await _saveMeta();
  }

  Future<void> setArchived(String sessionId, bool archived) async {
    final next = [
      if (archived) sessionId,
      for (final id in state.archivedIds)
        if (id != sessionId) id,
    ];
    state = state.copyWith(
      archivedIds: next,
      clearCurrent: archived && state.currentSessionId == sessionId,
    );
    await _saveMeta();
  }

  Future<void> deleteSession(String sessionId) async {
    final conn = ref.read(activeConnectionProvider).value;
    if (conn != null && conn.initResult.capabilities.canDeleteSession) {
      await conn.client.deleteSession(sessionId);
    }
    final next = state.sessions.where((s) => s.sessionId != sessionId).toList();
    final nextCurrent = state.currentSessionId == sessionId
        ? null
        : state.currentSessionId;
    final nextTitles = Map<String, String>.from(state.customTitles)
      ..remove(sessionId);
    final nextFolders = Map<String, String>.from(state.sessionFolders)
      ..remove(sessionId);
    final nextWorkspaces = Map<String, String>.from(state.sessionWorkspaces)
      ..remove(sessionId);
    final nextDeleted = [
      ...state.deletedIds,
      if (!state.deletedIds.contains(sessionId)) sessionId,
    ];
    state = state.copyWith(
      sessions: next,
      currentSessionId: nextCurrent,
      clearCurrent: nextCurrent == null,
      pinnedIds: state.pinnedIds.where((id) => id != sessionId).toList(),
      archivedIds: state.archivedIds.where((id) => id != sessionId).toList(),
      deletedIds: nextDeleted,
      customTitles: nextTitles,
      sessionFolders: nextFolders,
      sessionWorkspaces: nextWorkspaces,
    );
    await _saveMeta();
  }
}

final sessionsProvider = NotifierProvider<SessionsController, SessionsState>(
  SessionsController.new,
);

/// One workspace node in the drawer tree with its conversations listed beneath it.
class WorkspaceSessionGroup {
  const WorkspaceSessionGroup({
    required this.key,
    required this.title,
    required this.path,
    required this.sessions,
    this.workspace,
    this.isDefault = false,
    this.isSelected = false,
  });

  final String key;
  final String title;
  final String path;
  final List<AcpSessionInfo> sessions;
  final WorkspaceItem? workspace;
  final bool isDefault;
  final bool isSelected;
}

/// Groups conversations underneath their owning workspaces for the drawer tree.
final workspaceSessionGroupsProvider = Provider<List<WorkspaceSessionGroup>>((
  ref,
) {
  final sessionsState = ref.watch(sessionsProvider);
  final wsState = ref.watch(workspacesProvider);
  final archivedSet = sessionsState.archivedIds.toSet();
  final deletedSet = sessionsState.deletedIds.toSet();
  final pinnedSet = sessionsState.pinnedIds.toSet();
  final pinnedOrder = {
    for (var i = 0; i < sessionsState.pinnedIds.length; i++)
      sessionsState.pinnedIds[i]: i,
  };
  final filteredView =
      sessionsState.filter != DrawerSessionFilter.all ||
      sessionsState.activeFolder != null;

  final buckets = <String, List<AcpSessionInfo>>{};
  final unregisteredPaths = <String, String>{};
  final defaultWs =
      wsState.workspaces.where((w) => w.isDefault).firstOrNull ??
      wsState.workspaces.firstOrNull;

  for (final s in sessionsState.sessions) {
    if (deletedSet.contains(s.sessionId)) continue;
    if (!_matchesFilter(
      s,
      sessionsState.filter,
      sessionsState.activeFolder,
      sessionsState.sessionFolders[s.sessionId],
      archivedSet,
      pinnedSet,
    )) {
      continue;
    }
    final cwd = sessionsState.effectiveCwdOf(s);
    final matched = matchWorkspaceForCwd(cwd, wsState.workspaces);
    if (matched != null) {
      buckets.putIfAbsent(matched.id, () => []).add(s);
    } else if (cwd.isNotEmpty) {
      // Never resurrect a workspace the user explicitly removed.
      if (wsState.isPathRemoved(cwd)) continue;
      final key = 'path:$cwd';
      unregisteredPaths[key] = cwd;
      buckets.putIfAbsent(key, () => []).add(s);
    } else if (defaultWs != null) {
      buckets.putIfAbsent(defaultWs.id, () => []).add(s);
    } else {
      const key = 'default';
      unregisteredPaths[key] = '';
      buckets.putIfAbsent(key, () => []).add(s);
    }
  }

  List<AcpSessionInfo> sortSessions(List<AcpSessionInfo> list) {
    final copy = List<AcpSessionInfo>.from(list);
    copy.sort((a, b) {
      if (sessionsState.filter != DrawerSessionFilter.archived) {
        final pa = pinnedOrder[a.sessionId];
        final pb = pinnedOrder[b.sessionId];
        if (pa != null && pb != null) return pa.compareTo(pb);
        if (pa != null) return -1;
        if (pb != null) return 1;
      }
      final ta = a.updatedAt;
      final tb = b.updatedAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return copy;
  }

  // Order registered workspaces: pinned workspaces first, then remaining in user order.
  final pinnedWsSet = wsState.pinnedIds.toSet();
  final orderedWorkspaces = [
    for (final w in wsState.workspaces)
      if (pinnedWsSet.contains(w.id)) w,
    for (final w in wsState.workspaces)
      if (!pinnedWsSet.contains(w.id)) w,
  ];

  final result = <WorkspaceSessionGroup>[];
  final currentSid = sessionsState.currentSessionId;
  for (final ws in orderedWorkspaces) {
    final items = sortSessions(buckets[ws.id] ?? const []);
    if (filteredView && items.isEmpty) continue;
    final containsCurrent =
        currentSid != null && items.any((s) => s.sessionId == currentSid);
    result.add(
      WorkspaceSessionGroup(
        key: ws.id,
        title: ws.displayTitle,
        path: normalizeWorkspacePath(ws.path),
        sessions: items,
        workspace: ws,
        isDefault: ws.isDefault,
        isSelected: wsState.selectedId == ws.id || containsCurrent,
      ),
    );
  }

  // Append any historical unregistered workspace directories that own matching sessions.
  for (final entry in unregisteredPaths.entries) {
    final items = sortSessions(buckets[entry.key] ?? const []);
    if (items.isEmpty) continue;
    final path = entry.value;
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    final title = parts.isEmpty ? (path.isEmpty ? '默认工作区' : path) : parts.last;
    final containsCurrent =
        currentSid != null && items.any((s) => s.sessionId == currentSid);
    result.add(
      WorkspaceSessionGroup(
        key: entry.key,
        title: title,
        path: path,
        sessions: items,
        isDefault: path.isEmpty,
        isSelected: containsCurrent,
      ),
    );
  }

  return result;
});

/// Sessions filtered by active workspace, active folder, and archive/pin filter.
final filteredSessionsProvider = Provider<List<AcpSessionInfo>>((ref) {
  final state = ref.watch(sessionsProvider);
  final selectedWs = ref.watch(selectedWorkspaceProvider);
  final archivedSet = state.archivedIds.toSet();
  final deletedSet = state.deletedIds.toSet();
  final pinnedSet = state.pinnedIds.toSet();

  return [
    for (final s in state.sessions)
      if (!deletedSet.contains(s.sessionId) &&
          _matches(
            s,
            state.filter,
            state.activeFolder,
            state.sessionFolders[s.sessionId],
            selectedWs,
            archivedSet,
            pinnedSet,
            state.effectiveCwdOf(s),
          ))
        s,
  ];
});

bool _matchesFilter(
  AcpSessionInfo s,
  DrawerSessionFilter filter,
  String? activeFolder,
  String? sessionFolder,
  Set<String> archived,
  Set<String> pinned,
) {
  if (activeFolder != null && sessionFolder != activeFolder) {
    return false;
  }
  return switch (filter) {
    DrawerSessionFilter.all => !archived.contains(s.sessionId),
    DrawerSessionFilter.pinned =>
      pinned.contains(s.sessionId) && !archived.contains(s.sessionId),
    DrawerSessionFilter.archived => archived.contains(s.sessionId),
  };
}

bool _matches(
  AcpSessionInfo s,
  DrawerSessionFilter filter,
  String? activeFolder,
  String? sessionFolder,
  WorkspaceItem? ws,
  Set<String> archived,
  Set<String> pinned,
  String effectiveCwd,
) {
  if (ws != null && effectiveCwd.isNotEmpty) {
    final normWs = normalizeWorkspacePath(ws.path);
    final inside =
        effectiveCwd == normWs ||
        (normWs == '/'
            ? effectiveCwd.startsWith('/')
            : effectiveCwd.startsWith('$normWs/'));
    if (!inside) {
      return false;
    }
  }
  return _matchesFilter(
    s,
    filter,
    activeFolder,
    sessionFolder,
    archived,
    pinned,
  );
}
