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
    this.filter = DrawerSessionFilter.all,
  });

  final List<AcpSessionInfo> sessions;
  final String? currentSessionId;
  final bool loading;
  final String? error;
  final List<String> pinnedIds;
  final List<String> archivedIds;
  final Map<String, String> customTitles;
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
    filter: filter ?? this.filter,
  );
}

class SessionsController extends Notifier<SessionsState> {
  String _prefsKey = '';

  @override
  SessionsState build() {
    final host = ref.watch(hostsProvider.select((h) => h.active));
    _prefsKey = 'agy.sessions.meta.${host.kind.name}.${host.id}';
    unawaited(_loadMeta(_prefsKey));

    final connAsync = ref.watch(activeConnectionProvider);
    final conn = connAsync.value;
    if (conn == null) return const SessionsState();
    unawaited(_refreshFor(conn));
    return const SessionsState(loading: true);
  }

  Future<void> _loadMeta(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty || !ref.mounted || _prefsKey != key) return;
      final map = jsonDecode(raw) as Map<String, Object?>;
      state = state.copyWith(
        pinnedIds: (map['pinned'] as List?)?.whereType<String>().toList() ?? const [],
        archivedIds: (map['archived'] as List?)?.whereType<String>().toList() ?? const [],
        customTitles: {
          if (map['titles'] is Map)
            for (final e in (map['titles'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
        },
      );
    } catch (_) {}
  }

  Future<void> _saveMeta() async {
    final key = _prefsKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'pinned': state.pinnedIds,
          'archived': state.archivedIds,
          'titles': state.customTitles,
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
    state = state.copyWith(filter: filter);
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
    state = state.copyWith(
      sessions: next,
      currentSessionId: nextCurrent,
      clearCurrent: nextCurrent == null,
      pinnedIds: state.pinnedIds.where((id) => id != sessionId).toList(),
      archivedIds: state.archivedIds.where((id) => id != sessionId).toList(),
      customTitles: nextTitles,
    );
    await _saveMeta();
  }
}

final sessionsProvider = NotifierProvider<SessionsController, SessionsState>(
  SessionsController.new,
);

/// Sessions filtered by the drawer's selected workspace and status filter.
final filteredSessionsProvider = Provider<List<AcpSessionInfo>>((ref) {
  final st = ref.watch(sessionsProvider);
  final selectedWs = ref.watch(selectedWorkspaceProvider);
  return [
    for (final s in st.sessions)
      if (switch (st.filter) {
        DrawerSessionFilter.all => !st.isArchived(s.sessionId),
        DrawerSessionFilter.pinned =>
          !st.isArchived(s.sessionId) && st.isPinned(s.sessionId),
        DrawerSessionFilter.archived => st.isArchived(s.sessionId),
      })
        if (selectedWs == null ||
            s.cwd.isEmpty ||
            s.cwd == selectedWs.path ||
            s.cwd.startsWith('${selectedWs.path}/'))
          s,
  ];
});
