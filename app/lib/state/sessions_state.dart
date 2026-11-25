import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_state.dart';

class SessionsState {
  const SessionsState({
    this.sessions = const [],
    this.currentSessionId,
    this.loading = false,
    this.error,
  });

  final List<AcpSessionInfo> sessions;
  final String? currentSessionId;
  final bool loading;
  final String? error;

  AcpSessionInfo? get currentSession {
    final id = currentSessionId;
    if (id == null) return null;
    for (final s in sessions) {
      if (s.sessionId == id) return s;
    }
    return null;
  }

  SessionsState copyWith({
    List<AcpSessionInfo>? sessions,
    String? currentSessionId,
    bool clearCurrent = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => SessionsState(
    sessions: sessions ?? this.sessions,
    currentSessionId: clearCurrent
        ? null
        : (currentSessionId ?? this.currentSessionId),
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

class SessionsController extends Notifier<SessionsState> {
  @override
  SessionsState build() {
    final connAsync = ref.watch(activeConnectionProvider);
    final conn = connAsync.value;
    if (conn == null) return const SessionsState();
    unawaited(_refreshFor(conn));
    return const SessionsState(loading: true);
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
      final page = await conn.client.listSessions(cwd: conn.defaultCwd);
      if (!ref.mounted) return;
      state = state.copyWith(
        sessions: page.sessions,
        loading: false,
        currentSessionId:
            state.currentSessionId ?? page.sessions.firstOrNull?.sessionId,
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

  Future<void> deleteSession(String sessionId) async {
    final conn = ref.read(activeConnectionProvider).value;
    if (conn == null) return;
    if (conn.initResult.capabilities.canDeleteSession) {
      await conn.client.deleteSession(sessionId);
    }
    final next = state.sessions.where((s) => s.sessionId != sessionId).toList();
    final nextCurrent = state.currentSessionId == sessionId
        ? next.firstOrNull?.sessionId
        : state.currentSessionId;
    state = state.copyWith(
      sessions: next,
      currentSessionId: nextCurrent,
      clearCurrent: nextCurrent == null,
    );
  }
}

final sessionsProvider = NotifierProvider<SessionsController, SessionsState>(
  SessionsController.new,
);
