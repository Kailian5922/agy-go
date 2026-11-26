import 'package:acp_client/acp_client.dart';

/// Directly observed ACP wire stage within an in-flight turn (no client-side guessing).
enum TurnLivePhase {
  /// Prompt in flight; awaiting the next event from `agy acp`.
  waiting,

  /// Receiving `agent_thought_chunk` from the model.
  thinking,

  /// Executing an active tool call, active `plan` step, or explicit engine status.
  working,

  /// Receiving `agent_message_chunk` from the model.
  responding,

  /// Engine explicitly reported a transient network / rate-limit retry.
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

final _kBoldHeadingRe = RegExp(r'^\s*\*\*([^*\n]{2,120})\*\*\s*$');
final _kMdHeadingRe = RegExp(r'^\s*#{1,3}\s+(.{2,120})$');

/// Extracts the model's latest native thought heading/line from `agent_thought_chunk`.
///
/// Prefers standalone Markdown section headers that Gemini/Antigravity emits natively
/// inside its thinking stream (e.g. `**Analyzing the status bar**` or `## Plan`),
/// falling back to the latest non-empty reasoning line when prose has no headings.
String latestThoughtHeadline(String raw) {
  final lines = raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';

  for (var i = lines.length - 1; i >= 0; i--) {
    final line = lines[i];
    final bold = _kBoldHeadingRe.firstMatch(line);
    if (bold != null) {
      final title = bold.group(1)!.trim();
      if (title.isNotEmpty) return title;
    }
    final md = _kMdHeadingRe.firstMatch(line);
    if (md != null) {
      final title = md.group(1)!.replaceAll('**', '').trim();
      if (title.isNotEmpty) return title;
    }
  }

  return lines.last.replaceAll('**', '').trim();
}

/// Resolves the concise top-header status directly from native ACP signals
/// without guessing or fabricating intermediate phases.
String resolveNativeHeaderStatus({
  required TurnLivePhase phase,
  String? activeToolStatus,
  String? nativeStatusLabel,
  String? activePlanLabel,
  String? liveThoughtHeadline,
  TurnRetryInfo? activeRetry,
}) {
  if (activeRetry != null || phase == TurnLivePhase.retrying) {
    return activeRetry?.compactPillLabel() ?? '重试中';
  }
  final tool = activeToolStatus?.trim();
  if (tool != null && tool.isNotEmpty) return tool;

  final native = nativeStatusLabel?.trim();
  if (native != null && native.isNotEmpty) return native;

  if (phase == TurnLivePhase.thinking) {
    final heading = liveThoughtHeadline?.trim();
    if (heading != null && heading.isNotEmpty) return '思考 · $heading';
    return '思考中';
  }
  if (phase == TurnLivePhase.responding) {
    return '回复中';
  }

  final plan = activePlanLabel?.trim();
  if (plan != null && plan.isNotEmpty) return plan;

  return '等待响应';
}

/// Derives real-time turn liveness strictly from native ACP events and factual
/// elapsed time — never guessing or fabricating what the model might be doing.
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
  String? liveStatusLabel,
  String? liveThoughtHeadline,
  double? liveTokensPerSecond,
  bool inline = true,
}) {
  final anchor = lastActivityAt ?? startedAt ?? now;
  final silentSecs = now.difference(anchor).inSeconds.clamp(0, 86400);
  final hasSpeed = liveTokensPerSecond != null && liveTokensPerSecond > 0;
  final compactSpeed = hasSpeed
      ? formatTokensPerSecond(liveTokensPerSecond, compact: true)
      : null;
  final fullSpeed = hasSpeed
      ? formatTokensPerSecond(liveTokensPerSecond)
      : null;
  final cleanStatus = liveStatusLabel?.trim();
  final hasStatus = cleanStatus != null && cleanStatus.isNotEmpty;
  final cleanPlan = activePlanLabel?.trim();
  final hasPlan = cleanPlan != null && cleanPlan.isNotEmpty;
  final cleanThought = liveThoughtHeadline?.trim();
  final hasThoughtHeading = cleanThought != null && cleanThought.isNotEmpty;

  // 1. Explicit network / rate-limit retry reported by `agy acp`.
  if (activeRetry != null) {
    final retryAge = now
        .difference(activeRetry.timestamp)
        .inSeconds
        .clamp(0, 86400);
    final ageSuffix = retryAge >= 15
        ? ' · ${formatChineseDuration(retryAge)}'
        : '';
    return TurnHealth(
      tone: TurnHealthTone.retrying,
      silentSeconds: silentSecs,
      pillText: activeRetry.compactPillLabel(),
      detailHeadline: '${activeRetry.summary}$ageSuffix',
      bannerText: '${activeRetry.summary}$ageSuffix',
    );
  }

  // 2. Active tool call: show the model/engine's own native action/title verbatim.
  if (hasActiveTool) {
    final label = (activeToolLabel != null && activeToolLabel.trim().isNotEmpty)
        ? activeToolLabel.trim()
        : '工具执行中';
    final warnLongTool = silentSecs >= 180;
    return TurnHealth(
      tone: warnLongTool
          ? TurnHealthTone.suspectedStall
          : TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: warnLongTool
          ? '$label · ${formatCompactDuration(silentSecs)}'
          : label,
      detailHeadline: warnLongTool
          ? '$label（已运行 ${formatChineseDuration(silentSecs)} 未返回结果）'
          : label,
      bannerText: warnLongTool
          ? '「$label」已运行 ${formatChineseDuration(silentSecs)} 未返回结果，可查看日志或停止'
          : null,
    );
  }

  // 3. Explicit native engine status / compaction / notice emitted by `agy`.
  if (hasStatus) {
    final compact = formatCompactDuration(silentSecs);
    final full = formatChineseDuration(silentSecs);
    final tone = silentSecs >= 60
        ? TurnHealthTone.suspectedStall
        : (silentSecs >= 15 ? TurnHealthTone.waiting : TurnHealthTone.active);
    return TurnHealth(
      tone: tone,
      silentSeconds: silentSecs,
      pillText: silentSecs >= 15 ? '$cleanStatus · $compact' : cleanStatus,
      detailHeadline: silentSecs >= 15
          ? '$cleanStatus（距上次事件 $full）'
          : cleanStatus,
      bannerText: silentSecs >= 60 ? '$cleanStatus（已 $full 无新事件）' : null,
    );
  }

  // 4. Actively receiving `agent_thought_chunk`: surface the model's native heading & speed.
  if (phase == TurnLivePhase.thinking) {
    final base = hasThoughtHeading ? '思考 · $cleanThought' : '思考中';
    if (silentSecs >= 60) {
      final compact = formatCompactDuration(silentSecs);
      final full = formatChineseDuration(silentSecs);
      return TurnHealth(
        tone: TurnHealthTone.suspectedStall,
        silentSeconds: silentSecs,
        pillText: '$base · $compact无新事件',
        detailHeadline: '$base（已 $full 未收到新思考片段）',
        bannerText: '已 $full 未收到引擎新事件，可查看日志或停止',
      );
    }
    if (silentSecs >= 15) {
      final compact = formatCompactDuration(silentSecs);
      final full = formatChineseDuration(silentSecs);
      return TurnHealth(
        tone: TurnHealthTone.waiting,
        silentSeconds: silentSecs,
        pillText: '$base · $compact',
        detailHeadline: '$base（上次收到思考片段：$full前）',
      );
    }
    final pillSuffix = compactSpeed != null ? ' · $compactSpeed' : '';
    final detailParts = <String>[
      ?fullSpeed,
      if (thoughtChars > 0) '已 ${formatCharCount(thoughtChars)}',
    ];
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: '$base$pillSuffix',
      detailHeadline: detailParts.isEmpty
          ? base
          : '$base（${detailParts.join(' · ')}）',
    );
  }

  // 5. Actively receiving `agent_message_chunk`.
  if (phase == TurnLivePhase.responding) {
    if (silentSecs >= 60) {
      final compact = formatCompactDuration(silentSecs);
      final full = formatChineseDuration(silentSecs);
      return TurnHealth(
        tone: TurnHealthTone.suspectedStall,
        silentSeconds: silentSecs,
        pillText: '回复中 · $compact无新事件',
        detailHeadline: '已 $full 未收到新的回复片段',
        bannerText: '已 $full 未收到引擎新事件，可查看日志或停止',
      );
    }
    if (silentSecs >= 15) {
      final compact = formatCompactDuration(silentSecs);
      final full = formatChineseDuration(silentSecs);
      return TurnHealth(
        tone: TurnHealthTone.waiting,
        silentSeconds: silentSecs,
        pillText: '回复中 · $compact',
        detailHeadline: '回复中（上次收到片段：$full前）',
      );
    }
    final pillSuffix = compactSpeed != null
        ? ' · $compactSpeed'
        : (answerChars > 0 ? ' · ${formatCharCount(answerChars)}' : '…');
    final speedPart = fullSpeed != null ? '$fullSpeed · ' : '';
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: '回复中$pillSuffix',
      detailHeadline: '正在接收回复（$speedPart已 ${formatCharCount(answerChars)}）',
    );
  }

  // 6. Active native `plan` / `plan_update` step from `update_steps`.
  if (hasPlan) {
    final compact = formatCompactDuration(silentSecs);
    final full = formatChineseDuration(silentSecs);
    final tone = silentSecs >= 60
        ? TurnHealthTone.suspectedStall
        : (silentSecs >= 15 ? TurnHealthTone.waiting : TurnHealthTone.active);
    return TurnHealth(
      tone: tone,
      silentSeconds: silentSecs,
      pillText: silentSecs >= 15 ? '$cleanPlan · $compact' : cleanPlan,
      detailHeadline: silentSecs >= 15
          ? '$cleanPlan（距上次事件 $full）'
          : cleanPlan,
      bannerText: silentSecs >= 60 ? '已 $full 未收到引擎新事件，可查看日志或停止' : null,
    );
  }

  // 7. Waiting for the next native ACP event from `agy` (no speculation).
  if (silentSecs >= 60) {
    final compact = formatCompactDuration(silentSecs);
    final full = formatChineseDuration(silentSecs);
    return TurnHealth(
      tone: TurnHealthTone.suspectedStall,
      silentSeconds: silentSecs,
      pillText: '等待响应 · $compact无事件',
      detailHeadline: '已 $full 未收到引擎新事件',
      bannerText: '已 $full 未收到引擎新事件，可查看日志或停止',
    );
  }
  if (silentSecs >= 15) {
    final compact = formatCompactDuration(silentSecs);
    final full = formatChineseDuration(silentSecs);
    return TurnHealth(
      tone: TurnHealthTone.waiting,
      silentSeconds: silentSecs,
      pillText: '等待响应 · $compact',
      detailHeadline: '等待引擎返回下一步事件（已等待 $full）',
    );
  }

  return TurnHealth(
    tone: TurnHealthTone.active,
    silentSeconds: silentSecs,
    pillText: inline ? '等待响应…' : '等待模型响应…',
    detailHeadline: '已发送请求，等待引擎返回事件…',
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

/// Returns the latest native thought heading/line from [item]'s timeline
/// (or merged thought buffer), or `null` if no reasoning text has arrived yet.
String? latestAssistantThoughtHeadline(AssistantTranscriptItem? item) {
  if (item == null) return null;
  for (final entry in item.timeline.reversed) {
    if (entry is ThoughtTimelineEntry && entry.text.trim().isNotEmpty) {
      final heading = latestThoughtHeadline(entry.text);
      if (heading.isNotEmpty) return heading;
    }
  }
  if (item.thought.trim().isNotEmpty) {
    final heading = latestThoughtHeadline(item.thought);
    if (heading.isNotEmpty) return heading;
  }
  return null;
}

const _kTerminalStatusTokens = <String>{
  'end',
  'ended',
  'done',
  'complete',
  'completed',
  'finished',
  'idle',
  'ready',
  'ok',
  'success',
  'succeeded',
  'cancelled',
  'canceled',
  'state_idle',
  'state_fully_idle',
};

const _kOpaqueMachineStatusTokens = <String>{
  'in_progress',
  'inprogress',
  'pending',
  'running',
  'active',
  'busy',
  'working',
  'status',
  'progress',
  'begin',
  'report',
  'start',
  'started',
  'update',
  'session_update',
  'none',
  'null',
  'true',
  'false',
};

String _clipStatusText(String raw) {
  final clean = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.length <= 80) return clean;
  return '${clean.substring(0, 80)}…';
}

/// Extracts a verbatim native engine status update (or explicit terminal clear)
/// from an ACP `session/update` or JSON-RPC progress/status notification.
///
/// Never guesses or invents a phase from keyword matching: returns only text
/// that `agy acp` / the model actually emitted, or factual protocol state labels
/// (e.g. `compaction_update` / `STATE_WAITING_FOR_TASKS`).
({String? text, bool clear})? extractNativeStatusUpdate({
  required String kindOrMethod,
  required Map<String, Object?> payload,
}) {
  final kindLower = kindOrMethod.trim().toLowerCase();

  String? cleanStr(Object? raw) {
    if (raw is! String) return null;
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return s.isEmpty ? null : s;
  }

  final nestedVal = payload['value'];
  final valMap = nestedVal is Map ? nestedVal : null;
  final rawMeta = payload['_meta'];
  final metaMap = rawMeta is Map ? rawMeta : null;

  final stateToken = (cleanStr(valMap?['kind']) ??
          cleanStr(payload['status']) ??
          cleanStr(payload['state']) ??
          cleanStr(valMap?['status']))
      ?.toLowerCase();

  if (kindLower == 'background_turn_completed' ||
      (stateToken != null && _kTerminalStatusTokens.contains(stateToken))) {
    return (text: null, clear: true);
  }

  if (stateToken == 'state_waiting_for_tasks' ||
      stateToken == 'waiting_for_tasks') {
    return (text: '等待后台任务', clear: false);
  }

  // Prefer human-readable descriptive fields emitted by the engine/model verbatim.
  final valTitle = cleanStr(valMap?['title']);
  final valMsg = cleanStr(valMap?['message']) ?? cleanStr(valMap?['detail']);
  if (valTitle != null && valMsg != null && valTitle != valMsg) {
    return (text: _clipStatusText('$valTitle · $valMsg'), clear: false);
  }

  final descriptiveCandidates = <String?>[
    cleanStr(metaMap?['toolAction']),
    cleanStr(payload['message']),
    cleanStr(payload['detail']),
    cleanStr(payload['title']),
    cleanStr(payload['summary']),
    cleanStr(payload['text']),
    valMsg,
    valTitle,
    cleanStr(metaMap?['message']),
    cleanStr(metaMap?['status']),
  ];
  for (final cand in descriptiveCandidates) {
    if (cand == null) continue;
    final low = cand.toLowerCase();
    if (_kTerminalStatusTokens.contains(low)) {
      return (text: null, clear: true);
    }
    if (_kOpaqueMachineStatusTokens.contains(low)) continue;
    return (text: _clipStatusText(cand), clear: false);
  }

  if (kindLower == 'compaction_update' ||
      kindLower == 'compaction_summary_chunk') {
    return (text: '压缩上下文中', clear: false);
  }
  if (kindLower == 'background_turn_started') {
    return (text: '后台任务执行中', clear: false);
  }

  // Only surface raw `status`/`state` if it isn't an opaque boilerplate enum token.
  final rawState = cleanStr(payload['status']) ?? cleanStr(payload['state']);
  if (rawState != null) {
    final low = rawState.toLowerCase();
    if (!_kOpaqueMachineStatusTokens.contains(low) &&
        !_kTerminalStatusTokens.contains(low)) {
      return (text: _clipStatusText(rawState), clear: false);
    }
  }

  return null;
}

/// Parses factual Antigravity `trajectoryStateUpdate` markers from engine logs
/// (e.g. `STATE_WAITING_FOR_TASKS` when waiting on background tasks/subagents).
({String? statusText, bool clear})? parseTrajectoryStateFromLogLine(
  String rawLine,
) {
  final cleaned = cleanEngineLogLine(rawLine);
  if (cleaned.isEmpty) return null;
  if (cleaned.contains('STATE_WAITING_FOR_TASKS')) {
    return (statusText: '等待后台任务', clear: false);
  }
  if ((cleaned.contains('trajectoryStateUpdate') ||
          cleaned.contains('trajectory_state')) &&
      (cleaned.contains('STATE_IDLE') ||
          cleaned.contains('STATE_FULLY_IDLE'))) {
    return (statusText: null, clear: true);
  }
  return null;
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
