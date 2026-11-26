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

  static AcpToolKind parse(Object? raw) => switch (raw) {
    'read' => read,
    'edit' => edit,
    'delete' => delete,
    'move' => move,
    'search' => search,
    'execute' => execute,
    'think' => think,
    'fetch' => fetch,
    'switch_mode' => switchMode,
    _ => other,
  };
}

enum AcpToolStatus {
  pending,
  inProgress,
  paused,
  completed,
  failed,
  cancelled;

  static AcpToolStatus parse(Object? raw) => switch (raw) {
    'pending' => pending,
    'in_progress' => inProgress,
    'paused' => paused,
    'completed' => completed,
    'failed' => failed,
    'cancelled' => cancelled,
    _ => pending,
  };

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
    switch (_asString(json['type'])) {
      case 'diff':
        return AcpDiffToolContent(
          path: _asString(json['path']),
          oldText: _asNullableString(json['oldText']),
          newText: _asString(json['newText']),
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
  });

  factory AcpToolCall.fromJson(Map<String, Object?> json) {
    final parsedContent = <AcpToolContent>[];
    for (final raw in _asList(json['content'])) {
      if (raw is Map) {
        final item = AcpToolContent.fromJson(Map<String, Object?>.from(raw));
        if (item != null) parsedContent.add(item);
      }
    }
    return AcpToolCall(
      toolCallId: _asString(json['toolCallId']),
      title: _asString(json['title']),
      name: _asNullableString(json['name']),
      kind: AcpToolKind.parse(json['kind']),
      status: AcpToolStatus.parse(json['status']),
      locations: _asList(json['locations'])
          .whereType<Map>()
          .map((m) => AcpToolLocation.fromJson(Map<String, Object?>.from(m)))
          .toList(),
      content: parsedContent,
      rawInput: json['rawInput'],
      rawOutput: json['rawOutput'],
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

  AcpToolCall mergePatch(Map<String, Object?> patch) {
    final patchContent = patch['content'] is List
        ? [
            for (final raw in _asList(patch['content']))
              if (raw is Map)
                ?AcpToolContent.fromJson(Map<String, Object?>.from(raw)),
          ]
        : null;

    return AcpToolCall(
      toolCallId: toolCallId,
      title: _asNullableString(patch['title']) ?? title,
      name: _asNullableString(patch['name']) ?? name,
      kind: patch.containsKey('kind') ? AcpToolKind.parse(patch['kind']) : kind,
      status: patch.containsKey('status')
          ? AcpToolStatus.parse(patch['status'])
          : status,
      locations: patch['locations'] is List
          ? _asList(patch['locations'])
              .whereType<Map>()
              .map((m) => AcpToolLocation.fromJson(Map<String, Object?>.from(m)))
              .toList()
          : locations,
      content: patchContent ?? content,
      rawInput: patch.containsKey('rawInput') ? patch['rawInput'] : rawInput,
      rawOutput: patch.containsKey('rawOutput') ? patch['rawOutput'] : rawOutput,
    );
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
    content: _asString(json['content']),
    status: _asString(json['status'], 'pending'),
    priority: _asNullableString(json['priority']),
  );

  final String content;
  final String status;
  final String? priority;
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
    this.costAmount,
    this.costCurrency,
  });

  factory AcpUsageInfo.fromJson(Map<String, Object?> json) {
    final cost = _asMap(json['cost']);
    return AcpUsageInfo(
      usedTokens: _asInt(json['used']),
      sizeTokens: _asInt(json['size']),
      costAmount: (cost['amount'] as num?)?.toDouble(),
      costCurrency: _asNullableString(cost['currency']),
    );
  }

  final int? usedTokens;
  final int? sizeTokens;
  final double? costAmount;
  final String? costCurrency;
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

  static AcpSessionUpdate fromJson(Map<String, Object?> json) {
    final kind = _asString(json['sessionUpdate']);
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
      case 'plan':
        return PlanUpdate(
          _asList(json['entries'])
              .whereType<Map>()
              .map((m) => AcpPlanEntry.fromJson(Map<String, Object?>.from(m)))
              .toList(),
        );
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
      default:
        return UnknownSessionUpdate(kind: kind, raw: json);
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

final class UnknownSessionUpdate extends AcpSessionUpdate {
  const UnknownSessionUpdate({required this.kind, required this.raw});
  final String kind;
  final Map<String, Object?> raw;
}
