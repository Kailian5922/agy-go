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
  static const _maxListPages = 10;

  String _prefsKey = '';
  int _metaGen = 0;
  int _refreshSeq = 0;
  Future<void> _metaReady = Future.value();
  final Map<String, SessionsState> _hostCache = {};
  final Set<String> _createdInMemory = {};

  @override
  SessionsState build() {
    final host = ref.watch(hostsProvider.select((h) => h.active));
    final key = 'agy.sessions.meta.${host.kind.name}.${host.id}';
    if (_prefsKey != key) {
      _createdInMemory.clear();
    }
    _prefsKey = key;
    final metaGen = ++_metaGen;
    _refreshSeq++;
    _metaReady = _loadMeta(key, metaGen);

    // Re-query sessions whenever workspaces finish loading or change paths so
    // non-default workspace sessions are always discovered reliably.
    ref.listen<(bool, String)>(
      workspacesProvider.select(
        (w) => (w.loaded, w.workspaces.map((e) => e.path).join('|')),
      ),
      (prev, next) {
        if (prev == null || prev == next) return;
        final conn = ref.read(activeConnectionProvider).value;
        if (conn != null) unawaited(_refreshFor(conn));
      },
    );

    final cached = _hostCache[key];
    final conn = ref.watch(activeConnectionProvider.select((a) => a.value));
    if (conn == null || !conn.initResult.capabilities.canListSessions) {
      return cached != null
          ? cached.copyWith(loading: false)
          : const SessionsState();
    }
    Future<void>.microtask(() {
      if (ref.mounted) unawaited(_refreshFor(conn));
    });
    return cached != null
        ? cached.copyWith(loading: true, clearError: true)
        : const SessionsState(loading: true);
  }

  void _setState(SessionsState next) {
    state = next;
    if (_prefsKey.isNotEmpty) {
      _hostCache[_prefsKey] = next;
    }
  }

  Future<void> _loadMeta(String key, int expectedGen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null ||
          raw.isEmpty ||
          !ref.mounted ||
          _prefsKey != key ||
          _metaGen != expectedGen) {
        return;
      }
      final map = jsonDecode(raw) as Map<String, Object?>;
      final deleted =
          (map['deleted'] as List?)?.whereType<String>().toList() ?? const [];
      final deletedSet = {...deleted, ...state.deletedIds};
      final filteredSessions = deletedSet.isEmpty
          ? state.sessions
          : state.sessions
                .where((s) => !deletedSet.contains(s.sessionId))
                .toList();
      final clearCurrent =
          state.currentSessionId != null &&
          deletedSet.contains(state.currentSessionId);

      // Merge disk metadata with any mutations that happened before hydration
      // completed so neither disk data nor in-memory actions are lost.
      final diskWorkspaces = <String, String>{
        if (map['sessionWorkspaces'] is Map)
          for (final e in (map['sessionWorkspaces'] as Map).entries)
            if (e.key is String && e.value is String)
              e.key as String: normalizeWorkspacePath(e.value as String),
      };
      final diskCreatedAt = <String, DateTime>{
        if (map['sessionCreatedAt'] is Map)
          for (final e in (map['sessionCreatedAt'] as Map).entries)
            if (e.key is String && e.value is String)
              e.key as String: ?DateTime.tryParse(e.value as String),
      };
      final diskTitles = <String, String>{
        if (map['titles'] is Map)
          for (final e in (map['titles'] as Map).entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      };
      final diskPinned =
          (map['pinned'] as List?)?.whereType<String>().toList() ?? const [];
      final diskArchived =
          (map['archived'] as List?)?.whereType<String>().toList() ?? const [];

      _setState(
        state.copyWith(
          sessions: filteredSessions,
          clearCurrent: clearCurrent,
          pinnedIds: [
            ...state.pinnedIds,
            for (final id in diskPinned)
              if (!state.pinnedIds.contains(id) && !deletedSet.contains(id)) id,
          ],
          archivedIds: [
            ...state.archivedIds,
            for (final id in diskArchived)
              if (!state.archivedIds.contains(id) && !deletedSet.contains(id))
                id,
          ],
          deletedIds: deletedSet.toList(),
          customTitles: {...diskTitles, ...state.customTitles},
          sessionWorkspaces: {...diskWorkspaces, ...state.sessionWorkspaces},
          sessionCreatedAt: {...diskCreatedAt, ...state.sessionCreatedAt},
        ),
      );
    } catch (_) {}
  }

  Future<void> _saveMeta() async {
    final key = _prefsKey;
    final gen = _metaGen;
    await _metaReady;
    if (!ref.mounted || _prefsKey != key || _metaGen != gen) return;
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

  Future<List<AcpSessionInfo>> _listAllPages(
    HostConnection conn, {
    String? cwd,
  }) async {
    final collected = <AcpSessionInfo>[];
    String? cursor;
    for (var page = 0; page < _maxListPages; page++) {
      final res = await conn.client.listSessions(cwd: cwd, cursor: cursor);
      collected.addAll(res.sessions);
      final next = res.nextCursor?.trim();
      if (next == null || next.isEmpty || next == cursor) break;
      cursor = next;
    }
    return collected;
  }

  Future<void> _refreshFor(HostConnection conn) async {
    final seq = ++_refreshSeq;
    final key = _prefsKey;
    // Wait for persisted sessionWorkspaces/deletedIds/pinnedIds before merging
    // or writing back to SharedPreferences (prevents wiping metadata on startup).
    await _metaReady;
    if (!ref.mounted || seq != _refreshSeq || _prefsKey != key) return;

    if (!conn.initResult.capabilities.canListSessions) {
      _setState(state.copyWith(loading: false, clearError: true));
      return;
    }
    _setState(state.copyWith(loading: true, clearError: true));
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

      // 1. Global session listing (following pagination cursors).
      final globalSessions = await _listAllPages(conn);
      if (!ref.mounted || seq != _refreshSeq || _prefsKey != key) return;
      ingest(globalSessions);

      // 2. Per-workspace session listing for every registered workspace AND any
      // persisted session workspace paths, ensuring sessions scoped to
      // non-default workspaces are always discovered.
      final wsPaths = <String>{};
      for (final ws in ref.read(workspacesProvider).workspaces) {
        final norm = normalizeWorkspacePath(ws.path);
        if (norm.isNotEmpty) wsPaths.add(norm);
      }
      for (final savedPath in state.sessionWorkspaces.values) {
        final norm = normalizeWorkspacePath(savedPath);
        if (norm.isNotEmpty) wsPaths.add(norm);
      }
      for (final path in wsPaths) {
        if (!ref.mounted || seq != _refreshSeq || _prefsKey != key) return;
        try {
          final wsSessions = await _listAllPages(conn, cwd: path);
          if (!ref.mounted || seq != _refreshSeq || _prefsKey != key) return;
          ingest(wsSessions, fallbackCwd: path);
        } catch (_) {
          // Ignore individual unreachable directories; keep other workspaces intact.
        }
      }

      // Re-check latest deletedIds in case deleteSession ran mid-refresh.
      final latestDeleted = state.deletedIds.toSet();
      byId.removeWhere((id, _) => latestDeleted.contains(id));

      // Preserve the active session and any session created in this runtime
      // session if `agy acp` has not flushed it onto disk yet.
      final keepIds = <String>{
        if (state.currentSessionId != null) state.currentSessionId!,
        ..._createdInMemory,
      };
      for (final s in state.sessions) {
        if (keepIds.contains(s.sessionId) &&
            !latestDeleted.contains(s.sessionId) &&
            !byId.containsKey(s.sessionId)) {
          byId[s.sessionId] = s;
        }
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

      if (!ref.mounted || seq != _refreshSeq || _prefsKey != key) return;
      _setState(
        state.copyWith(
          sessions: merged,
          sessionWorkspaces: nextWorkspaces,
          sessionCreatedAt: nextCreatedAt,
          loading: false,
        ),
      );
      if (metaChanged) {
        unawaited(_saveMeta());
      }
    } catch (e) {
      if (!ref.mounted || seq != _refreshSeq || _prefsKey != key) return;
      _setState(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void selectSession(String? sessionId) {
    _setState(
      state.copyWith(
        currentSessionId: sessionId,
        clearCurrent: sessionId == null,
      ),
    );
  }

  Future<void> batchArchive(Set<String> ids, bool archived) async {
    if (ids.isEmpty) return;
    await _metaReady;
    final remaining = state.archivedIds.where((id) => !ids.contains(id)).toList();
    final next = archived ? [...ids, ...remaining] : remaining;
    final clearCur = archived &&
        state.currentSessionId != null &&
        ids.contains(state.currentSessionId);
    _setState(state.copyWith(archivedIds: next, clearCurrent: clearCur));
    await _saveMeta();
  }

  Future<void> batchDelete(Set<String> ids) async {
    for (final id in ids.toList()) {
      await deleteSession(id);
    }
  }

  /// Removes sessions whose owning workspace matches [workspacePath] without
  /// touching conversations owned by more specific registered child workspaces.
  Future<void> removeWorkspaceSessions(String workspacePath) async {
    final normWs = normalizeWorkspacePath(workspacePath);
    if (normWs.isEmpty) return;
    final workspaces = ref.read(workspacesProvider).workspaces;
    final ids = <String>{};
    for (final s in state.sessions) {
      final cwd = state.effectiveCwdOf(s);
      final inside =
          cwd == normWs ||
          (normWs == '/' ? cwd.startsWith('/') : cwd.startsWith('$normWs/'));
      if (!inside) continue;
      // If a more specific registered child workspace still owns this session,
      // never delete it when removing an ancestor directory.
      final owner = matchWorkspaceForCwd(cwd, workspaces);
      if (owner != null && normalizeWorkspacePath(owner.path) != normWs) {
        continue;
      }
      ids.add(s.sessionId);
    }
    if (ids.isNotEmpty) {
      await batchDelete(ids);
    }
  }

  void registerCreatedSession(AcpSessionInfo info, {bool select = true}) {
    _createdInMemory.add(info.sessionId);
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

    _setState(
      state.copyWith(
        sessions: next,
        currentSessionId: select ? info.sessionId : state.currentSessionId,
        deletedIds: state.deletedIds.where((id) => id != info.sessionId).toList(),
        sessionWorkspaces: nextWorkspaces,
        sessionCreatedAt: nextCreatedAt,
      ),
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
    _setState(state.copyWith(sessions: next));
  }

  Future<void> renameSession(String sessionId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    await _metaReady;
    final nextTitles = Map<String, String>.from(state.customTitles)
      ..[sessionId] = clean;
    _setState(state.copyWith(customTitles: nextTitles));
    updateSessionTitle(sessionId, clean);
    await _saveMeta();
  }

  Future<void> togglePin(String sessionId) async {
    await _metaReady;
    final pinned = state.isPinned(sessionId);
    final next = [
      if (!pinned) sessionId,
      for (final id in state.pinnedIds)
        if (id != sessionId) id,
    ];
    _setState(state.copyWith(pinnedIds: next));
    await _saveMeta();
  }

  Future<void> batchSetPinned(Set<String> ids, bool pinned) async {
    if (ids.isEmpty) return;
    await _metaReady;
    final remaining = state.pinnedIds.where((id) => !ids.contains(id)).toList();
    final next = pinned ? [...ids, ...remaining] : remaining;
    _setState(state.copyWith(pinnedIds: next));
    await _saveMeta();
  }

  Future<void> setArchived(String sessionId, bool archived) async {
    await _metaReady;
    final next = [
      if (archived) sessionId,
      for (final id in state.archivedIds)
        if (id != sessionId) id,
    ];
    _setState(
      state.copyWith(
        archivedIds: next,
        clearCurrent: archived && state.currentSessionId == sessionId,
      ),
    );
    await _saveMeta();
  }

  Future<void> deleteSession(String sessionId) async {
    await _metaReady;
    _createdInMemory.remove(sessionId);
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
    _setState(
      state.copyWith(
        sessions: next,
        currentSessionId: nextCurrent,
        clearCurrent: nextCurrent == null,
        pinnedIds: state.pinnedIds.where((id) => id != sessionId).toList(),
        archivedIds: state.archivedIds.where((id) => id != sessionId).toList(),
        deletedIds: nextDeleted,
        customTitles: nextTitles,
        sessionWorkspaces: nextWorkspaces,
        sessionCreatedAt: nextCreatedAt,
      ),
    );
    await _saveMeta();
  }
}

final sessionsProvider = NotifierProvider<SessionsController, SessionsState>(
  SessionsController.new,
);
