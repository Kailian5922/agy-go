import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_state.dart';
import 'hosts_state.dart';
import 'runtime_state.dart';
import 'settings_state.dart';

/// Cadence window of an Antigravity quota bucket.
enum QuotaWindowKind {
  fiveHour,
  weekly,
  other;

  static QuotaWindowKind parse({
    String? window,
    String? id,
    String? name,
  }) {
    final w = (window ?? '').trim().toLowerCase();
    if (w == '5h' || w == 'five_hour' || w == 'five-hour' || w == '5hour') {
      return QuotaWindowKind.fiveHour;
    }
    if (w == 'weekly' || w == '7d' || w == 'seven_day' || w == 'week') {
      return QuotaWindowKind.weekly;
    }
    final probe = '${id ?? ''} ${name ?? ''}'.toLowerCase();
    if (probe.contains('5h') ||
        probe.contains('five hour') ||
        probe.contains('five-hour') ||
        probe.contains('five_hour')) {
      return QuotaWindowKind.fiveHour;
    }
    if (probe.contains('weekly') ||
        probe.contains('7d') ||
        probe.contains('seven day') ||
        probe.contains('week')) {
      return QuotaWindowKind.weekly;
    }
    return QuotaWindowKind.other;
  }

  String get shortLabel => switch (this) {
    QuotaWindowKind.fiveHour => '5 小时额度',
    QuotaWindowKind.weekly => '周额度',
    QuotaWindowKind.other => '额度',
  };
}

/// One quota bucket (e.g. `gemini-5h`, `gemini-weekly`, `3p-5h`, `3p-weekly`).
class QuotaBucket {
  const QuotaBucket({
    required this.id,
    required this.name,
    required this.windowKind,
    required this.remainingFraction,
    this.resetTime,
    this.disabled = false,
    this.description,
  });

  final String id;
  final String name;
  final QuotaWindowKind windowKind;
  final double remainingFraction;
  final DateTime? resetTime;
  final bool disabled;
  final String? description;

  /// Antigravity enforces a 1% pre-reservation floor where <1% remaining enters soft lockout.
  bool get isSoftLocked => remainingFraction < 0.01;
}

/// One model-family quota pool (e.g. `Gemini Models`, `Claude and GPT models`).
class QuotaGroup {
  const QuotaGroup({
    required this.name,
    required this.buckets,
    this.description,
  });

  final String name;
  final String? description;
  final List<QuotaBucket> buckets;

  QuotaBucket? get fiveHourBucket {
    for (final b in buckets) {
      if (b.windowKind == QuotaWindowKind.fiveHour) return b;
    }
    return null;
  }

  QuotaBucket? get weeklyBucket {
    for (final b in buckets) {
      if (b.windowKind == QuotaWindowKind.weekly) return b;
    }
    return null;
  }

  /// Concise Chinese label for known Antigravity quota groups.
  String get displayName {
    final lower = name.trim().toLowerCase();
    if (lower == 'gemini models' || lower == 'gemini') {
      return 'Gemini 模型';
    }
    if (lower.contains('claude') && lower.contains('gpt')) {
      return 'Claude / GPT 模型';
    }
    if (lower == '3p' || lower == 'third party' || lower == 'third-party') {
      return 'Claude / GPT 模型';
    }
    return name.trim().isEmpty ? '模型额度' : name.trim();
  }

  /// Whether this quota group corresponds to a model category tab (`Gemini`, `Claude`, `OpenAI`, ...).
  bool matchesCategory(String category) {
    final cat = category.trim().toLowerCase();
    if (cat.isEmpty) return false;
    final probe = [
      name,
      description ?? '',
      for (final b in buckets) b.id,
    ].join(' ').toLowerCase();

    if (cat == 'gemini') {
      return probe.contains('gemini');
    }
    if (cat == 'claude' || cat == 'openai' || cat == 'gpt' || cat == '3p') {
      return probe.contains('claude') ||
          probe.contains('gpt') ||
          probe.contains('3p') ||
          probe.contains('openai');
    }
    return probe.contains(cat);
  }
}

enum QuotaLoadStatus {
  idle,
  loading,
  loaded,
  apiKeyMode,
  notSignedIn,
  unavailable,
}

class QuotaState {
  const QuotaState({
    this.status = QuotaLoadStatus.idle,
    this.groups = const [],
    this.description,
    this.fetchedAt,
    this.errorMessage,
    this.isRefreshing = false,
  });

  final QuotaLoadStatus status;
  final List<QuotaGroup> groups;
  final String? description;
  final DateTime? fetchedAt;
  final String? errorMessage;
  final bool isRefreshing;

  bool get hasData => status == QuotaLoadStatus.loaded && groups.isNotEmpty;

  /// Picks the quota group(s) most relevant to [category] (e.g. `Gemini` or `Claude`),
  /// prioritizing a specific model match when multiple groups match the family.
  List<QuotaGroup> groupsForCategory(String? category, {String? selectedModelName}) {
    if (groups.isEmpty) return const [];
    if (category == null || category.trim().isEmpty) return groups;
    final matched = groups.where((g) => g.matchesCategory(category)).toList();
    if (matched.isEmpty) return groups;
    if (matched.length > 1 && selectedModelName != null && selectedModelName.isNotEmpty) {
      final needle = selectedModelName.toLowerCase();
      final exact = matched.where((g) {
        final gn = g.name.toLowerCase();
        return gn != 'gemini models' && needle.contains(gn);
      }).toList();
      if (exact.isNotEmpty) return exact;
    }
    return matched;
  }

  QuotaState copyWith({
    QuotaLoadStatus? status,
    List<QuotaGroup>? groups,
    String? description,
    DateTime? fetchedAt,
    String? errorMessage,
    bool clearError = false,
    bool? isRefreshing,
  }) => QuotaState(
    status: status ?? this.status,
    groups: groups ?? this.groups,
    description: description ?? this.description,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    isRefreshing: isRefreshing ?? this.isRefreshing,
  );
}

/// Structured outcome from parsing `agy -p /usage --output-format json`.
class QuotaParseResult {
  const QuotaParseResult({
    required this.status,
    this.groups = const [],
    this.description,
    this.errorMessage,
  });

  final QuotaLoadStatus status;
  final List<QuotaGroup> groups;
  final String? description;
  final String? errorMessage;
}

/// Formats remaining quota fraction (`0.0..1.0`) as a concise percentage (`95%`, `<1%`, `0%`).
String formatQuotaPercent(double remainingFraction) {
  final clamped = remainingFraction.clamp(0.0, 1.0);
  if (clamped <= 0) return '0%';
  if (clamped < 0.01) return '<1%';
  return '${(clamped * 100).round()}%';
}

/// Formats reset timestamp into a compact Chinese countdown (`3小时58分后重置`, `6天15小时后重置`).
String? formatQuotaResetCountdown(DateTime? resetTime, {DateTime? now}) {
  if (resetTime == null) return null;
  final diff = resetTime.toUtc().difference((now ?? DateTime.now()).toUtc());
  if (diff <= Duration.zero) return '即将重置';
  final days = diff.inDays;
  final hours = diff.inHours.remainder(24);
  final mins = diff.inMinutes.remainder(60);
  if (days > 0) {
    return hours > 0 ? '$days天$hours小时后重置' : '$days天后重置';
  }
  if (hours > 0) {
    return mins > 0 ? '$hours小时$mins分后重置' : '$hours小时后重置';
  }
  if (mins > 0) {
    return '$mins分钟后重置';
  }
  return '1分钟内重置';
}

/// Parses `agy -p /usage --output-format json` stdout/stderr into structured 5h & weekly quotas.
QuotaParseResult parseAgyUsageCliOutput(
  String stdout, {
  String stderr = '',
  int exitCode = 0,
}) {
  final combinedErrorProbe = '$stdout\n$stderr'.toLowerCase();
  final decoded = _extractJsonObject(stdout);

  if (decoded != null) {
    final statusRaw = (decoded['status'] as String? ?? '').trim().toUpperCase();
    final cmd = decoded['command'];
    final data = cmd is Map ? cmd['data'] : null;
    final dataMap = data is Map ? Map<String, Object?>.from(data) : null;
    final description = dataMap?['description'] as String?;

    final groups = <QuotaGroup>[];
    final rawGroups = dataMap?['groups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is! Map) continue;
        final gMap = Map<String, Object?>.from(g);
        final gName = (gMap['name'] as String? ?? '').trim();
        final gDesc = gMap['description'] as String?;
        final buckets = <QuotaBucket>[];
        final rawBuckets = gMap['buckets'];
        if (rawBuckets is List) {
          for (final b in rawBuckets) {
            if (b is! Map) continue;
            final bMap = Map<String, Object?>.from(b);
            final fracNum = bMap['remaining_fraction'] ?? bMap['remainingFraction'];
            if (fracNum is! num) continue;
            final id = (bMap['id'] as String? ?? '').trim();
            final name = (bMap['name'] as String? ?? '').trim();
            final window = bMap['window'] as String?;
            final resetRaw = (bMap['reset_time'] ?? bMap['resetTime']) as String?;
            final resetTime = resetRaw != null && resetRaw.trim().isNotEmpty
                ? DateTime.tryParse(resetRaw.trim())
                : null;
            buckets.add(
              QuotaBucket(
                id: id,
                name: name,
                windowKind: QuotaWindowKind.parse(
                  window: window,
                  id: id,
                  name: name,
                ),
                remainingFraction: fracNum.toDouble().clamp(0.0, 1.0),
                resetTime: resetTime,
                disabled: bMap['disabled'] == true,
                description: bMap['description'] as String?,
              ),
            );
          }
        }
        if (buckets.isNotEmpty) {
          groups.add(
            QuotaGroup(
              name: gName.isNotEmpty ? gName : '模型额度',
              description: gDesc,
              buckets: buckets,
            ),
          );
        }
      }
    }

    // Fallback: parse TSV `response` string if structured `command.data.groups` is absent.
    if (groups.isEmpty) {
      final responseStr = decoded['response'] as String? ?? '';
      groups.addAll(_parseTsvResponse(responseStr));
    }

    if (groups.isNotEmpty) {
      return QuotaParseResult(
        status: QuotaLoadStatus.loaded,
        groups: groups,
        description: description,
      );
    }

    final respErr = (decoded['error'] ?? decoded['response'] ?? '').toString();
    if (_looksSignedOut('$respErr $stderr')) {
      return const QuotaParseResult(
        status: QuotaLoadStatus.notSignedIn,
        errorMessage: '请先登录 Google 账号以查看订阅额度',
      );
    }
    if (statusRaw.isNotEmpty && statusRaw != 'SUCCESS') {
      return QuotaParseResult(
        status: QuotaLoadStatus.unavailable,
        errorMessage: respErr.trim().isNotEmpty
            ? respErr.trim()
            : '查询额度失败 ($statusRaw)',
      );
    }
  }

  // Fallback if CLI printed plain TSV text directly without JSON envelope.
  final tsvGroups = _parseTsvResponse(stdout);
  if (tsvGroups.isNotEmpty) {
    return QuotaParseResult(status: QuotaLoadStatus.loaded, groups: tsvGroups);
  }

  if (_looksSignedOut(combinedErrorProbe)) {
    return const QuotaParseResult(
      status: QuotaLoadStatus.notSignedIn,
      errorMessage: '请先登录 Google 账号以查看订阅额度',
    );
  }

  final errDetail = stderr.trim().isNotEmpty
      ? stderr.trim().split('\n').first.trim()
      : (exitCode != 0 ? 'agy 返回退出码 $exitCode' : '暂未获取到额度数据');
  return QuotaParseResult(
    status: QuotaLoadStatus.unavailable,
    errorMessage: errDetail,
  );
}

bool _looksSignedOut(String text) {
  final lower = text.toLowerCase();
  return lower.contains('not signed in') ||
      lower.contains('not logged in') ||
      lower.contains('sign in') ||
      lower.contains('login required') ||
      lower.contains('unauthenticated') ||
      lower.contains('authentication required') ||
      lower.contains('please authenticate');
}

Map<String, Object?>? _extractJsonObject(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final direct = jsonDecode(trimmed);
    if (direct is Map) return Map<String, Object?>.from(direct);
  } catch (_) {}

  // Try extracting the outermost JSON object in case CLI logged preamble lines.
  final firstBrace = trimmed.indexOf('{');
  final lastBrace = trimmed.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    try {
      final slice = trimmed.substring(firstBrace, lastBrace + 1);
      final decoded = jsonDecode(slice);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
  }

  // Try scanning line-by-line from bottom (stream-json style).
  final lines = trimmed.split('\n').reversed;
  for (final line in lines) {
    final l = line.trim();
    if (!l.startsWith('{') || !l.endsWith('}')) continue;
    try {
      final decoded = jsonDecode(l);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
  }
  return null;
}

List<QuotaGroup> _parseTsvResponse(String raw) {
  if (raw.trim().isEmpty) return const [];
  final byGroup = <String, List<QuotaBucket>>{};
  for (final line in raw.split('\n')) {
    final parts = line.split('\t').map((p) => p.trim()).toList();
    if (parts.length < 3) continue;
    final groupName = parts[0];
    final bucketName = parts[1];
    final pctRaw = parts[2].replaceAll('%', '').trim();
    final pct = double.tryParse(pctRaw);
    if (groupName.isEmpty || pct == null) continue;
    final resetTime = parts.length >= 4 && parts[3].isNotEmpty
        ? DateTime.tryParse(parts[3])
        : null;
    final kind = QuotaWindowKind.parse(name: bucketName);
    byGroup.putIfAbsent(groupName, () => []).add(
      QuotaBucket(
        id: '${groupName.toLowerCase()}-${kind.name}',
        name: bucketName,
        windowKind: kind,
        remainingFraction: (pct / 100.0).clamp(0.0, 1.0),
        resetTime: resetTime,
      ),
    );
  }
  return [
    for (final entry in byGroup.entries)
      QuotaGroup(name: entry.key, buckets: entry.value),
  ];
}

/// On-demand Antigravity 5-hour & weekly quota controller (zero background polling).
class QuotaController extends Notifier<QuotaState> {
  static const cacheTtl = Duration(seconds: 60);

  Future<void>? _inflight;
  int _gen = 0;

  @override
  QuotaState build() {
    // Reset cached quota cleanly when switching active host (local vs SSH).
    ref.watch(hostsProvider.select((h) => h.active.id));
    _inflight = null;
    _gen++;
    return const QuotaState();
  }

  /// Ensures quota is loaded if cache is empty or older than [cacheTtl].
  /// Pass [force] = true for explicit user refresh.
  Future<void> ensureLoaded({bool force = false}) {
    if (!force &&
        state.status == QuotaLoadStatus.loaded &&
        state.fetchedAt != null &&
        DateTime.now().difference(state.fetchedAt!) < cacheTtl) {
      return Future<void>.value();
    }
    if (_inflight != null) return _inflight!;
    final future = _fetchInternal();
    _inflight = future;
    return future.whenComplete(() {
      if (identical(_inflight, future)) {
        _inflight = null;
      }
    });
  }

  Future<void> _fetchInternal() async {
    final myGen = _gen;
    final conn = ref.read(activeConnectionProvider).value;
    if (conn == null) return;

    final settings = ref.read(settingsProvider);
    if (conn.isLocal &&
        settings.authMode == LocalAuthMode.geminiApiKey &&
        settings.apiKey.trim().isNotEmpty) {
      state = QuotaState(
        status: QuotaLoadStatus.apiKeyMode,
        fetchedAt: DateTime.now(),
      );
      return;
    }

    state = state.copyWith(
      status: state.hasData ? state.status : QuotaLoadStatus.loading,
      isRefreshing: true,
      clearError: true,
    );

    try {
      String stdout = '';
      String stderr = '';
      int exitCode = 0;

      if (conn.isLocal) {
        final raw = await ref.read(runtimeChannelProvider).fetchQuota();
        if (!ref.mounted || _gen != myGen) return;
        if (raw['unsupported'] == true) {
          state = state.copyWith(
            status: state.hasData ? state.status : QuotaLoadStatus.unavailable,
            isRefreshing: false,
            errorMessage: '当前环境不支持本机额度查询',
          );
          return;
        }
        if (raw['apiKeyMode'] == true) {
          state = QuotaState(
            status: QuotaLoadStatus.apiKeyMode,
            fetchedAt: DateTime.now(),
          );
          return;
        }
        stdout = raw['stdout'] as String? ?? '';
        stderr = raw['stderr'] as String? ?? '';
        exitCode = (raw['exitCode'] as num?)?.toInt() ?? 0;
      } else if (conn.sshConnection != null) {
        stdout = await conn.sshConnection!.fetchQuotaJson();
        if (!ref.mounted || _gen != myGen) return;
      } else {
        state = state.copyWith(
          status: QuotaLoadStatus.unavailable,
          isRefreshing: false,
          errorMessage: '当前连接不支持查询额度',
        );
        return;
      }

      final parsed = parseAgyUsageCliOutput(
        stdout,
        stderr: stderr,
        exitCode: exitCode,
      );
      if (!ref.mounted || _gen != myGen) return;

      if (parsed.status == QuotaLoadStatus.loaded) {
        state = QuotaState(
          status: QuotaLoadStatus.loaded,
          groups: parsed.groups,
          description: parsed.description,
          fetchedAt: DateTime.now(),
          isRefreshing: false,
        );
      } else if (state.hasData && parsed.status == QuotaLoadStatus.unavailable) {
        // Keep last known good quota visible while reporting refresh error.
        state = state.copyWith(
          isRefreshing: false,
          errorMessage: parsed.errorMessage,
        );
      } else {
        state = QuotaState(
          status: parsed.status,
          errorMessage: parsed.errorMessage,
          fetchedAt: DateTime.now(),
          isRefreshing: false,
        );
      }
    } catch (e) {
      if (!ref.mounted || _gen != myGen) return;
      state = state.copyWith(
        status: state.hasData ? state.status : QuotaLoadStatus.unavailable,
        isRefreshing: false,
        errorMessage: '查询额度失败：$e',
      );
    }
  }
}

final quotaProvider = NotifierProvider<QuotaController, QuotaState>(
  QuotaController.new,
);
