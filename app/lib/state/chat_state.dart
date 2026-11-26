import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show AppLifecycleState, WidgetsBinding;

import 'agy_config_state.dart';
import 'connection_state.dart';
import 'phone_state.dart';
import 'runtime_state.dart';
import 'sessions_state.dart';
import 'settings_state.dart';
import 'system_state.dart';
import 'turn_telemetry.dart';
import 'workspaces_state.dart';

export 'turn_telemetry.dart';

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
    this.lastActivityAt,
    this.livePhase = TurnLivePhase.waiting,
    this.liveStatusLabel,
    this.turnChars = 0,
    this.thoughtChars = 0,
    this.answerChars = 0,
    this.liveTokensPerSecond,
    this.estimatedTurnTokens = 0,
    this.activeRetry,
    this.retryCount = 0,
    this.turnEvents = const [],
    this.turnLogs = const [],
    this.backgroundRunningIds = const {},
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
  final DateTime? lastActivityAt;
  final TurnLivePhase livePhase;
  final String? liveStatusLabel;
  final int turnChars;
  final int thoughtChars;
  final int answerChars;
  final double? liveTokensPerSecond;
  final int estimatedTurnTokens;
  final TurnRetryInfo? activeRetry;
  final int retryCount;
  final List<TurnActivityLogEntry> turnEvents;
  final List<String> turnLogs;

  /// Session IDs currently generating in the background while the user views
  /// another conversation or workspace.
  final Set<String> backgroundRunningIds;

  final bool isSending;
  final bool isLoadingSession;
  final bool isPreparingModels;
  final bool isUpdatingModel;
  final bool authRequired;
  final String? quotedText;
  final String? error;
  final String? modelError;

  bool get isBusy => isSending || transcript.isStreaming;

  bool get hasAnyRunningSession => isBusy || backgroundRunningIds.isNotEmpty;

  /// All session IDs currently running (foreground + parked background sessions).
  Set<String> get runningSessionIds => {
    if (isBusy && sessionId != null) sessionId!,
    ...backgroundRunningIds,
  };

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
    DateTime? Function()? lastActivityAt,
    TurnLivePhase? livePhase,
    String? Function()? liveStatusLabel,
    int? turnChars,
    int? thoughtChars,
    int? answerChars,
    double? Function()? liveTokensPerSecond,
    int? estimatedTurnTokens,
    TurnRetryInfo? Function()? activeRetry,
    int? retryCount,
    List<TurnActivityLogEntry>? turnEvents,
    List<String>? turnLogs,
    Set<String>? backgroundRunningIds,
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
    lastActivityAt: lastActivityAt == null
        ? this.lastActivityAt
        : lastActivityAt(),
    livePhase: livePhase ?? this.livePhase,
    liveStatusLabel: liveStatusLabel == null
        ? this.liveStatusLabel
        : liveStatusLabel(),
    turnChars: turnChars ?? this.turnChars,
    thoughtChars: thoughtChars ?? this.thoughtChars,
    answerChars: answerChars ?? this.answerChars,
    liveTokensPerSecond: liveTokensPerSecond == null
        ? this.liveTokensPerSecond
        : liveTokensPerSecond(),
    estimatedTurnTokens: estimatedTurnTokens ?? this.estimatedTurnTokens,
    activeRetry: activeRetry == null ? this.activeRetry : activeRetry(),
    retryCount: retryCount ?? this.retryCount,
    turnEvents: turnEvents ?? this.turnEvents,
    turnLogs: turnLogs ?? this.turnLogs,
    backgroundRunningIds: backgroundRunningIds ?? this.backgroundRunningIds,
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

class _ParkedSession {
  _ParkedSession(this.snapshot) : lastTouched = DateTime.now();

  ChatState snapshot;
  DateTime lastTouched;
}

class ChatController extends Notifier<ChatState> {
  static const _maxTurnEvents = 16;
  static const _maxTurnLogs = 16;
  static const _maxParkedSessions = 12;

  StreamSubscription<AcpSessionNotification>? _updateSub;
  StreamSubscription<PendingPermission>? _permSub;
  StreamSubscription<AcpRawNotification>? _otherNotifSub;
  StreamSubscription<String>? _stderrSub;
  HostConnection? _activeConn;

  /// Tracks the session ID currently owned by this controller so self-originated
  /// `sessionsProvider.registerCreatedSession` updates NEVER trigger a reload or
  /// tear down an in-flight first turn.
  String? _ownedSessionId;
  int _loadGeneration = 0;

  /// Per-session state so switching conversations or workspaces NEVER interrupts
  /// an in-flight turn on another session.
  final Map<String, _ParkedSession> _parkedSessions = {};
  final Map<String, int> _turnGenBySession = {};
  final Map<String, TurnSpeedTracker> _speedTrackers = {};
  final Map<String, Completer<void>> _inFlightPromptBySession = {};
  int _pendingSendSeq = 0;
  String? _pendingNewSessionKey;

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

  int _turnGenOf(String key) => _turnGenBySession[key] ?? 0;

  int _bumpTurnGen(String key) {
    final next = _turnGenOf(key) + 1;
    _turnGenBySession[key] = next;
    return next;
  }

  TurnSpeedTracker _speedTrackerOf(String sid) =>
      _speedTrackers.putIfAbsent(sid, TurnSpeedTracker.new);

  static bool _sameStringSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Set<String> _computeBackgroundRunningIds() => {
    for (final entry in _parkedSessions.entries)
      if (entry.value.snapshot.isBusy) entry.key,
  };

  void _syncBackgroundRunningIds() {
    if (!ref.mounted) return;
    final next = _computeBackgroundRunningIds();
    if (!_sameStringSet(state.backgroundRunningIds, next)) {
      state = state.copyWith(backgroundRunningIds: next);
    }
  }

  ChatState? _sessionStateOf(String sid) {
    if (state.sessionId == sid) return state;
    return _parkedSessions[sid]?.snapshot;
  }

  void _updateSessionState(
    String sid,
    ChatState Function(ChatState current) transform,
  ) {
    if (!ref.mounted) return;
    if (state.sessionId == sid) {
      state = transform(state);
      return;
    }
    final parked = _parkedSessions[sid];
    if (parked == null) return;
    final wasBusy = parked.snapshot.isBusy;
    final next = transform(parked.snapshot);
    parked.snapshot = next;
    parked.lastTouched = DateTime.now();
    if (wasBusy != next.isBusy) {
      _syncBackgroundRunningIds();
    }
  }

  void _parkActiveSession() {
    final sid = state.sessionId;
    if (sid == null || sid.isEmpty) return;
    // Never park an unloaded shell unless it has active streaming/messages.
    if (state.isLoadingSession &&
        !state.isBusy &&
        state.transcript.items.isEmpty) {
      return;
    }
    _parkedSessions[sid] = _ParkedSession(
      state.copyWith(
        clearDraftSession: true,
        backgroundRunningIds: const {},
      ),
    );
    _evictIdleParkedSessions();
  }

  void _evictIdleParkedSessions() {
    if (_parkedSessions.length <= _maxParkedSessions) return;
    final idleKeys = _parkedSessions.entries
        .where((e) => !e.value.snapshot.isBusy)
        .toList()
      ..sort((a, b) => a.value.lastTouched.compareTo(b.value.lastTouched));
    for (final entry in idleKeys) {
      if (_parkedSessions.length <= _maxParkedSessions) break;
      for (final p in entry.value.snapshot.pendingPermissions) {
        p.cancel();
      }
      _parkedSessions.remove(entry.key);
      _speedTrackers.remove(entry.key);
    }
  }

  void _clearAllParkedSessions() {
    for (final entry in _parkedSessions.values) {
      for (final p in entry.snapshot.pendingPermissions) {
        p.cancel();
      }
    }
    _parkedSessions.clear();
    _turnGenBySession.clear();
    _speedTrackers.clear();
    _inFlightPromptBySession.clear();
    _pendingNewSessionKey = null;
  }

  void _onDeletedSessionsChanged(List<String>? previous, List<String> next) {
    if (_parkedSessions.isEmpty) return;
    final conn = _activeConn;
    var changed = false;
    for (final sid in next) {
      final parked = _parkedSessions.remove(sid);
      if (parked == null) continue;
      changed = true;
      _bumpTurnGen(sid);
      _speedTrackers.remove(sid);
      _inFlightPromptBySession.remove(sid);
      for (final p in parked.snapshot.pendingPermissions) {
        p.cancel();
      }
      if (parked.snapshot.isBusy && conn != null) {
        unawaited(conn.client.cancel(sid).catchError((_) {}));
      }
    }
    if (changed) {
      _syncBackgroundRunningIds();
    }
  }

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
    _otherNotifSub?.cancel();
    _stderrSub?.cancel();
    _updateSub = null;
    _permSub = null;
    _otherNotifSub = null;
    _stderrSub = null;
    _activeConn = conn;
    _ownedSessionId = null;
    _clearAllParkedSessions();
    _draftFuture = null;
    _draftFutureCwd = null;
    _cachedModes = null;
    _cachedConfigOptions = const [];
    _loadGeneration++;

    ref.onDispose(() {
      unawaited(_updateSub?.cancel());
      unawaited(_permSub?.cancel());
      unawaited(_otherNotifSub?.cancel());
      unawaited(_stderrSub?.cancel());
    });

    ref.listen<String?>(
      sessionsProvider.select((s) => s.currentSessionId),
      _onSelectedSessionChanged,
    );

    ref.listen<List<String>>(
      sessionsProvider.select((s) => s.deletedIds),
      _onDeletedSessionsChanged,
    );

    ref.listen<String>(
      effectiveWorkingDirProvider,
      _onWorkingDirChanged,
    );

    ref.listen<WorkspaceItem?>(
      selectedWorkspaceProvider,
      _onWorkspaceSelectionChanged,
    );

    ref.listen<(bool, String?, String?)>(
      phoneControlProvider.select((p) => (p.enabled, p.mcpUrl, p.mcpToken)),
      (prev, next) {
        if (prev == next) return;
        final c = _activeConn;
        if (c == null || !c.isLocal) return;
        if (state.sessionId == null && !state.isSending) {
          _discardDraftSession(c);
          unawaited(prepareDraftSession(forceRefresh: true));
        }
      },
    );

    ref.listen<(int, String?)>(
      localRuntimeProvider.select((s) => (s.logSeq, s.lastLogLine)),
      (prev, next) {
        if (!state.hasAnyRunningSession) return;
        if (_activeConn?.isLocal != true) return;
        final line = next.$2;
        if (line == null || line.isEmpty) return;
        if (prev != null && prev.$1 == next.$1) return;
        _onProcessLogLine(line);
      },
    );

    if (conn == null) return const ChatState();

    _updateSub = conn.client.updates.listen(_onUpdate);
    _permSub = conn.client.permissionRequests.listen(_onPermissionRequest);
    _otherNotifSub = conn.client.otherNotifications.listen(_onOtherNotification);
    _stderrSub = conn.client.stderrLines.listen((line) {
      if (!state.hasAnyRunningSession) return;
      _onProcessLogLine(line);
    });

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

    // Park the currently visible conversation so any running turn continues
    // uninterrupted in the background instead of being torn down.
    _parkActiveSession();
    _pendingNewSessionKey = null;

    if (next == null || next.isEmpty) {
      _ownedSessionId = null;
      _loadGeneration++;
      state = ChatState(
        transcript: ChatTranscript(
          modes: _cachedModes,
          configOptions: _cachedConfigOptions,
        ),
        isPreparingModels: _cachedConfigOptions.isEmpty,
        backgroundRunningIds: _computeBackgroundRunningIds(),
      );
      unawaited(prepareDraftSession());
      return;
    }

    // If this session is already parked in memory (e.g. still streaming in the
    // background or recently viewed), restore it instantaneously without calling
    // `session/load`, preserving live streaming chunks, speed metrics, and state.
    final parked = _parkedSessions.remove(next);
    if (parked != null) {
      _discardDraftSession(conn);
      _ownedSessionId = next;
      _loadGeneration++;
      final liveTps = parked.snapshot.isSending
          ? _speedTrackers[next]?.liveTokensPerSecond(DateTime.now())
          : null;
      state = parked.snapshot.copyWith(
        liveTokensPerSecond: () => liveTps,
        backgroundRunningIds: _computeBackgroundRunningIds(),
      );
      return;
    }

    // User selected a different history session from drawer or search.
    _discardDraftSession(conn);
    _ownedSessionId = next;
    final gen = ++_loadGeneration;
    final sessionInfo = ref.read(sessionsProvider).currentSession;
    final rawCwd = sessionInfo?.cwd.trim() ?? '';
    final String cwd = rawCwd.isNotEmpty
        ? rawCwd
        : ref.read(effectiveWorkingDirProvider);
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
      backgroundRunningIds: _computeBackgroundRunningIds(),
      isLoadingSession: true,
    );
    unawaited(_loadExistingSession(conn, next, cwd, gen));
  }

  void _onWorkingDirChanged(String? previous, String next) {
    final conn = _activeConn;
    if (conn == null) return;
    if (previous == next) return;

    // Only rotate the silent draft session when on the fresh idle home screen.
    if (state.sessionId == null &&
        !state.isSending &&
        state.draftSessionCwd != next) {
      _discardDraftSession(conn);
      unawaited(prepareDraftSession(forceRefresh: true));
    }
  }

  void _onWorkspaceSelectionChanged(WorkspaceItem? previous, WorkspaceItem? next) {
    if (next == null || previous?.path == next.path) return;
    // Switching workspace while a turn is running parks that turn in the
    // background and opens a fresh conversation in the newly selected workspace.
    if (state.sessionId == null && state.isSending) {
      startNewChat();
      return;
    }
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
    _parkActiveSession();
    _pendingNewSessionKey = null;
    _ownedSessionId = null;
    _loadGeneration++;
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
      backgroundRunningIds: _computeBackgroundRunningIds(),
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
    final desiredAgentMode = effectiveAgentMode();
    final bodyWithPlan =
        desiredAgentMode == AgyAgentMode.plan &&
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

    final turnNow = DateTime.now();
    final existingSid = state.sessionId;
    final isFirstTurn = existingSid == null || existingSid.isEmpty;
    final String cwd =
        state.sessionCwd ?? ref.read(effectiveWorkingDirProvider);
    final capturedAgentMode = state.sessionAgentMode;
    final capturedToolPerm = state.sessionToolPermission;
    final capturedAdditionalDirs = List<String>.from(state.additionalDirectories);
    final capturedAllowAll = state.allowAllForSession;

    final pendingKey = isFirstTurn ? '__pending_${++_pendingSendSeq}' : null;
    final pendingGen = pendingKey != null ? _bumpTurnGen(pendingKey) : 0;
    if (pendingKey != null) {
      _pendingNewSessionKey = pendingKey;
    }
    var sid = existingSid;
    var myGen = !isFirstTurn ? _bumpTurnGen(existingSid) : 0;

    final initialEvents = <TurnActivityLogEntry>[
      TurnActivityLogEntry(timestamp: turnNow, label: '已发送请求，等待模型响应'),
    ];

    state = state.copyWith(
      isSending: true,
      turnStartedAt: () => turnNow,
      lastActivityAt: () => turnNow,
      livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
      turnChars: 0,
      thoughtChars: 0,
      answerChars: 0,
      liveTokensPerSecond: () => null,
      estimatedTurnTokens: 0,
      activeRetry: () => null,
      retryCount: 0,
      turnEvents: initialEvents,
      turnLogs: const [],
      attachments: const [],
      clearError: true,
      clearQuotedText: true,
      authRequired: false,
    );

    final displayPrompt = [
      if (stagedAttachments.isNotEmpty)
        stagedAttachments
            .map((a) => a.isImage ? '[图片: ${a.name}]' : '[附件: ${a.name}]')
            .join(' '),
      if (text.isNotEmpty) text,
    ].join('\n');

    final blocks = <AcpContentBlock>[
      for (final a in stagedAttachments) a.toAcpBlock(),
      if (text.isNotEmpty) AcpTextBlock(text),
    ];

    try {
      if (isFirstTurn) {
        // If a background draft pre-warm is currently running for this exact cwd,
        // wait for it rather than racing a second `session/new`.
        if (_draftFuture != null && _draftFutureCwd == cwd) {
          await _draftFuture;
          if (!ref.mounted ||
              _activeConn != conn ||
              _turnGenOf(pendingKey!) != pendingGen) {
            return;
          }
        }

        final currentMcpServers = _sessionMcpServers(conn);
        final stillOwningForegroundBeforeCreate =
            _ownedSessionId == null && _pendingNewSessionKey == pendingKey;
        final canReuseDraft =
            stillOwningForegroundBeforeCreate &&
            state.draftSessionId != null &&
            state.draftSessionId!.isNotEmpty &&
            state.draftSessionCwd == cwd &&
            _draftMcpSignature == _mcpSignature(currentMcpServers) &&
            _sameStringList(state.draftAdditionalDirs, capturedAdditionalDirs);

        AcpSessionModeState? modes = stillOwningForegroundBeforeCreate
            ? state.transcript.modes
            : _cachedModes;
        List<AcpConfigOption> configs = stillOwningForegroundBeforeCreate
            ? state.transcript.configOptions
            : _cachedConfigOptions;

        if (canReuseDraft) {
          sid = state.draftSessionId!;
        } else {
          if (stillOwningForegroundBeforeCreate) {
            _discardDraftSession(conn);
          }
          final handle = await conn.client.newSession(
            cwd: cwd,
            mcpServers: currentMcpServers,
            additionalDirectories: capturedAdditionalDirs,
          );
          if (!ref.mounted ||
              _activeConn != conn ||
              _turnGenOf(pendingKey!) != pendingGen) {
            return;
          }
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
          if (!ref.mounted ||
              _activeConn != conn ||
              _turnGenOf(pendingKey) != pendingGen) {
            return;
          }
          if (applied.isNotEmpty) {
            configs = applied;
            _cachedConfigOptions = applied;
          }
        }

        myGen = _bumpTurnGen(sid);
        _speedTrackerOf(sid).reset();
        if (capturedAgentMode != null) {
          _sessionModes[sid] = capturedAgentMode;
        }
        if (capturedToolPerm != null) {
          _sessionPermissions[sid] = capturedToolPerm;
        }
        if (capturedAllowAll) {
          _allowAllSessions.add(sid);
        }

        final stillForeground =
            _ownedSessionId == null && _pendingNewSessionKey == pendingKey;

        final titleSeed = cleanBody.isNotEmpty
            ? cleanBody
            : stagedAttachments.map((a) => a.name).join(', ');
        final createdInfo = AcpSessionInfo(
          sessionId: sid,
          cwd: cwd,
          title: titleSeed.length > 36
              ? '${titleSeed.substring(0, 36)}…'
              : titleSeed,
          updatedAt: DateTime.now(),
        );

        if (stillForeground) {
          _pendingNewSessionKey = null;
          // Own & commit this session BEFORE calling registerCreatedSession so
          // `sessionsProvider.currentSessionId` changing NEVER triggers a reload!
          _ownedSessionId = sid;
          state = state.copyWith(
            sessionId: sid,
            sessionCwd: cwd,
            clearDraftSession: true,
            transcript: state.transcript
                .copyWith(modes: modes, configOptions: configs)
                .appendUserPrompt(displayPrompt),
          );
          ref
              .read(sessionsProvider.notifier)
              .registerCreatedSession(createdInfo, select: true);
        } else {
          // User switched conversations or workspaces while `session/new` was
          // awaiting — park this new session and continue executing in background.
          _parkedSessions[sid] = _ParkedSession(
            ChatState(
              sessionId: sid,
              sessionCwd: cwd,
              additionalDirectories: capturedAdditionalDirs,
              transcript: ChatTranscript(
                modes: modes,
                configOptions: configs,
              ).appendUserPrompt(displayPrompt),
              sessionAgentMode: capturedAgentMode,
              sessionToolPermission: capturedToolPerm,
              allowAllForSession: capturedAllowAll,
              turnStartedAt: turnNow,
              lastActivityAt: turnNow,
              livePhase: TurnLivePhase.waiting,
              turnEvents: initialEvents,
              isSending: true,
            ),
          );
          _syncBackgroundRunningIds();
          ref
              .read(sessionsProvider.notifier)
              .registerCreatedSession(createdInfo, select: false);
        }

        // Apply non-standard execution mode on the ACP session if matched.
        if (modes != null && desiredAgentMode != AgyAgentMode.standard) {
          final match = modes.availableModes
              .where(
                (m) => desiredAgentMode.acpModeAliases.contains(
                  m.id.toLowerCase(),
                ),
              )
              .firstOrNull;
          if (match != null && match.id != modes.currentModeId) {
            try {
              await conn.client.setMode(sid, match.id);
              if (ref.mounted && _activeConn == conn) {
                _updateSessionState(
                  sid,
                  (cur) => cur.copyWith(
                    transcript: cur.transcript.applyUpdate(
                      CurrentModeUpdate(match.id),
                    ),
                  ),
                );
              }
            } catch (_) {}
          }
        }
      } else {
        if (!ref.mounted ||
            _activeConn != conn ||
            _turnGenOf(sid!) != myGen) {
          return;
        }
        _speedTrackerOf(sid).reset();
        _updateSessionState(
          sid,
          (cur) => cur.copyWith(
            transcript: cur.transcript.appendUserPrompt(displayPrompt),
          ),
        );
      }

      await _executePromptOnSession(
        conn: conn,
        sid: sid,
        blocks: blocks,
        myGen: myGen,
      );
    } on AcpRpcException catch (e) {
      if (!ref.mounted || _activeConn != conn) return;
      if (isFirstTurn && pendingKey != null) {
        if (_turnGenOf(pendingKey) != pendingGen) return;
        if (_pendingNewSessionKey == pendingKey && state.sessionId == null) {
          _pendingNewSessionKey = null;
          state = state.copyWith(
            transcript: state.transcript.finishTurn(AcpStopReason.unknown),
            isSending: false,
            turnStartedAt: () => null,
            lastActivityAt: () => null,
            livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
            liveTokensPerSecond: () => null,
            activeRetry: () => null,
            authRequired: e.isAuthRequired,
            error: e.isAuthRequired
                ? 'Antigravity CLI 尚未登录或未配置 Gemini API Key，请前往「本机引擎 / 设置」完成认证。'
                : e.message,
          );
        }
      }
    } catch (e) {
      if (!ref.mounted || _activeConn != conn) return;
      if (isFirstTurn && pendingKey != null) {
        if (_turnGenOf(pendingKey) != pendingGen) return;
        if (_pendingNewSessionKey == pendingKey && state.sessionId == null) {
          _pendingNewSessionKey = null;
          state = state.copyWith(
            transcript: state.transcript.finishTurn(AcpStopReason.unknown),
            isSending: false,
            turnStartedAt: () => null,
            lastActivityAt: () => null,
            livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
            liveTokensPerSecond: () => null,
            activeRetry: () => null,
            error: e.toString(),
          );
        }
      }
    }
  }

  /// Executes `session/prompt` on [sid] and finalizes state whether [sid] is
  /// still in the foreground or was parked into the background mid-turn.
  Future<void> _executePromptOnSession({
    required HostConnection conn,
    required String sid,
    required List<AcpContentBlock> blocks,
    required int myGen,
  }) async {
    try {
      final result = await _sendPromptWithCancelSettle(conn, sid, blocks, myGen);
      if (result == null ||
          !ref.mounted ||
          _activeConn != conn ||
          _turnGenOf(sid) != myGen) {
        return;
      }

      final metrics = _speedTrackers[sid]?.finalize(usage: result.usage);
      _speedTrackers.remove(sid);

      _updateSessionState(
        sid,
        (cur) => cur.copyWith(
          transcript: cur.transcript.finishTurn(
            result.stopReason,
            usage: result.usage,
            metrics: metrics,
          ),
          isSending: false,
          turnStartedAt: () => null,
          lastActivityAt: () => null,
          livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
          liveTokensPerSecond: () => null,
          activeRetry: () => null,
        ),
      );

      if (_isAppBackgrounded &&
          ref.read(settingsProvider).notifyOnTurnComplete) {
        final snap = _sessionStateOf(sid);
        final sessionInfo = ref
            .read(sessionsProvider)
            .sessions
            .where((s) => s.sessionId == sid)
            .firstOrNull;
        final sessionTitle =
            snap?.transcript.title ?? sessionInfo?.title ?? 'AGY Go';
        unawaited(
          ref.read(systemToolsProvider.notifier).notifyTurnEvent(
            title: '回复已完成 · $sessionTitle',
            body: '点击返回查看最新输出与变更',
            urgent: false,
          ),
        );
      }

      final after = _sessionStateOf(sid);
      if (after != null && after.queuedMessages.isNotEmpty) {
        final nextMsg = after.queuedMessages.first;
        _updateSessionState(
          sid,
          (cur) => cur.copyWith(queuedMessages: cur.queuedMessages.sublist(1)),
        );
        if (state.sessionId == sid) {
          unawaited(send(nextMsg));
        } else {
          final nextGen = _bumpTurnGen(sid);
          final nextNow = DateTime.now();
          _speedTrackerOf(sid).reset();
          _updateSessionState(
            sid,
            (cur) => cur.copyWith(
              isSending: true,
              turnStartedAt: () => nextNow,
              lastActivityAt: () => nextNow,
              livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
              turnChars: 0,
              thoughtChars: 0,
              answerChars: 0,
              liveTokensPerSecond: () => null,
              estimatedTurnTokens: 0,
              activeRetry: () => null,
              retryCount: 0,
              turnEvents: [
                TurnActivityLogEntry(timestamp: nextNow, label: '已发送排队请求，等待模型响应'),
              ],
              turnLogs: const [],
              clearError: true,
              transcript: cur.transcript.appendUserPrompt(nextMsg),
            ),
          );
          unawaited(
            _executePromptOnSession(
              conn: conn,
              sid: sid,
              blocks: [AcpTextBlock(nextMsg)],
              myGen: nextGen,
            ),
          );
        }
      }
    } on AcpRpcException catch (e) {
      if (!ref.mounted || _activeConn != conn || _turnGenOf(sid) != myGen) {
        return;
      }
      _speedTrackers.remove(sid);
      _updateSessionState(
        sid,
        (cur) => cur.copyWith(
          transcript: cur.transcript.finishTurn(AcpStopReason.unknown),
          isSending: false,
          turnStartedAt: () => null,
          lastActivityAt: () => null,
          livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
          liveTokensPerSecond: () => null,
          activeRetry: () => null,
          authRequired: e.isAuthRequired,
          error: e.isAuthRequired
              ? 'Antigravity CLI 尚未登录或未配置 Gemini API Key，请前往「本机引擎 / 设置」完成认证。'
              : e.message,
        ),
      );
    } catch (e) {
      if (!ref.mounted || _activeConn != conn || _turnGenOf(sid) != myGen) {
        return;
      }
      _speedTrackers.remove(sid);
      _updateSessionState(
        sid,
        (cur) => cur.copyWith(
          transcript: cur.transcript.finishTurn(AcpStopReason.unknown),
          isSending: false,
          turnStartedAt: () => null,
          lastActivityAt: () => null,
          livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
          liveTokensPerSecond: () => null,
          activeRetry: () => null,
          error: e.toString(),
        ),
      );
    }
  }

  static bool _isPromptCancellingError(AcpRpcException e) {
    final lower = e.message.toLowerCase();
    return lower.contains('being cancelled') ||
        lower.contains('being canceled') ||
        lower.contains('wait for it to finish');
  }

  /// Sends `session/prompt` and handles `agy acp`'s session-cancellation window:
  /// when a previous turn on [sid] was just cancelled (e.g. via 「立即发送」 or Stop -> quick resend),
  /// waits for the previous prompt RPC to settle and retries ONLY on `agy acp`'s
  /// explicit `the running prompt is being cancelled` rejection.
  Future<AcpPromptResult?> _sendPromptWithCancelSettle(
    HostConnection conn,
    String sid,
    List<AcpContentBlock> blocks,
    int myGen,
  ) async {
    final existingDone = _inFlightPromptBySession[sid];
    final Completer<void>? priorDone =
        (existingDone != null && !existingDone.isCompleted)
        ? existingDone
        : null;

    if (priorDone != null) {
      await priorDone.future.timeout(
        const Duration(milliseconds: 400),
        onTimeout: () {},
      );
      if (!ref.mounted || _activeConn != conn || _turnGenOf(sid) != myGen) {
        return null;
      }
    }

    const cancelWaitMs = <int>[250, 500, 800, 1200, 1500, 2000, 2500, 3000];
    var loggedCancelWait = false;

    for (var attempt = 0; attempt <= cancelWaitMs.length; attempt++) {
      if (!ref.mounted || _activeConn != conn || _turnGenOf(sid) != myGen) {
        return null;
      }

      final myDone = Completer<void>();
      _inFlightPromptBySession[sid] = myDone;

      try {
        final res = await conn.client.prompt(sid, blocks);
        if (!myDone.isCompleted) myDone.complete();
        if (identical(_inFlightPromptBySession[sid], myDone)) {
          _inFlightPromptBySession.remove(sid);
        }
        return res;
      } on AcpRpcException catch (e) {
        if (!myDone.isCompleted) myDone.complete();
        if (_isPromptCancellingError(e) && attempt < cancelWaitMs.length) {
          // Restore priorDone so subsequent loops still wake up the instant it settles.
          if (priorDone != null && !priorDone.isCompleted) {
            _inFlightPromptBySession[sid] = priorDone;
          } else if (identical(_inFlightPromptBySession[sid], myDone)) {
            _inFlightPromptBySession.remove(sid);
          }

          if (!ref.mounted || _activeConn != conn || _turnGenOf(sid) != myGen) {
            return null;
          }
          if (!loggedCancelWait) {
            loggedCancelWait = true;
            _updateSessionState(
              sid,
              (cur) => cur.copyWith(
                lastActivityAt: () => DateTime.now(),
                turnEvents: _appendTurnEvent(
                  cur.turnEvents,
                  TurnActivityLogEntry(
                    timestamp: DateTime.now(),
                    label: '正在等待上一轮中止完成，随后自动发送…',
                  ),
                ),
              ),
            );
          }

          final delay = Duration(milliseconds: cancelWaitMs[attempt]);
          if (priorDone != null && !priorDone.isCompleted) {
            await Future.any<void>([
              priorDone.future,
              Future<void>.delayed(delay),
            ]);
            if (priorDone.isCompleted) {
              // Brief yield so agy acp releases its per-session cancel guard.
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          } else {
            await Future<void>.delayed(delay);
          }
          continue;
        }

        if (identical(_inFlightPromptBySession[sid], myDone)) {
          _inFlightPromptBySession.remove(sid);
        }
        if (_isPromptCancellingError(e)) {
          throw AcpRpcException(
            code: e.code,
            message: '上一轮任务仍在中止中（引擎暂未释放当前会话），请稍候几秒再试，或在「本机引擎」重启引擎。',
            data: e.data,
            method: e.method,
          );
        }
        rethrow;
      } catch (_) {
        if (!myDone.isCompleted) myDone.complete();
        if (identical(_inFlightPromptBySession[sid], myDone)) {
          _inFlightPromptBySession.remove(sid);
        }
        rethrow;
      }
    }
    return null;
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
  Future<void> regenerateLast({bool forceImmediate = false}) async {
    final lastUser = state.transcript.items
        .whereType<UserTranscriptItem>()
        .lastOrNull;
    if (lastUser == null) return;
    await send(lastUser.text, forceImmediate: forceImmediate);
  }

  /// Forks into a brand-new conversation seeded with a quote/context summary.
  Future<void> forkFromText(String seedText) async {
    startNewChat();
    setQuote(seedText);
  }

  /// Immediately unlocks the UI for the CURRENTLY VISIBLE session, finishes its
  /// streaming cursor/pending tool calls, and flushes ACP `session/cancel`,
  /// while leaving any parked background conversations completely untouched.
  Future<void> cancel() async {
    final sid = state.sessionId;
    if (sid != null && sid.isNotEmpty) {
      _bumpTurnGen(sid);
      _speedTrackers.remove(sid);
    } else if (_pendingNewSessionKey != null) {
      _bumpTurnGen(_pendingNewSessionKey!);
      _pendingNewSessionKey = null;
    }
    for (final p in state.pendingPermissions) {
      p.cancel();
    }
    state = state.copyWith(
      transcript: state.transcript.finishTurn(AcpStopReason.cancelled),
      pendingPermissions: const [],
      isSending: false,
      turnStartedAt: () => null,
      lastActivityAt: () => null,
      livePhase: TurnLivePhase.waiting,
      liveStatusLabel: () => null,
      liveTokensPerSecond: () => null,
      activeRetry: () => null,
    );
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    if (conn == null || sid == null) return;
    await conn.client
        .cancel(sid)
        .timeout(const Duration(seconds: 2), onTimeout: () {})
        .catchError((_) {});
  }

  Future<bool> logoutAgent() async {
    final conn = _activeConn ?? ref.read(activeConnectionProvider).value;
    if (conn == null) return false;
    try {
      await conn.client.logout();
      _cachedModes = null;
      _cachedConfigOptions = const [];
      _clearAllParkedSessions();
      state = state.copyWith(clearSessionId: true, isSending: false);
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
    final notifSid = notification.sessionId;

    // For a silent pre-warmed draft session, only ingest metadata updates
    // (configOptions / modes / availableCommands) — never stray message chunks.
    if (state.sessionId == null && state.draftSessionId == notifSid) {
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

    final current = _sessionStateOf(notifSid);
    if (current == null) return;

    // Ignore stray late content/tool chunks when idle (e.g. arriving right after
    // the user tapped Stop or after a network failure), while still ingesting
    // metadata/plan updates and late patches to already-known background tools.
    final update = notification.update;
    if (!current.isSending && !current.isLoadingSession) {
      final isMetadata =
          update is ConfigOptionUpdate ||
          update is CurrentModeUpdate ||
          update is AvailableCommandsUpdate ||
          update is SessionInfoUpdate ||
          update is UsageSessionUpdate ||
          update is PlanUpdate;
      final isKnownToolPatch =
          update is ToolCallPatchedUpdate &&
          current.transcript.items.any(
            (item) =>
                item is AssistantTranscriptItem &&
                item.toolCallById(update.toolCallId) != null,
          );
      if (!isMetadata && !isKnownToolPatch) return;
    }

    final now = DateTime.now();
    var addedAnswerChars = 0;
    var addedThoughtChars = 0;
    String? streamedText;
    var nextPhase = current.livePhase;
    var nextStatusLabel = current.liveStatusLabel;
    var statusChanged = false;
    var recoveredFromRetry = false;
    TurnRetryInfo? retryUpdate;

    switch (update) {
      case AgentMessageChunkUpdate(:final content):
        if (content case AcpTextBlock(:final text)) {
          addedAnswerChars = text.length;
          streamedText = text;
        }
        nextPhase = TurnLivePhase.responding;
        nextStatusLabel = null;
        statusChanged = true;
        recoveredFromRetry = current.activeRetry != null;
      case AgentThoughtChunkUpdate(:final content):
        if (content case AcpTextBlock(:final text)) {
          addedThoughtChars = text.length;
          streamedText = text;
        }
        nextPhase = TurnLivePhase.thinking;
        nextStatusLabel = null;
        statusChanged = true;
        recoveredFromRetry = current.activeRetry != null;
      case ToolCallCreatedUpdate():
      case ToolCallPatchedUpdate():
        recoveredFromRetry = current.activeRetry != null;
      case PlanUpdate():
        // Active plan step is stored directly on `transcript.plan` and rendered
        // natively without duplicating or leaving stale `liveStatusLabel` state.
        recoveredFromRetry = current.activeRetry != null;
      case AgentStatusUpdate():
        retryUpdate = parseRetryFromStatusUpdate(update, now: now);
        if (retryUpdate == null) {
          final statusEvent = extractNativeStatusUpdate(
            kindOrMethod: update.kind,
            payload: update.raw,
          );
          if (statusEvent != null) {
            if (statusEvent.clear) {
              nextStatusLabel = null;
              if (nextPhase == TurnLivePhase.working) {
                nextPhase = TurnLivePhase.waiting;
              }
            } else {
              nextPhase = TurnLivePhase.working;
              nextStatusLabel = statusEvent.text;
            }
            statusChanged = true;
          }
          recoveredFromRetry = current.activeRetry != null;
        }
      case ConfigOptionUpdate(:final configOptions):
        _cachedConfigOptions = configOptions;
      case UnknownSessionUpdate():
        retryUpdate = parseRetryFromUnknownUpdate(update, now: now);
        if (retryUpdate == null) {
          final statusEvent = extractNativeStatusUpdate(
            kindOrMethod: update.kind,
            payload: update.raw,
          );
          if (statusEvent != null) {
            if (statusEvent.clear) {
              nextStatusLabel = null;
              if (nextPhase == TurnLivePhase.working) {
                nextPhase = TurnLivePhase.waiting;
              }
            } else {
              nextPhase = TurnLivePhase.working;
              nextStatusLabel = statusEvent.text;
            }
            statusChanged = true;
          }
        }
      default:
        break;
    }

    final nextTranscript = current.transcript.applyUpdate(update);
    if (update case SessionInfoUpdate(:final title?)) {
      ref.read(sessionsProvider.notifier).updateSessionTitle(notifSid, title);
    }

    var nextLiveTps = current.liveTokensPerSecond;
    var nextEstTokens = current.estimatedTurnTokens;
    if (current.isSending && streamedText != null && streamedText.isNotEmpty) {
      final tracker = _speedTrackerOf(notifSid);
      tracker.recordChunk(streamedText, now);
      nextLiveTps = tracker.liveTokensPerSecond(now);
      nextEstTokens = tracker.totalEstimatedTokens.round();
    }

    if (update is ToolCallCreatedUpdate || update is ToolCallPatchedUpdate) {
      final last = nextTranscript.items.isNotEmpty
          ? nextTranscript.items.last
          : null;
      final activeTools = last is AssistantTranscriptItem
          ? last.toolCalls.where((t) => t.status.isActive).toList()
          : const <AcpToolCall>[];
      if (activeTools.isNotEmpty) {
        nextPhase = TurnLivePhase.working;
        nextStatusLabel = null;
        statusChanged = true;
        nextLiveTps = null;
      } else if (current.isSending) {
        // Tool batch finished: wait honestly for the next native ACP event
        // (thought, tool call, plan update, or message) without fabricating a phase.
        nextPhase = TurnLivePhase.waiting;
        nextStatusLabel = null;
        statusChanged = true;
        nextLiveTps = null;
      }
    }

    var nextEvents = current.turnEvents;
    if (current.isSending && recoveredFromRetry) {
      nextEvents = _appendTurnEvent(
        nextEvents,
        TurnActivityLogEntry(timestamp: now, label: '网络已恢复，继续输出'),
      );
    } else if (current.isSending &&
        current.thoughtChars == 0 &&
        addedThoughtChars > 0) {
      nextEvents = _appendTurnEvent(
        nextEvents,
        TurnActivityLogEntry(timestamp: now, label: '开始接收模型思考'),
      );
    } else if (current.isSending &&
        current.answerChars == 0 &&
        addedAnswerChars > 0) {
      nextEvents = _appendTurnEvent(
        nextEvents,
        TurnActivityLogEntry(timestamp: now, label: '开始生成正文回复'),
      );
    }

    final addedChars = addedAnswerChars + addedThoughtChars;
    _updateSessionState(
      notifSid,
      (cur) => cur.copyWith(
        transcript: nextTranscript,
        turnChars: cur.turnChars + addedChars,
        thoughtChars: cur.thoughtChars + addedThoughtChars,
        answerChars: cur.answerChars + addedAnswerChars,
        liveTokensPerSecond: cur.isSending ? () => nextLiveTps : null,
        estimatedTurnTokens: cur.isSending ? nextEstTokens : null,
        lastActivityAt: cur.isSending ? () => now : null,
        livePhase: cur.isSending ? nextPhase : null,
        liveStatusLabel: (cur.isSending && statusChanged)
            ? () => nextStatusLabel
            : null,
        activeRetry: recoveredFromRetry ? () => null : null,
        turnEvents: nextEvents,
      ),
    );

    if (current.isSending && retryUpdate != null) {
      _recordLiveRetry(retryUpdate, sessionId: notifSid);
    }
  }

  /// Resolves which running session should receive a session-less notification
  /// or process log line. Returns `null` when targeting the foreground pending
  /// (pre-sessionId) turn or when ambiguous across multiple background sessions.
  String? _resolveRunningTargetSessionId({String? explicitSessionId}) {
    if (explicitSessionId != null &&
        _sessionStateOf(explicitSessionId)?.isSending == true) {
      return explicitSessionId;
    }
    if (state.isSending && state.sessionId != null) {
      return state.sessionId;
    }
    if (!state.isSending && state.backgroundRunningIds.length == 1) {
      return state.backgroundRunningIds.first;
    }
    return null;
  }

  void _onOtherNotification(AcpRawNotification notif) {
    if (!ref.mounted || !state.hasAnyRunningSession) return;
    final explicitSid = notif.params['sessionId'] as String?;
    final targetSid = _resolveRunningTargetSessionId(
      explicitSessionId: explicitSid,
    );
    final foregroundPending =
        targetSid == null && state.isSending && state.sessionId == null;
    if (targetSid == null && !foregroundPending) return;

    final now = DateTime.now();
    final retry = parseRetryFromRawNotification(notif, now: now);
    if (retry != null) {
      _recordLiveRetry(retry, sessionId: targetSid);
      return;
    }
    final statusEvent = extractNativeStatusUpdate(
      kindOrMethod: notif.method,
      payload: notif.params,
    );
    final methodLower = notif.method.toLowerCase();
    if (statusEvent != null ||
        methodLower.contains('progress') ||
        methodLower.contains('status')) {
      ChatState applyStatus(ChatState cur) {
        if (statusEvent == null) {
          return cur.copyWith(lastActivityAt: () => now);
        }
        if (statusEvent.clear) {
          return cur.copyWith(
            lastActivityAt: () => now,
            livePhase: cur.livePhase == TurnLivePhase.working
                ? TurnLivePhase.waiting
                : cur.livePhase,
            liveStatusLabel: () => null,
          );
        }
        return cur.copyWith(
          lastActivityAt: () => now,
          livePhase: TurnLivePhase.working,
          liveStatusLabel: () => statusEvent.text,
        );
      }

      if (targetSid != null) {
        _updateSessionState(targetSid, applyStatus);
      } else if (foregroundPending) {
        state = applyStatus(state);
      }
    }
  }

  void _onProcessLogLine(String rawLine) {
    if (!ref.mounted || !state.hasAnyRunningSession) return;
    final cleaned = cleanEngineLogLine(rawLine);
    if (cleaned.isEmpty) return;

    final targetSid = _resolveRunningTargetSessionId();
    final foregroundPending =
        targetSid == null && state.isSending && state.sessionId == null;
    if (targetSid == null && !foregroundPending) return;

    final lower = cleaned.toLowerCase();
    final isNoise =
        lower.startsWith('[bridge]') || lower.startsWith('[installer]');
    if (!isNoise) {
      if (targetSid != null) {
        _updateSessionState(targetSid, (cur) {
          final nextLogs = [...cur.turnLogs, cleaned];
          if (nextLogs.length > _maxTurnLogs) {
            nextLogs.removeRange(0, nextLogs.length - _maxTurnLogs);
          }
          return cur.copyWith(turnLogs: nextLogs);
        });
      } else if (foregroundPending) {
        final nextLogs = [...state.turnLogs, cleaned];
        if (nextLogs.length > _maxTurnLogs) {
          nextLogs.removeRange(0, nextLogs.length - _maxTurnLogs);
        }
        state = state.copyWith(turnLogs: nextLogs);
      }
    }

    final retry = parseRetryFromLogLine(rawLine);
    if (retry != null) {
      _recordLiveRetry(retry, sessionId: targetSid);
      return;
    }

    final traj = parseTrajectoryStateFromLogLine(rawLine);
    if (traj != null) {
      final now = DateTime.now();
      ChatState applyTraj(ChatState cur) {
        if (traj.clear) {
          if (cur.liveStatusLabel != '等待后台任务') return cur;
          return cur.copyWith(
            lastActivityAt: () => now,
            liveStatusLabel: () => null,
            livePhase: cur.livePhase == TurnLivePhase.working
                ? TurnLivePhase.waiting
                : cur.livePhase,
          );
        }
        return cur.copyWith(
          lastActivityAt: () => now,
          livePhase: TurnLivePhase.working,
          liveStatusLabel: () => traj.statusText,
        );
      }

      if (targetSid != null) {
        _updateSessionState(targetSid, applyTraj);
      } else if (foregroundPending) {
        state = applyTraj(state);
      }
    }
  }

  void _recordLiveRetry(TurnRetryInfo retry, {String? sessionId}) {
    if (!ref.mounted) return;
    if (sessionId != null) {
      final target = _sessionStateOf(sessionId);
      if (target == null || !target.isSending) return;
      _updateSessionState(sessionId, (cur) {
        final nextEvents = _appendTurnEvent(
          cur.turnEvents,
          TurnActivityLogEntry(
            timestamp: retry.timestamp,
            label: retry.summary,
            detail: retry.rawMessage,
            isWarning: true,
          ),
        );
        return cur.copyWith(
          livePhase: TurnLivePhase.retrying,
          activeRetry: () => retry,
          retryCount: cur.retryCount + 1,
          lastActivityAt: () => retry.timestamp,
          liveTokensPerSecond: () => null,
          turnEvents: nextEvents,
        );
      });
      return;
    }

    if (!state.isSending) return;
    final nextEvents = _appendTurnEvent(
      state.turnEvents,
      TurnActivityLogEntry(
        timestamp: retry.timestamp,
        label: retry.summary,
        detail: retry.rawMessage,
        isWarning: true,
      ),
    );
    state = state.copyWith(
      livePhase: TurnLivePhase.retrying,
      activeRetry: () => retry,
      retryCount: state.retryCount + 1,
      lastActivityAt: () => retry.timestamp,
      liveTokensPerSecond: () => null,
      turnEvents: nextEvents,
    );
  }

  static List<TurnActivityLogEntry> _appendTurnEvent(
    List<TurnActivityLogEntry> current,
    TurnActivityLogEntry entry,
  ) {
    final next = [...current, entry];
    if (next.length > _maxTurnEvents) {
      next.removeRange(0, next.length - _maxTurnEvents);
    }
    return next;
  }

  void _onPermissionRequest(PendingPermission pending) {
    if (!ref.mounted) return;
    final reqSid = pending.request.sessionId;
    final target = _sessionStateOf(reqSid);
    if (target == null) return;

    final settings = ref.read(settingsProvider);
    final perm =
        target.sessionToolPermission ??
        _sessionPermissions[reqSid] ??
        settings.toolPermission;
    final mode =
        target.sessionAgentMode ?? _sessionModes[reqSid] ?? settings.agentMode;
    final autoChat =
        target.allowAllForSession || _allowAllSessions.contains(reqSid);

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

    _updateSessionState(
      reqSid,
      (cur) => cur.copyWith(
        pendingPermissions: [...cur.pendingPermissions, pending],
      ),
    );

    if (_isAppBackgrounded && settings.notifyOnApproval) {
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
