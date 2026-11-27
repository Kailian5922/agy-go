/// Wire models for the Agent Client Protocol (ACP v1, forward-compatible with v2 extensions).

Map<String, Object?> _asMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

List<Object?> _asList(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

String _asString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _asNullableString(Object? value) => value is String ? value : null;

bool _asBool(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;

int? _asInt(Object? value) => value is num ? value.toInt() : null;

/// Implementation identity exchanged during `initialize`.
class AcpImplementation {
  const AcpImplementation({
    required this.name,
    required this.version,
    this.title,
  });

  factory AcpImplementation.fromJson(Map<String, Object?> json) =>
      AcpImplementation(
        name: _asString(json['name']),
        version: _asString(json['version']),
        title: _asNullableString(json['title']),
      );

  final String name;
  final String version;
  final String? title;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'version': version,
    if (title != null) 'title': title,
  };
}

/// Client capabilities advertised in `initialize`.
class AcpClientCapabilities {
  const AcpClientCapabilities({
    this.readTextFile = false,
    this.writeTextFile = false,
    this.terminal = false,
  });

  final bool readTextFile;
  final bool writeTextFile;
  final bool terminal;

  Map<String, Object?> toJson() => <String, Object?>{
    'fs': <String, Object?>{
      'readTextFile': readTextFile,
      'writeTextFile': writeTextFile,
    },
    'terminal': terminal,
  };
}

/// Authentication method advertised by the agent.
class AcpAuthMethod {
  const AcpAuthMethod({
    required this.id,
    required this.name,
    this.description,
    this.type,
  });

  factory AcpAuthMethod.fromJson(Map<String, Object?> json) => AcpAuthMethod(
    id: _asString(json['id']),
    name: _asString(json['name'], _asString(json['id'])),
    description: _asNullableString(json['description']),
    type: _asNullableString(json['type']),
  );

  final String id;
  final String name;
  final String? description;
  final String? type;
}

/// Capabilities advertised by the agent in `initialize`.
class AcpAgentCapabilities {
  const AcpAgentCapabilities({
    this.loadSession = false,
    this.canListSessions = false,
    this.canResumeSession = false,
    this.canCloseSession = false,
    this.canDeleteSession = false,
    this.supportsImages = false,
    this.supportsAudio = false,
    this.supportsEmbeddedContext = false,
    this.supportsHttpMcp = false,
    this.supportsSseMcp = false,
    this.supportsLogout = false,
  });

  factory AcpAgentCapabilities.fromJson(Map<String, Object?> json) {
    final promptCaps = _asMap(json['promptCapabilities']);
    final mcpCaps = _asMap(json['mcpCapabilities']);
    final sessionCaps = _asMap(json['sessionCapabilities']);
    final authCaps = _asMap(json['auth']);

    return AcpAgentCapabilities(
      loadSession: _asBool(json['loadSession']),
      canListSessions: sessionCaps.containsKey('list') && sessionCaps['list'] != null,
      canResumeSession: sessionCaps.containsKey('resume') && sessionCaps['resume'] != null,
      canCloseSession: sessionCaps.containsKey('close') && sessionCaps['close'] != null,
      canDeleteSession: sessionCaps.containsKey('delete') && sessionCaps['delete'] != null,
      supportsImages: _asBool(promptCaps['image']),
      supportsAudio: _asBool(promptCaps['audio']),
      supportsEmbeddedContext: _asBool(promptCaps['embeddedContext']),
      supportsHttpMcp: _asBool(mcpCaps['http']),
      supportsSseMcp: _asBool(mcpCaps['sse']),
      supportsLogout: authCaps.containsKey('logout') && authCaps['logout'] != null,
    );
  }

  final bool loadSession;
  final bool canListSessions;
  final bool canResumeSession;
  final bool canCloseSession;
  final bool canDeleteSession;
  final bool supportsImages;
  final bool supportsAudio;
  final bool supportsEmbeddedContext;
  final bool supportsHttpMcp;
  final bool supportsSseMcp;
  final bool supportsLogout;
}

/// Response to `initialize`.
class AcpInitializeResult {
  const AcpInitializeResult({
    required this.protocolVersion,
    required this.capabilities,
    this.agentInfo,
    this.authMethods = const [],
  });

  factory AcpInitializeResult.fromJson(Map<String, Object?> json) {
    final infoMap = json['agentInfo'];
    return AcpInitializeResult(
      protocolVersion: json['protocolVersion'] ?? 1,
      capabilities: AcpAgentCapabilities.fromJson(_asMap(json['agentCapabilities'])),
      agentInfo: infoMap is Map
          ? AcpImplementation.fromJson(Map<String, Object?>.from(infoMap))
          : null,
      authMethods: _asList(json['authMethods'])
          .whereType<Map>()
          .map((m) => AcpAuthMethod.fromJson(Map<String, Object?>.from(m)))
          .toList(),
    );
  }

  final Object protocolVersion;
  final AcpAgentCapabilities capabilities;
  final AcpImplementation? agentInfo;
  final List<AcpAuthMethod> authMethods;
}

/// MCP server passed to `session/new` or `session/load`.
sealed class AcpMcpServerConfig {
  const AcpMcpServerConfig({required this.name});

  final String name;
  Map<String, Object?> toJson();
}

final class StdioMcpServerConfig extends AcpMcpServerConfig {
  const StdioMcpServerConfig({
    required super.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  final String command;
  final List<String> args;
  final Map<String, String> env;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'command': command,
    'args': args,
    'env': [
      for (final e in env.entries)
        <String, Object?>{'name': e.key, 'value': e.value},
    ],
  };
}

final class HttpMcpServerConfig extends AcpMcpServerConfig {
  const HttpMcpServerConfig({
    required super.name,
    required this.url,
    this.headers = const {},
    this.transportType = 'http',
  });

  final String url;
  final Map<String, String> headers;
  final String transportType;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': transportType,
    'name': name,
    'url': url,
    'headers': [
      for (final e in headers.entries)
        <String, Object?>{'name': e.key, 'value': e.value},
    ],
  };
}

/// Mode offered by an ACP session (e.g., code, plan, ask).
class AcpSessionMode {
  const AcpSessionMode({
    required this.id,
    required this.name,
    this.description,
  });

  factory AcpSessionMode.fromJson(Map<String, Object?> json) => AcpSessionMode(
    id: _asString(json['id']),
    name: _asString(json['name'], _asString(json['id'])),
    description: _asNullableString(json['description']),
  );

  final String id;
  final String name;
  final String? description;
}

class AcpSessionModeState {
  const AcpSessionModeState({
    required this.currentModeId,
    required this.availableModes,
  });

  factory AcpSessionModeState.fromJson(Map<String, Object?> json) =>
      AcpSessionModeState(
        currentModeId: _asString(json['currentModeId']),
        availableModes: _asList(json['availableModes'])
            .whereType<Map>()
            .map((m) => AcpSessionMode.fromJson(Map<String, Object?>.from(m)))
            .toList(),
      );

  final String currentModeId;
  final List<AcpSessionMode> availableModes;
}

class AcpConfigOptionValue {
  const AcpConfigOptionValue({
    required this.value,
    required this.name,
    this.description,
    this.group,
  });

  factory AcpConfigOptionValue.fromJson(Map<String, Object?> json, {String? group}) {
    final value =
        _asNullableString(json['value']) ??
        _asNullableString(json['modelId']) ??
        _asString(json['id']);
    return AcpConfigOptionValue(
      value: value,
      name: _asString(json['name'], value),
      description: _asNullableString(json['description']),
      group: group,
    );
  }

  final String value;
  final String name;
  final String? description;
  final String? group;
}

/// Dynamic session option (e.g. `model`, `thought_level`, `reasoning_effort`, `mode`).
class AcpConfigOption {
  const AcpConfigOption({
    required this.id,
    required this.name,
    required this.type,
    required this.currentValue,
    this.description,
    this.category,
    this.options = const [],
  });

  factory AcpConfigOption.fromJson(Map<String, Object?> json) {
    final flatOptions = <AcpConfigOptionValue>[];
    for (final raw in _asList(json['options'])) {
      if (raw is! Map) continue;
      final map = Map<String, Object?>.from(raw);
      if (map['options'] is List) {
        final groupName =
            _asNullableString(map['name']) ?? _asNullableString(map['group']);
        for (final nested in _asList(map['options'])) {
          if (nested is Map) {
            flatOptions.add(
              AcpConfigOptionValue.fromJson(
                Map<String, Object?>.from(nested),
                group: groupName,
              ),
            );
          }
        }
      } else {
        flatOptions.add(AcpConfigOptionValue.fromJson(map));
      }
    }

    return AcpConfigOption(
      id: _asString(json['id']),
      name: _asString(json['name'], _asString(json['id'])),
      type: _asString(json['type'], 'select'),
      currentValue: json['currentValue'],
      description: _asNullableString(json['description']),
      category: _asNullableString(json['category']),
      options: flatOptions,
    );
  }

  final String id;
  final String name;
  final String type;
  final Object? currentValue;
  final String? description;
  final String? category;
  final List<AcpConfigOptionValue> options;

  bool get isModelOption =>
      category?.toLowerCase() == 'model' || id.toLowerCase() == 'model';

  bool get isThoughtLevelOption {
    final cat = category?.toLowerCase() ?? '';
    final lower = id.toLowerCase();
    return cat == 'thought_level' ||
        cat == 'reasoning_effort' ||
        cat == 'thinking_level' ||
        cat == 'thinking' ||
        cat == 'effort' ||
        lower == 'thought_level' ||
        lower == 'reasoning_effort' ||
        lower == 'thinking_level' ||
        lower == 'thinking' ||
        lower == 'effort';
  }

  bool get isModeOption {
    final cat = category?.toLowerCase() ?? '';
    final lower = id.toLowerCase();
    return cat == 'mode' ||
        cat == 'approval_mode' ||
        lower == 'mode' ||
        lower == 'agent_mode' ||
        lower == 'approval_mode';
  }

  AcpConfigOption copyWith({
    Object? currentValue,
    List<AcpConfigOptionValue>? options,
  }) => AcpConfigOption(
    id: id,
    name: name,
    type: type,
    currentValue: currentValue ?? this.currentValue,
    description: description,
    category: category,
    options: options ?? this.options,
  );
}

/// Handle returned from `session/new`, `session/load`, or `session/resume`.
class AcpSessionHandle {
  const AcpSessionHandle({
    required this.sessionId,
    this.modes,
    this.configOptions = const [],
  });

  factory AcpSessionHandle.fromJson(
    Map<String, Object?> json, {
    String? fallbackSessionId,
  }) {
    final modesRaw = json['modes'];
    final configOptions = _asList(json['configOptions'])
        .whereType<Map>()
        .map((m) => AcpConfigOption.fromJson(Map<String, Object?>.from(m)))
        .toList();

    // Fallback: if an ACP server advertises models under `models.availableModels`
    // without a `configOptions` model select, synthesize one so UI always lists them.
    if (!configOptions.any((o) => o.isModelOption) && json['models'] is Map) {
      final modelsMap = Map<String, Object?>.from(json['models'] as Map);
      final available = _asList(modelsMap['availableModels'])
          .whereType<Map>()
          .map((m) => AcpConfigOptionValue.fromJson(Map<String, Object?>.from(m)))
          .where((v) => v.value.isNotEmpty)
          .toList();
      if (available.isNotEmpty) {
        configOptions.insert(
          0,
          AcpConfigOption(
            id: 'model',
            name: 'Model',
            type: 'select',
            category: 'model',
            currentValue: _asNullableString(modelsMap['currentModelId']) ??
                available.first.value,
            options: available,
          ),
        );
      }
    }

    return AcpSessionHandle(
      sessionId: _asNullableString(json['sessionId']) ?? fallbackSessionId ?? '',
      modes: modesRaw is Map
          ? AcpSessionModeState.fromJson(Map<String, Object?>.from(modesRaw))
          : null,
      configOptions: configOptions,
    );
  }

  final String sessionId;
  final AcpSessionModeState? modes;
  final List<AcpConfigOption> configOptions;
}

/// Summary row returned by `session/list`.
class AcpSessionInfo {
  const AcpSessionInfo({
    required this.sessionId,
    required this.cwd,
    this.title,
    this.updatedAt,
  });

  factory AcpSessionInfo.fromJson(Map<String, Object?> json) => AcpSessionInfo(
    sessionId: _asString(json['sessionId']),
    cwd: _asString(json['cwd']),
    title: _asNullableString(json['title']),
    updatedAt: DateTime.tryParse(_asString(json['updatedAt'])),
  );

  final String sessionId;
  final String cwd;
  final String? title;
  final DateTime? updatedAt;
}

class AcpSessionListPage {
  const AcpSessionListPage({
    required this.sessions,
    this.nextCursor,
  });

  factory AcpSessionListPage.fromJson(Map<String, Object?> json) =>
      AcpSessionListPage(
        sessions: _asList(json['sessions'])
            .whereType<Map>()
            .map((m) => AcpSessionInfo.fromJson(Map<String, Object?>.from(m)))
            .toList(),
        nextCursor: _asNullableString(json['nextCursor']),
      );

  final List<AcpSessionInfo> sessions;
  final String? nextCursor;
}

/// Content blocks carried in `session/prompt` and streamed message chunks.
sealed class AcpContentBlock {
  const AcpContentBlock();

  Map<String, Object?> toJson();

  static AcpContentBlock fromJson(Map<String, Object?> json) {
    switch (_asString(json['type'])) {
      case 'text':
        return AcpTextBlock(_asString(json['text']));
      case 'image':
        return AcpImageBlock(
          data: _asString(json['data']),
          mimeType: _asString(json['mimeType'], 'image/png'),
          uri: _asNullableString(json['uri']),
        );
      case 'resource_link':
        return AcpResourceLinkBlock(
          uri: _asString(json['uri']),
          name: _asString(json['name']),
          mimeType: _asNullableString(json['mimeType']),
          title: _asNullableString(json['title']),
        );
      case 'resource':
        final res = _asMap(json['resource']);
        final text = _asNullableString(res['text']);
        if (text != null) return AcpTextBlock(text);
        final uri = _asString(res['uri'], _asString(json['uri']));
        final mimeType =
            _asNullableString(res['mimeType']) ??
            _asNullableString(json['mimeType']);
        if (uri.isNotEmpty) {
          final slash = uri.lastIndexOf('/');
          final name = slash >= 0 && slash + 1 < uri.length
              ? uri.substring(slash + 1)
              : uri;
          return AcpResourceLinkBlock(
            uri: uri,
            name: name,
            mimeType: mimeType,
          );
        }
        return const AcpTextBlock('');
      default:
        return AcpTextBlock(_asString(json['text'], json.toString()));
    }
  }
}

final class AcpTextBlock extends AcpContentBlock {
  const AcpTextBlock(this.text);
  final String text;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'text',
    'text': text,
  };
}

final class AcpImageBlock extends AcpContentBlock {
  const AcpImageBlock({
    required this.data,
    required this.mimeType,
    this.uri,
  });

  final String data;
  final String mimeType;
  final String? uri;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'image',
    'data': data,
    'mimeType': mimeType,
    if (uri != null) 'uri': uri,
  };
}

final class AcpResourceLinkBlock extends AcpContentBlock {
  const AcpResourceLinkBlock({
    required this.uri,
    required this.name,
    this.mimeType,
    this.title,
  });

  final String uri;
  final String name;
  final String? mimeType;
  final String? title;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'resource_link',
    'uri': uri,
    'name': name,
    if (mimeType != null) 'mimeType': mimeType,
    if (title != null) 'title': title,
  };
}

enum AcpToolKind {
  read,
  edit,
  delete,
  move,
  search,
  execute,
  think,
  fetch,
  switchMode,
  other;

  static AcpToolKind parse(Object? raw) {
    final normalized = raw is String ? raw.trim().toLowerCase() : '';
    return switch (normalized) {
      'read' || 'view' || 'read_file' || 'view_file' => read,
      'edit' || 'write' || 'patch' || 'replace' || 'file_edit' => edit,
      'delete' || 'remove' || 'rm' => delete,
      'move' || 'rename' || 'mv' => move,
      'search' || 'grep' || 'glob' || 'find' => search,
      'execute' || 'exec' || 'run' || 'bash' || 'shell' || 'terminal' || 'command' => execute,
      'think' || 'reason' || 'thinking' => think,
      'fetch' || 'web' || 'web_search' || 'http' => fetch,
      'switch_mode' || 'switchmode' => switchMode,
      _ => other,
    };
  }

  /// Infers tool kind from explicit [rawKind], falling back to programmatic [name]
  /// or human-readable [title] when an ACP server omits or sends `other`.
  static AcpToolKind infer({Object? rawKind, String? name, String? title}) {
    final parsed = parse(rawKind);
    if (parsed != other) return parsed;
    final probe = '${name ?? ''} ${title ?? ''}'.trim().toLowerCase();
    if (probe.isEmpty) return other;
    if (probe.contains('replace_file') ||
        probe.contains('write_to_file') ||
        probe.contains('write_file') ||
        probe.contains('edit_file') ||
        probe.contains('apply_patch') ||
        probe.contains('str_replace') ||
        probe.startsWith('edit ') ||
        probe.startsWith('write ') ||
        probe.startsWith('update ') ||
        probe.startsWith('patch ') ||
        probe.startsWith('create ')) {
      return edit;
    }
    if (probe.contains('delete_file') ||
        probe.contains('remove_file') ||
        probe.startsWith('delete ')) {
      return delete;
    }
    if (probe.contains('move_file') ||
        probe.contains('rename_file') ||
        probe.startsWith('move ') ||
        probe.startsWith('rename ')) {
      return move;
    }
    if (probe.contains('read_file') ||
        probe.contains('view_file') ||
        probe.contains('list_dir') ||
        probe.contains('view_file_outline') ||
        probe.startsWith('read ') ||
        probe.startsWith('view ') ||
        probe.startsWith('open ') ||
        probe.startsWith('list ')) {
      return read;
    }
    if (probe.contains('grep') ||
        probe.contains('glob') ||
        probe.contains('find_by_name') ||
        probe.contains('codebase_search') ||
        probe.startsWith('search ') ||
        probe.startsWith('find ')) {
      return search;
    }
    if (probe.contains('run_command') ||
        probe.contains('run_workflow') ||
        probe.contains('bash') ||
        probe.contains('shell') ||
        probe.contains('terminal') ||
        probe.startsWith('run ')) {
      return execute;
    }
    if (probe.contains('read_url') ||
        probe.contains('web_search') ||
        probe.contains('search_web') ||
        probe.contains('fetch')) {
      return fetch;
    }
    return other;
  }
}

enum AcpToolStatus {
  pending,
  inProgress,
  paused,
  completed,
  failed,
  cancelled;

  static AcpToolStatus? parseNullable(Object? raw) {
    if (raw is! String) return null;
    return switch (raw.trim().toLowerCase()) {
      'pending' || 'queued' => pending,
      'in_progress' || 'inprogress' || 'running' || 'working' || 'executing' || 'started' =>
        inProgress,
      'paused' || 'waiting' || 'waiting_for_approval' => paused,
      'completed' || 'complete' || 'done' || 'success' || 'succeeded' => completed,
      'failed' || 'fail' || 'error' || 'errored' => failed,
      'cancelled' || 'canceled' || 'aborted' => cancelled,
      _ => null,
    };
  }

  static AcpToolStatus parse(Object? raw) => parseNullable(raw) ?? pending;

  bool get isActive =>
      this == pending || this == inProgress || this == paused;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

class AcpToolLocation {
  const AcpToolLocation({required this.path, this.line});

  factory AcpToolLocation.fromJson(Map<String, Object?> json) =>
      AcpToolLocation(
        path: _asString(json['path']),
        line: _asInt(json['line']),
      );

  final String path;
  final int? line;
}

sealed class AcpToolContent {
  const AcpToolContent();

  static AcpToolContent? fromJson(Map<String, Object?> json) {
    switch (_asString(json['type']).toLowerCase()) {
      case 'diff' || 'file_change' || 'edit':
        final path =
            _asNullableString(json['path']) ??
            _asNullableString(json['filePath']) ??
            _asNullableString(json['file_path']) ??
            '';
        final oldText =
            _asNullableString(json['oldText']) ??
            _asNullableString(json['old_text']) ??
            _asNullableString(json['oldString']) ??
            _asNullableString(json['old_string']);
        final newText =
            _asNullableString(json['newText']) ??
            _asNullableString(json['new_text']) ??
            _asNullableString(json['newString']) ??
            _asNullableString(json['new_string']) ??
            _asNullableString(json['content']) ??
            '';
        return AcpDiffToolContent(
          path: path,
          oldText: oldText,
          newText: newText,
        );
      case 'terminal':
        return AcpTerminalToolContent(terminalId: _asString(json['terminalId']));
      case 'content':
        final inner = json['content'];
        if (inner is Map) {
          return AcpBlockToolContent(
            AcpContentBlock.fromJson(Map<String, Object?>.from(inner)),
          );
        }
        return null;
      default:
        if (json['oldText'] is String ||
            json['newText'] is String ||
            json['old_text'] is String ||
            json['new_text'] is String) {
          return AcpDiffToolContent(
            path:
                _asNullableString(json['path']) ??
                _asNullableString(json['filePath']) ??
                _asNullableString(json['file_path']) ??
                '',
            oldText:
                _asNullableString(json['oldText']) ??
                _asNullableString(json['old_text']),
            newText:
                _asNullableString(json['newText']) ??
                _asNullableString(json['new_text']) ??
                '',
          );
        }
        if (json['text'] is String) {
          return AcpBlockToolContent(AcpTextBlock(json['text']! as String));
        }
        return null;
    }
  }
}

final class AcpDiffToolContent extends AcpToolContent {
  const AcpDiffToolContent({
    required this.path,
    this.oldText,
    required this.newText,
  });

  final String path;
  final String? oldText;
  final String newText;
}

final class AcpTerminalToolContent extends AcpToolContent {
  const AcpTerminalToolContent({required this.terminalId});
  final String terminalId;
}

final class AcpBlockToolContent extends AcpToolContent {
  const AcpBlockToolContent(this.block);
  final AcpContentBlock block;
}

/// Snapshot or incremental patch for a tool invocation.
class AcpToolCall {
  const AcpToolCall({
    required this.toolCallId,
    required this.title,
    this.name,
    this.kind = AcpToolKind.other,
    this.status = AcpToolStatus.pending,
    this.locations = const [],
    this.content = const [],
    this.rawInput,
    this.rawOutput,
    this.meta,
  });

  factory AcpToolCall.fromJson(Map<String, Object?> json) {
    final parsedContent = <AcpToolContent>[];
    for (final raw in _asList(json['content'])) {
      if (raw is Map) {
        final item = AcpToolContent.fromJson(Map<String, Object?>.from(raw));
        if (item != null) parsedContent.add(item);
      }
    }
    final title = _asString(json['title']);
    final name = _asNullableString(json['name']);
    final rawMeta = json['_meta'];
    return AcpToolCall(
      toolCallId: _asString(json['toolCallId']),
      title: title,
      name: name,
      kind: AcpToolKind.infer(rawKind: json['kind'], name: name, title: title),
      status: AcpToolStatus.parse(json['status']),
      locations: _asList(json['locations'])
          .whereType<Map>()
          .map((m) => AcpToolLocation.fromJson(Map<String, Object?>.from(m)))
          .toList(),
      content: parsedContent,
      rawInput: json['rawInput'] ?? json['args'],
      rawOutput: json['rawOutput'],
      meta: rawMeta is Map ? Map<String, Object?>.from(rawMeta) : null,
    );
  }

  final String toolCallId;
  final String title;
  final String? name;
  final AcpToolKind kind;
  final AcpToolStatus status;
  final List<AcpToolLocation> locations;
  final List<AcpToolContent> content;
  final Object? rawInput;
  final Object? rawOutput;
  final Map<String, Object?>? meta;

  static String? _cleanStringField(Object? raw) {
    if (raw is! String) return null;
    final clean = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return clean.isEmpty ? null : clean;
  }

  /// Native present-participle action string emitted by the model itself
  /// (e.g. `"Viewing README.md"`, `"Analyzing directory"`, `"Running tests"`).
  String? get nativeToolAction {
    if (rawInput is Map) {
      final m = rawInput! as Map;
      final direct =
          _cleanStringField(m['toolAction']) ??
          _cleanStringField(m['tool_action']);
      if (direct != null) return direct;
    }
    if (meta != null) {
      return _cleanStringField(meta!['toolAction']) ??
          _cleanStringField(meta!['tool_action']) ??
          _cleanStringField(meta!['action']);
    }
    return null;
  }

  /// Native concise summary emitted by the model itself
  /// (e.g. `"Read README.md"`, `"Directory analysis"`, `"Test execution"`).
  String? get nativeToolSummary {
    if (rawInput is Map) {
      final m = rawInput! as Map;
      final direct =
          _cleanStringField(m['toolSummary']) ??
          _cleanStringField(m['tool_summary']) ??
          _cleanStringField(m['Description']) ??
          _cleanStringField(m['description']);
      if (direct != null) return direct;
    }
    if (meta != null) {
      return _cleanStringField(meta!['toolSummary']) ??
          _cleanStringField(meta!['tool_summary']) ??
          _cleanStringField(meta!['summary']);
    }
    return null;
  }

  /// Whether [title] is merely a bare internal snake_case tool identifier
  /// (like `run_command` or `read_file`) rather than human-readable action text.
  bool get _titleIsBareToolName {
    final t = title.trim();
    if (t.isEmpty) return true;
    final n = name?.trim();
    if (n != null && n.isNotEmpty && t.toLowerCase() == n.toLowerCase()) {
      return true;
    }
    return RegExp(r'^[a-z0-9]+(?:_[a-z0-9]+)+$').hasMatch(t);
  }

  /// Exact native status/label emitted by the model or `agy acp` for this tool call
  /// without client-side phase guessing.
  String? get nativeDisplayLabel {
    final action = nativeToolAction;
    final summary = nativeToolSummary;
    final cleanTitle = _cleanStringField(title);
    final descriptiveTitle =
        (cleanTitle != null && !_titleIsBareToolName) ? cleanTitle : null;

    if (status.isActive) {
      return action ?? descriptiveTitle ?? summary ?? cleanTitle ?? _cleanStringField(name);
    }
    return summary ?? descriptiveTitle ?? action ?? cleanTitle ?? _cleanStringField(name);
  }

  /// All file diffs associated with this tool call: prefers explicit ACP
  /// [AcpDiffToolContent] blocks and falls back to live edit arguments in
  /// [rawInput] so file changes appear immediately even while `in_progress`.
  List<AcpDiffToolContent> get effectiveDiffs {
    final explicit = [
      for (final c in content)
        if (c is AcpDiffToolContent) c,
    ];
    if (explicit.isNotEmpty) return explicit;
    return _extractDiffsFromRawInput();
  }

  /// Whether this tool call edits, creates, moves, or deletes files.
  bool get modifiesFiles =>
      kind == AcpToolKind.edit ||
      kind == AcpToolKind.delete ||
      kind == AcpToolKind.move ||
      effectiveDiffs.isNotEmpty;

  List<AcpDiffToolContent> _extractDiffsFromRawInput() {
    if (rawInput is! Map) return const [];
    final input = rawInput! as Map;
    String resolvePath() {
      for (final key in const [
        'Path',
        'TargetFile',
        'target_file',
        'file_path',
        'filePath',
        'filepath',
        'path',
        'AbsolutePath',
      ]) {
        final v = input[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      if (locations.isNotEmpty && locations.first.path.trim().isNotEmpty) {
        return locations.first.path.trim();
      }
      return '';
    }

    final path = resolvePath();

    // Multi-chunk edits (`ReplacementChunks` / `edits`).
    final chunks = input['ReplacementChunks'] ?? input['edits'];
    if (chunks is List && chunks.isNotEmpty) {
      final out = <AcpDiffToolContent>[];
      for (final c in chunks.whereType<Map>()) {
        final oldText =
            _asNullableString(c['TargetContent']) ??
            _asNullableString(c['Target']) ??
            _asNullableString(c['old_string']) ??
            _asNullableString(c['oldString']) ??
            _asNullableString(c['old_text']) ??
            _asNullableString(c['oldText']);
        final newText =
            _asNullableString(c['ReplacementContent']) ??
            _asNullableString(c['Replacement']) ??
            _asNullableString(c['new_string']) ??
            _asNullableString(c['newString']) ??
            _asNullableString(c['new_text']) ??
            _asNullableString(c['newText']);
        if (oldText != null || newText != null) {
          out.add(
            AcpDiffToolContent(
              path: path,
              oldText: oldText,
              newText: newText ?? '',
            ),
          );
        }
      }
      if (out.isNotEmpty) return out;
    }

    // Single replace edit (`Target`/`Replacement` from agy acp `edit_file`,
    // `TargetContent`/`ReplacementContent`, `old_string`/`new_string`, etc.).
    final oldText =
        _asNullableString(input['Target']) ??
        _asNullableString(input['TargetContent']) ??
        _asNullableString(input['old_string']) ??
        _asNullableString(input['oldString']) ??
        _asNullableString(input['old_str']) ??
        _asNullableString(input['old_text']) ??
        _asNullableString(input['oldText']);
    final newText =
        _asNullableString(input['Replacement']) ??
        _asNullableString(input['ReplacementContent']) ??
        _asNullableString(input['new_string']) ??
        _asNullableString(input['newString']) ??
        _asNullableString(input['new_str']) ??
        _asNullableString(input['new_text']) ??
        _asNullableString(input['newText']);
    if (oldText != null || newText != null) {
      return [
        AcpDiffToolContent(
          path: path,
          oldText: oldText,
          newText: newText ?? '',
        ),
      ];
    }

    // Whole-file write/create (`Content` from agy acp `write_file`, `CodeContent`, `content`).
    final isWriteTool =
        kind == AcpToolKind.edit ||
        name == 'write_file' ||
        name == 'write_to_file';
    if (isWriteTool && path.isNotEmpty) {
      final body =
          _asNullableString(input['Content']) ??
          _asNullableString(input['CodeContent']) ??
          _asNullableString(input['file_text']) ??
          _asNullableString(input['content']);
      if (body != null && body.isNotEmpty) {
        return [AcpDiffToolContent(path: path, oldText: null, newText: body)];
      }
    }
    return const [];
  }

  AcpToolCall mergePatch(Map<String, Object?> patch) {
    final parsedPatchContent = patch['content'] is List
        ? [
            for (final raw in _asList(patch['content']))
              if (raw is Map)
                ?AcpToolContent.fromJson(Map<String, Object?>.from(raw)),
          ]
        : null;

    // Preserve earlier content/diffs when a status-only patch sends an empty
    // content array or omits previously sent diff blocks.
    List<AcpToolContent> mergedContent;
    if (parsedPatchContent == null || parsedPatchContent.isEmpty) {
      mergedContent = content;
    } else {
      final patchHasDiff = parsedPatchContent.any((c) => c is AcpDiffToolContent);
      final existingDiffs = [
        for (final c in content)
          if (c is AcpDiffToolContent) c,
      ];
      if (!patchHasDiff && existingDiffs.isNotEmpty) {
        mergedContent = [...existingDiffs, ...parsedPatchContent];
      } else {
        mergedContent = parsedPatchContent;
      }
    }

    final patchLocations = patch['locations'] is List
        ? _asList(patch['locations'])
              .whereType<Map>()
              .map((m) => AcpToolLocation.fromJson(Map<String, Object?>.from(m)))
              .toList()
        : null;

    final nextTitle = (_asNullableString(patch['title']) ?? '').isNotEmpty
        ? patch['title']! as String
        : title;
    final nextName = (_asNullableString(patch['name']) ?? '').isNotEmpty
        ? patch['name']! as String
        : name;
    final parsedStatus = AcpToolStatus.parseNullable(patch['status']);
    final explicitKind = patch.containsKey('kind')
        ? AcpToolKind.parse(patch['kind'])
        : AcpToolKind.other;
    final nextKind = explicitKind != AcpToolKind.other
        ? explicitKind
        : (kind != AcpToolKind.other
              ? kind
              : AcpToolKind.infer(name: nextName, title: nextTitle));
    final patchMeta = patch['_meta'] is Map
        ? Map<String, Object?>.from(patch['_meta']! as Map)
        : null;
    final mergedMeta = patchMeta == null
        ? meta
        : <String, Object?>{...?meta, ...patchMeta};

    return AcpToolCall(
      toolCallId: toolCallId,
      title: nextTitle,
      name: nextName,
      kind: nextKind,
      status: parsedStatus ?? status,
      locations: (patchLocations != null && patchLocations.isNotEmpty)
          ? patchLocations
          : locations,
      content: mergedContent,
      rawInput: patch['rawInput'] ?? patch['args'] ?? rawInput,
      rawOutput: patch['rawOutput'] ?? rawOutput,
      meta: mergedMeta,
    );
  }

  /// Merges a re-emitted `tool_call` frame without wiping already-accumulated
  /// diffs, content blocks, locations, arguments, outputs, or metadata.
  AcpToolCall mergeWith(AcpToolCall incoming) {
    List<AcpToolContent> mergedContent;
    if (incoming.content.isEmpty) {
      mergedContent = content;
    } else {
      final incomingHasDiff = incoming.content.any(
        (c) => c is AcpDiffToolContent,
      );
      final existingDiffs = [
        for (final c in content)
          if (c is AcpDiffToolContent) c,
      ];
      if (!incomingHasDiff && existingDiffs.isNotEmpty) {
        mergedContent = [...existingDiffs, ...incoming.content];
      } else {
        mergedContent = incoming.content;
      }
    }
    final nextTitle = incoming.title.trim().isNotEmpty ? incoming.title : title;
    final nextName = (incoming.name?.trim().isNotEmpty ?? false)
        ? incoming.name
        : name;
    final nextKind = incoming.kind != AcpToolKind.other
        ? incoming.kind
        : (kind != AcpToolKind.other
              ? kind
              : AcpToolKind.infer(name: nextName, title: nextTitle));
    final mergedMeta = incoming.meta == null
        ? meta
        : <String, Object?>{...?meta, ...incoming.meta!};
    return AcpToolCall(
      toolCallId: toolCallId,
      title: nextTitle,
      name: nextName,
      kind: nextKind,
      status: incoming.status,
      locations: incoming.locations.isNotEmpty ? incoming.locations : locations,
      content: mergedContent,
      rawInput: incoming.rawInput ?? rawInput,
      rawOutput: incoming.rawOutput ?? rawOutput,
      meta: mergedMeta,
    );
  }

  /// Returns a copy with [status] updated while preserving all other fields.
  AcpToolCall withStatus(AcpToolStatus nextStatus) => nextStatus == status
      ? this
      : AcpToolCall(
          toolCallId: toolCallId,
          title: title,
          name: name,
          kind: kind,
          status: nextStatus,
          locations: locations,
          content: content,
          rawInput: rawInput,
          rawOutput: rawOutput,
          meta: meta,
        );

  /// Extracts live checklist steps when `agy acp` emits the built-in
  /// `update_steps` tool call (instead of a separate `plan` session update).
  List<AcpPlanEntry>? get extractedPlanEntries {
    final toolName = name?.trim().toLowerCase();
    if (toolName != 'update_steps') return null;
    if (rawInput is! Map) return null;
    final rawSteps = (rawInput! as Map)['steps'];
    if (rawSteps is! List) return null;
    final entries = <AcpPlanEntry>[];
    for (final raw in rawSteps) {
      if (raw is! Map) continue;
      final map = Map<String, Object?>.from(raw);
      final text =
          (_asNullableString(map['title']) ??
                  _asNullableString(map['content']) ??
                  '')
              .trim();
      if (text.isEmpty) continue;
      entries.add(
        AcpPlanEntry(
          content: text,
          status: AcpPlanEntry.normalizeStatus(_asString(map['status'], 'pending')),
          priority: _asNullableString(map['priority']),
        ),
      );
    }
    return entries;
  }
}

enum AcpPermissionOptionKind {
  allowOnce,
  allowAlways,
  rejectOnce,
  rejectAlways,
  other;

  static AcpPermissionOptionKind parse(Object? raw) => switch (raw) {
    'allow_once' => allowOnce,
    'allow_always' => allowAlways,
    'reject_once' => rejectOnce,
    'reject_always' => rejectAlways,
    _ => other,
  };

  bool get isAllow => this == allowOnce || this == allowAlways;
}

class AcpPermissionOption {
  const AcpPermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  factory AcpPermissionOption.fromJson(Map<String, Object?> json) =>
      AcpPermissionOption(
        optionId: _asString(json['optionId']),
        name: _asString(json['name'], _asString(json['optionId'])),
        kind: AcpPermissionOptionKind.parse(json['kind']),
      );

  final String optionId;
  final String name;
  final AcpPermissionOptionKind kind;
}

class AcpPermissionRequest {
  const AcpPermissionRequest({
    required this.sessionId,
    required this.toolCall,
    required this.options,
  });

  factory AcpPermissionRequest.fromJson(Map<String, Object?> json) =>
      AcpPermissionRequest(
        sessionId: _asString(json['sessionId']),
        toolCall: AcpToolCall.fromJson(_asMap(json['toolCall'])),
        options: _asList(json['options'])
            .whereType<Map>()
            .map((m) => AcpPermissionOption.fromJson(Map<String, Object?>.from(m)))
            .toList(),
      );

  final String sessionId;
  final AcpToolCall toolCall;
  final List<AcpPermissionOption> options;
}

sealed class AcpPermissionOutcome {
  const AcpPermissionOutcome();
  Map<String, Object?> toJson();
}

final class AcpPermissionSelected extends AcpPermissionOutcome {
  const AcpPermissionSelected(this.optionId);
  final String optionId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'outcome': 'selected',
    'optionId': optionId,
  };
}

final class AcpPermissionCancelled extends AcpPermissionOutcome {
  const AcpPermissionCancelled();

  @override
  Map<String, Object?> toJson() => const <String, Object?>{
    'outcome': 'cancelled',
  };
}

class AcpPlanEntry {
  const AcpPlanEntry({
    required this.content,
    required this.status,
    this.priority,
  });

  factory AcpPlanEntry.fromJson(Map<String, Object?> json) => AcpPlanEntry(
    content: _asNullableString(json['content']) ?? _asString(json['title']),
    status: normalizeStatus(_asString(json['status'], 'pending')),
    priority: _asNullableString(json['priority']),
  );

  static String normalizeStatus(String raw) => switch (raw.trim().toLowerCase()) {
    'done' || 'complete' || 'completed' || 'finished' => 'completed',
    'in_progress' || 'inprogress' || 'running' || 'active' => 'in_progress',
    'failed' || 'fail' || 'error' => 'failed',
    'skipped' => 'skipped',
    'cancelled' || 'canceled' => 'cancelled',
    _ => 'pending',
  };

  final String content;
  final String status;
  final String? priority;

  bool get isCompleted => normalizeStatus(status) == 'completed';
  bool get isInProgress => normalizeStatus(status) == 'in_progress';
  bool get isFailed => normalizeStatus(status) == 'failed';
  bool get isSkipped =>
      normalizeStatus(status) == 'skipped' ||
      normalizeStatus(status) == 'cancelled';
}

class AcpSlashCommand {
  const AcpSlashCommand({
    required this.name,
    this.description,
    this.inputHint,
  });

  factory AcpSlashCommand.fromJson(Map<String, Object?> json) {
    final input = _asMap(json['input']);
    return AcpSlashCommand(
      name: _asString(json['name']),
      description: _asNullableString(json['description']),
      inputHint: _asNullableString(input['hint']),
    );
  }

  final String name;
  final String? description;
  final String? inputHint;
}

class AcpUsageInfo {
  const AcpUsageInfo({
    this.usedTokens,
    this.sizeTokens,
    this.inputTokens,
    this.outputTokens,
    this.thoughtTokens,
    this.cachedReadTokens,
    this.totalTokens,
    this.costAmount,
    this.costCurrency,
  });

  factory AcpUsageInfo.fromJson(Map<String, Object?> json) {
    final nested = _asMap(json['usage']);
    final src = nested.isNotEmpty ? {...json, ...nested} : json;
    final cost = _asMap(src['cost']);
    return AcpUsageInfo(
      usedTokens:
          _asInt(src['used']) ??
          _asInt(src['usedTokens']) ??
          _asInt(src['used_tokens']) ??
          _asInt(src['contextUsed']) ??
          _asInt(src['context_used']) ??
          _asInt(src['contextTokens']) ??
          _asInt(src['context_tokens']),
      sizeTokens:
          _asInt(src['size']) ??
          _asInt(src['sizeTokens']) ??
          _asInt(src['size_tokens']) ??
          _asInt(src['contextSize']) ??
          _asInt(src['context_size']) ??
          _asInt(src['contextWindow']) ??
          _asInt(src['context_window']) ??
          _asInt(src['maxTokens']) ??
          _asInt(src['max_tokens']) ??
          _asInt(src['limit']),
      inputTokens:
          _asInt(src['inputTokens']) ??
          _asInt(src['input_tokens']) ??
          _asInt(src['promptTokens']) ??
          _asInt(src['prompt_tokens']),
      outputTokens:
          _asInt(src['outputTokens']) ??
          _asInt(src['output_tokens']) ??
          _asInt(src['completionTokens']) ??
          _asInt(src['completion_tokens']),
      thoughtTokens:
          _asInt(src['thoughtTokens']) ??
          _asInt(src['thought_tokens']) ??
          _asInt(src['thinkingTokens']) ??
          _asInt(src['thinking_tokens']) ??
          _asInt(src['reasoningTokens']) ??
          _asInt(src['reasoning_tokens']),
      cachedReadTokens:
          _asInt(src['cachedReadTokens']) ??
          _asInt(src['cached_read_tokens']) ??
          _asInt(src['cacheReadTokens']) ??
          _asInt(src['cache_read_tokens']) ??
          _asInt(src['cacheReadInputTokens']) ??
          _asInt(src['cachedContentTokenCount']),
      totalTokens: _asInt(src['totalTokens']) ?? _asInt(src['total_tokens']),
      costAmount: (cost['amount'] as num?)?.toDouble(),
      costCurrency: _asNullableString(cost['currency']),
    );
  }

  final int? usedTokens;
  final int? sizeTokens;
  final int? inputTokens;
  final int? outputTokens;
  final int? thoughtTokens;
  final int? cachedReadTokens;
  final int? totalTokens;
  final double? costAmount;
  final String? costCurrency;

  /// Merges a newer partial usage frame (e.g. `session/prompt` result carrying
  /// `inputTokens`/`outputTokens` without `used`/`size`, or a `usage_update`
  /// carrying `used`/`size` without per-turn counts) while preserving prior
  /// non-null metrics.
  AcpUsageInfo merge(AcpUsageInfo? other) {
    if (other == null) return this;
    return AcpUsageInfo(
      usedTokens: other.usedTokens ?? usedTokens,
      sizeTokens: other.sizeTokens ?? sizeTokens,
      inputTokens: other.inputTokens ?? inputTokens,
      outputTokens: other.outputTokens ?? outputTokens,
      thoughtTokens: other.thoughtTokens ?? thoughtTokens,
      cachedReadTokens: other.cachedReadTokens ?? cachedReadTokens,
      totalTokens: other.totalTokens ?? totalTokens,
      costAmount: other.costAmount ?? costAmount,
      costCurrency: other.costCurrency ?? costCurrency,
    );
  }

  /// Best server-reported context token count: prefers explicit `usedTokens`
  /// from `usage_update`, falling back to `totalTokens` or `input + output + thought`.
  int? get effectiveUsedTokens {
    if (usedTokens != null) return usedTokens;
    if (totalTokens != null) return totalTokens;
    if (inputTokens != null || outputTokens != null || thoughtTokens != null) {
      return (inputTokens ?? 0) + (outputTokens ?? 0) + (thoughtTokens ?? 0);
    }
    return null;
  }

  /// Total tokens generated by the model in this turn (answer + thinking), when provided.
  int? get generatedTokens {
    if (outputTokens == null && thoughtTokens == null) return null;
    return (outputTokens ?? 0) + (thoughtTokens ?? 0);
  }
}

enum AcpStopReason {
  endTurn,
  maxTokens,
  maxTurnRequests,
  refusal,
  cancelled,
  unknown;

  static AcpStopReason parse(Object? raw) => switch (raw) {
    'end_turn' => endTurn,
    'max_tokens' => maxTokens,
    'max_turn_requests' => maxTurnRequests,
    'refusal' => refusal,
    'cancelled' => cancelled,
    _ => unknown,
  };
}

class AcpPromptResult {
  const AcpPromptResult({required this.stopReason, this.usage});

  factory AcpPromptResult.fromJson(Map<String, Object?> json) => AcpPromptResult(
    stopReason: AcpStopReason.parse(json['stopReason']),
    usage: json['usage'] is Map
        ? AcpUsageInfo.fromJson(Map<String, Object?>.from(json['usage']! as Map))
        : null,
  );

  final AcpStopReason stopReason;
  final AcpUsageInfo? usage;
}

/// Notification envelope delivered via `session/update`.
class AcpSessionNotification {
  const AcpSessionNotification({
    required this.sessionId,
    required this.update,
  });

  factory AcpSessionNotification.fromJson(Map<String, Object?> json) =>
      AcpSessionNotification(
        sessionId: _asString(json['sessionId']),
        update: AcpSessionUpdate.fromJson(_asMap(json['update'])),
      );

  final String sessionId;
  final AcpSessionUpdate update;
}

sealed class AcpSessionUpdate {
  const AcpSessionUpdate();

  static List<AcpPlanEntry> _parsePlanEntries(Map<String, Object?> json) {
    final direct = _asList(json['entries']);
    if (direct.isNotEmpty) {
      return direct
          .whereType<Map>()
          .map((m) => AcpPlanEntry.fromJson(Map<String, Object?>.from(m)))
          .toList();
    }
    final nestedPlan = json['plan'];
    if (nestedPlan is Map) {
      final nestedEntries = _asList(nestedPlan['entries']);
      if (nestedEntries.isNotEmpty) {
        return nestedEntries
            .whereType<Map>()
            .map((m) => AcpPlanEntry.fromJson(Map<String, Object?>.from(m)))
            .toList();
      }
      final markdown = _asNullableString(nestedPlan['content']);
      if (markdown != null && markdown.trim().isNotEmpty) {
        final lines = markdown
            .replaceAll('\r\n', '\n')
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final checklist = <AcpPlanEntry>[];
        final checkRe = RegExp(r'^[-*]\s+\[([ xX~-])\]\s+(.+)$');
        for (final line in lines) {
          final m = checkRe.firstMatch(line);
          if (m != null) {
            final mark = m.group(1)!.toLowerCase();
            final status = switch (mark) {
              'x' => 'completed',
              '~' => 'in_progress',
              '-' => 'skipped',
              _ => 'pending',
            };
            checklist.add(AcpPlanEntry(content: m.group(2)!.trim(), status: status));
          }
        }
        if (checklist.isNotEmpty) return checklist;
      }
    }
    return const [];
  }

  static AcpSessionUpdate fromJson(Map<String, Object?> json) {
    final kind = _asString(json['sessionUpdate']);
    final rawMeta = json['_meta'];
    final meta = rawMeta is Map ? Map<String, Object?>.from(rawMeta) : null;
    switch (kind) {
      case 'agent_message_chunk':
        return AgentMessageChunkUpdate(
          AcpContentBlock.fromJson(_asMap(json['content'])),
        );
      case 'agent_thought_chunk':
        return AgentThoughtChunkUpdate(
          AcpContentBlock.fromJson(_asMap(json['content'])),
        );
      case 'user_message_chunk':
        return UserMessageChunkUpdate(
          AcpContentBlock.fromJson(_asMap(json['content'])),
        );
      case 'tool_call':
        return ToolCallCreatedUpdate(AcpToolCall.fromJson(json));
      case 'tool_call_update':
        return ToolCallPatchedUpdate(
          toolCallId: _asString(json['toolCallId']),
          patch: json,
        );
      case 'plan' || 'plan_update':
        return PlanUpdate(_parsePlanEntries(json));
      case 'plan_removed':
        return const PlanUpdate([]);
      case 'available_commands_update':
        return AvailableCommandsUpdate(
          _asList(json['availableCommands'])
              .whereType<Map>()
              .map((m) => AcpSlashCommand.fromJson(Map<String, Object?>.from(m)))
              .toList(),
        );
      case 'current_mode_update':
        return CurrentModeUpdate(_asString(json['currentModeId']));
      case 'config_option_update':
        return ConfigOptionUpdate(
          _asList(json['configOptions'])
              .whereType<Map>()
              .map((m) => AcpConfigOption.fromJson(Map<String, Object?>.from(m)))
              .toList(),
        );
      case 'session_info_update':
        return SessionInfoUpdate(
          title: _asNullableString(json['title']),
          updatedAt: DateTime.tryParse(_asString(json['updatedAt'])),
        );
      case 'usage_update':
        return UsageSessionUpdate(AcpUsageInfo.fromJson(json));
      case 'compaction_update' || 'compaction_summary_chunk':
        final statusText =
            _asNullableString(json['status']) ??
            _asNullableString(json['state']) ??
            'compacting';
        final detailText =
            _asNullableString(json['message']) ??
            _asNullableString(json['detail']) ??
            _asNullableString(json['summary']) ??
            (json['content'] is Map
                ? _asNullableString((json['content']! as Map)['text'])
                : null);
        return AgentStatusUpdate(
          kind: kind,
          status: statusText,
          detail: detailText,
          meta: meta,
          raw: json,
        );
      case 'status' ||
          'status_update' ||
          'session_status' ||
          'agent_status' ||
          'progress' ||
          'step_update' ||
          'notice' ||
          'activity' ||
          'task_notification' ||
          'background_turn_started' ||
          'background_turn_completed':
        final statusText =
            _asNullableString(json['status']) ??
            _asNullableString(json['state']) ??
            _asNullableString(json['phase']) ??
            _asNullableString(json['title']) ??
            kind;
        final detailText =
            _asNullableString(json['message']) ??
            _asNullableString(json['detail']) ??
            _asNullableString(json['text']) ??
            _asNullableString(json['description']) ??
            _asNullableString(json['content']) ??
            (json['content'] is Map
                ? _asNullableString((json['content']! as Map)['text'])
                : null);
        return AgentStatusUpdate(
          kind: kind,
          status: statusText,
          detail: detailText,
          meta: meta,
          raw: json,
        );
      default:
        return UnknownSessionUpdate(kind: kind, meta: meta, raw: json);
    }
  }
}

final class AgentMessageChunkUpdate extends AcpSessionUpdate {
  const AgentMessageChunkUpdate(this.content);
  final AcpContentBlock content;
}

final class AgentThoughtChunkUpdate extends AcpSessionUpdate {
  const AgentThoughtChunkUpdate(this.content);
  final AcpContentBlock content;
}

final class UserMessageChunkUpdate extends AcpSessionUpdate {
  const UserMessageChunkUpdate(this.content);
  final AcpContentBlock content;
}

final class ToolCallCreatedUpdate extends AcpSessionUpdate {
  const ToolCallCreatedUpdate(this.toolCall);
  final AcpToolCall toolCall;
}

final class ToolCallPatchedUpdate extends AcpSessionUpdate {
  const ToolCallPatchedUpdate({required this.toolCallId, required this.patch});
  final String toolCallId;
  final Map<String, Object?> patch;
}

final class PlanUpdate extends AcpSessionUpdate {
  const PlanUpdate(this.entries);
  final List<AcpPlanEntry> entries;
}

final class AvailableCommandsUpdate extends AcpSessionUpdate {
  const AvailableCommandsUpdate(this.commands);
  final List<AcpSlashCommand> commands;
}

final class CurrentModeUpdate extends AcpSessionUpdate {
  const CurrentModeUpdate(this.currentModeId);
  final String currentModeId;
}

final class ConfigOptionUpdate extends AcpSessionUpdate {
  const ConfigOptionUpdate(this.configOptions);
  final List<AcpConfigOption> configOptions;
}

final class SessionInfoUpdate extends AcpSessionUpdate {
  const SessionInfoUpdate({this.title, this.updatedAt});
  final String? title;
  final DateTime? updatedAt;
}

final class UsageSessionUpdate extends AcpSessionUpdate {
  const UsageSessionUpdate(this.usage);
  final AcpUsageInfo usage;
}

final class AgentStatusUpdate extends AcpSessionUpdate {
  const AgentStatusUpdate({
    required this.kind,
    required this.status,
    this.detail,
    this.meta,
    this.raw = const {},
  });

  final String kind;
  final String status;
  final String? detail;
  final Map<String, Object?>? meta;
  final Map<String, Object?> raw;
}

final class UnknownSessionUpdate extends AcpSessionUpdate {
  const UnknownSessionUpdate({
    required this.kind,
    this.meta,
    required this.raw,
  });
  final String kind;
  final Map<String, Object?>? meta;
  final Map<String, Object?> raw;
}
