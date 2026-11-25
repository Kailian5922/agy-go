import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_state.dart';
import 'phone_state.dart';
import 'sessions_state.dart';
import 'settings_state.dart';
import 'workspaces_state.dart';

class ChatState {
  const ChatState({
    this.sessionId,
    this.sessionCwd,
    this.transcript = const ChatTranscript(),
    this.pendingPermissions = const [],
    this.isSending = false,
    this.isLoadingSession = false,
    this.authRequired = false,
    this.quotedText,
    this.error,
  });

  final String? sessionId;
  final String? sessionCwd;
  final ChatTranscript transcript;
  final List<PendingPermission> pendingPermissions;
  final bool isSending;
  final bool isLoadingSession;
  final bool authRequired;
  final String? quotedText;
  final String? error;

  bool get isBusy => isSending || transcript.isStreaming;

  ChatState copyWith({
    String? sessionId,
    bool clearSessionId = false,
    String? sessionCwd,
    bool clearSessionCwd = false,
    ChatTranscript? transcript,
    List<PendingPermission>? pendingPermissions,
    bool? isSending,
    bool? isLoadingSession,
    bool? authRequired,
    String? quotedText,
    bool clearQuotedText = false,
    String? error,
    bool clearError = false,
  }) => ChatState(
    sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
    sessionCwd: clearSessionCwd ? null : (sessionCwd ?? this.sessionCwd),
    transcript: transcript ?? this.transcript,
    pendingPermissions: pendingPermissions ?? this.pendingPermissions,
    isSending: isSending ?? this.isSending,
    isLoadingSession: isLoadingSession ?? this.isLoadingSession,
    authRequired: authRequired ?? this.authRequired,
    quotedText: clearQuotedText ? null : (quotedText ?? this.quotedText),
    error: clearError ? null : (error ?? this.error),
  );
}

class ChatController extends Notifier<ChatState> {
  StreamSubscription<AcpSessionNotification>? _updateSub;
  StreamSubscription<PendingPermission>? _permSub;
  String? _loadedSessionId;
  final Set<String> _allowAllSessions = {};

  List<AcpMcpServerConfig> _sessionMcpServers(HostConnection conn) {
    if (!conn.isLocal || !conn.initResult.capabilities.supportsHttpMcp) {
      return const [];
    }
    final phone = ref.read(phoneControlProvider);
    if (!phone.isMcpReady) return const [];
    return [
      HttpMcpServerConfig(
        name: 'phone',
        url: phone.mcpUrl!,
        headers: {'Authorization': 'Bearer ${phone.mcpToken!}'},
      ),
    ];
  }

  @override
  ChatState build() {
    final conn = ref.watch(activeConnectionProvider).value;
    final selectedId = ref.watch(
      sessionsProvider.select((s) => s.currentSessionId),
    );

    _updateSub?.cancel();
    _permSub?.cancel();
    _updateSub = null;
    _permSub = null;
    _loadedSessionId = null;

    ref.onDispose(() {
      unawaited(_updateSub?.cancel());
      unawaited(_permSub?.cancel());
    });

    if (conn == null) return const ChatState();

    _updateSub = conn.client.updates.listen(_onUpdate);
    _permSub = conn.client.permissionRequests.listen(_onPermissionRequest);

    if (selectedId != null && selectedId.isNotEmpty) {
      final sessionInfo = ref.read(sessionsProvider).currentSession;
      final String cwd =
          sessionInfo?.cwd ?? ref.read(effectiveWorkingDirProvider);
      unawaited(_loadExistingSession(conn, selectedId, cwd));
      return ChatState(
        sessionId: selectedId,
        sessionCwd: cwd,
        isLoadingSession: true,
      );
    }
    return const ChatState();
  }

  Future<void> _loadExistingSession(
    HostConnection conn,
    String sid,
    String cwd,
  ) async {
    _loadedSessionId = sid;
    final mcpServers = _sessionMcpServers(conn);
    try {
      final AcpSessionHandle handle;
      if (conn.initResult.capabilities.loadSession) {
        handle = await conn.client.loadSession(
          sessionId: sid,
          cwd: cwd,
          mcpServers: mcpServers,
        );
      } else if (conn.initResult.capabilities.canResumeSession) {
        handle = await conn.client.resumeSession(
          sessionId: sid,
          cwd: cwd,
          mcpServers: mcpServers,
        );
      } else {
        if (!ref.mounted || _loadedSessionId != sid) return;
        state = state.copyWith(isLoadingSession: false);
        return;
      }
      if (!ref.mounted || _loadedSessionId != sid) return;
      state = state.copyWith(
        sessionId: handle.sessionId,
        sessionCwd: cwd,
        transcript: state.transcript.copyWith(
          modes: handle.modes ?? state.transcript.modes,
          configOptions: handle.configOptions.isNotEmpty
              ? handle.configOptions
              : state.transcript.configOptions,
        ),
        isLoadingSession: false,
        authRequired: false,
        clearError: true,
      );
    } on AcpRpcException catch (e) {
      if (!ref.mounted || _loadedSessionId != sid) return;
      state = state.copyWith(
        isLoadingSession: false,
        authRequired: e.isAuthRequired,
        error: e.message,
      );
    } catch (e) {
      if (!ref.mounted || _loadedSessionId != sid) return;
      state = state.copyWith(isLoadingSession: false, error: e.toString());
    }
  }

  void startNewChat() {
    _loadedSessionId = null;
    ref.read(sessionsProvider.notifier).selectSession(null);
    state = const ChatState();
  }

  void setQuote(String? text) {
    final clean = text?.trim();
    if (clean == null || clean.isEmpty) {
      state = state.copyWith(clearQuotedText: true);
    } else {
      state = state.copyWith(quotedText: clean);
    }
  }

  void allowAllForCurrentSession() {
    final sid = state.sessionId;
    if (sid != null) _allowAllSessions.add(sid);
  }

  Future<void> send(String rawText) async {
    final cleanBody = rawText.trim();
    if (cleanBody.isEmpty) return;

    final quote = state.quotedText;
    final text = quote != null && quote.isNotEmpty
        ? '> ${quote.replaceAll('\n', '\n> ')}\n\n$cleanBody'
        : cleanBody;

    final conn = ref.read(activeConnectionProvider).value;
    if (conn == null) {
      state = state.copyWith(error: '引擎未连接，请先启动本机引擎或选择 SSH 主机。');
      return;
    }

    state = state.copyWith(
      isSending: true,
      clearError: true,
      clearQuotedText: true,
      authRequired: false,
    );

    try {
      var sid = state.sessionId;
      final String cwd =
          state.sessionCwd ?? ref.read(effectiveWorkingDirProvider);
      if (sid == null || sid.isEmpty) {
        final handle = await conn.client.newSession(
          cwd: cwd,
          mcpServers: _sessionMcpServers(conn),
        );
        sid = handle.sessionId;
        _loadedSessionId = sid;
        ref.read(sessionsProvider.notifier).registerCreatedSession(
          AcpSessionInfo(
            sessionId: sid,
            cwd: cwd,
            title: cleanBody.length > 36
                ? '${cleanBody.substring(0, 36)}…'
                : cleanBody,
            updatedAt: DateTime.now(),
          ),
        );
        state = state.copyWith(
          sessionId: sid,
          sessionCwd: cwd,
          transcript: state.transcript.copyWith(
            modes: handle.modes,
            configOptions: handle.configOptions,
          ),
        );
      }

      state = state.copyWith(
        transcript: state.transcript.appendUserPrompt(text),
      );

      final result = await conn.client.promptText(sid, text);
      if (!ref.mounted) return;
      state = state.copyWith(
        transcript: state.transcript.finishTurn(
          result.stopReason,
          usage: result.usage,
        ),
        isSending: false,
      );
    } on AcpRpcException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        transcript: state.transcript.finishTurn(AcpStopReason.unknown),
        isSending: false,
        authRequired: e.isAuthRequired,
        error: e.isAuthRequired
            ? 'Antigravity CLI 尚未登录或未配置 Gemini API Key，请前往「本机引擎 / 设置」完成认证。'
            : e.message,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        transcript: state.transcript.finishTurn(AcpStopReason.unknown),
        isSending: false,
        error: e.toString(),
      );
    }
  }

  Future<void> cancel() async {
    final conn = ref.read(activeConnectionProvider).value;
    final sid = state.sessionId;
    if (conn == null || sid == null) return;
    await conn.client.cancel(sid);
    state = state.copyWith(
      pendingPermissions: const [],
      isSending: false,
    );
  }

  void respondPermission(
    PendingPermission pending,
    String? optionId, {
    bool allowAllForChat = false,
  }) {
    if (allowAllForChat) {
      allowAllForCurrentSession();
    }
    if (optionId == null) {
      pending.cancel();
    } else {
      pending.select(optionId);
    }
    state = state.copyWith(
      pendingPermissions: state.pendingPermissions
          .where((p) => p.id != pending.id)
          .toList(),
    );
  }

  Future<void> setMode(String modeId) async {
    final conn = ref.read(activeConnectionProvider).value;
    final sid = state.sessionId;
    if (conn == null || sid == null) return;
    try {
      await conn.client.setMode(sid, modeId);
      state = state.copyWith(
        transcript: state.transcript.applyUpdate(CurrentModeUpdate(modeId)),
      );
    } catch (e) {
      state = state.copyWith(error: '切换模式失败: $e');
    }
  }

  Future<void> setConfigOption(String configId, Object value) async {
    final conn = ref.read(activeConnectionProvider).value;
    final sid = state.sessionId;
    if (conn == null || sid == null) return;
    try {
      final updated = await conn.client.setConfigOption(
        sid,
        configId: configId,
        value: value,
      );
      if (updated.isNotEmpty) {
        state = state.copyWith(
          transcript: state.transcript.copyWith(configOptions: updated),
        );
      }
    } catch (e) {
      state = state.copyWith(error: '更新会话选项失败: $e');
    }
  }

  void _onUpdate(AcpSessionNotification notification) {
    if (!ref.mounted) return;
    final currentSid = state.sessionId;
    if (currentSid != null && notification.sessionId != currentSid) return;

    final nextTranscript = state.transcript.applyUpdate(notification.update);
    if (notification.update case SessionInfoUpdate(:final title?)
        when currentSid != null) {
      ref.read(sessionsProvider.notifier).updateSessionTitle(currentSid, title);
    }
    state = state.copyWith(transcript: nextTranscript);
  }

  void _onPermissionRequest(PendingPermission pending) {
    if (!ref.mounted) return;
    final currentSid = state.sessionId;
    if (currentSid != null && pending.request.sessionId != currentSid) return;

    final autoGlobal = ref.read(settingsProvider).autoApproveCommands;
    final autoChat = currentSid != null && _allowAllSessions.contains(currentSid);
    if (autoGlobal || autoChat) {
      final allow = pending.request.options
          .where((o) => o.kind.isAllow)
          .firstOrNull;
      if (allow != null) {
        pending.select(allow.optionId);
        return;
      }
    }

    state = state.copyWith(
      pendingPermissions: [...state.pendingPermissions, pending],
    );
  }
}

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
