import 'dart:async';

import 'json_rpc.dart';
import 'models.dart';
import 'transport.dart';

/// A pending permission request awaiting a user decision.
class PendingPermission {
  PendingPermission({
    required this.id,
    required this.request,
    required Completer<AcpPermissionOutcome> completer,
  }) : _completer = completer;

  final String id;
  final AcpPermissionRequest request;
  final Completer<AcpPermissionOutcome> _completer;

  bool get isCompleted => _completer.isCompleted;

  void select(String optionId) {
    if (!_completer.isCompleted) {
      _completer.complete(AcpPermissionSelected(optionId));
    }
  }

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete(const AcpPermissionCancelled());
    }
  }
}

/// High-level ACP client speaking JSON-RPC 2.0 over any [AcpTransport].
class AcpClient {
  AcpClient(
    AcpTransport transport, {
    this.clientInfo = const AcpImplementation(
      name: 'agy-go',
      version: '0.1.0',
      title: 'AGY Go',
    ),
    this.clientCapabilities = const AcpClientCapabilities(),
  }) : _peer = AcpJsonRpcPeer(transport) {
    _peer.onNotification('session/update', _onSessionUpdate);
    _peer.onRequest('session/request_permission', _onPermissionRequest);
  }

  final AcpJsonRpcPeer _peer;
  final AcpImplementation clientInfo;
  final AcpClientCapabilities clientCapabilities;

  final _updates = StreamController<AcpSessionNotification>.broadcast();
  final _permissions = StreamController<PendingPermission>.broadcast();
  final _pendingPermissions = <String, PendingPermission>{};
  int _permissionSeq = 0;

  AcpInitializeResult? _initResult;

  AcpInitializeResult? get initResult => _initResult;
  bool get isClosed => _peer.isClosed;
  Future<void> get done => _peer.done;
  Stream<String> get stderrLines => _peer.transport.stderrLines;

  /// Real-time `session/update` notifications across all sessions on this link.
  Stream<AcpSessionNotification> get updates => _updates.stream;

  /// Incoming `session/request_permission` requests requiring UI resolution.
  Stream<PendingPermission> get permissionRequests => _permissions.stream;

  /// Currently unresolved permission prompts.
  List<PendingPermission> get pendingPermissions =>
      _pendingPermissions.values.where((p) => !p.isCompleted).toList();

  /// Step 1 of every ACP connection: negotiate protocol version & capabilities.
  Future<AcpInitializeResult> initialize({
    int protocolVersion = 1,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final result = await _peer.sendRequest(
      'initialize',
      <String, Object?>{
        'protocolVersion': protocolVersion,
        'clientCapabilities': clientCapabilities.toJson(),
        'clientInfo': clientInfo.toJson(),
      },
      timeout,
    );
    _initResult = AcpInitializeResult.fromJson(result);
    return _initResult!;
  }

  /// Authenticates using one of the `authMethods` advertised during [initialize].
  Future<void> authenticate(
    String methodId, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    await _peer.sendRequest(
      'authenticate',
      <String, Object?>{'methodId': methodId},
      timeout,
    );
  }

  Future<void> logout({Duration timeout = const Duration(seconds: 15)}) async {
    await _peer.sendRequest('logout', const <String, Object?>{}, timeout);
  }

  /// Creates a new conversation session rooted at [cwd].
  Future<AcpSessionHandle> newSession({
    required String cwd,
    List<AcpMcpServerConfig> mcpServers = const [],
    List<String> additionalDirectories = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await _peer.sendRequest(
      'session/new',
      <String, Object?>{
        'cwd': cwd,
        'mcpServers': [for (final s in mcpServers) s.toJson()],
        if (additionalDirectories.isNotEmpty)
          'additionalDirectories': additionalDirectories,
      },
      timeout,
    );
    return AcpSessionHandle.fromJson(result);
  }

  /// Lists sessions known to the agent (requires `sessionCapabilities.list`).
  Future<AcpSessionListPage> listSessions({
    String? cwd,
    String? cursor,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final result = await _peer.sendRequest(
      'session/list',
      <String, Object?>{
        if (cwd != null) 'cwd': cwd,
        if (cursor != null) 'cursor': cursor,
      },
      timeout,
    );
    return AcpSessionListPage.fromJson(result);
  }

  /// Loads an existing session and replays history through [updates].
  Future<AcpSessionHandle> loadSession({
    required String sessionId,
    required String cwd,
    List<AcpMcpServerConfig> mcpServers = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await _peer.sendRequest(
      'session/load',
      <String, Object?>{
        'sessionId': sessionId,
        'cwd': cwd,
        'mcpServers': [for (final s in mcpServers) s.toJson()],
      },
      timeout,
    );
    return AcpSessionHandle.fromJson(result, fallbackSessionId: sessionId);
  }

  /// Resumes a session without replaying prior messages.
  Future<AcpSessionHandle> resumeSession({
    required String sessionId,
    required String cwd,
    List<AcpMcpServerConfig> mcpServers = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await _peer.sendRequest(
      'session/resume',
      <String, Object?>{
        'sessionId': sessionId,
        'cwd': cwd,
        'mcpServers': [for (final s in mcpServers) s.toJson()],
      },
      timeout,
    );
    return AcpSessionHandle.fromJson(result, fallbackSessionId: sessionId);
  }

  Future<void> closeSession(
    String sessionId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _peer.sendRequest(
      'session/close',
      <String, Object?>{'sessionId': sessionId},
      timeout,
    );
  }

  Future<void> deleteSession(
    String sessionId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _peer.sendRequest(
      'session/delete',
      <String, Object?>{'sessionId': sessionId},
      timeout,
    );
  }

  /// Sends a user turn and awaits its completion [AcpPromptResult].
  ///
  /// Streamed content and tool calls arrive via [updates] while this future is pending.
  Future<AcpPromptResult> prompt(
    String sessionId,
    List<AcpContentBlock> blocks,
  ) async {
    final result = await _peer.sendRequest(
      'session/prompt',
      <String, Object?>{
        'sessionId': sessionId,
        'prompt': [for (final b in blocks) b.toJson()],
      },
    );
    return AcpPromptResult.fromJson(result);
  }

  /// Convenience helper for sending plain text.
  Future<AcpPromptResult> promptText(String sessionId, String text) =>
      prompt(sessionId, [AcpTextBlock(text)]);

  /// Cancels the active prompt turn and resolves any pending permission prompts as cancelled.
  Future<void> cancel(String sessionId) async {
    for (final pending in _pendingPermissions.values.toList()) {
      if (pending.request.sessionId == sessionId) {
        pending.cancel();
      }
    }
    await _peer.sendNotification(
      'session/cancel',
      <String, Object?>{'sessionId': sessionId},
    );
  }

  Future<void> setMode(
    String sessionId,
    String modeId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _peer.sendRequest(
      'session/set_mode',
      <String, Object?>{'sessionId': sessionId, 'modeId': modeId},
      timeout,
    );
  }

  Future<List<AcpConfigOption>> setConfigOption(
    String sessionId, {
    required String configId,
    required Object value,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final params = <String, Object?>{
      'sessionId': sessionId,
      'configId': configId,
      if (value is bool) 'type': 'boolean',
      'value': value,
    };
    final result = await _peer.sendRequest(
      'session/set_config_option',
      params,
      timeout,
    );
    final raw = result['configOptions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => AcpConfigOption.fromJson(Map<String, Object?>.from(m)))
        .toList();
  }

  void _onSessionUpdate(Map<String, Object?> params) {
    if (_updates.isClosed) return;
    _updates.add(AcpSessionNotification.fromJson(params));
  }

  Future<Map<String, Object?>> _onPermissionRequest(
    Map<String, Object?> params,
  ) async {
    final request = AcpPermissionRequest.fromJson(params);
    final id = 'perm_${++_permissionSeq}';
    final completer = Completer<AcpPermissionOutcome>();
    final pending = PendingPermission(
      id: id,
      request: request,
      completer: completer,
    );
    _pendingPermissions[id] = pending;

    if (_permissions.hasListener && !_permissions.isClosed) {
      _permissions.add(pending);
    } else {
      // Fail closed if no UI listener is attached to approve sensitive actions.
      pending.cancel();
    }

    try {
      final outcome = await completer.future;
      return <String, Object?>{'outcome': outcome.toJson()};
    } finally {
      _pendingPermissions.remove(id);
    }
  }

  Future<void> close() async {
    for (final pending in _pendingPermissions.values.toList()) {
      pending.cancel();
    }
    _pendingPermissions.clear();
    await _peer.close();
    if (!_updates.isClosed) await _updates.close();
    if (!_permissions.isClosed) await _permissions.close();
  }
}
