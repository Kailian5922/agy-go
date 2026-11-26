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
    this.draftSessionId,
    this.draftSessionCwd,
    this.draftAdditionalDirs = const [],
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
    this.isPreparingModels = false,
    this.isUpdatingModel = false,
    this.authRequired = false,
    this.quotedText,
    this.error,
    this.modelError,
  });

  /// Active conversation session ID (null on fresh empty screen before message #1).
  final String? sessionId;
  final String? sessionCwd;

  /// Pre-warmed silent ACP draft session used to discover & switch models/effort
  /// before message #1, then seamlessly promoted to [sessionId] on send.
  final String? draftSessionId;
  final String? draftSessionCwd;
  final List<String> draftAdditionalDirs;

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
  final bool isPreparingModels;
  final bool isUpdatingModel;
  final bool authRequired;
  final String? quotedText;
  final String? error;
  final String? modelError;

  bool get isBusy => isSending || transcript.isStreaming;

  /// The live ACP session ID backing RPCs (active chat or pre-warmed draft).
  String? get activeRpcSessionId => sessionId ?? draftSessionId;

  AcpConfigOption? get modelConfigOption =>
      transcript.configOptions.where((c) => c.isModelOption).firstOrNull;

  AcpConfigOption? get thoughtLevelOption =>
      transcript.configOptions.where((c) => c.isThoughtLevelOption).firstOrNull;

  List<AcpConfigOption> get otherConfigOptions => transcript.configOptions
      .where((c) => !c.isModelOption && !c.isThoughtLevelOption && !c.isModeOption)
      .toList();

  ChatState copyWith({
    String? sessionId,
    bool clearSessionId = false,
    String? sessionCwd,
    bool clearSessionCwd = false,
    String? draftSessionId,
    String? draftSessionCwd,
    List<String>? draftAdditionalDirs,
    bool clearDraftSession = false,
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
    bool? isPreparingModels,
    bool? isUpdatingModel,
    bool? authRequired,
    String? quotedText,
    bool clearQuotedText = false,
    String? error,
    bool clearError = false,
    String? modelError,
    bool clearModelError = false,
  }) => ChatState(
    sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
    sessionCwd: clearSessionCwd ? null : (sessionCwd ?? this.sessionCwd),
    draftSessionId: clearDraftSession
        ? null
        : (draftSessionId ?? this.draftSessionId),
    draftSessionCwd: clearDraftSession
        ? null
        : (draftSessionCwd ?? this.draftSessionCwd),
    draftAdditionalDirs: clearDraftSession
        ? const []
        : (draftAdditionalDirs ?? this.draftAdditionalDirs),
    additionalDirectories: additionalDirectories ?? this.additionalDirectories,
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
    turnStartedAt: turnStartedAt == null ? this.turnStartedAt : turnStartedAt(),
    turnChars: turnChars ?? this.turnChars,
    isSending: isSending ?? this.isSending,
    isLoadingSession: isLoadingSession ?? this.isLoadingSession,
    isPreparingModels: isPreparingModels ?? this.isPreparingModels,
    isUpdatingModel: isUpdatingModel ?? this.isUpdatingModel,
    authRequired: authRequired ?? this.authRequired,
    quotedText: clearQuotedText ? null : (quotedText ?? this.quotedText),
    error: clearError ? null : (error ?? this.error),
    modelError: clearModelError ? null : (modelError ?? this.modelError),
  );
}

class ChatController extends Notifier<ChatState> {
  StreamSubscription<AcpSessionNotification>? _updateSub;
  StreamSubscription<PendingPermission>? _permSub;
  HostConnection? _activeConn;

  /// Tracks the session ID currently owned by this controller so self-originated
  /// `sessionsProvider.registerCreatedSession` updates NEVER trigger a reload or
  /// tear down an in-flight first turn.
  String? _ownedSessionId;
  int _loadGeneration = 0;
  int _turnGen = 0;

  Future<String?>? _draftFuture;
  String? _draftFutureCwd;

  AcpSessionModeState? _cachedModes;
  List<AcpConfigOption> _cachedConfigOptions = const [];

  final Set<String> _allowAllSessions = {};
  final Map<String, AgyAgentMode> _sessionModes = {};
  final Map<String, AgyToolPermission> _sessionPermissions = {};

  bool get _isAppBackgrounded {
    final life = WidgetsBinding.instance.lifecycleState;
    return life == AppLifecycleState.paused ||
        life == AppLifecycleState.hidden ||
        life == AppLifecycleState.inactive;
  }

  String _draftMcpSignature = '';

  List<AcpMcpServerConfig> _sessionMcpServers(HostConnection conn) {
    final servers = <AcpMcpServerConfig>[];
    if (conn.isLocal) {
      final caps = conn.initResult.capabilities;
      if (caps.supportsHttpMcp) {
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
      }
      final configured = ref.read(agyConfigProvider).mcpServers;
      for (final entry in configured) {
        if (entry.name == 'phone') continue;
        final cfg = entry.toAcpConfig();
        if (cfg == null) continue;
        if (cfg is HttpMcpServerConfig) {
          if (cfg.transportType == 'sse' && !caps.supportsSseMcp) continue;
          if (cfg.transportType != 'sse' && !caps.supportsHttpMcp) continue;
        }
        servers.add(cfg);
      }
    }
    return servers;
  }

  static String _mcpSignature(List<AcpMcpServerConfig> servers) {
    if (servers.isEmpty) return '';
    return servers
        .map((s) => switch (s) {
              HttpMcpServerConfig(:final name, :final transportType, :final url) =>
                '$transportType:$name:$url',
              StdioMcpServerConfig(:final name, :final command, :final args) =>
                'stdio:$name:$command:${args.join(",")}',
            })
        .join('|');
  }

  static bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  ChatState build() {
    // Watch ONLY the active connection value (not sessionsProvider.currentSessionId!)
    // so registering a brand-new session mid-send never disposes this controller.
    final conn = ref.watch(activeConnectionProvider.select((a) => a.value));

    _updateSub?.cancel();
    _permSub?.cancel();
    _updateSub = null;
    _permSub = null;
    _activeConn = conn;
    _ownedSessionId = null;
    _draftFuture = null;
    _draftFutureCwd = null;
    _cachedModes = null;
    _cachedConfigOptions = const [];
    _loadGeneration++;
    _turnGen++;

    ref.onDispose(() {
      unawaited(_updateSub?.cancel());
      unawaited(_permSub?.cancel());
    });

    ref.listen<String?>(
      sessionsProvider.select((s) => s.currentSessionId),
      _onSelectedSessionChanged,
    );

    ref.listen<String>(
      effectiveWorkingDirProvider,
      _onWorkingDirChanged,
    );

    ref.listen<WorkspaceItem?>(
      selectedWorkspaceProvider,
      _onWorkspaceSelectionChanged,
    );

    if (conn == null) return const ChatState();

    _updateSub = conn.client.updates.listen(_onUpdate);
    _permSub = conn.client.permissionRequests.listen(_onPermissionRequest);

    final selectedId = ref.read(sessionsProvider).currentSessionId;
    if (selectedId != null && selectedId.isNotEmpty) {
      final sessionInfo = ref.read(sessionsProvider).currentSession;
      final String cwd =
          sessionInfo?.cwd ?? ref.read(effectiveWorkingDirProvider);
      _ownedSessionId = selectedId;
      final gen = ++_loadGeneration;
      unawaited(_loadExistingSession(conn, selectedId, cwd, gen));
      return ChatState(
        sessionId: selectedId,
        sessionCwd: cwd,
        sessionAgentMode: _sessionModes[selectedId],
        sessionToolPermission: _sessionPermissions[selectedId],
        allowAllForSession: _allowAllSessions.contains(selectedId),
        isLoadingSession: true,
      );
    }

    // Fresh home screen: pre-warm a silent draft ACP session in the background so
    // live models & thinking effort options are selectable BEFORE message #1.
    Future.microtask(() {
      if (ref.mounted && _activeConn == conn && state.sessionId == null) {
        unawaited(prepareDraftSession());
      }
    });
    return const ChatState(isPreparingModels: true);
  }

  void _onSelectedSessionChanged(String? previous, String? next) {
    final conn = _activeConn;
    if (conn == null) return;

    // Self-originated promotion from new/draft -> active conversation: do NOT reload!
    if (next == _ownedSessionId) return;

    if (next == null || next.isEmpty) {
      _ownedSessionId = null;
      _loadGeneration++;
      _turnGen++;
      state = ChatState(
        transcript: ChatTranscript(
          modes: _cachedModes,
          configOptions: _cachedConfigOptions,
        ),
        isPreparingModels: _cachedConfigOptions.isEmpty,
      );
      unawaited(prepareDraftSession());
      return;
    }

    // User selected a different history session from drawer or search.
    _discardDraftSession(conn);
    _ownedSessionId = next;
    final gen = ++_loadGeneration;
    _turnGen++;
    final sessionInfo = ref.read(sessionsProvider).currentSession;
    final String cwd =
        sessionInfo?.cwd ?? ref.read(effectiveWorkingDirProvider);
    state = ChatState(
      sessionId: next,
      sessionCwd: cwd,
      transcript: ChatTranscript(
        modes: _cachedModes,
        configOptions: _cachedConfigOptions,
      ),
      sessionAgentMode: _sessionModes[next],
      sessionToolPermission: _sessionPermissions[next],
      allowAllForSession: _allowAllSessions.contains(next),
      isLoadingSession: true,
    );
    unawaited(_loadExistingSession(conn, next, cwd, gen));
  }

  void _onWorkingDirChanged(String? previous, String next) {
    final conn = _activeConn;
    if (conn == null) return;
    if (previous == next) return;

    // Only rotate the silent draft session when on the fresh home screen.
    if (state.sessionId == null && state.draftSessionCwd != next) {
      _discardDraftSession(conn);
      unawaited(prepareDraftSession(forceRefresh: true));
    }
  }

  void _onWorkspaceSelectionChanged(WorkspaceItem? previous, WorkspaceItem? next) {
    if (next == null || previous?.path == next.path) return;
    if (state.isBusy) return;
    final activeCwd = state.sessionCwd;
    if (state.sessionId != null && activeCwd != null) {
      final normActive = normalizeWorkspacePath(activeCwd);
      final normNext = normalizeWorkspacePath(next.path);
      final inside =
          normActive == normNext ||
          (normNext == '/'
              ? normActive.startsWith('/')
              : normActive.startsWith('$normNext/'));
      if (!inside) {
        startNewChat();
      }
    }
  }

  void _discardDraftSession(HostConnection conn) {
    final oldDraft = state.draftSessionId;
    _draftFuture = null;
    _draftFutureCwd = null;
    if (oldDraft != null && oldDraft.isNotEmpty) {
      state = state.copyWith(clearDraftSession: true);
      if (conn.initResult.capabilities.canCloseSession) {
        unawaited(conn.client.closeSession(oldDraft).catchError((_) {}));
      }
    }
  }

  AgyAgentMode effectiveAgentMode() =>
      state.sessionAgentMode ?? ref.read(settingsProvider).agentMode;

  AgyToolPermission effectiveToolPermission() =>
      state.sessionToolPermission ?? ref.read(settingsProvider).toolPermission;

  /// Pre-creates (or refreshes) a silent ACP draft session so the user can inspect
  /// and switch real Antigravity models & thinking effort levels before sending message #1.
  Future<String?> prepareDraftSession({bool forceRefresh = false}) async {
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    if (conn == null) return null;
    if (state.sessionId != null) return state.sessionId;

    final String cwd = ref.read(effectiveWorkingDirProvider);
    final extraDirs = List<String>.from(state.additionalDirectories);

    if (!forceRefresh &&
        state.draftSessionId != null &&
        state.draftSessionCwd == cwd &&
        _sameStringList(state.draftAdditionalDirs, extraDirs)) {
      return state.draftSessionId;
    }

    if (!forceRefresh && _draftFuture != null && _draftFutureCwd == cwd) {
      return _draftFuture;
    }

    if (forceRefresh && state.draftSessionId != null) {
      _discardDraftSession(conn);
    }

    final future = _createDraftSession(conn, cwd, extraDirs);
    _draftFuture = future;
    _draftFutureCwd = cwd;
    try {
      return await future;
    } finally {
      if (identical(_draftFuture, future)) {
        _draftFuture = null;
        _draftFutureCwd = null;
      }
    }
  }

  Future<String?> _createDraftSession(
    HostConnection conn,
    String cwd,
    List<String> extraDirs,
  ) async {
    if (!ref.mounted || _activeConn != conn || state.sessionId != null) {
      return state.sessionId;
    }
    state = state.copyWith(isPreparingModels: true, clearModelError: true);
    try {
      final mcpServers = _sessionMcpServers(conn);
      final mcpSig = _mcpSignature(mcpServers);
      final handle = await conn.client.newSession(
        cwd: cwd,
        mcpServers: mcpServers,
        additionalDirectories: extraDirs,
      );
      if (!ref.mounted || _activeConn != conn) return null;
      if (state.sessionId != null) {
        // User opened/started a real session while draft was loading.
        if (conn.initResult.capabilities.canCloseSession) {
          unawaited(
            conn.client.closeSession(handle.sessionId).catchError((_) {}),
          );
        }
        return state.sessionId;
      }

      var configs = handle.configOptions;
      if (handle.modes != null) _cachedModes = handle.modes;

      // Apply user's saved preferred model & thinking effort BEFORE publishing the
      // draft session so the UI never flickers or races a manual model pick.
      final applied = await _applyPreferredModelAndThought(
        conn,
        handle.sessionId,
        configs,
      );
      if (!ref.mounted || _activeConn != conn) return null;
      if (state.sessionId != null) {
        if (conn.initResult.capabilities.canCloseSession) {
          unawaited(
            conn.client.closeSession(handle.sessionId).catchError((_) {}),
          );
        }
        return state.sessionId;
      }
      if (applied.isNotEmpty) {
        configs = applied;
      }
      if (configs.isNotEmpty) _cachedConfigOptions = configs;
      _draftMcpSignature = mcpSig;

      state = state.copyWith(
        draftSessionId: handle.sessionId,
        draftSessionCwd: cwd,
        draftAdditionalDirs: extraDirs,
        transcript: state.transcript.copyWith(
          modes: handle.modes ?? state.transcript.modes,
          configOptions: configs.isNotEmpty
              ? configs
              : state.transcript.configOptions,
        ),
        isPreparingModels: false,
        authRequired: false,
        clearModelError: true,
      );
      return handle.sessionId;
    } on AcpRpcException catch (e) {
      if (!ref.mounted || _activeConn != conn) return null;
      state = state.copyWith(
        isPreparingModels: false,
        authRequired: e.isAuthRequired,
        modelError: e.isAuthRequired
            ? 'Antigravity CLI 尚未完成认证，请先前往「本机引擎」登录 Google 账号或填写 Gemini API Key。'
            : e.message,
      );
      return null;
    } catch (e) {
      if (!ref.mounted || _activeConn != conn) return null;
      state = state.copyWith(
        isPreparingModels: false,
        modelError: e.toString(),
      );
      return null;
    }
  }

  Future<List<AcpConfigOption>> _applyPreferredModelAndThought(
    HostConnection conn,
    String sid,
    List<AcpConfigOption> initialConfigs,
  ) async {
    var configs = initialConfigs;
    if (configs.isEmpty) return configs;
    final settings = ref.read(settingsProvider);

    final prefModel = settings.preferredModelId;
    final modelOpt = configs.where((c) => c.isModelOption).firstOrNull;
    if (prefModel != null &&
        modelOpt != null &&
        '${modelOpt.currentValue}' != prefModel &&
        modelOpt.options.any((o) => o.value == prefModel)) {
      try {
        final updated = await conn.client.setConfigOption(
          sid,
          configId: modelOpt.id,
          value: prefModel,
        );
        if (updated.isNotEmpty) {
          configs = updated;
        }
      } catch (_) {
        // Keep server default if preferred model is unavailable on this host.
      }
    }

    final prefThought = settings.preferredThoughtLevel;
    final thoughtOpt = configs.where((c) => c.isThoughtLevelOption).firstOrNull;
    if (prefThought != null &&
        thoughtOpt != null &&
        '${thoughtOpt.currentValue}' != prefThought &&
        thoughtOpt.options.any((o) => o.value == prefThought)) {
      try {
        final updated = await conn.client.setConfigOption(
          sid,
          configId: thoughtOpt.id,
          value: prefThought,
        );
        if (updated.isNotEmpty) {
          configs = updated;
        }
      } catch (_) {}
    }

    return configs;
  }

  Future<void> _loadExistingSession(
    HostConnection conn,
    String sid,
    String cwd,
    int gen,
  ) async {
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
        if (!ref.mounted || _loadGeneration != gen) return;
        state = state.copyWith(
          transcript: state.transcript.finishAllStreaming(),
          isLoadingSession: false,
        );
        return;
      }
      if (!ref.mounted || _loadGeneration != gen) return;
      if (handle.modes != null) _cachedModes = handle.modes;
      if (handle.configOptions.isNotEmpty) {
        _cachedConfigOptions = handle.configOptions;
      }
      state = state.copyWith(
        sessionId: handle.sessionId,
        sessionCwd: cwd,
        transcript: state.transcript.finishAllStreaming().copyWith(
          modes: handle.modes ?? state.transcript.modes,
          configOptions: handle.configOptions.isNotEmpty
              ? handle.configOptions
              : state.transcript.configOptions,
        ),
        isLoadingSession: false,
        authRequired: false,
        clearError: true,
        clearModelError: true,
      );
    } on AcpRpcException catch (e) {
      if (!ref.mounted || _loadGeneration != gen) return;
      state = state.copyWith(
        transcript: state.transcript.finishAllStreaming(),
        isLoadingSession: false,
        authRequired: e.isAuthRequired,
        error: e.message,
      );
    } catch (e) {
      if (!ref.mounted || _loadGeneration != gen) return;
      state = state.copyWith(
        transcript: state.transcript.finishAllStreaming(),
        isLoadingSession: false,
        error: e.toString(),
      );
    }
  }

  void startNewChat() {
    final conn = _activeConn;
    _ownedSessionId = null;
    _loadGeneration++;
    _turnGen++;
    if (conn != null) {
      _discardDraftSession(conn);
    }
    ref.read(sessionsProvider.notifier).selectSession(null);
    state = ChatState(
      transcript: ChatTranscript(
        modes: _cachedModes,
        configOptions: _cachedConfigOptions,
      ),
      isPreparingModels: conn != null && _cachedConfigOptions.isEmpty,
    );
    if (conn != null) {
      unawaited(prepareDraftSession());
    }
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
    final rpcSid = state.activeRpcSessionId;
    if (rpcSid != null && available.isNotEmpty) {
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
    if (permission == AgyToolPermission.alwaysProceed &&
        state.pendingPermissions.isNotEmpty) {
      for (final p in state.pendingPermissions.toList()) {
        final allow = p.request.options.where((o) => o.kind.isAllow).firstOrNull;
        if (allow != null) respondPermission(p, allow.optionId);
      }
    }
  }

  /// Selects a model (works both BEFORE message #1 via the draft session and mid-chat).
  /// Updates `thought_level` options dynamically from `agy acp`'s response.
  Future<bool> selectModel(String modelValue) async {
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    if (conn == null) return false;

    final sid = state.activeRpcSessionId ?? await prepareDraftSession();
    if (sid == null) return false;

    final modelOpt = state.modelConfigOption;
    final configId = modelOpt?.id ?? 'model';

    state = state.copyWith(isUpdatingModel: true, clearModelError: true);
    try {
      List<AcpConfigOption> updated = const [];
      try {
        updated = await conn.client.setConfigOption(
          sid,
          configId: configId,
          value: modelValue,
        );
      } on AcpRpcException catch (e) {
        if (e.code == -32601) {
          await conn.client.setModel(sid, modelValue);
        } else {
          rethrow;
        }
      }
      if (!ref.mounted || _activeConn != conn) return false;

      final nextConfigs = updated.isNotEmpty
          ? updated
          : [
              for (final opt in state.transcript.configOptions)
                if (opt.id == configId)
                  opt.copyWith(currentValue: modelValue)
                else
                  opt,
            ];
      _cachedConfigOptions = nextConfigs;
      state = state.copyWith(
        transcript: state.transcript.copyWith(configOptions: nextConfigs),
        isUpdatingModel: false,
        clearModelError: true,
      );
      unawaited(
        ref.read(settingsProvider.notifier).setPreferredModelId(modelValue),
      );
      // Persist the resulting thought level for this model if advertised.
      final newThought = state.thoughtLevelOption?.currentValue;
      if (newThought is String && newThought.isNotEmpty) {
        unawaited(
          ref
              .read(settingsProvider.notifier)
              .setPreferredThoughtLevel(newThought),
        );
      }
      return true;
    } catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        isUpdatingModel: false,
        modelError: '切换模型失败：$e',
      );
      return false;
    }
  }

  /// Selects a thinking effort / thought level (works both before message #1 and mid-chat).
  Future<bool> selectThoughtLevel(String levelValue) async {
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    if (conn == null) return false;

    final sid = state.activeRpcSessionId ?? await prepareDraftSession();
    if (sid == null) return false;

    final thoughtOpt = state.thoughtLevelOption;
    if (thoughtOpt == null) return false;

    final ok = await setConfigOption(thoughtOpt.id, levelValue);
    if (ok) {
      unawaited(
        ref
            .read(settingsProvider.notifier)
            .setPreferredThoughtLevel(levelValue),
      );
    }
    return ok;
  }

  Future<void> send(String rawText, {bool forceImmediate = false}) async {
    final cleanBody = rawText.trim();
    final stagedAttachments = List<ChatAttachment>.from(state.attachments);
    if (cleanBody.isEmpty && stagedAttachments.isEmpty) return;

    // Handle mid-turn message submission (Steer / Immediate vs Queue).
    if (state.isBusy) {
      final behavior = ref.read(settingsProvider).queuedBehavior;
      if (!forceImmediate && behavior == AgyQueuedMessageBehavior.queue) {
        if (cleanBody.isNotEmpty) {
          state = state.copyWith(
            queuedMessages: [...state.queuedMessages, cleanBody],
          );
        }
        return;
      }
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

    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    if (conn == null) {
      state = state.copyWith(error: '引擎未连接，请先启动本机引擎或选择 SSH 主机。');
      return;
    }

    final myGen = ++_turnGen;
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
      final isFirstTurn = sid == null || sid.isEmpty;

      if (isFirstTurn) {
        // If a background draft pre-warm is currently running for this exact cwd,
        // wait for it rather than racing a second `session/new`.
        if (_draftFuture != null && _draftFutureCwd == cwd) {
          await _draftFuture;
          if (!ref.mounted || _activeConn != conn || _turnGen != myGen) return;
        }

        final currentMcpServers = _sessionMcpServers(conn);
        final canReuseDraft =
            state.draftSessionId != null &&
            state.draftSessionId!.isNotEmpty &&
            state.draftSessionCwd == cwd &&
            _draftMcpSignature == _mcpSignature(currentMcpServers) &&
            _sameStringList(
              state.draftAdditionalDirs,
              state.additionalDirectories,
            );

        AcpSessionModeState? modes = state.transcript.modes;
        List<AcpConfigOption> configs = state.transcript.configOptions;

        if (canReuseDraft) {
          sid = state.draftSessionId!;
        } else {
          _discardDraftSession(conn);
          final handle = await conn.client.newSession(
            cwd: cwd,
            mcpServers: currentMcpServers,
            additionalDirectories: state.additionalDirectories,
          );
          if (!ref.mounted || _activeConn != conn || _turnGen != myGen) return;
          sid = handle.sessionId;
          modes = handle.modes ?? modes;
          configs = handle.configOptions.isNotEmpty
              ? handle.configOptions
              : configs;
          if (modes != null) _cachedModes = modes;
          if (configs.isNotEmpty) _cachedConfigOptions = configs;

          // Ensure user's pre-selected model & thinking effort are applied BEFORE message #1!
          final applied = await _applyPreferredModelAndThought(
            conn,
            sid,
            configs,
          );
          if (!ref.mounted || _activeConn != conn || _turnGen != myGen) return;
          if (applied.isNotEmpty) {
            configs = applied;
            _cachedConfigOptions = applied;
          }
        }

        // Own & commit this session BEFORE calling registerCreatedSession so
        // `sessionsProvider.currentSessionId` changing NEVER triggers a reload!
        _ownedSessionId = sid;
        if (state.sessionAgentMode != null) {
          _sessionModes[sid] = state.sessionAgentMode!;
        }
        if (state.sessionToolPermission != null) {
          _sessionPermissions[sid] = state.sessionToolPermission!;
        }

        state = state.copyWith(
          sessionId: sid,
          sessionCwd: cwd,
          clearDraftSession: true,
          transcript: state.transcript.copyWith(
            modes: modes,
            configOptions: configs,
          ),
        );

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

        // Apply non-standard execution mode on the ACP session if matched.
        final desiredMode = effectiveAgentMode();
        if (modes != null && desiredMode != AgyAgentMode.standard) {
          final match = modes.availableModes
              .where(
                (m) => desiredMode.acpModeAliases.contains(m.id.toLowerCase()),
              )
              .firstOrNull;
          if (match != null && match.id != modes.currentModeId) {
            await setMode(match.id);
          }
        }
      }

      if (!ref.mounted || _ownedSessionId != sid || _turnGen != myGen) return;

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
      if (!ref.mounted || _ownedSessionId != sid || _turnGen != myGen) return;
      state = state.copyWith(
        transcript: state.transcript.finishTurn(
          result.stopReason,
          usage: result.usage,
        ),
        isSending: false,
        turnStartedAt: () => null,
      );

      if (_isAppBackgrounded &&
          ref.read(settingsProvider).notifyOnTurnComplete) {
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

      if (state.queuedMessages.isNotEmpty) {
        final nextMsg = state.queuedMessages.first;
        state = state.copyWith(
          queuedMessages: state.queuedMessages.sublist(1),
        );
        unawaited(send(nextMsg));
      }
    } on AcpRpcException catch (e) {
      if (!ref.mounted || _turnGen != myGen) return;
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
      if (!ref.mounted || _turnGen != myGen) return;
      state = state.copyWith(
        transcript: state.transcript.finishTurn(AcpStopReason.unknown),
        isSending: false,
        turnStartedAt: () => null,
        error: e.toString(),
      );
    }
  }

  /// Interrupts any active/stuck turn and sends queued message at [index] immediately.
  Future<void> sendQueuedNow(int index) async {
    if (index < 0 || index >= state.queuedMessages.length) return;
    final msg = state.queuedMessages[index];
    final next = List<String>.from(state.queuedMessages)..removeAt(index);
    state = state.copyWith(queuedMessages: next);
    await send(msg, forceImmediate: true);
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

  /// Immediately unlocks the UI, finishes any streaming cursor/pending tool calls,
  /// and sends ACP `session/cancel` non-blockingly so a hung network turn never traps the user.
  Future<void> cancel() async {
    _turnGen++;
    for (final p in state.pendingPermissions) {
      p.cancel();
    }
    state = state.copyWith(
      transcript: state.transcript.finishTurn(AcpStopReason.cancelled),
      pendingPermissions: const [],
      isSending: false,
      turnStartedAt: () => null,
    );
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    final sid = state.sessionId;
    if (conn == null || sid == null) return;
    unawaited(conn.client.cancel(sid).catchError((_) {}));
  }

  Future<bool> logoutAgent() async {
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    if (conn == null) return false;
    try {
      await conn.client.logout();
      _cachedModes = null;
      _cachedConfigOptions = const [];
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
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    final sid = state.activeRpcSessionId ?? await prepareDraftSession();
    if (conn == null || sid == null) return;
    try {
      await conn.client.setMode(sid, modeId);
      if (!ref.mounted) return;
      final nextTranscript = state.transcript.applyUpdate(
        CurrentModeUpdate(modeId),
      );
      if (nextTranscript.modes != null) _cachedModes = nextTranscript.modes;
      state = state.copyWith(transcript: nextTranscript);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(modelError: '切换模式失败: $e');
    }
  }

  Future<bool> setConfigOption(String configId, Object value) async {
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    final sid = state.activeRpcSessionId ?? await prepareDraftSession();
    if (conn == null || sid == null) return false;
    state = state.copyWith(isUpdatingModel: true, clearModelError: true);
    try {
      final updated = await conn.client.setConfigOption(
        sid,
        configId: configId,
        value: value,
      );
      if (!ref.mounted) return false;
      final nextConfigs = updated.isNotEmpty
          ? updated
          : [
              for (final opt in state.transcript.configOptions)
                if (opt.id == configId)
                  opt.copyWith(currentValue: value)
                else
                  opt,
            ];
      _cachedConfigOptions = nextConfigs;
      state = state.copyWith(
        transcript: state.transcript.copyWith(configOptions: nextConfigs),
        isUpdatingModel: false,
        clearModelError: true,
      );
      return true;
    } catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        isUpdatingModel: false,
        modelError: '更新会话选项失败: $e',
      );
      return false;
    }
  }

  void _onUpdate(AcpSessionNotification notification) {
    if (!ref.mounted) return;
    final targetSid = state.activeRpcSessionId;
    if (targetSid == null || notification.sessionId != targetSid) return;

    // For a silent pre-warmed draft session, only ingest metadata updates
    // (configOptions / modes / availableCommands) — never stray message chunks.
    final isDraftOnly = state.sessionId == null;
    if (isDraftOnly) {
      final update = notification.update;
      if (update is ConfigOptionUpdate) {
        _cachedConfigOptions = update.configOptions;
        state = state.copyWith(
          transcript: state.transcript.applyUpdate(update),
        );
      } else if (update is CurrentModeUpdate ||
          update is AvailableCommandsUpdate) {
        final next = state.transcript.applyUpdate(update);
        if (next.modes != null) _cachedModes = next.modes;
        state = state.copyWith(transcript: next);
      }
      return;
    }

    // Ignore stray late content/tool chunks when idle (e.g. arriving right after
    // the user tapped Stop or after a network failure), while still ingesting
    // metadata updates (config options, modes, session title, usage).
    final update = notification.update;
    if (!state.isSending && !state.isLoadingSession) {
      final isMetadata =
          update is ConfigOptionUpdate ||
          update is CurrentModeUpdate ||
          update is AvailableCommandsUpdate ||
          update is SessionInfoUpdate ||
          update is UsageSessionUpdate;
      if (!isMetadata) return;
    }

    var addedChars = 0;
    switch (update) {
      case AgentMessageChunkUpdate(:final content):
        if (content case AcpTextBlock(:final text)) addedChars = text.length;
      case AgentThoughtChunkUpdate(:final content):
        if (content case AcpTextBlock(:final text)) addedChars = text.length;
      case ConfigOptionUpdate(:final configOptions):
        _cachedConfigOptions = configOptions;
      default:
        break;
    }

    final nextTranscript = state.transcript.applyUpdate(update);
    if (update case SessionInfoUpdate(:final title?)) {
      final currentSid = state.sessionId;
      if (currentSid != null) {
        ref.read(sessionsProvider.notifier).updateSessionTitle(currentSid, title);
      }
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

    var shouldAutoAllow = perm == AgyToolPermission.alwaysProceed || autoChat;

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
