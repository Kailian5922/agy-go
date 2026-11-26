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
    this.customTitles = const {},
    this.folders = const [],
    this.sessionFolders = const {},
    this.activeFolder,
    this.filter = DrawerSessionFilter.all,
  });

  final List<AcpSessionInfo> sessions;
  final String? currentSessionId;
  final bool loading;
  final String? error;
  final List<String> pinnedIds;
  final List<String> archivedIds;
  final Map<String, String> customTitles;
  final List<String> folders;
  final Map<String, String> sessionFolders;
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

  bool isPinned(String id) => pinnedIds.contains(id);
  bool isArchived(String id) => archivedIds.contains(id);
  String? folderOf(String id) => sessionFolders[id];

  SessionsState copyWith({
    List<AcpSessionInfo>? sessions,
    String? currentSessionId,
    bool clearCurrent = false,
    bool? loading,
    String? error,
    bool clearError = false,
    List<String>? pinnedIds,
    List<String>? archivedIds,
    Map<String, String>? customTitles,
    List<String>? folders,
    Map<String, String>? sessionFolders,
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
    customTitles: customTitles ?? this.customTitles,
    folders: folders ?? this.folders,
    sessionFolders: sessionFolders ?? this.sessionFolders,
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
      state = state.copyWith(
        pinnedIds:
            (map['pinned'] as List?)?.whereType<String>().toList() ?? const [],
        archivedIds:
            (map['archived'] as List?)?.whereType<String>().toList() ?? const [],
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
          'titles': state.customTitles,
          'folders': state.folders,
          'sessionFolders': state.sessionFolders,
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
      final page = await conn.client.listSessions();
      if (!ref.mounted) return;
      state = state.copyWith(
        sessions: page.sessions,
        loading: false,
      );
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

  void registerCreatedSession(AcpSessionInfo info) {
    final next = [
      info,
      ...state.sessions.where((s) => s.sessionId != info.sessionId),
    ];
    state = state.copyWith(
      sessions: next,
      currentSessionId: info.sessionId,
    );
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
    state = state.copyWith(
      sessions: next,
      currentSessionId: nextCurrent,
      clearCurrent: nextCurrent == null,
      pinnedIds: state.pinnedIds.where((id) => id != sessionId).toList(),
      archivedIds: state.archivedIds.where((id) => id != sessionId).toList(),
      customTitles: nextTitles,
      sessionFolders: nextFolders,
    );
    await _saveMeta();
  }
}

final sessionsProvider = NotifierProvider<SessionsController, SessionsState>(
  SessionsController.new,
);

/// Sessions filtered by active workspace, active folder, and archive/pin filter.
final filteredSessionsProvider = Provider<List<AcpSessionInfo>>((ref) {
  final state = ref.watch(sessionsProvider);
  final selectedWs = ref.watch(selectedWorkspaceProvider);
  final archivedSet = state.archivedIds.toSet();
  final pinnedSet = state.pinnedIds.toSet();

  return [
    for (final s in state.sessions)
      if (_matches(
        s,
        state.filter,
        state.activeFolder,
        state.sessionFolders[s.sessionId],
        selectedWs,
        archivedSet,
        pinnedSet,
      ))
        s,
  ];
});

bool _matches(
  AcpSessionInfo s,
  DrawerSessionFilter filter,
  String? activeFolder,
  String? sessionFolder,
  WorkspaceItem? ws,
  Set<String> archived,
  Set<String> pinned,
) {
  if (ws != null && s.cwd.isNotEmpty) {
    final normCwd = s.cwd.endsWith('/') && s.cwd.length > 1
        ? s.cwd.substring(0, s.cwd.length - 1)
        : s.cwd;
    if (normCwd != ws.path && !normCwd.startsWith('${ws.path}/')) {
      return false;
    }
  }
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
