import 'dart:async';
import 'dart:convert';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_state.dart';
import 'hosts_state.dart';
import 'workspaces_state.dart';

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
    this.sessionWorkspaces = const {},
    this.sessionCreatedAt = const {},
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

  /// Persisted `sessionId -> normalized workspace cwd` mapping so every
  /// conversation reliably matches its owning workspace scope.
  final Map<String, String> sessionWorkspaces;

  /// Persisted first-seen / creation timestamp per session for `创建时间` sorting.
  final Map<String, DateTime> sessionCreatedAt;

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
    Map<String, String>? sessionWorkspaces,
    Map<String, DateTime>? sessionCreatedAt,
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
    sessionWorkspaces: sessionWorkspaces ?? this.sessionWorkspaces,
    sessionCreatedAt: sessionCreatedAt ?? this.sessionCreatedAt,
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
    if (conn == null || !conn.initResult.capabilities.canListSessions) {
      return const SessionsState();
    }
    Future<void>.microtask(() {
      if (ref.mounted) unawaited(_refreshFor(conn));
    });
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
        sessionWorkspaces: {
          if (map['sessionWorkspaces'] is Map)
            for (final e in (map['sessionWorkspaces'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: normalizeWorkspacePath(e.value as String),
        },
        sessionCreatedAt: {
          if (map['sessionCreatedAt'] is Map)
            for (final e in (map['sessionCreatedAt'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: ?DateTime.tryParse(e.value as String),
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
          'deleted': state.deletedIds,
          'titles': state.customTitles,
          'sessionWorkspaces': state.sessionWorkspaces,
          'sessionCreatedAt': {
            for (final e in state.sessionCreatedAt.entries)
              e.key: e.value.toIso8601String(),
          },
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
      final nextCreatedAt = Map<String, DateTime>.from(state.sessionCreatedAt);
      var metaChanged = false;
      final observedNow = DateTime.now();
      for (final s in merged) {
        if (s.cwd.trim().isNotEmpty) {
          final norm = normalizeWorkspacePath(s.cwd);
          if (nextWorkspaces[s.sessionId] != norm) {
            nextWorkspaces[s.sessionId] = norm;
            metaChanged = true;
          }
        }
        if (!nextCreatedAt.containsKey(s.sessionId)) {
          nextCreatedAt[s.sessionId] = s.updatedAt ?? observedNow;
          metaChanged = true;
        }
      }

      if (!ref.mounted) return;
      state = state.copyWith(
        sessions: merged,
        sessionWorkspaces: nextWorkspaces,
        sessionCreatedAt: nextCreatedAt,
        loading: false,
      );
      if (metaChanged) {
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

  void registerCreatedSession(AcpSessionInfo info, {bool select = true}) {
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
    final nextCreatedAt = Map<String, DateTime>.from(state.sessionCreatedAt)
      ..putIfAbsent(info.sessionId, DateTime.now);

    state = state.copyWith(
      sessions: next,
      currentSessionId: select ? info.sessionId : state.currentSessionId,
      deletedIds: state.deletedIds.where((id) => id != info.sessionId).toList(),
      sessionWorkspaces: nextWorkspaces,
      sessionCreatedAt: nextCreatedAt,
    );
    unawaited(_saveMeta());
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

  Future<void> batchSetPinned(Set<String> ids, bool pinned) async {
    if (ids.isEmpty) return;
    final remaining = state.pinnedIds.where((id) => !ids.contains(id)).toList();
    final next = pinned ? [...ids, ...remaining] : remaining;
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
    final nextWorkspaces = Map<String, String>.from(state.sessionWorkspaces)
      ..remove(sessionId);
    final nextCreatedAt = Map<String, DateTime>.from(state.sessionCreatedAt)
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
      sessionWorkspaces: nextWorkspaces,
      sessionCreatedAt: nextCreatedAt,
    );
    await _saveMeta();
  }
}

final sessionsProvider = NotifierProvider<SessionsController, SessionsState>(
  SessionsController.new,
);
