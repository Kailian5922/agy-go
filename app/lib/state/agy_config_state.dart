import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'runtime_state.dart';
import 'workspaces_state.dart';

/// User-configured MCP server entry stored in `~/.gemini/antigravity-cli/settings.json`.
class AgyMcpServerEntry {
  const AgyMcpServerEntry({
    required this.name,
    required this.transport, // 'stdio' | 'http' | 'sse'
    this.command = '',
    this.args = const [],
    this.url = '',
    this.headers = const {},
    this.env = const {},
    this.enabled = true,
  });

  factory AgyMcpServerEntry.fromJson(String name, Map<String, Object?> json) {
    final url = json['url'] as String? ?? json['httpUrl'] as String? ?? '';
    final typeRaw = (json['type'] as String? ?? '').toLowerCase();
    final transport = url.isNotEmpty
        ? (typeRaw == 'sse' ? 'sse' : 'http')
        : 'stdio';
    return AgyMcpServerEntry(
      name: name,
      transport: transport,
      command: json['command'] as String? ?? '',
      args: (json['args'] as List?)?.whereType<String>().toList() ?? const [],
      url: url,
      headers: _stringMap(json['headers']),
      env: _stringMap(json['env']),
      enabled: json['disabled'] != true,
    );
  }

  final String name;
  final String transport;
  final String command;
  final List<String> args;
  final String url;
  final Map<String, String> headers;
  final Map<String, String> env;
  final bool enabled;

  bool get isRemote => transport == 'http' || transport == 'sse';

  Map<String, Object?> toJson() => <String, Object?>{
    if (isRemote) ...{
      'type': transport,
      'url': url,
      if (headers.isNotEmpty) 'headers': headers,
    } else ...{
      'command': command,
      if (args.isNotEmpty) 'args': args,
      if (env.isNotEmpty) 'env': env,
    },
    if (!enabled) 'disabled': true,
  };

  AcpMcpServerConfig? toAcpConfig() {
    if (!enabled) return null;
    if (isRemote) {
      if (url.trim().isEmpty) return null;
      return HttpMcpServerConfig(
        name: name,
        url: url.trim(),
        headers: headers,
        transportType: transport,
      );
    }
    if (command.trim().isEmpty) return null;
    return StdioMcpServerConfig(
      name: name,
      command: command.trim(),
      args: args,
      env: env,
    );
  }

  AgyMcpServerEntry copyWith({
    String? name,
    String? transport,
    String? command,
    List<String>? args,
    String? url,
    Map<String, String>? headers,
    Map<String, String>? env,
    bool? enabled,
  }) => AgyMcpServerEntry(
    name: name ?? this.name,
    transport: transport ?? this.transport,
    command: command ?? this.command,
    args: args ?? this.args,
    url: url ?? this.url,
    headers: headers ?? this.headers,
    env: env ?? this.env,
    enabled: enabled ?? this.enabled,
  );

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value != null)
          e.key as String: '${e.value}',
    };
  }
}

/// Discovered Agent Skill (`SKILL.md` under `~/.gemini/skills`, `.agents/skills`, or `.gemini/skills`).
class AgySkillItem {
  const AgySkillItem({
    required this.name,
    required this.description,
    required this.filePath,
    required this.scope, // 'global' | 'workspace'
  });

  final String name;
  final String description;
  final String filePath;
  final String scope;
}

/// Permission rule lists in `~/.gemini/antigravity-cli/settings.json` (`permissions.{allow,ask,deny}`).
class AgyPermissionRules {
  const AgyPermissionRules({
    this.allow = const [],
    this.ask = const [],
    this.deny = const [],
  });

  factory AgyPermissionRules.fromJson(Object? raw) {
    if (raw is! Map) return const AgyPermissionRules();
    return AgyPermissionRules(
      allow: (raw['allow'] as List?)?.whereType<String>().toList() ?? const [],
      ask: (raw['ask'] as List?)?.whereType<String>().toList() ?? const [],
      deny: (raw['deny'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  final List<String> allow;
  final List<String> ask;
  final List<String> deny;

  bool get isEmpty => allow.isEmpty && ask.isEmpty && deny.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'allow': allow,
    'ask': ask,
    'deny': deny,
  };

  AgyPermissionRules copyWith({
    List<String>? allow,
    List<String>? ask,
    List<String>? deny,
  }) => AgyPermissionRules(
    allow: allow ?? this.allow,
    ask: ask ?? this.ask,
    deny: deny ?? this.deny,
  );
}

class AgyConfigState {
  const AgyConfigState({
    this.loaded = false,
    this.settingsPath = '',
    this.rawSettingsJson = '{}',
    this.permissionRules = const AgyPermissionRules(),
    this.mcpServers = const [],
    this.skills = const [],
    this.globalMemoryPath = '',
    this.globalMemoryText = '',
    this.workspaceMemoryPath = '',
    this.workspaceMemoryText = '',
    this.error,
  });

  final bool loaded;
  final String settingsPath;
  final String rawSettingsJson;
  final AgyPermissionRules permissionRules;
  final List<AgyMcpServerEntry> mcpServers;
  final List<AgySkillItem> skills;
  final String globalMemoryPath;
  final String globalMemoryText;
  final String workspaceMemoryPath;
  final String workspaceMemoryText;
  final String? error;

  AgyConfigState copyWith({
    bool? loaded,
    String? settingsPath,
    String? rawSettingsJson,
    AgyPermissionRules? permissionRules,
    List<AgyMcpServerEntry>? mcpServers,
    List<AgySkillItem>? skills,
    String? globalMemoryPath,
    String? globalMemoryText,
    String? workspaceMemoryPath,
    String? workspaceMemoryText,
    String? error,
    bool clearError = false,
  }) => AgyConfigState(
    loaded: loaded ?? this.loaded,
    settingsPath: settingsPath ?? this.settingsPath,
    rawSettingsJson: rawSettingsJson ?? this.rawSettingsJson,
    permissionRules: permissionRules ?? this.permissionRules,
    mcpServers: mcpServers ?? this.mcpServers,
    skills: skills ?? this.skills,
    globalMemoryPath: globalMemoryPath ?? this.globalMemoryPath,
    globalMemoryText: globalMemoryText ?? this.globalMemoryText,
    workspaceMemoryPath: workspaceMemoryPath ?? this.workspaceMemoryPath,
    workspaceMemoryText: workspaceMemoryText ?? this.workspaceMemoryText,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Manages Antigravity CLI native files on device:
/// - `~/.gemini/antigravity-cli/settings.json` (`permissions`, `mcpServers`, raw editor)
/// - `~/.gemini/GEMINI.md` & `<workspace>/GEMINI.md`
/// - Agent Skills under `~/.gemini/skills`, `<workspace>/.agents/skills`, `<workspace>/.gemini/skills`
class AgyConfigController extends Notifier<AgyConfigState> {
  @override
  AgyConfigState build() {
    final home = ref.watch(
      localRuntimeProvider.select((s) => s.status.homePath),
    );
    final cwd = ref.watch(effectiveWorkingDirProvider);
    unawaited(_reload(home, cwd));
    return AgyConfigState(
      settingsPath: _settingsPathFor(home),
      globalMemoryPath: _globalMemoryPathFor(home),
      workspaceMemoryPath: _workspaceMemoryPathFor(cwd),
    );
  }

  static String _settingsPathFor(String? home) {
    final root = (home != null && home.isNotEmpty)
        ? home
        : (Platform.environment['HOME'] ?? Directory.current.path);
    return '$root/.gemini/antigravity-cli/settings.json';
  }

  static String _globalMemoryPathFor(String? home) {
    final root = (home != null && home.isNotEmpty)
        ? home
        : (Platform.environment['HOME'] ?? Directory.current.path);
    return '$root/.gemini/GEMINI.md';
  }

  static String _workspaceMemoryPathFor(String cwd) {
    final clean = cwd.endsWith('/') && cwd.length > 1
        ? cwd.substring(0, cwd.length - 1)
        : cwd;
    return '$clean/GEMINI.md';
  }

  Future<void> refresh() async {
    final home = ref.read(localRuntimeProvider).status.homePath;
    final cwd = ref.read(effectiveWorkingDirProvider);
    await _reload(home, cwd);
  }

  Future<void> _reload(String? home, String cwd) async {
    final settingsPath = _settingsPathFor(home);
    final globalMemPath = _globalMemoryPathFor(home);
    final wsMemPath = _workspaceMemoryPathFor(cwd);

    Map<String, Object?> map = {};
    String rawJson = '{}';
    try {
      final f = File(settingsPath);
      if (await f.exists()) {
        rawJson = await f.readAsString();
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          map = Map<String, Object?>.from(decoded);
        }
      }
    } catch (_) {}

    final permRules = AgyPermissionRules.fromJson(map['permissions']);
    final mcps = <AgyMcpServerEntry>[];
    if (map['mcpServers'] is Map) {
      for (final entry in (map['mcpServers'] as Map).entries) {
        if (entry.key is String && entry.value is Map) {
          mcps.add(
            AgyMcpServerEntry.fromJson(
              entry.key as String,
              Map<String, Object?>.from(entry.value as Map),
            ),
          );
        }
      }
    }

    final globalMem = await _safeReadText(globalMemPath);
    final wsMem = await _safeReadText(wsMemPath);
    final skills = await _scanSkills(home, cwd);

    if (!ref.mounted) return;
    state = AgyConfigState(
      loaded: true,
      settingsPath: settingsPath,
      rawSettingsJson: const JsonEncoder.withIndent('  ').convert(map),
      permissionRules: permRules,
      mcpServers: mcps,
      skills: skills,
      globalMemoryPath: globalMemPath,
      globalMemoryText: globalMem,
      workspaceMemoryPath: wsMemPath,
      workspaceMemoryText: wsMem,
    );
  }

  Future<String> _safeReadText(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return '';
  }

  Future<List<AgySkillItem>> _scanSkills(String? home, String cwd) async {
    final root = (home != null && home.isNotEmpty)
        ? home
        : (Platform.environment['HOME'] ?? '');
    final searchDirs = <(String, String)>[
      if (root.isNotEmpty) ('$root/.gemini/skills', 'global'),
      if (root.isNotEmpty) ('$root/.agents/skills', 'global'),
      if (cwd.isNotEmpty) ('$cwd/.agents/skills', 'workspace'),
      if (cwd.isNotEmpty) ('$cwd/.gemini/skills', 'workspace'),
    ];
    final seen = <String>{};
    final out = <AgySkillItem>[];

    for (final (dirPath, scope) in searchDirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final skillFile = File('${entity.path}/SKILL.md');
          if (!await skillFile.exists()) continue;
          final parsed = await _parseSkillFile(skillFile, entity.path, scope);
          if (parsed != null && seen.add(parsed.name)) {
            out.add(parsed);
          }
        }
      } catch (_) {}
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<AgySkillItem?> _parseSkillFile(
    File file,
    String dirPath,
    String scope,
  ) async {
    try {
      final content = await file.readAsString();
      var name = dirPath.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'skill';
      var description = '';
      final fm = RegExp(r'^---\s*\n([\s\S]*?)\n---').firstMatch(content);
      if (fm != null) {
        final yaml = fm.group(1)!;
        final nameMatch = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(yaml);
        final descMatch = RegExp(r'^description:\s*(.+)$', multiLine: true).firstMatch(yaml);
        if (nameMatch != null) {
          name = nameMatch.group(1)!.trim().replaceAll(RegExp(r'^["\x27]|["\x27]$'), '');
        }
        if (descMatch != null) {
          description = descMatch.group(1)!.trim().replaceAll(RegExp(r'^["\x27]|["\x27]$'), '');
        }
      }
      if (description.isEmpty) {
        final firstLine = content
            .split('\n')
            .map((l) => l.trim())
            .firstWhere(
              (l) => l.isNotEmpty && !l.startsWith('---') && !l.startsWith('#'),
              orElse: () => 'Agent Skill',
            );
        description = firstLine;
      }
      return AgySkillItem(
        name: name,
        description: description,
        filePath: file.path,
        scope: scope,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> _readSettingsMap() async {
    final f = File(state.settingsPath);
    if (!await f.exists()) return {};
    try {
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return {};
  }

  Future<void> _writeSettingsMap(Map<String, Object?> map) async {
    final f = File(state.settingsPath);
    await f.parent.create(recursive: true);
    final pretty = const JsonEncoder.withIndent('  ').convert(map);
    await f.writeAsString('$pretty\n');
    await refresh();
  }

  Future<void> addPermissionRule(String listName, String rule) async {
    final clean = rule.trim();
    if (clean.isEmpty) return;
    final current = state.permissionRules;
    final next = switch (listName) {
      'allow' => current.copyWith(
        allow: {...current.allow, clean}.toList(),
      ),
      'ask' => current.copyWith(
        ask: {...current.ask, clean}.toList(),
      ),
      'deny' => current.copyWith(
        deny: {...current.deny, clean}.toList(),
      ),
      _ => current,
    };
    final map = await _readSettingsMap();
    map['permissions'] = next.toJson();
    await _writeSettingsMap(map);
  }

  Future<void> removePermissionRule(String listName, String rule) async {
    final current = state.permissionRules;
    final next = switch (listName) {
      'allow' => current.copyWith(
        allow: current.allow.where((r) => r != rule).toList(),
      ),
      'ask' => current.copyWith(
        ask: current.ask.where((r) => r != rule).toList(),
      ),
      'deny' => current.copyWith(
        deny: current.deny.where((r) => r != rule).toList(),
      ),
      _ => current,
    };
    final map = await _readSettingsMap();
    map['permissions'] = next.toJson();
    await _writeSettingsMap(map);
  }

  Future<void> upsertMcpServer(AgyMcpServerEntry entry) async {
    final map = await _readSettingsMap();
    final servers = map['mcpServers'] is Map
        ? Map<String, Object?>.from(map['mcpServers'] as Map)
        : <String, Object?>{};
    servers[entry.name.trim()] = entry.toJson();
    map['mcpServers'] = servers;
    await _writeSettingsMap(map);
  }

  Future<void> deleteMcpServer(String name) async {
    final map = await _readSettingsMap();
    if (map['mcpServers'] is Map) {
      final servers = Map<String, Object?>.from(map['mcpServers'] as Map)
        ..remove(name);
      map['mcpServers'] = servers;
      await _writeSettingsMap(map);
    }
  }

  Future<String?> saveRawSettingsJson(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return '根对象必须是 JSON Object ({...})';
      await _writeSettingsMap(Map<String, Object?>.from(decoded));
      return null;
    } catch (e) {
      return 'JSON 格式错误：$e';
    }
  }

  Future<void> saveMemoryFile({
    required bool global,
    required String content,
  }) async {
    final path = global ? state.globalMemoryPath : state.workspaceMemoryPath;
    if (path.isEmpty) return;
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
    await refresh();
  }

  Future<void> createSkill({
    required String name,
    required String description,
    required String body,
    bool global = true,
  }) async {
    final safe = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-]'), '-');
    if (safe.isEmpty) return;
    final home = ref.read(localRuntimeProvider).status.homePath;
    final cwd = ref.read(effectiveWorkingDirProvider);
    final base = global
        ? '${home ?? Platform.environment['HOME'] ?? Directory.current.path}/.gemini/skills'
        : '$cwd/.agents/skills';
    final file = File('$base/$safe/SKILL.md');
    await file.parent.create(recursive: true);
    final doc = '''---
name: $safe
description: ${description.trim()}
---

${body.trim()}
''';
    await file.writeAsString(doc);
    await refresh();
  }
}

final agyConfigProvider = NotifierProvider<AgyConfigController, AgyConfigState>(
  AgyConfigController.new,
);
