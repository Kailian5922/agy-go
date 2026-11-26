import 'package:acp_client/acp_client.dart';

/// Current active stage within an in-flight turn.
enum TurnLivePhase {
  waiting,
  analyzing,
  thinking,
  working,
  responding,
  retrying,
}

/// Live health classification shown to distinguish active thinking from retries or stalls.
enum TurnHealthTone {
  /// Actively receiving tokens or running a tool.
  active,

  /// Quiet gap (15–59s) while model thinks server-side or prepares next step.
  waiting,

  /// Engine reported a transient network / rate-limit retry.
  retrying,

  /// Prolonged silence (>= 60s) with no active tool and no retry log.
  suspectedStall,
}

/// Parsed transient network / rate-limit retry notice emitted by `agy acp`.
class TurnRetryInfo {
  const TurnRetryInfo({
    required this.summary,
    required this.rawMessage,
    required this.timestamp,
    this.rateLimited = false,
    this.attempt,
    this.maxAttempts,
    this.retryInSeconds,
  });

  final String summary;
  final String rawMessage;
  final DateTime timestamp;
  final bool rateLimited;
  final int? attempt;
  final int? maxAttempts;
  final int? retryInSeconds;

  String compactPillLabel() {
    final prefix = rateLimited ? '限流重试' : '网络重试';
    if (attempt != null && maxAttempts != null) {
      return '$prefix ($attempt/$maxAttempts)…';
    }
    if (attempt != null) {
      return '$prefix #$attempt…';
    }
    if (retryInSeconds != null && retryInSeconds! > 0) {
      return '$prefix (${retryInSeconds}s)…';
    }
    return '$prefix中…';
  }
}

/// One timestamped milestone or warning recorded during the current turn.
class TurnActivityLogEntry {
  const TurnActivityLogEntry({
    required this.timestamp,
    required this.label,
    this.detail,
    this.isWarning = false,
  });

  final DateTime timestamp;
  final String label;
  final String? detail;
  final bool isWarning;
}

/// Derived real-time turn liveness snapshot for ActivityStrip, banners, and diagnostics sheet.
class TurnHealth {
  const TurnHealth({
    required this.tone,
    required this.silentSeconds,
    required this.pillText,
    required this.detailHeadline,
    this.bannerText,
  });

  final TurnHealthTone tone;
  final int silentSeconds;
  final String pillText;
  final String detailHeadline;
  final String? bannerText;

  bool get showAlertBanner => bannerText != null && bannerText!.isNotEmpty;
}

/// Formats seconds into compact Chinese duration (`42秒` or `2分05秒`).
String formatChineseDuration(int totalSeconds) {
  final secs = totalSeconds.clamp(0, 86400);
  if (secs < 60) return '$secs秒';
  final m = secs ~/ 60;
  final s = secs % 60;
  return '$m分${s.toString().padLeft(2, '0')}秒';
}

/// Formats seconds into ultra-compact duration for narrow inline pills (`42s` or `2m05s`).
String formatCompactDuration(int totalSeconds) {
  final secs = totalSeconds.clamp(0, 86400);
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  final s = secs % 60;
  return '${m}m${s.toString().padLeft(2, '0')}s';
}

/// Formats recency of the last received engine chunk/event (`刚刚` / `12 秒前` / `2 分 05 秒前`).
String formatLastSignalAge(int silentSeconds) {
  if (silentSeconds <= 3) return '刚刚';
  return '${formatChineseDuration(silentSeconds)}前';
}

/// Formats character count concisely (`320字` / `1.4k字`).
String formatCharCount(int chars) {
  if (chars < 1000) return '$chars字';
  return '${(chars / 1000).toStringAsFixed(1)}k字';
}

/// Estimates LLM token count for mixed CJK + ASCII/code text.
/// CJK characters average ~0.68 tokens/char and ASCII/Latin/code averages ~0.25 tokens/char.
double estimateTokenCount(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  var other = 0;
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if ((code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0x3000 && code <= 0x303F) ||
        (code >= 0x3040 && code <= 0x30FF) ||
        (code >= 0xAC00 && code <= 0xD7AF) ||
        (code >= 0xFF00 && code <= 0xFFEF)) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk * 0.68 + other * 0.25;
}

/// Formats tokens/second cleanly (`48.6 tok/s`, `124 tok/s`, or compact `49 tok/s`).
String formatTokensPerSecond(double tps, {bool compact = false}) {
  if (tps <= 0 || !tps.isFinite) return '';
  if (compact || tps >= 100) {
    return '${tps.round()} tok/s';
  }
  return '${tps.toStringAsFixed(1)} tok/s';
}

/// Tracks real-time sliding-window and active-generation tokens/second for a turn,
/// excluding long tool-execution or network-stall pauses so generation speed stays accurate.
class TurnSpeedTracker {
  static const _window = Duration(seconds: 5);
  static const _maxActiveGapSec = 1.5;

  final List<({DateTime time, double tokens})> _samples = [];
  double _totalEstimatedTokens = 0;
  double _activeSeconds = 0;
  DateTime? _firstChunkAt;
  DateTime? _lastChunkAt;

  double get totalEstimatedTokens => _totalEstimatedTokens;

  void reset() {
    _samples.clear();
    _totalEstimatedTokens = 0;
    _activeSeconds = 0;
    _firstChunkAt = null;
    _lastChunkAt = null;
  }

  /// Records a streamed thought or answer text chunk.
  void recordChunk(String text, DateTime now) {
    final est = estimateTokenCount(text);
    if (est <= 0) return;

    if (_firstChunkAt == null) {
      _firstChunkAt = now;
    } else if (_lastChunkAt != null) {
      final gapSec = now.difference(_lastChunkAt!).inMilliseconds / 1000.0;
      if (gapSec > 0) {
        _activeSeconds += gapSec > _maxActiveGapSec ? _maxActiveGapSec : gapSec;
      }
    }
    _lastChunkAt = now;
    _totalEstimatedTokens += est;

    _samples.add((time: now, tokens: est));
    final cutoff = now.subtract(_window);
    while (_samples.length > 1 && _samples.first.time.isBefore(cutoff)) {
      _samples.removeAt(0);
    }
  }

  /// Returns live tokens/second while chunks are actively flowing (null if idle/silent >= 8s).
  double? liveTokensPerSecond(DateTime now) {
    if (_lastChunkAt == null || _totalEstimatedTokens < 1.0) return null;
    if (now.difference(_lastChunkAt!).inMilliseconds >= 8000) return null;

    final cutoff = now.subtract(_window);
    var windowTokens = 0.0;
    DateTime? earliest;
    var count = 0;
    for (final s in _samples) {
      if (s.time.isBefore(cutoff)) continue;
      earliest ??= s.time;
      windowTokens += s.tokens;
      count++;
    }

    if (count >= 2 && earliest != null) {
      final spanSec = _lastChunkAt!.difference(earliest).inMilliseconds / 1000.0;
      if (spanSec >= 0.35) {
        return (windowTokens / spanSec).clamp(0.1, 9999.0);
      }
    }

    if (_activeSeconds >= 0.25) {
      return (_totalEstimatedTokens / _activeSeconds).clamp(0.1, 9999.0);
    }
    if (_firstChunkAt != null) {
      final elapsedSec = now.difference(_firstChunkAt!).inMilliseconds / 1000.0;
      if (elapsedSec >= 0.3) {
        return (_totalEstimatedTokens / elapsedSec).clamp(0.1, 9999.0);
      }
    }
    return null;
  }

  /// Computes final per-turn speed metrics, preferring server-reported generated tokens when available.
  AcpTurnMetrics? finalize({AcpUsageInfo? usage, DateTime? now}) {
    final serverTokens = usage?.generatedTokens;
    final hasServer = serverTokens != null && serverTokens > 0;
    final tokens = hasServer ? serverTokens : _totalEstimatedTokens.round();
    if (tokens <= 0) return null;

    var genSec = _activeSeconds;
    if (genSec < 0.2 && _firstChunkAt != null) {
      final end = _lastChunkAt ?? now ?? DateTime.now();
      genSec = end.difference(_firstChunkAt!).inMilliseconds / 1000.0;
    }
    if (genSec < 0.2) genSec = 0.2;

    return AcpTurnMetrics(
      tokensPerSecond: (tokens / genSec).clamp(0.1, 9999.0),
      tokens: tokens,
      generationSeconds: genSec,
      estimated: !hasServer,
    );
  }
}

/// Extracts the latest [maxLines] non-empty lines from long reasoning text so
/// collapsed live thinking previews always move forward instead of freezing on line 1.
String tailPreviewLines(String raw, {int maxLines = 3}) {
  final lines = raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';
  final start = lines.length > maxLines ? lines.length - maxLines : 0;
  return lines.sublist(start).join('\n');
}

/// Extracts the latest concise non-empty heading/line for the live thinking header.
String latestThoughtHeadline(String raw) {
  final lines = raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.replaceAll('**', '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';
  return lines.last;
}

/// Maps an active ACP tool kind to the semantic live phase shown in the UI
/// (`分析中` for read/search/fetch, `思考中` for think, `Working / 编辑中` for edits & commands).
TurnLivePhase phaseForToolKind(AcpToolKind kind) => switch (kind) {
  AcpToolKind.read || AcpToolKind.search || AcpToolKind.fetch =>
    TurnLivePhase.analyzing,
  AcpToolKind.think => TurnLivePhase.thinking,
  _ => TurnLivePhase.working,
};

/// Concise top-header status text reflecting real-time agent activity.
String headerStatusLabelForPhase(
  TurnLivePhase phase, {
  AcpToolKind? activeToolKind,
}) => switch (phase) {
  TurnLivePhase.retrying => '重试中',
  TurnLivePhase.analyzing => '分析中',
  TurnLivePhase.thinking => '思考中',
  TurnLivePhase.working =>
    (activeToolKind == AcpToolKind.edit ||
            activeToolKind == AcpToolKind.delete ||
            activeToolKind == AcpToolKind.move)
        ? '编辑中'
        : 'Working',
  TurnLivePhase.responding => '生成中',
  TurnLivePhase.waiting => 'Working',
};

/// Evaluates whether the active turn is analyzing, working, thinking, streaming,
/// retrying, waiting, or potentially stalled.
TurnHealth deriveTurnHealth({
  required DateTime? startedAt,
  required DateTime? lastActivityAt,
  required TurnLivePhase phase,
  required TurnRetryInfo? activeRetry,
  required int thoughtChars,
  required int answerChars,
  required bool hasActiveTool,
  required String? activeToolLabel,
  required String? activePlanLabel,
  required DateTime now,
  AcpToolKind? activeToolKind,
  String? liveStatusLabel,
  double? liveTokensPerSecond,
  bool inline = true,
}) {
  final anchor = lastActivityAt ?? startedAt ?? now;
  final silentSecs = now.difference(anchor).inSeconds.clamp(0, 86400);

  // 1. Explicit network / rate-limit retry reported by agy acp.
  if (activeRetry != null) {
    final retryAge = now.difference(activeRetry.timestamp).inSeconds.clamp(0, 86400);
    final ageSuffix = retryAge >= 15 ? ' · ${formatChineseDuration(retryAge)}' : '';
    return TurnHealth(
      tone: TurnHealthTone.retrying,
      silentSeconds: silentSecs,
      pillText: activeRetry.compactPillLabel(),
      detailHeadline: '${activeRetry.summary}$ageSuffix',
      bannerText: '${activeRetry.summary}$ageSuffix',
    );
  }

  // 2. Active tool call running locally/remotely — clearly distinguish 分析中 / 编辑中 / Working.
  if (hasActiveTool) {
    final label = (activeToolLabel != null && activeToolLabel.isNotEmpty)
        ? activeToolLabel
        : '执行工具';
    final prefix = switch (activeToolKind) {
      AcpToolKind.read || AcpToolKind.search || AcpToolKind.fetch => '分析中',
      AcpToolKind.edit || AcpToolKind.delete || AcpToolKind.move => '编辑中',
      AcpToolKind.think => '思考中',
      _ => 'Working',
    };
    final warnLongTool = silentSecs >= 180;
    return TurnHealth(
      tone: warnLongTool ? TurnHealthTone.suspectedStall : TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: warnLongTool
          ? '工具已等待 ${formatCompactDuration(silentSecs)}'
          : '$prefix · $label',
      detailHeadline: warnLongTool
          ? '工具运行已超过 ${formatChineseDuration(silentSecs)} 未返回结果'
          : '$prefix：$label',
      bannerText: warnLongTool
          ? '工具「$label」已 ${formatChineseDuration(silentSecs)} 无输出，可点右侧停止或查看日志'
          : null,
    );
  }

  // 3. Prolonged silence (>= 60s) with no chunks, no tool running, and no retry log.
  if (silentSecs >= 60) {
    final compact = formatCompactDuration(silentSecs);
    final full = formatChineseDuration(silentSecs);
    return TurnHealth(
      tone: TurnHealthTone.suspectedStall,
      silentSeconds: silentSecs,
      pillText: '$compact无新输出',
      detailHeadline: '已 $full 未收到模型新输出（可能在深度思考或网络已断开）',
      bannerText: '已 $full 未收到模型输出，可能仍在深度思考或网络已卡住',
    );
  }

  // 4. Short quiet gap (15–59s): make wait duration explicit so user knows it hasn't stopped silently.
  if (silentSecs >= 15) {
    final compact = formatCompactDuration(silentSecs);
    final full = formatChineseDuration(silentSecs);
    final (waitLabel, waitHeadline) = switch (phase) {
      TurnLivePhase.analyzing => (
        '分析中 · $compact前更新',
        '正在分析工具结果与上下文（距上次输出 $full）',
      ),
      TurnLivePhase.working => (
        'Working · $compact前更新',
        '正在执行任务步骤（距上次输出 $full）',
      ),
      TurnLivePhase.thinking => (
        '深度思考中 · $compact前更新',
        '深度思考中（距上次输出 $full）',
      ),
      _ when thoughtChars > 0 => (
        '深度思考中 · $compact前更新',
        '深度思考中（距上次输出 $full）',
      ),
      _ => (
        'Working · $compact',
        '等待模型返回下一步内容（已等待 $full）',
      ),
    };
    return TurnHealth(
      tone: TurnHealthTone.waiting,
      silentSeconds: silentSecs,
      pillText: waitLabel,
      detailHeadline: waitHeadline,
    );
  }

  final hasSpeed = liveTokensPerSecond != null && liveTokensPerSecond > 0;
  final compactSpeed = hasSpeed
      ? formatTokensPerSecond(liveTokensPerSecond, compact: true)
      : null;
  final fullSpeed = hasSpeed
      ? formatTokensPerSecond(liveTokensPerSecond)
      : null;
  final cleanStatus = liveStatusLabel?.trim();
  final hasStatus = cleanStatus != null && cleanStatus.isNotEmpty;

  // 5. Actively running (< 15s since last chunk/event).
  if (phase == TurnLivePhase.responding) {
    final pillSuffix = compactSpeed != null
        ? ' · $compactSpeed'
        : (answerChars > 0 ? ' · ${formatCharCount(answerChars)}' : '…');
    final speedPart = fullSpeed != null ? '$fullSpeed · ' : '';
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: '生成中$pillSuffix',
      detailHeadline: '正在实时输出回复（$speedPart已 ${formatCharCount(answerChars)}）',
    );
  }
  if (phase == TurnLivePhase.analyzing) {
    final detail = hasStatus ? cleanStatus : null;
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: detail != null ? '分析中 · $detail' : '分析中…',
      detailHeadline: detail != null
          ? '正在分析：$detail'
          : '正在分析文件与工具返回结果…',
    );
  }
  if (phase == TurnLivePhase.working) {
    final detail = hasStatus
        ? cleanStatus
        : (activePlanLabel != null && activePlanLabel.isNotEmpty
              ? activePlanLabel
              : null);
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: detail != null ? 'Working · $detail' : 'Working…',
      detailHeadline: detail != null ? 'Working：$detail' : '正在推进当前任务…',
    );
  }
  if (phase == TurnLivePhase.thinking || thoughtChars > 0) {
    final pillSuffix = compactSpeed != null
        ? ' · $compactSpeed'
        : (thoughtChars > 0 ? ' · ${formatCharCount(thoughtChars)}' : '…');
    final speedPart = fullSpeed != null ? '$fullSpeed · ' : '';
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: '思考中$pillSuffix',
      detailHeadline:
          '正在实时思考（$speedPart已 ${formatCharCount(thoughtChars)}，${formatLastSignalAge(silentSecs)}更新）',
    );
  }

  if (activePlanLabel != null && activePlanLabel.isNotEmpty) {
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: 'Working · $activePlanLabel',
      detailHeadline: '执行计划：$activePlanLabel',
    );
  }

  return TurnHealth(
    tone: TurnHealthTone.active,
    silentSeconds: silentSecs,
    pillText: hasStatus
        ? cleanStatus
        : (inline ? 'Working…' : 'Antigravity Working…'),
    detailHeadline: hasStatus ? cleanStatus : '已发送请求，模型正在接入与分析…',
  );
}

final _ansiEscapeRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
final _streamTagRegex = RegExp(r'^\[(?:stderr|stdout|system|installer|auth)\]\s*');
final _attemptPairRegex = RegExp(
  r'(?:attempt|retry|try|第)\s*#?(\d+)\s*(?:/|of|out of)\s*(\d+)',
  caseSensitive: false,
);
final _attemptSingleRegex = RegExp(
  r'(?:attempt|retry|retrying|第)\s*#?(\d+)\s*次?',
  caseSensitive: false,
);
final _delaySecondsRegex = RegExp(
  r'(?:in|after|wait(?:ing)?|backoff|retry[-_ ]?after[:\s=]*)\s*(\d+(?:\.\d+)?)\s*(ms|s|sec|secs|seconds|秒)',
  caseSensitive: false,
);

/// Cleans stream prefixes and ANSI codes from a raw engine log line.
String cleanEngineLogLine(String raw) {
  var s = raw.replaceAll(_ansiEscapeRegex, '').trim();
  s = s.replaceFirst(_streamTagRegex, '').trim();
  return s;
}

/// Parses transient network / rate-limit / backoff retry signals from an `agy acp`
/// process log line (`stderr` / non-JSON `stdout`).
TurnRetryInfo? parseRetryFromLogLine(String rawLine, {DateTime? now}) {
  final cleaned = cleanEngineLogLine(rawLine);
  if (cleaned.isEmpty) return null;
  final lower = cleaned.toLowerCase();

  // Ignore routine AGY Go runtime lifecycle lines.
  if (lower.startsWith('[runtime]') ||
      lower.startsWith('[bridge]') ||
      lower.startsWith('[installer]')) {
    return null;
  }

  final hasRetryKeyword =
      lower.contains('retry') ||
      lower.contains('retrying') ||
      lower.contains('backoff') ||
      lower.contains('reconnect') ||
      lower.contains('trying again') ||
      cleaned.contains('重试');

  final isRateLimit =
      lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('rate_limit') ||
      lower.contains('too many requests') ||
      lower.contains('resource_exhausted') ||
      lower.contains('quota exceeded');

  final isServiceBusy =
      lower.contains('503') ||
      lower.contains('502') ||
      lower.contains('504') ||
      lower.contains('overloaded') ||
      lower.contains('service unavailable') ||
      lower.contains('unavailable');

  final isNetworkDrop =
      lower.contains('connection reset') ||
      lower.contains('broken pipe') ||
      lower.contains('unexpected eof') ||
      lower.contains('i/o timeout') ||
      lower.contains('deadline exceeded') ||
      lower.contains('context deadline') ||
      lower.contains('tls handshake') ||
      lower.contains('socket hang up') ||
      lower.contains('econnreset') ||
      lower.contains('etimedout') ||
      lower.contains('network error') ||
      lower.contains('stream interrupted') ||
      lower.contains('stream error') ||
      lower.contains('temporary failure');

  if (!hasRetryKeyword && !isRateLimit && !isServiceBusy && !isNetworkDrop) {
    return null;
  }

  int? attempt;
  int? maxAttempts;
  final pair = _attemptPairRegex.firstMatch(cleaned);
  if (pair != null) {
    attempt = int.tryParse(pair.group(1)!);
    maxAttempts = int.tryParse(pair.group(2)!);
  } else {
    final single = _attemptSingleRegex.firstMatch(cleaned);
    if (single != null) {
      attempt = int.tryParse(single.group(1)!);
    }
  }

  int? retrySecs;
  final delayMatch = _delaySecondsRegex.firstMatch(cleaned);
  if (delayMatch != null) {
    final numVal = double.tryParse(delayMatch.group(1)!);
    final unit = delayMatch.group(2)!.toLowerCase();
    if (numVal != null && numVal > 0) {
      retrySecs = unit == 'ms' ? (numVal / 1000).ceil() : numVal.round();
    }
  }

  final baseReason = isRateLimit
      ? '触发模型限流 (429)，正在等待重试'
      : isServiceBusy
      ? '上游服务繁忙，正在自动重试'
      : isNetworkDrop
      ? '网络波动或连接中断，正在自动重试'
      : '网络不稳定，引擎正在自动重试';

  final details = <String>[];
  if (attempt != null && maxAttempts != null) {
    details.add('第 $attempt/$maxAttempts 次');
  } else if (attempt != null) {
    details.add('第 $attempt 次');
  }
  if (retrySecs != null && retrySecs > 0) {
    details.add('约 ${retrySecs}s 后');
  }

  final summary = details.isEmpty
      ? baseReason
      : '$baseReason（${details.join(' · ')}）';

  return TurnRetryInfo(
    summary: summary,
    rawMessage: cleaned.length > 240 ? '${cleaned.substring(0, 240)}…' : cleaned,
    timestamp: now ?? DateTime.now(),
    rateLimited: isRateLimit,
    attempt: attempt,
    maxAttempts: maxAttempts,
    retryInSeconds: retrySecs,
  );
}

/// Parses retry/network status info from an [AgentStatusUpdate] payload.
TurnRetryInfo? parseRetryFromStatusUpdate(
  AgentStatusUpdate update, {
  DateTime? now,
}) {
  return _parseRetryFromMap(
    kindOrMethod: update.kind,
    payload: update.raw,
    now: now,
  );
}

/// Parses retry/network status info from an unknown ACP `session/update` payload.
TurnRetryInfo? parseRetryFromUnknownUpdate(
  UnknownSessionUpdate update, {
  DateTime? now,
}) {
  return _parseRetryFromMap(
    kindOrMethod: update.kind,
    payload: update.raw,
    now: now,
  );
}

/// Parses retry/network status info from a non-`session/update` JSON-RPC notification.
TurnRetryInfo? parseRetryFromRawNotification(
  AcpRawNotification notif, {
  DateTime? now,
}) {
  return _parseRetryFromMap(
    kindOrMethod: notif.method,
    payload: notif.params,
    now: now,
  );
}

/// Extracts real-time semantic phase (`分析中` / `Working` / `思考中` / `生成中`)
/// and optional concise label from an ACP status/progress notification payload.
({TurnLivePhase phase, String? label})? parseLiveStatusFromMap({
  required String kindOrMethod,
  required Map<String, Object?> payload,
}) {
  final pieces = <String>[];
  String? bestLabel;
  void consider(Object? raw, {bool preferLabel = false}) {
    if (raw is! String) return;
    final clean = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return;
    pieces.add(clean);
    if (preferLabel && bestLabel == null) {
      bestLabel = clean.length > 48 ? '${clean.substring(0, 48)}…' : clean;
    }
  }

  consider(payload['message'], preferLabel: true);
  consider(payload['detail'], preferLabel: true);
  consider(payload['title'], preferLabel: true);
  consider(payload['status']);
  consider(payload['state']);
  consider(payload['phase']);
  consider(payload['text']);

  final nestedVal = payload['value'];
  if (nestedVal is Map) {
    consider(nestedVal['message'], preferLabel: true);
    consider(nestedVal['title'], preferLabel: true);
    consider(nestedVal['status']);
    consider(nestedVal['kind']);
  }

  if (pieces.isEmpty) return null;
  final probe = '$kindOrMethod ${pieces.join(' ')}'.toLowerCase();

  final TurnLivePhase phase;
  if (probe.contains('analyz') ||
      probe.contains('analys') ||
      probe.contains('inspect') ||
      probe.contains('review') ||
      probe.contains('search') ||
      probe.contains('reading') ||
      probe.contains('scan') ||
      probe.contains('分析') ||
      probe.contains('阅读') ||
      probe.contains('检索')) {
    phase = TurnLivePhase.analyzing;
  } else if (probe.contains('think') ||
      probe.contains('reason') ||
      probe.contains('plan') ||
      probe.contains('思考') ||
      probe.contains('规划')) {
    phase = TurnLivePhase.thinking;
  } else if (probe.contains('respond') ||
      probe.contains('generat') ||
      probe.contains('writ') ||
      probe.contains('answer') ||
      probe.contains('生成') ||
      probe.contains('回复')) {
    phase = TurnLivePhase.responding;
  } else if (probe.contains('work') ||
      probe.contains('edit') ||
      probe.contains('patch') ||
      probe.contains('run') ||
      probe.contains('exec') ||
      probe.contains('tool') ||
      probe.contains('task') ||
      probe.contains('busy') ||
      probe.contains('progress') ||
      probe.contains('in_progress') ||
      probe.contains('编辑') ||
      probe.contains('执行') ||
      probe.contains('修改')) {
    phase = TurnLivePhase.working;
  } else {
    return null;
  }

  // Avoid echoing generic raw enum words ("working", "analyzing") as redundant detail.
  final labelLower = bestLabel?.toLowerCase() ?? '';
  final redundant =
      labelLower == 'working' ||
      labelLower == 'analyzing' ||
      labelLower == 'thinking' ||
      labelLower == 'running' ||
      labelLower == 'in_progress' ||
      labelLower == 'busy' ||
      labelLower == 'status' ||
      labelLower == 'progress';

  return (phase: phase, label: redundant ? null : bestLabel);
}

TurnRetryInfo? _parseRetryFromMap({
  required String kindOrMethod,
  required Map<String, Object?> payload,
  DateTime? now,
}) {
  final parts = <String>[];
  if (kindOrMethod.isNotEmpty) parts.add(kindOrMethod);
  for (final key in const ['message', 'text', 'reason', 'error', 'detail', 'status']) {
    final v = payload[key];
    if (v is String && v.trim().isNotEmpty) {
      parts.add(v.trim());
    }
  }
  final nestedVal = payload['value'];
  if (nestedVal is Map) {
    for (final key in const ['title', 'message', 'status']) {
      final v = nestedVal[key];
      if (v is String && v.trim().isNotEmpty) {
        parts.add(v.trim());
      }
    }
  }
  final combined = parts.join(' ');
  final parsed = parseRetryFromLogLine(combined, now: now);
  if (parsed == null) return null;

  final attempt =
      parsed.attempt ?? (payload['attempt'] as num?)?.toInt();
  final maxAttempts =
      parsed.maxAttempts ?? (payload['maxAttempts'] as num?)?.toInt();
  int? retrySecs = parsed.retryInSeconds;
  if (retrySecs == null) {
    final ms = (payload['retryAfterMs'] ?? payload['delayMs']) as num?;
    final sec = (payload['retryAfterSeconds'] ?? payload['retryInSeconds']) as num?;
    if (sec != null && sec > 0) {
      retrySecs = sec.round();
    } else if (ms != null && ms > 0) {
      retrySecs = (ms / 1000).ceil();
    }
  }

  if (attempt == parsed.attempt &&
      maxAttempts == parsed.maxAttempts &&
      retrySecs == parsed.retryInSeconds) {
    return parsed;
  }

  final baseReason = parsed.rateLimited
      ? '触发模型限流 (429)，正在等待重试'
      : '网络不稳定，引擎正在自动重试';
  final details = <String>[];
  if (attempt != null && maxAttempts != null) {
    details.add('第 $attempt/$maxAttempts 次');
  } else if (attempt != null) {
    details.add('第 $attempt 次');
  }
  if (retrySecs != null && retrySecs > 0) {
    details.add('约 ${retrySecs}s 后');
  }
  return TurnRetryInfo(
    summary: details.isEmpty ? baseReason : '$baseReason（${details.join(' · ')}）',
    rawMessage: parsed.rawMessage,
    timestamp: parsed.timestamp,
    rateLimited: parsed.rateLimited,
    attempt: attempt,
    maxAttempts: maxAttempts,
    retryInSeconds: retrySecs,
  );
}
