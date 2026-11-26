// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:acp_client/acp_client.dart';

/// Well-known POSIX / Android root directories that appear after a `../../../../`
/// traversal prefix when `agy acp` computes paths relative to its own launch cwd
/// inside Android's deep app sandbox (`/data/user/0/<pkg>/files/runtime/home/workspace`).
const _kRootSegments = <String>{
  'storage',
  'sdcard',
  'mnt',
  'data',
  'system',
  'vendor',
  'product',
  'apex',
  'home',
  'root',
  'usr',
  'etc',
  'var',
  'opt',
  'tmp',
  'proc',
  'dev',
  'bin',
  'lib',
  'Users',
};

final _kFileTitlePrefix = RegExp(
  r'^(?:(?:view|read|reading|open|opening|edit|editing|write|writing|create|creating|delete|deleting|remove|removing|update|updating|modify|modifying|patch|patching|inspect|inspecting|list|listing)\s+)?(?:file|directory|dir|folder|path)?\s*:?\s+',
  caseSensitive: false,
);

final _kTrailingLineSuffix = RegExp(
  r'(?:\s*\((?:lines?\s*)?(\d+(?:\s*[-–]\s*\d+)?)\)|\s*\[L?(\d+(?:\s*[-–]\s*L?\d+)?)\]|:(\d+(?:-\d+)?))$',
  caseSensitive: false,
);

final _kEmbeddedParentTraversal = RegExp(
  r'(?:\.\./)+[^\s"' "'" r'`<>|;,\)\]]+',
);

final _kAndroidAppHome = RegExp(
  r'^/data/(?:user/\d+|data)/[^/]+/files/runtime/home(?=/|$)',
);

/// Normalizes a raw file path from an ACP tool call, collapsing `../../../../../../`
/// parent traversals, `file://` URIs, redundant slashes, and `./` prefixes.
String normalizeToolPath(String rawPath, {String? baseCwd}) {
  var p = rawPath.trim();
  if (p.isEmpty) return '';

  // Strip matching outer quotes or backticks.
  if (p.length >= 2) {
    final first = p[0];
    final last = p[p.length - 1];
    if ((first == '"' && last == '"') ||
        (first == "'" && last == "'") ||
        (first == '`' && last == '`')) {
      p = p.substring(1, p.length - 1).trim();
    }
  }

  if (p.startsWith('file://')) {
    p = p.substring('file://'.length);
    try {
      p = Uri.decodeFull(p);
    } catch (_) {}
  }

  p = p.replaceAll(RegExp(r'/{2,}'), '/');

  // Handle leading `../` chains (e.g. `../../../../../../storage/emulated/0/...`).
  if (p.startsWith('../')) {
    var rest = p;
    while (rest.startsWith('../')) {
      rest = rest.substring(3);
    }
    if (rest.isEmpty) return '/';
    final firstSeg = rest.split('/').first;
    if (_kRootSegments.contains(firstSeg)) {
      return _normalizePosix('/$rest');
    }
    if (baseCwd != null && baseCwd.trim().isNotEmpty) {
      final cleanBase = baseCwd.trim().replaceAll(RegExp(r'/{2,}'), '/');
      return _normalizePosix('$cleanBase/$p');
    }
    return _normalizePosix(rest);
  }

  if (p.startsWith('/')) {
    return _normalizePosix(p);
  }

  if (p.startsWith('./')) {
    p = p.substring(2);
  }
  return _normalizePosix(p);
}

String _normalizePosix(String path) {
  final isAbs = path.startsWith('/');
  final parts = <String>[];
  for (final seg in path.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (!isAbs) {
        parts.add('..');
      }
    } else {
      parts.add(seg);
    }
  }
  if (isAbs) {
    return '/${parts.join('/')}';
  }
  return parts.isEmpty ? '.' : parts.join('/');
}

String _canonicalForPrefix(String p) {
  var out = p;
  if (out.endsWith('/') && out.length > 1) {
    out = out.substring(0, out.length - 1);
  }
  if (out == '/sdcard') return '/storage/emulated/0';
  if (out.startsWith('/sdcard/')) {
    return '/storage/emulated/0${out.substring('/sdcard'.length)}';
  }
  return out;
}

/// Formats a normalized path cleanly for human display (mirroring DSH Go's `displayPath`):
/// 1. Resolves `../../../../../../` noise.
/// 2. Strips the active [workspaceCwd] prefix when the file lives inside it.
/// 3. Shortens `/storage/emulated/0/...` -> `/sdcard/...` and Android app runtime home -> `~/...`.
String displayToolPath(String rawPath, {String? workspaceCwd}) {
  final clean = normalizeToolPath(rawPath, baseCwd: workspaceCwd);
  if (clean.isEmpty) return '';

  if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
    final canonClean = _canonicalForPrefix(clean);
    final canonWs = _canonicalForPrefix(
      normalizeToolPath(workspaceCwd),
    );
    if (canonWs.isNotEmpty && canonWs != '/') {
      if (canonClean == canonWs) return '.';
      if (canonClean.startsWith('$canonWs/')) {
        return canonClean.substring(canonWs.length + 1);
      }
    }
  }

  if (clean == '/storage/emulated/0') return '/sdcard';
  if (clean.startsWith('/storage/emulated/0/')) {
    return '/sdcard${clean.substring('/storage/emulated/0'.length)}';
  }

  if (_kAndroidAppHome.hasMatch(clean)) {
    final shortened = clean.replaceFirst(_kAndroidAppHome, '~');
    return shortened.isEmpty ? '~' : shortened;
  }

  return clean;
}

/// Estimates visual column width (CJK characters count as 2, ASCII as 1).
int _visualWidth(String text) {
  var w = 0;
  for (final r in text.runes) {
    w += r > 0x2E7F ? 2 : 1;
  }
  return w;
}

/// Keeps the filename and immediate parent folder visible on narrow mobile rows
/// by middle-eliding overly deep paths (e.g. `/sdcard/…/js/plugins.js`) while
/// leaving short / workspace-relative paths untouched.
String compactSingleLinePath(String path, {int maxVisualWidth = 34}) {
  if (_visualWidth(path) <= maxVisualWidth) return path;
  final isAbs = path.startsWith('/');
  final rawSegments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (rawSegments.length <= 2) return path;

  final head = isAbs ? '/${rawSegments.first}' : rawSegments.first;
  final last = rawSegments.last;
  final parent = rawSegments[rawSegments.length - 2];

  if (rawSegments.length >= 4) {
    final withParent = '$head/…/$parent/$last';
    if (_visualWidth(withParent) <= maxVisualWidth + 6) {
      return withParent;
    }
  }
  return '$head/…/$last';
}

({String path, String? lineSuffix}) _splitLineSuffix(String input) {
  final match = _kTrailingLineSuffix.firstMatch(input);
  if (match == null) return (path: input, lineSuffix: null);
  final range = (match.group(1) ?? match.group(2) ?? match.group(3) ?? '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('–', '-')
      .replaceAll(RegExp(r'L', caseSensitive: false), '');
  final before = input.substring(0, match.start).trimRight();
  return (path: before, lineSuffix: range.isEmpty ? null : ':$range');
}

String? _extractPathFromRawInput(Object? rawInput) {
  if (rawInput is! Map) return null;
  for (final key in const [
    'Path',
    'file_path',
    'filePath',
    'filepath',
    'path',
    'AbsolutePath',
    'TargetFile',
    'target_file',
    'DirectoryPath',
    'SearchPath',
    'uri',
  ]) {
    final val = rawInput[key];
    if (val is String && val.trim().isNotEmpty) return val.trim();
  }
  return null;
}

String? _extractStringArg(Object? rawInput, List<String> keys) {
  if (rawInput is! Map) return null;
  for (final key in keys) {
    final val = rawInput[key];
    if (val is String && val.trim().isNotEmpty) return val.trim();
  }
  return null;
}

/// Scrubs any embedded `../../../../../../storage/...` tokens inside arbitrary
/// tool titles or shell commands so walls of `../` never pollute the UI.
String scrubTraversalPaths(String text, {String? workspaceCwd}) {
  if (!text.contains('../')) return text;
  return text.replaceAllMapped(_kEmbeddedParentTraversal, (m) {
    final token = m.group(0)!;
    return displayToolPath(token, workspaceCwd: workspaceCwd);
  });
}

/// Formats a concise, readable single-line summary for an [AcpToolCall] row.
///
/// Mirrors DSH Go's `ToolView.summary`:
/// - File tools (`read`/`edit`/`delete`/`move`): prefers structured `locations` or
///   `rawInput` path, strips redundant `"File "`/`"Read "` prefixes, resolves
///   `../../../../../../` traversals, strips active [workspaceCwd], and middle-elides
///   overly deep external paths so the filename is always legible.
/// - `search`: formats `pattern · path` when available, otherwise scrubs paths.
/// - `execute`: one-line command with any `../../..` path noise cleaned.
String formatToolSummary(
  AcpToolCall tc, {
  String? workspaceCwd,
  bool compact = true,
}) {
  String oneLine(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  final isFileKind =
      tc.kind == AcpToolKind.read ||
      tc.kind == AcpToolKind.edit ||
      tc.kind == AcpToolKind.delete ||
      tc.kind == AcpToolKind.move;

  if (isFileKind) {
    final titleSplit = _splitLineSuffix(tc.title.trim());
    String? candidate;
    if (tc.locations.isNotEmpty && tc.locations.first.path.trim().isNotEmpty) {
      candidate = tc.locations.first.path.trim();
    } else if (_extractPathFromRawInput(tc.rawInput) case final p?) {
      candidate = p;
    } else if (titleSplit.path.isNotEmpty) {
      final stripped = titleSplit.path.replaceFirst(_kFileTitlePrefix, '').trim();
      candidate = stripped.isNotEmpty ? stripped : titleSplit.path;
    }

    if (candidate != null && candidate.isNotEmpty) {
      final display = displayToolPath(candidate, workspaceCwd: workspaceCwd);
      final shown = compact ? compactSingleLinePath(display) : display;
      final suffix = titleSplit.lineSuffix;
      return suffix != null ? '$shown$suffix' : shown;
    }
  }

  if (tc.kind == AcpToolKind.search) {
    final pattern = _extractStringArg(tc.rawInput, const [
      'pattern',
      'query',
      'Query',
      'Pattern',
    ]);
    final where =
        (tc.locations.isNotEmpty ? tc.locations.first.path : null) ??
        _extractPathFromRawInput(tc.rawInput);
    if (pattern != null && pattern.isNotEmpty) {
      if (where != null && where.trim().isNotEmpty) {
        final d = displayToolPath(where, workspaceCwd: workspaceCwd);
        final shown = compact ? compactSingleLinePath(d, maxVisualWidth: 24) : d;
        return '${oneLine(pattern)} · $shown';
      }
      return oneLine(pattern);
    }
  }

  if (tc.kind == AcpToolKind.execute) {
    final cmd = _extractStringArg(tc.rawInput, const [
      'command',
      'CommandLine',
      'cmd',
    ]);
    final raw = (cmd != null && cmd.isNotEmpty) ? cmd : tc.title;
    if (raw.trim().isNotEmpty) {
      return oneLine(scrubTraversalPaths(raw, workspaceCwd: workspaceCwd));
    }
  }

  if (tc.title.trim().isNotEmpty) {
    return oneLine(scrubTraversalPaths(tc.title, workspaceCwd: workspaceCwd));
  }
  if (tc.locations.isNotEmpty && tc.locations.first.path.trim().isNotEmpty) {
    final display = displayToolPath(
      tc.locations.first.path,
      workspaceCwd: workspaceCwd,
    );
    return compact ? compactSingleLinePath(display) : display;
  }
  return tc.name ?? tc.kind.name;
}

final _kBareToolNameRe = RegExp(r'^[a-z0-9]+(?:_[a-z0-9]+)+$');
final _kBarePathLikeRe = RegExp(
  r'^(?:file\s+)?(?:file://|/|\.\./|\./|~/)',
  caseSensitive: false,
);
final _kAgyTimestampHeaderRe = RegExp(
  r'^(?:(?:Created|Completed) At:\s+[^\n]*\n)+',
);

/// Returns the model/engine's own native action/status description for [tc]
/// (preferring `rawInput.toolAction` while active, `rawInput.toolSummary` when done,
/// or a descriptive ACP `title`), scrubbing only Android `../../../../` traversal noise.
///
/// Returns `null` when neither the model nor `agy acp` supplied a native descriptive
/// label (e.g. only a bare path or bare internal tool identifier).
String? extractNativeToolLabel(
  AcpToolCall tc, {
  String? workspaceCwd,
}) {
  String clean(String raw) {
    var out = scrubTraversalPaths(
      raw.trim().replaceAll(RegExp(r'\s+'), ' '),
      workspaceCwd: workspaceCwd,
    );
    if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
      final canonWs = _canonicalForPrefix(normalizeToolPath(workspaceCwd));
      if (canonWs.isNotEmpty && canonWs != '/') {
        out = out.replaceAll('$canonWs/', '');
      }
    }
    out = out.replaceAll('/storage/emulated/0/', '/sdcard/');
    out = out.replaceAll(_kAndroidAppHome, '~');
    return out.trim();
  }

  final action = tc.nativeToolAction;
  final summary = tc.nativeToolSummary;
  final rawTitle = tc.title.trim().replaceAll(RegExp(r'\s+'), ' ');
  final titleIsBare =
      rawTitle.isEmpty ||
      (tc.name != null && rawTitle.toLowerCase() == tc.name!.trim().toLowerCase()) ||
      _kBareToolNameRe.hasMatch(rawTitle) ||
      _kBarePathLikeRe.hasMatch(rawTitle);
  final descriptiveTitle = titleIsBare ? null : rawTitle;

  if (tc.status.isActive) {
    final pick = action ?? descriptiveTitle ?? summary;
    if (pick != null && pick.isNotEmpty) return clean(pick);
  } else {
    final pick = summary ?? descriptiveTitle ?? action;
    if (pick != null && pick.isNotEmpty) return clean(pick);
  }

  if (tc.name == 'invoke_subagent' && tc.rawInput is Map) {
    final role = _extractStringArg(tc.rawInput, const ['Role', 'role', 'TypeName']);
    if (role != null && role.isNotEmpty) return clean(role);
  }

  return null;
}

/// Formats what [tc] is natively doing for live status bars / headers:
/// uses the exact native `toolAction` / `title` / `toolSummary` when available,
/// falling back directly to the factual target summary (path / command / tool name)
/// without inventing a guessed phase prefix.
String formatNativeToolLiveStatus(
  AcpToolCall tc, {
  String? workspaceCwd,
}) {
  final native = extractNativeToolLabel(tc, workspaceCwd: workspaceCwd);
  if (native != null && native.isNotEmpty) return native;
  return formatToolSummary(tc, workspaceCwd: workspaceCwd);
}

/// Strips the model-facing `Created At:` / `Completed At:` header lines that
/// `agy acp` prepends to command `rawOutput` / text content.
String stripAgyCommandResultHeader(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n');
  return normalized.replaceFirst(_kAgyTimestampHeaderRe, '').trim();
}
