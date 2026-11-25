import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class PhoneControlState {
  const PhoneControlState({
    this.enabled = false,
    this.accessibilityConnected = false,
    this.safetyMode = PhoneSafetyMode.confirmAll,
    this.mcpUrl,
    this.mcpToken,
    this.pendingApprovals = const [],
    this.auditLog = const [],
  });

  final bool enabled;
  final bool accessibilityConnected;
  final PhoneSafetyMode safetyMode;
  final String? mcpUrl;
  final String? mcpToken;
  final List<PhoneApprovalPrompt> pendingApprovals;
  final List<PhoneAuditEntry> auditLog;

  bool get isMcpReady => enabled && mcpUrl != null && mcpToken != null;

  PhoneControlState copyWith({
    bool? enabled,
    bool? accessibilityConnected,
    PhoneSafetyMode? safetyMode,
    String? mcpUrl,
    bool clearMcp = false,
    String? mcpToken,
    List<PhoneApprovalPrompt>? pendingApprovals,
    List<PhoneAuditEntry>? auditLog,
  }) => PhoneControlState(
    enabled: enabled ?? this.enabled,
    accessibilityConnected:
        accessibilityConnected ?? this.accessibilityConnected,
    safetyMode: safetyMode ?? this.safetyMode,
    mcpUrl: clearMcp ? null : (mcpUrl ?? this.mcpUrl),
    mcpToken: clearMcp ? null : (mcpToken ?? this.mcpToken),
    pendingApprovals: pendingApprovals ?? this.pendingApprovals,
    auditLog: auditLog ?? this.auditLog,
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
      if (raw != null && ref.mounted) _applyStatusMap(raw);
    } on MissingPluginException {
      state = state.copyWith(enabled: enabled);
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
      safetyMode: PhoneSafetyMode.parse(raw['safetyMode']),
      mcpUrl: url,
      mcpToken: token,
      clearMcp: url == null,
      pendingApprovals: pending,
    );
  }
}

final phoneControlProvider =
    NotifierProvider<PhoneControlController, PhoneControlState>(
      PhoneControlController.new,
    );
