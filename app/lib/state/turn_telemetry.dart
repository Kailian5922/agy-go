import 'package:acp_client/acp_client.dart';

/// Current active stage within an in-flight turn.
enum TurnLivePhase {
  waiting,
  thinking,
  responding,
  toolRunning,
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

/// Evaluates whether the active turn is streaming smoothly, retrying, waiting, or potentially stalled.
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

  // 2. Active tool call running locally/remotely.
  if (hasActiveTool) {
    final label = (activeToolLabel != null && activeToolLabel.isNotEmpty)
        ? activeToolLabel
        : '正在执行工具…';
    final warnLongTool = silentSecs >= 180;
    return TurnHealth(
      tone: warnLongTool ? TurnHealthTone.suspectedStall : TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: warnLongTool
          ? '工具已等待 ${formatCompactDuration(silentSecs)}'
          : label,
      detailHeadline: warnLongTool
          ? '工具运行已超过 ${formatChineseDuration(silentSecs)} 未返回结果'
          : '正在执行：$label',
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
    final waitLabel = phase == TurnLivePhase.thinking || thoughtChars > 0
        ? '深度思考中 · $compact前更新'
        : '等待响应 · $compact';
    return TurnHealth(
      tone: TurnHealthTone.waiting,
      silentSeconds: silentSecs,
      pillText: waitLabel,
      detailHeadline: phase == TurnLivePhase.thinking || thoughtChars > 0
          ? '深度思考中（距上次输出 $full）'
          : '等待模型返回下一步内容（已等待 $full）',
    );
  }

  // 5. Actively streaming (< 15s since last chunk/event).
  if (activePlanLabel != null && activePlanLabel.isNotEmpty && phase == TurnLivePhase.waiting) {
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: activePlanLabel,
      detailHeadline: '执行计划：$activePlanLabel',
    );
  }
  if (phase == TurnLivePhase.responding) {
    final suffix = answerChars > 0 ? ' · ${formatCharCount(answerChars)}' : '…';
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: '生成中$suffix',
      detailHeadline: '正在实时流式输出回复（已 ${formatCharCount(answerChars)}）',
    );
  }
  if (phase == TurnLivePhase.thinking || thoughtChars > 0) {
    final suffix = thoughtChars > 0 ? ' · ${formatCharCount(thoughtChars)}' : '…';
    return TurnHealth(
      tone: TurnHealthTone.active,
      silentSeconds: silentSecs,
      pillText: '思考中$suffix',
      detailHeadline: '正在实时思考（已 ${formatCharCount(thoughtChars)}，${formatLastSignalAge(silentSecs)}更新）',
    );
  }

  return TurnHealth(
    tone: TurnHealthTone.active,
    silentSeconds: silentSecs,
    pillText: inline ? '思考与生成中…' : 'Antigravity 思考与生成中…',
    detailHeadline: '已发送请求，等待模型开始响应…',
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
