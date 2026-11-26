import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_state.dart';
import 'runtime_state.dart';

enum PhoneSafetyMode {
  confirmAll('confirm_all', '逐项确认（最安全）', '每次点按、滑动、输入和打开应用前均弹窗确认'),
  confirmSensitive('confirm_sensitive', '确认修改操作', '读屏自动放行，所有点按/输入/打开应用均需确认'),
  autoNonFinancial('auto_non_financial', '自动放行非敏感操作', '普通操作自动执行；银行/支付/密码及敏感词操作强制确认');

  const PhoneSafetyMode(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  static PhoneSafetyMode parse(Object? raw) => PhoneSafetyMode.values.firstWhere(
    (m) => m.wire == raw,
    orElse: () => PhoneSafetyMode.confirmAll,
  );
}

class PhoneApprovalPrompt {
  const PhoneApprovalPrompt({
    required this.id,
    required this.tool,
    required this.summary,
    required this.riskLevel,
    this.foregroundPackage,
    required this.reason,
  });

  factory PhoneApprovalPrompt.fromMap(Map<Object?, Object?> raw) =>
      PhoneApprovalPrompt(
        id: raw['id'] as String? ?? '',
        tool: raw['tool'] as String? ?? '',
        summary: raw['summary'] as String? ?? '',
        riskLevel: raw['riskLevel'] as String? ?? 'normal',
        foregroundPackage: raw['foregroundPackage'] as String?,
        reason: raw['reason'] as String? ?? '',
      );

  final String id;
  final String tool;
  final String summary;
  final String riskLevel;
  final String? foregroundPackage;
  final String reason;

  bool get isHighRisk => riskLevel == 'protected' || riskLevel == 'sensitive';
}

class PhoneAuditEntry {
  const PhoneAuditEntry({
    required this.at,
    required this.tool,
    required this.summary,
    required this.outcome,
  });

  factory PhoneAuditEntry.fromMap(Map<Object?, Object?> raw) => PhoneAuditEntry(
    at: DateTime.fromMillisecondsSinceEpoch((raw['atMs'] as num?)?.toInt() ?? 0),
    tool: raw['tool'] as String? ?? '',
    summary: raw['summary'] as String? ?? '',
    outcome: raw['outcome'] as String? ?? '',
  );

  final DateTime at;
  final String tool;
  final String summary;
  final String outcome;
}

class PhoneSelfCheckReport {
  const PhoneSelfCheckReport({
    required this.ok,
    required this.mcpProbeOk,
    required this.mcpProbeDetail,
    required this.mcpConfigOk,
    required this.mcpClientConnected,
    required this.accessibilityConnected,
    required this.accessibilityEnabledInSettings,
    required this.screenReadOk,
    required this.summary,
    this.restrictedSettings,
    this.mcpConfigPath,
  });

  factory PhoneSelfCheckReport.fromMap(Map<Object?, Object?> raw) =>
      PhoneSelfCheckReport(
        ok: raw['ok'] == true,
        mcpProbeOk: raw['mcpProbeOk'] == true,
        mcpProbeDetail: raw['mcpProbeDetail'] as String? ?? '',
        mcpConfigOk: raw['mcpConfigOk'] == true,
        mcpClientConnected: raw['mcpClientConnected'] == true,
        accessibilityConnected: raw['accessibilityConnected'] == true,
        accessibilityEnabledInSettings:
            raw['accessibilityEnabledInSettings'] == true,
        screenReadOk: raw['screenReadOk'] == true,
        summary: raw['summary'] as String? ?? '',
        restrictedSettings: raw['restrictedSettings'] as String?,
        mcpConfigPath: raw['mcpConfigPath'] as String?,
      );

  final bool ok;
  final bool mcpProbeOk;
  final String mcpProbeDetail;
  final bool mcpConfigOk;
  final bool mcpClientConnected;
  final bool accessibilityConnected;
  final bool accessibilityEnabledInSettings;
  final bool screenReadOk;
  final String summary;
  final String? restrictedSettings;
  final String? mcpConfigPath;
}

class PhoneControlState {
  const PhoneControlState({
    this.enabled = false,
    this.accessibilityConnected = false,
    this.accessibilityEnabledInSettings = false,
    this.restrictedSettings,
    this.safetyMode = PhoneSafetyMode.confirmAll,
    this.mcpUrl,
    this.mcpToken,
    this.mcpClientConnected = false,
    this.mcpClientName,
    this.mcpConfigPath,
    this.pendingApprovals = const [],
    this.auditLog = const [],
    this.lastSelfCheck,
    this.isChecking = false,
  });

  final bool enabled;
  final bool accessibilityConnected;
  final bool accessibilityEnabledInSettings;
  final String? restrictedSettings;
  final PhoneSafetyMode safetyMode;
  final String? mcpUrl;
  final String? mcpToken;
  final bool mcpClientConnected;
  final String? mcpClientName;
  final String? mcpConfigPath;
  final List<PhoneApprovalPrompt> pendingApprovals;
  final List<PhoneAuditEntry> auditLog;
  final PhoneSelfCheckReport? lastSelfCheck;
  final bool isChecking;

  bool get isMcpReady => enabled && mcpUrl != null && mcpToken != null;

  /// True when Android Settings lists the service as enabled but the OS hasn't bound it.
  bool get accessibilityStuckInSettings =>
      !accessibilityConnected && accessibilityEnabledInSettings;

  /// True when Android 13+ sideload restricted settings is likely blocking the accessibility toggle.
  bool get likelyBlockedByRestrictedSettings =>
      !accessibilityConnected &&
      (restrictedSettings == 'guarded' || restrictedSettings == 'acknowledged');

  PhoneControlState copyWith({
    bool? enabled,
    bool? accessibilityConnected,
    bool? accessibilityEnabledInSettings,
    String? Function()? restrictedSettings,
    PhoneSafetyMode? safetyMode,
    String? mcpUrl,
    bool clearMcp = false,
    String? mcpToken,
    bool? mcpClientConnected,
    String? Function()? mcpClientName,
    String? Function()? mcpConfigPath,
    List<PhoneApprovalPrompt>? pendingApprovals,
    List<PhoneAuditEntry>? auditLog,
    PhoneSelfCheckReport? Function()? lastSelfCheck,
    bool? isChecking,
  }) => PhoneControlState(
    enabled: enabled ?? this.enabled,
    accessibilityConnected:
        accessibilityConnected ?? this.accessibilityConnected,
    accessibilityEnabledInSettings:
        accessibilityEnabledInSettings ?? this.accessibilityEnabledInSettings,
    restrictedSettings: restrictedSettings != null
        ? restrictedSettings()
        : this.restrictedSettings,
    safetyMode: safetyMode ?? this.safetyMode,
    mcpUrl: clearMcp ? null : (mcpUrl ?? this.mcpUrl),
    mcpToken: clearMcp ? null : (mcpToken ?? this.mcpToken),
    mcpClientConnected: clearMcp
        ? false
        : (mcpClientConnected ?? this.mcpClientConnected),
    mcpClientName: clearMcp
        ? null
        : (mcpClientName != null ? mcpClientName() : this.mcpClientName),
    mcpConfigPath: mcpConfigPath != null ? mcpConfigPath() : this.mcpConfigPath,
    pendingApprovals: pendingApprovals ?? this.pendingApprovals,
    auditLog: auditLog ?? this.auditLog,
    lastSelfCheck: lastSelfCheck != null ? lastSelfCheck() : this.lastSelfCheck,
    isChecking: isChecking ?? this.isChecking,
  );
}

class PhoneControlController extends Notifier<PhoneControlState> {
  static const _methods = MethodChannel('agy/phone');
  static const _events = EventChannel('agy/phone/events');
  StreamSubscription<Object?>? _sub;

  @override
  PhoneControlState build() {
    try {
      _sub = _events.receiveBroadcastStream().listen(
        _onEvent,
        onError: (_) {},
      );
    } catch (_) {
      // Non-Android / unit test environment.
    }
    ref.onDispose(() => unawaited(_sub?.cancel()));
    unawaited(refresh());
    return const PhoneControlState();
  }

  Future<void> refresh() async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>('getStatus');
      final rawAudit = await _methods.invokeMethod<List<Object?>>('getAuditLog');
      if (!ref.mounted) return;
      if (raw != null) _applyStatusMap(raw);
      if (rawAudit != null) {
        final entries = rawAudit
            .whereType<Map<Object?, Object?>>()
            .map(PhoneAuditEntry.fromMap)
            .toList()
            .reversed
            .toList();
        state = state.copyWith(auditLog: entries);
      }
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
        'setEnabled',
        {'enabled': enabled},
      );
      if (raw != null && ref.mounted) {
        _applyStatusMap(raw);
      }
    } on MissingPluginException {
      state = state.copyWith(enabled: enabled);
    }

    if (!ref.mounted) return;
    // When toggling Phone Control while the local engine is running and idle,
    // restart `agy acp` seamlessly so it reloads `~/.gemini/config/mcp_config.json`
    // and connects to `phone` MCP immediately without requiring manual restart.
    final rt = ref.read(localRuntimeProvider).status;
    final hasActiveChat = ref.read(chatProvider).hasAnyRunningSession;
    if (rt.isRunning && !hasActiveChat) {
      unawaited(ref.read(localRuntimeProvider.notifier).restart());
    }
  }

  Future<void> setSafetyMode(PhoneSafetyMode mode) async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
        'setSafetyMode',
        {'mode': mode.wire},
      );
      if (raw != null && ref.mounted) _applyStatusMap(raw);
    } on MissingPluginException {
      state = state.copyWith(safetyMode: mode);
    }
  }

  Future<void> resolveApproval(String id, {required bool approved}) async {
    state = state.copyWith(
      pendingApprovals: state.pendingApprovals.where((p) => p.id != id).toList(),
    );
    try {
      await _methods.invokeMethod<bool>('resolveApproval', {
        'id': id,
        'approved': approved,
      });
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> emergencyStop() async {
    state = state.copyWith(
      enabled: false,
      clearMcp: true,
      pendingApprovals: const [],
    );
    try {
      await _methods.invokeMethod<void>('emergencyStop');
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _methods.invokeMethod<void>('openAccessibilitySettings');
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> openAppDetails() async {
    try {
      await _methods.invokeMethod<void>('openAppDetails');
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<PhoneSelfCheckReport?> runSelfCheck() async {
    state = state.copyWith(isChecking: true);
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
        'runSelfCheck',
      );
      if (!ref.mounted) return null;
      if (raw != null) {
        final report = PhoneSelfCheckReport.fromMap(raw);
        state = state.copyWith(
          isChecking: false,
          lastSelfCheck: () => report,
          accessibilityConnected: report.accessibilityConnected,
          accessibilityEnabledInSettings: report.accessibilityEnabledInSettings,
          restrictedSettings: () => report.restrictedSettings,
          mcpClientConnected: report.mcpClientConnected,
        );
        return report;
      }
      state = state.copyWith(isChecking: false);
      return null;
    } on MissingPluginException {
      if (ref.mounted) state = state.copyWith(isChecking: false);
      return null;
    } catch (_) {
      if (ref.mounted) state = state.copyWith(isChecking: false);
      return null;
    }
  }

  void _onEvent(Object? raw) {
    if (!ref.mounted || raw is! Map) return;
    switch (raw['type']) {
      case 'status':
        final st = raw['status'];
        if (st is Map) _applyStatusMap(st);
      case 'approvalRequest':
        final req = raw['request'];
        if (req is Map) {
          final prompt = PhoneApprovalPrompt.fromMap(req);
          state = state.copyWith(
            pendingApprovals: [
              ...state.pendingApprovals.where((p) => p.id != prompt.id),
              prompt,
            ],
          );
        }
      case 'audit':
        final entry = raw['entry'];
        if (entry is Map) {
          state = state.copyWith(
            auditLog: [
              PhoneAuditEntry.fromMap(entry),
              ...state.auditLog,
            ].take(120).toList(),
          );
        }
    }
  }

  void _applyStatusMap(Map<Object?, Object?> raw) {
    final pendingRaw = raw['pendingApprovals'];
    final pending = pendingRaw is List
        ? pendingRaw
              .whereType<Map<Object?, Object?>>()
              .map(PhoneApprovalPrompt.fromMap)
              .toList()
        : state.pendingApprovals;
    final url = raw['mcpUrl'] as String?;
    final token = raw['mcpToken'] as String?;
    state = state.copyWith(
      enabled: raw['enabled'] == true,
      accessibilityConnected: raw['accessibilityConnected'] == true,
      accessibilityEnabledInSettings:
          raw['accessibilityEnabledInSettings'] == true,
      restrictedSettings: () => raw['restrictedSettings'] as String?,
      safetyMode: PhoneSafetyMode.parse(raw['safetyMode']),
      mcpUrl: url,
      mcpToken: token,
      clearMcp: url == null,
      mcpClientConnected: raw['mcpClientConnected'] == true,
      mcpClientName: () => raw['mcpClientName'] as String?,
      mcpConfigPath: () => raw['mcpConfigPath'] as String?,
      pendingApprovals: pending,
    );
  }
}

final phoneControlProvider =
    NotifierProvider<PhoneControlController, PhoneControlState>(
      PhoneControlController.new,
    );
