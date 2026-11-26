// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/chat/tool_format.dart';
import '../ui/theme/theme.dart';
import 'chat_state.dart';
import 'phone_state.dart';
import 'sessions_state.dart';
import 'settings_state.dart';

enum LiveActivityKind { running, waiting, done, failed, phone }

/// Immutable live capsule notification payload pushed to Android's `LiveActivity`.
/// Value equality guarantees identical states are never reposted.
@immutable
class LiveActivityPayload {
  const LiveActivityPayload({
    required this.kind,
    required this.title,
    required this.text,
    required this.chip,
    required this.publicText,
    required this.accentColor,
    this.sinceMs,
    this.sessionId,
  });

  final LiveActivityKind kind;
  final String title;
  final String text;
  final String chip;
  final String publicText;
  final int accentColor;
  final int? sinceMs;
  final String? sessionId;

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'title': title,
    'text': text,
    'chip': chip,
    'publicText': publicText,
    'accentColor': accentColor,
    if (sinceMs != null) 'sinceMs': sinceMs,
    if (sessionId != null) 'sessionId': sessionId,
  };

  @override
  bool operator ==(Object other) =>
      other is LiveActivityPayload &&
      other.kind == kind &&
      other.title == title &&
      other.text == text &&
      other.chip == chip &&
      other.publicText == publicText &&
      other.accentColor == accentColor &&
      other.sinceMs == sinceMs &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(
    kind,
    title,
    text,
    chip,
    publicText,
    accentColor,
    sinceMs,
    sessionId,
  );
}

@immutable
class LiveActivityPush {
  const LiveActivityPush({required this.enabled, this.activity});

  final bool enabled;
  final LiveActivityPayload? activity;

  @override
  bool operator ==(Object other) =>
      other is LiveActivityPush &&
      other.enabled == enabled &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(enabled, activity);
}

@immutable
class LiveActivitySystemStatus {
  const LiveActivitySystemStatus({
    this.supported = false,
    this.allowed = false,
    this.settingsAvailable = false,
    this.xiaomiFocus = false,
    this.notificationsEnabled = true,
    this.channelOpen = true,
    this.islandVendor = false,
    this.sdk = 0,
    this.unknown = false,
  });

  factory LiveActivitySystemStatus.fromMap(Map<Object?, Object?> raw) =>
      LiveActivitySystemStatus(
        supported: raw['supported'] == true,
        allowed: raw['allowed'] == true,
        settingsAvailable: raw['settings'] == true,
        xiaomiFocus: raw['xiaomiFocus'] == true,
        notificationsEnabled: raw['notificationsEnabled'] != false,
        channelOpen: raw['channelOpen'] != false,
        islandVendor: raw['islandVendor'] == true,
        sdk: (raw['sdk'] as num?)?.toInt() ?? 0,
      );

  final bool supported;
  final bool allowed;
  final bool settingsAvailable;
  final bool xiaomiFocus;
  final bool notificationsEnabled;
  final bool channelOpen;
  final bool islandVendor;
  final int sdk;
  final bool unknown;

  bool get needsPromotionPermission => supported && !allowed;
  bool get blockedBySystemNotifications => !notificationsEnabled || !channelOpen;
}

class LiveActivityChannel {
  const LiveActivityChannel([
    this._channel = const MethodChannel('agy/system'),
  ]);

  final MethodChannel _channel;

  Future<void> push(LiveActivityPush data) async {
    try {
      await _channel.invokeMethod<bool>('updateLiveActivity', {
        'enabled': data.enabled,
        'activity': data.activity?.toMap(),
      });
    } on MissingPluginException {
      // Non-Android / unit test environment.
    } catch (_) {}
  }

  Future<LiveActivitySystemStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getLiveActivityStatus',
      );
      if (raw == null) return const LiveActivitySystemStatus(unknown: true);
      return LiveActivitySystemStatus.fromMap(raw);
    } on MissingPluginException {
      return const LiveActivitySystemStatus(unknown: true);
    } catch (_) {
      return const LiveActivitySystemStatus(unknown: true);
    }
  }

  Future<bool> openLiveSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openLiveActivitySettings') ??
          false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> preview({required int accentColor}) async {
    try {
      return await _channel.invokeMethod<bool>('previewLiveActivity', {
            'accentColor': accentColor,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

final liveActivityChannelProvider = Provider<LiveActivityChannel>(
  (ref) => const LiveActivityChannel(),
);

/// Tracks whether AGY Go is currently in the foreground (updated by [AgyGoApp]).
class AppForegroundController extends Notifier<bool> {
  @override
  bool build() => true;

  void setForeground(bool value) {
    if (state != value) state = value;
  }
}

final appForegroundProvider =
    NotifierProvider<AppForegroundController, bool>(
      AppForegroundController.new,
    );

/// Brief completion/failure banner kept alive for 12s after a background turn finishes.
enum LiveEndingKind { done, failed }

class _LiveEndingController extends Notifier<LiveEndingKind?> {
  Timer? _timer;

  @override
  LiveEndingKind? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void flash(LiveEndingKind kind) {
    _timer?.cancel();
    state = kind;
    _timer = Timer(const Duration(seconds: 12), () {
      if (ref.mounted) state = null;
    });
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    if (state != null) state = null;
  }
}

final _liveEndingProvider =
    NotifierProvider<_LiveEndingController, LiveEndingKind?>(
      _LiveEndingController.new,
    );

String _toolVerb(AcpToolKind kind) => switch (kind) {
  AcpToolKind.read => '读取',
  AcpToolKind.edit => '编辑',
  AcpToolKind.delete => '删除',
  AcpToolKind.move => '移动',
  AcpToolKind.search => '搜索',
  AcpToolKind.execute => '运行',
  AcpToolKind.fetch => '抓取',
  AcpToolKind.think => '思考',
  _ => '执行',
};

/// Pure reducer deriving the current Live Activity capsule payload from app state.
LiveActivityPayload? deriveLiveActivity({
  required ChatState chat,
  required PhoneControlState phone,
  required String sessionTitle,
  required AppSettings settings,
  required bool foreground,
  LiveEndingKind? ending,
}) {
  final accentColor = AppAccent.fromId(settings.accent).seed.toARGB32();
  final cleanTitle = sessionTitle.trim().isNotEmpty
      ? sessionTitle.trim()
      : 'AGY Go';

  // 1. Phone control approval outranks everything so the user can immediately respond.
  if (phone.pendingApprovals.isNotEmpty) {
    final approval = phone.pendingApprovals.first;
    final detail = approval.summary.trim().isNotEmpty
        ? approval.summary.trim()
        : (approval.reason.trim().isNotEmpty
              ? approval.reason.trim()
              : approval.tool);
    return LiveActivityPayload(
      kind: LiveActivityKind.waiting,
      title: '手机操控等待确认',
      text: detail,
      chip: '待确认',
      publicText: 'AGY Go 正在等待确认手机操作',
      accentColor: accentColor,
      sinceMs: chat.turnStartedAt?.millisecondsSinceEpoch,
      sessionId: chat.sessionId,
    );
  }

  // 2. Agent tool / command permission approval.
  if (chat.pendingPermissions.isNotEmpty) {
    final tc = chat.pendingPermissions.first.request.toolCall;
    final summary = formatToolSummary(tc, workspaceCwd: chat.sessionCwd);
    return LiveActivityPayload(
      kind: LiveActivityKind.waiting,
      title: cleanTitle,
      text: summary.isNotEmpty ? '等待确认 · $summary' : '等待审批确认',
      chip: '待确认',
      publicText: 'AGY Go 在等你确认操作',
      accentColor: accentColor,
      sinceMs: chat.turnStartedAt?.millisecondsSinceEpoch,
      sessionId: chat.sessionId,
    );
  }

  // 3. Active turn running (thinking / calling tools / following plan).
  if (chat.isBusy) {
    final lastItem = chat.transcript.items.isNotEmpty
        ? chat.transcript.items.last
        : null;
    final activeTool = lastItem is AssistantTranscriptItem
        ? lastItem.toolCalls.where((t) => t.status.isActive).lastOrNull
        : null;
    final activePlan = chat.transcript.plan
        .where((p) => p.status.toLowerCase() == 'in_progress')
        .firstOrNull;

    String line;
    String chip;
    if (chat.activeRetry != null) {
      line = chat.activeRetry!.summary;
      chip = '重试中';
    } else if (activeTool != null) {
      final summary = formatToolSummary(
        activeTool,
        workspaceCwd: chat.sessionCwd,
      );
      final verb = _toolVerb(activeTool.kind);
      line = summary.isNotEmpty ? '$verb · $summary' : '正在$verb…';
      chip = switch (activeTool.kind) {
        AcpToolKind.read || AcpToolKind.search || AcpToolKind.fetch => '分析中',
        AcpToolKind.edit || AcpToolKind.delete || AcpToolKind.move => '编辑中',
        _ => '干活中',
      };
    } else if (activePlan != null && activePlan.content.trim().isNotEmpty) {
      line = activePlan.content.trim();
      chip = '干活中';
    } else if (chat.livePhase == TurnLivePhase.analyzing) {
      line = chat.liveStatusLabel?.trim().isNotEmpty == true
          ? '分析中 · ${chat.liveStatusLabel!.trim()}'
          : '正在分析文件与工具结果…';
      chip = '分析中';
    } else if (chat.livePhase == TurnLivePhase.working) {
      line = chat.liveStatusLabel?.trim().isNotEmpty == true
          ? 'Working · ${chat.liveStatusLabel!.trim()}'
          : 'Working…';
      chip = '干活中';
    } else {
      line = '正在思考与生成…';
      chip = '思考中';
    }

    return LiveActivityPayload(
      kind: LiveActivityKind.running,
      title: cleanTitle,
      text: line,
      chip: chip,
      publicText: 'AGY Go 正在干活',
      accentColor: accentColor,
      sinceMs: chat.turnStartedAt?.millisecondsSinceEpoch,
      sessionId: chat.sessionId,
    );
  }

  // 3b. Parked background conversation(s) still running while user browses another chat/workspace.
  if (chat.backgroundRunningIds.isNotEmpty) {
    final count = chat.backgroundRunningIds.length;
    return LiveActivityPayload(
      kind: LiveActivityKind.running,
      title: 'AGY Go',
      text: count == 1 ? '后台有 1 个对话正在运行…' : '后台有 $count 个对话正在运行…',
      chip: '后台运行',
      publicText: 'AGY Go 后台对话运行中',
      accentColor: accentColor,
      sessionId: chat.backgroundRunningIds.first,
    );
  }

  // 4. Brief completion/failure pill when finished while app is in the background.
  if (!foreground && ending != null) {
    if (ending == LiveEndingKind.done && settings.notifyOnTurnComplete) {
      return LiveActivityPayload(
        kind: LiveActivityKind.done,
        title: cleanTitle,
        text: '本轮回复已完成',
        chip: '完成',
        publicText: 'AGY Go 做完了',
        accentColor: accentColor,
        sessionId: chat.sessionId,
      );
    }
    if (ending == LiveEndingKind.failed) {
      return LiveActivityPayload(
        kind: LiveActivityKind.failed,
        title: cleanTitle,
        text: chat.error?.trim().isNotEmpty == true
            ? chat.error!.trim()
            : '执行出错，点击查看',
        chip: '出错',
        publicText: 'AGY Go 出错了',
        accentColor: accentColor,
        sessionId: chat.sessionId,
      );
    }
  }

  return null;
}

final liveActivityPushProvider = Provider<LiveActivityPush>((ref) {
  final settings = ref.watch(settingsProvider);
  final enabled = settings.liveActivityEnabled;
  if (!enabled) {
    return const LiveActivityPush(enabled: false);
  }
  final chat = ref.watch(chatProvider);
  final phone = ref.watch(phoneControlProvider);
  final sessions = ref.watch(sessionsProvider);
  final foreground = ref.watch(appForegroundProvider);
  final ending = ref.watch(_liveEndingProvider);

  final currentSession = sessions.currentSession;
  final title = chat.transcript.title?.trim().isNotEmpty == true
      ? chat.transcript.title!.trim()
      : (currentSession != null
            ? sessions.displayTitle(currentSession)
            : 'AGY Go');

  return LiveActivityPush(
    enabled: true,
    activity: deriveLiveActivity(
      chat: chat,
      phone: phone,
      sessionTitle: title,
      settings: settings,
      foreground: foreground,
      ending: ending,
    ),
  );
});

/// Global bridge watched in [AgyGoApp]: tracks turn completion in background
/// and forwards deduplicated Live Activity updates to Android.
final liveActivityBridgeProvider = Provider<void>((ref) {
  final channel = ref.read(liveActivityChannelProvider);

  // Detect running -> idle transitions while backgrounded to flash 「完成」 / 「出错」.
  ref.listen<({bool isBusy, String? error})>(
    chatProvider.select((c) => (isBusy: c.hasAnyRunningSession, error: c.error)),
    (prev, next) {
      if (prev == null) return;
      if (!prev.isBusy && next.isBusy) {
        ref.read(_liveEndingProvider.notifier).clear();
      } else if (prev.isBusy && !next.isBusy) {
        final foreground = ref.read(appForegroundProvider);
        if (!foreground) {
          ref.read(_liveEndingProvider.notifier).flash(
            next.error != null ? LiveEndingKind.failed : LiveEndingKind.done,
          );
        }
      }
    },
  );

  // Returning to foreground clears any temporary 「完成」 / 「出错」 receipt.
  ref.listen<bool>(appForegroundProvider, (prev, next) {
    if (next) {
      ref.read(_liveEndingProvider.notifier).clear();
    }
  });

  // Push deduplicated payloads to native LiveActivity.
  ref.listen<LiveActivityPush>(
    liveActivityPushProvider,
    (prev, next) {
      if (prev == next) return;
      unawaited(channel.push(next));
    },
    fireImmediately: true,
  );
});

/// Queries Android's live capsule capability; invalidated when returning from Settings.
final liveActivityStatusProvider = FutureProvider<LiveActivitySystemStatus>(
  (ref) => ref.watch(liveActivityChannelProvider).status(),
);
