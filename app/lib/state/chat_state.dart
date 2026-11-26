import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show AppLifecycleState, WidgetsBinding;

import 'agy_config_state.dart';
import 'connection_state.dart';
import 'phone_state.dart';
import 'sessions_state.dart';
import 'settings_state.dart';
import 'system_state.dart';
import 'workspaces_state.dart';

/// A staged image or file attachment ready to be sent with the next ACP prompt.
class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.name,
    required this.path,
    required this.mimeType,
    this.sizeBytes = 0,
    this.bytes,
  });

  final String id;
  final String name;
  final String path;
  final String mimeType;
  final int sizeBytes;
  final Uint8List? bytes;

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  AcpContentBlock toAcpBlock() {
    if (isImage && bytes != null && bytes!.isNotEmpty) {
      return AcpImageBlock(
        data: base64Encode(bytes!),
        mimeType: mimeType,
        uri: path.isNotEmpty ? 'file://$path' : null,
      );
    }
    return AcpResourceLinkBlock(
      uri: path.startsWith('/') ? 'file://$path' : path,
      name: name,
      mimeType: mimeType,
      title: name,
    );
  }
}

class ChatState {
  const ChatState({
    this.sessionId,
    this.sessionCwd,
    this.additionalDirectories = const [],
    this.transcript = const ChatTranscript(),
    this.pendingPermissions = const [],
    this.attachments = const [],
    this.queuedMessages = const [],
    this.sessionAgentMode,
    this.sessionToolPermission,
    this.allowAllForSession = false,
    this.turnStartedAt,
    this.turnChars = 0,
    this.isSending = false,
    this.isLoadingSession = false,
    this.authRequired = false,
    this.quotedText,
    this.error,
  });

  final String? sessionId;
  final String? sessionCwd;
  final List<String> additionalDirectories;
  final ChatTranscript transcript;
  final List<PendingPermission> pendingPermissions;
  final List<ChatAttachment> attachments;
  final List<String> queuedMessages;
  final AgyAgentMode? sessionAgentMode;
  final AgyToolPermission? sessionToolPermission;
  final bool allowAllForSession;
  final DateTime? turnStartedAt;
  final int turnChars;
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
    List<String>? additionalDirectories,
    ChatTranscript? transcript,
    List<PendingPermission>? pendingPermissions,
    List<ChatAttachment>? attachments,
    List<String>? queuedMessages,
    AgyAgentMode? Function()? sessionAgentMode,
    AgyToolPermission? Function()? sessionToolPermission,
    bool? allowAllForSession,
    DateTime? Function()? turnStartedAt,
    int? turnChars,
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
    additionalDirectories:
        additionalDirectories ?? this.additionalDirectories,
    transcript: transcript ?? this.transcript,
    pendingPermissions: pendingPermissions ?? this.pendingPermissions,
    attachments: attachments ?? this.attachments,
    queuedMessages: queuedMessages ?? this.queuedMessages,
    sessionAgentMode: sessionAgentMode == null
        ? this.sessionAgentMode
        : sessionAgentMode(),
    sessionToolPermission: sessionToolPermission == null
        ? this.sessionToolPermission
        : sessionToolPermission(),
    allowAllForSession: allowAllForSession ?? this.allowAllForSession,
    turnStartedAt:
        turnStartedAt == null ? this.turnStartedAt : turnStartedAt(),
    turnChars: turnChars ?? this.turnChars,
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
  final Map<String, AgyAgentMode> _sessionModes = {};
  final Map<String, AgyToolPermission> _sessionPermissions = {};

  bool get _isAppBackgrounded {
    final life = WidgetsBinding.instance.lifecycleState;
    return life == AppLifecycleState.paused ||
        life == AppLifecycleState.hidden ||
        life == AppLifecycleState.inactive;
  }

  List<AcpMcpServerConfig> _sessionMcpServers(HostConnection conn) {
    final servers = <AcpMcpServerConfig>[];
    if (conn.isLocal && conn.initResult.capabilities.supportsHttpMcp) {
      final phone = ref.read(phoneControlProvider);
      if (phone.isMcpReady) {
        servers.add(
          HttpMcpServerConfig(
            name: 'phone',
            url: phone.mcpUrl!,
            headers: {'Authorization': 'Bearer ${phone.mcpToken!}'},
          ),
        );
      }
      final configured = ref.read(agyConfigProvider).mcpServers;
      for (final entry in configured) {
        if (entry.name == 'phone') continue;
        final cfg = entry.toAcpConfig();
        if (cfg != null) servers.add(cfg);
      }
    }
    return servers;
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
        sessionAgentMode: _sessionModes[selectedId],
        sessionToolPermission: _sessionPermissions[selectedId],
        allowAllForSession: _allowAllSessions.contains(selectedId),
        isLoadingSession: true,
      );
    }
    return const ChatState();
  }

  AgyAgentMode effectiveAgentMode() =>
      state.sessionAgentMode ?? ref.read(settingsProvider).agentMode;

  AgyToolPermission effectiveToolPermission() =>
      state.sessionToolPermission ?? ref.read(settingsProvider).toolPermission;

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

  void addAttachment(ChatAttachment item) {
    state = state.copyWith(attachments: [...state.attachments, item]);
  }

  void removeAttachment(String id) {
    state = state.copyWith(
      attachments: state.attachments.where((a) => a.id != id).toList(),
    );
  }

  void addAdditionalDirectory(String path) {
    final clean = path.trim();
    if (clean.isEmpty || state.additionalDirectories.contains(clean)) return;
    state = state.copyWith(
      additionalDirectories: [...state.additionalDirectories, clean],
    );
  }

  void removeQueuedMessage(int index) {
    if (index < 0 || index >= state.queuedMessages.length) return;
    final next = List<String>.from(state.queuedMessages)..removeAt(index);
    state = state.copyWith(queuedMessages: next);
  }

  void allowAllForCurrentSession([bool enabled = true]) {
    final sid = state.sessionId;
    if (sid != null) {
      if (enabled) {
        _allowAllSessions.add(sid);
      } else {
        _allowAllSessions.remove(sid);
      }
    }
    state = state.copyWith(allowAllForSession: enabled);
  }

  /// Switches the execution mode for the current session (and syncs ACP `session/set_mode`
  /// when the server advertises a matching mode).
  Future<void> setExecutionMode(
    AgyAgentMode mode, {
    bool persistAsDefault = false,
  }) async {
    final sid = state.sessionId;
    if (sid != null) {
      _sessionModes[sid] = mode;
    }
    state = state.copyWith(sessionAgentMode: () => mode);
    if (persistAsDefault) {
      await ref.read(settingsProvider.notifier).setAgentMode(mode);
    }
    final available = state.transcript.modes?.availableModes ?? const [];
    if (sid != null && available.isNotEmpty) {
      final matched = available.where((m) {
        final lower = m.id.toLowerCase();
        return mode.acpModeAliases.contains(lower);
      }).firstOrNull;
      if (matched != null) {
        await setMode(matched.id);
      }
    }
  }

  /// Switches the tool permission preset for the current session (and optionally default).
  Future<void> setSessionToolPermission(
    AgyToolPermission permission, {
    bool persistAsDefault = false,
  }) async {
    final sid = state.sessionId;
    if (sid != null) {
      _sessionPermissions[sid] = permission;
      if (permission == AgyToolPermission.alwaysProceed) {
        _allowAllSessions.add(sid);
      } else {
        _allowAllSessions.remove(sid);
      }
    }
    state = state.copyWith(
      sessionToolPermission: () => permission,
      allowAllForSession: permission == AgyToolPermission.alwaysProceed,
    );
    if (persistAsDefault) {
      await ref.read(settingsProvider.notifier).setToolPermission(permission);
    }
    // Auto-resolve any waiting permissions if switched into YOLO.
    if (permission == AgyToolPermission.alwaysProceed &&
        state.pendingPermissions.isNotEmpty) {
      for (final p in state.pendingPermissions.toList()) {
        final allow = p.request.options.where((o) => o.kind.isAllow).firstOrNull;
        if (allow != null) respondPermission(p, allow.optionId);
      }
    }
  }

  Future<void> send(String rawText) async {
    final cleanBody = rawText.trim();
    final stagedAttachments = List<ChatAttachment>.from(state.attachments);
    if (cleanBody.isEmpty && stagedAttachments.isEmpty) return;

    // Handle mid-turn message submission (Steer vs Queue).
    if (state.isBusy) {
      final behavior = ref.read(settingsProvider).queuedBehavior;
      if (behavior == AgyQueuedMessageBehavior.queue) {
        if (cleanBody.isNotEmpty) {
          state = state.copyWith(
            queuedMessages: [...state.queuedMessages, cleanBody],
          );
        }
        return;
      }
      // Steering mode: cancel active turn cleanly and immediately send the steering prompt.
      await cancel();
    }

    final quote = state.quotedText;
    final bodyWithPlan =
        effectiveAgentMode() == AgyAgentMode.plan &&
            cleanBody.isNotEmpty &&
            !cleanBody.startsWith('/')
        ? '/plan $cleanBody'
        : cleanBody;
    final text = quote != null && quote.isNotEmpty
        ? '> ${quote.replaceAll('\n', '\n> ')}\n\n$bodyWithPlan'
        : bodyWithPlan;

    final conn = ref.read(activeConnectionProvider).value;
    if (conn == null) {
      state = state.copyWith(error: '引擎未连接，请先启动本机引擎或选择 SSH 主机。');
      return;
    }

    state = state.copyWith(
      isSending: true,
      turnStartedAt: () => DateTime.now(),
      turnChars: 0,
      attachments: const [],
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
          additionalDirectories: state.additionalDirectories,
        );
        sid = handle.sessionId;
        _loadedSessionId = sid;
        if (state.sessionAgentMode != null) {
          _sessionModes[sid] = state.sessionAgentMode!;
        }
        if (state.sessionToolPermission != null) {
          _sessionPermissions[sid] = state.sessionToolPermission!;
        }
        final titleSeed = cleanBody.isNotEmpty
            ? cleanBody
            : stagedAttachments.map((a) => a.name).join(', ');
        ref.read(sessionsProvider.notifier).registerCreatedSession(
          AcpSessionInfo(
            sessionId: sid,
            cwd: cwd,
            title: titleSeed.length > 36
                ? '${titleSeed.substring(0, 36)}…'
                : titleSeed,
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
        // Apply session execution mode immediately on new ACP session if matched.
        final desiredMode = effectiveAgentMode();
        if (handle.modes != null && desiredMode != AgyAgentMode.standard) {
          final match = handle.modes!.availableModes
              .where((m) => desiredMode.acpModeAliases.contains(m.id.toLowerCase()))
              .firstOrNull;
          if (match != null && match.id != handle.modes!.currentModeId) {
            unawaited(setMode(match.id));
          }
        }
      }

      final displayPrompt = [
        if (stagedAttachments.isNotEmpty)
          stagedAttachments
              .map((a) => a.isImage ? '[图片: ${a.name}]' : '[附件: ${a.name}]')
              .join(' '),
        if (text.isNotEmpty) text,
      ].join('\n');

      state = state.copyWith(
        transcript: state.transcript.appendUserPrompt(displayPrompt),
      );

      final blocks = <AcpContentBlock>[
        for (final a in stagedAttachments) a.toAcpBlock(),
        if (text.isNotEmpty) AcpTextBlock(text),
      ];

      final result = await conn.client.prompt(sid, blocks);
      if (!ref.mounted) return;
      state = state.copyWith(
        transcript: state.transcript.finishTurn(
          result.stopReason,
          usage: result.usage,
        ),
        isSending: false,
        turnStartedAt: () => null,
      );

      if (_isAppBackgrounded && ref.read(settingsProvider).notifyOnTurnComplete) {
        final sessionTitle =
            state.transcript.title ??
            ref.read(sessionsProvider).currentSession?.title ??
            'AGY Go';
        unawaited(
          ref.read(systemToolsProvider.notifier).notifyTurnEvent(
            title: '回复已完成 · $sessionTitle',
            body: '点击返回查看最新输出与变更',
            urgent: false,
          ),
        );
      }

      // Automatically drain next queued message if any.
      if (state.queuedMessages.isNotEmpty) {
        final nextMsg = state.queuedMessages.first;
        state = state.copyWith(
          queuedMessages: state.queuedMessages.sublist(1),
        );
        unawaited(send(nextMsg));
      }
    } on AcpRpcException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        transcript: state.transcript.finishTurn(AcpStopReason.unknown),
        isSending: false,
        turnStartedAt: () => null,
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
        turnStartedAt: () => null,
        error: e.toString(),
      );
    }
  }

  /// Re-sends the most recent user prompt to regenerate a fresh answer.
  Future<void> regenerateLast() async {
    final lastUser = state.transcript.items
        .whereType<UserTranscriptItem>()
        .lastOrNull;
    if (lastUser == null) return;
    await send(lastUser.text);
  }

  /// Forks into a brand-new conversation seeded with a quote/context summary.
  Future<void> forkFromText(String seedText) async {
    startNewChat();
    setQuote(seedText);
  }

  Future<void> cancel() async {
    final conn = ref.read(activeConnectionProvider).value;
    final sid = state.sessionId;
    if (conn == null || sid == null) return;
    await conn.client.cancel(sid);
    state = state.copyWith(
      pendingPermissions: const [],
      isSending: false,
      turnStartedAt: () => null,
    );
  }

  Future<bool> logoutAgent() async {
    final conn = ref.read(activeConnectionProvider).value;
    if (conn == null) return false;
    try {
      await conn.client.logout();
      startNewChat();
      return true;
    } catch (e) {
      state = state.copyWith(error: '退出登录失败：$e');
      return false;
    }
  }

  void respondPermission(
    PendingPermission pending,
    String? optionId, {
    bool allowAllForChat = false,
  }) {
    if (allowAllForChat) {
      allowAllForCurrentSession(true);
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

    var addedChars = 0;
    switch (notification.update) {
      case AgentMessageChunkUpdate(:final content):
        if (content case AcpTextBlock(:final text)) addedChars = text.length;
      case AgentThoughtChunkUpdate(:final content):
        if (content case AcpTextBlock(:final text)) addedChars = text.length;
      default:
        break;
    }

    final nextTranscript = state.transcript.applyUpdate(notification.update);
    if (notification.update case SessionInfoUpdate(:final title?)
        when currentSid != null) {
      ref.read(sessionsProvider.notifier).updateSessionTitle(currentSid, title);
    }
    state = state.copyWith(
      transcript: nextTranscript,
      turnChars: state.turnChars + addedChars,
    );
  }

  void _onPermissionRequest(PendingPermission pending) {
    if (!ref.mounted) return;
    final currentSid = state.sessionId;
    if (currentSid != null && pending.request.sessionId != currentSid) return;

    final perm = effectiveToolPermission();
    final mode = effectiveAgentMode();
    final autoChat =
        state.allowAllForSession ||
        (currentSid != null && _allowAllSessions.contains(currentSid));

    var shouldAutoAllow =
        perm == AgyToolPermission.alwaysProceed || autoChat;

    // In accept-edits / auto execution modes, auto-approve workspace edits/reads while still asking for commands/deletes.
    if (!shouldAutoAllow &&
        perm != AgyToolPermission.strict &&
        (mode == AgyAgentMode.acceptEdits || mode == AgyAgentMode.auto)) {
      final kind = pending.request.toolCall.kind;
      if (kind == AcpToolKind.edit ||
          kind == AcpToolKind.read ||
          kind == AcpToolKind.search) {
        shouldAutoAllow = true;
      }
    }

    if (shouldAutoAllow) {
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

    if (_isAppBackgrounded && ref.read(settingsProvider).notifyOnApproval) {
      unawaited(
        ref.read(systemToolsProvider.notifier).notifyTurnEvent(
          title: '等待你的审批确认',
          body: pending.request.toolCall.title.isNotEmpty
              ? pending.request.toolCall.title
              : 'Antigravity 请求执行一项工具操作',
          urgent: true,
        ),
      );
    }
  }
}

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
