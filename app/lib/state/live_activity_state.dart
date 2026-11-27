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

@immutable
class _LiveEndingSnapshot {
  const _LiveEndingSnapshot({
    required this.kind,
    this.title,
    this.error,
    this.sessionId,
  });

  final LiveEndingKind kind;
  final String? title;
  final String? error;
  final String? sessionId;

  @override
  bool operator ==(Object other) =>
      other is _LiveEndingSnapshot &&
      other.kind == kind &&
      other.title == title &&
      other.error == error &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(kind, title, error, sessionId);
}

class _LiveEndingController extends Notifier<_LiveEndingSnapshot?> {
  Timer? _timer;

  @override
  _LiveEndingSnapshot? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void flash(_LiveEndingSnapshot snapshot) {
    _timer?.cancel();
    state = snapshot;
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
    NotifierProvider<_LiveEndingController, _LiveEndingSnapshot?>(
      _LiveEndingController.new,
    );

/// Pure reducer deriving the current Live Activity capsule payload from app state.
LiveActivityPayload? deriveLiveActivity({
  required ChatState chat,
  required PhoneControlState phone,
  required String sessionTitle,
  required AppSettings settings,
  required bool foreground,
  LiveEndingKind? ending,
  String? endingTitle,
  String? endingError,
  String? endingSessionId,
  Map<String, String> backgroundTitles = const {},
}) {
  final accentColor = AppAccent.fromId(settings.accent).seed.toARGB32();
  final cleanTitle = sessionTitle.trim().isNotEmpty
      ? sessionTitle.trim()
      : 'AGY Go';

  String resolveBgTitle(String sessionId, String? summaryTitle) {
    final fromSummary = summaryTitle?.trim();
    if (fromSummary != null && fromSummary.isNotEmpty) return fromSummary;
    final fromSessions = backgroundTitles[sessionId]?.trim();
    if (fromSessions != null && fromSessions.isNotEmpty) return fromSessions;
    return 'AGY Go';
  }

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

  // 2. Agent tool / command permission approval (foreground session).
  if (chat.pendingPermissions.isNotEmpty) {
    final tc = chat.pendingPermissions.first.request.toolCall;
    final summary = formatNativeToolLiveStatus(
      tc,
      workspaceCwd: chat.sessionCwd,
    );
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

  // 2b. Parked background session blocked on tool / command permission approval.
  final bgApproval = chat.backgroundSummaries.values
      .where((s) => s.hasPendingPermission)
      .firstOrNull;
  if (bgApproval != null) {
    final bgTitle = resolveBgTitle(bgApproval.sessionId, bgApproval.title);
    final detail = bgApproval.pendingPermissionLabel?.trim();
    return LiveActivityPayload(
      kind: LiveActivityKind.waiting,
      title: bgTitle,
      text: (detail != null && detail.isNotEmpty)
          ? '等待确认 · $detail'
          : '后台对话等待审批确认',
      chip: '待确认',
      publicText: 'AGY Go 在等你确认操作',
      accentColor: accentColor,
      sinceMs: bgApproval.turnStartedAt?.millisecondsSinceEpoch,
      sessionId: bgApproval.sessionId,
    );
  }

  // 3. Active turn running: surface native tool action, engine status, thought heading, or plan.
  if (chat.isBusy) {
    final lastItem = chat.transcript.items.isNotEmpty
        ? chat.transcript.items.last
        : null;
    final assistant = lastItem is AssistantTranscriptItem ? lastItem : null;
    final activeTools = assistant != null
        ? assistant.toolCalls.where((t) => t.status.isActive).toList()
        : const <AcpToolCall>[];
    final activeTool = activeTools.lastOrNull;
    final activePlan = chat.transcript.plan
        .where((p) => p.isInProgress)
        .firstOrNull;
    final nativeStatus = chat.liveStatusLabel?.trim();

    String line;
    String chip;
    if (chat.isStopping) {
      line = '正在中止当前轮次…';
      chip = '停止中';
    } else if (chat.activeRetry != null) {
      line = chat.activeRetry!.summary;
      chip = '重试中';
    } else if (activeTool != null &&
        chat.livePhase != TurnLivePhase.thinking &&
        chat.livePhase != TurnLivePhase.responding) {
      final base = formatNativeToolLiveStatus(
        activeTool,
        workspaceCwd: chat.sessionCwd,
      );
      line = activeTools.length > 1
          ? '$base (+${activeTools.length - 1})'
          : base;
      chip = '执行中';
    } else if (nativeStatus != null && nativeStatus.isNotEmpty) {
      line = nativeStatus;
      chip = '运行中';
    } else if (chat.livePhase == TurnLivePhase.thinking) {
      final heading = latestAssistantThoughtHeadline(assistant);
      line = heading != null ? '思考 · $heading' : '正在思考…';
      chip = '思考中';
    } else if (chat.livePhase == TurnLivePhase.responding) {
      line = '正在生成回复…';
      chip = '回复中';
    } else if (activeTool != null) {
      final base = formatNativeToolLiveStatus(
        activeTool,
        workspaceCwd: chat.sessionCwd,
      );
      line = activeTools.length > 1
          ? '$base (+${activeTools.length - 1})'
          : base;
      chip = '执行中';
    } else if (activePlan != null && activePlan.content.trim().isNotEmpty) {
      line = activePlan.content.trim();
      chip = '运行中';
    } else {
      line = '等待模型响应…';
      chip = '等待中';
    }

    return LiveActivityPayload(
      kind: LiveActivityKind.running,
      title: cleanTitle,
      text: line,
      chip: chip,
      publicText: 'AGY Go 正在运行',
      accentColor: accentColor,
      sinceMs: chat.turnStartedAt?.millisecondsSinceEpoch,
      sessionId: chat.sessionId,
    );
  }

  // 3b. Parked background conversation(s) still running while user browses another chat/workspace.
  if (chat.backgroundRunningIds.isNotEmpty) {
    final count = chat.backgroundRunningIds.length;
    final firstId = chat.backgroundRunningIds.first;
    final firstSummary = chat.backgroundSummaries[firstId];
    if (count == 1) {
      final bgTitle = resolveBgTitle(firstId, firstSummary?.title);
      String line;
      var chip = '后台运行';
      if (firstSummary?.activeRetrySummary != null &&
          firstSummary!.activeRetrySummary!.trim().isNotEmpty) {
        line = firstSummary.activeRetrySummary!.trim();
        chip = '重试中';
      } else if (firstSummary?.activeToolLabel != null &&
          firstSummary!.activeToolLabel!.trim().isNotEmpty &&
          firstSummary.livePhase != TurnLivePhase.thinking &&
          firstSummary.livePhase != TurnLivePhase.responding) {
        final base = firstSummary.activeToolLabel!.trim();
        line = firstSummary.activeToolCount > 1
            ? '$base (+${firstSummary.activeToolCount - 1})'
            : base;
      } else if (firstSummary?.liveStatusLabel != null &&
          firstSummary!.liveStatusLabel!.trim().isNotEmpty) {
        line = firstSummary.liveStatusLabel!.trim();
      } else if (firstSummary?.livePhase == TurnLivePhase.thinking) {
        line = '后台正在思考…';
      } else if (firstSummary?.livePhase == TurnLivePhase.responding) {
        line = '后台正在生成回复…';
      } else {
        line = '后台有 1 个对话正在运行…';
      }
      return LiveActivityPayload(
        kind: LiveActivityKind.running,
        title: bgTitle,
        text: line,
        chip: chip,
        publicText: 'AGY Go 后台对话运行中',
        accentColor: accentColor,
        sinceMs: firstSummary?.turnStartedAt?.millisecondsSinceEpoch,
        sessionId: firstId,
      );
    }

    DateTime? earliestStart;
    for (final id in chat.backgroundRunningIds) {
      final started = chat.backgroundSummaries[id]?.turnStartedAt;
      if (started != null &&
          (earliestStart == null || started.isBefore(earliestStart))) {
        earliestStart = started;
      }
    }
    return LiveActivityPayload(
      kind: LiveActivityKind.running,
      title: 'AGY Go',
      text: '后台有 $count 个对话正在运行…',
      chip: '后台运行',
      publicText: 'AGY Go 后台对话运行中',
      accentColor: accentColor,
      sinceMs: earliestStart?.millisecondsSinceEpoch,
      sessionId: firstId,
    );
  }

  // 4. Brief completion/failure pill when finished while app is in the background.
  if (!foreground && ending != null) {
    final resolvedTitle =
        (endingTitle != null && endingTitle.trim().isNotEmpty)
        ? endingTitle.trim()
        : cleanTitle;
    final resolvedSessionId = endingSessionId ?? chat.sessionId;
    if (ending == LiveEndingKind.done && settings.notifyOnTurnComplete) {
      return LiveActivityPayload(
        kind: LiveActivityKind.done,
        title: resolvedTitle,
        text: '本轮回复已完成',
        chip: '完成',
        publicText: 'AGY Go 做完了',
        accentColor: accentColor,
        sessionId: resolvedSessionId,
      );
    }
    if (ending == LiveEndingKind.failed) {
      final resolvedError =
          (endingError != null && endingError.trim().isNotEmpty)
          ? endingError.trim()
          : (chat.error?.trim().isNotEmpty == true
                ? chat.error!.trim()
                : '执行出错，点击查看');
      return LiveActivityPayload(
        kind: LiveActivityKind.failed,
        title: resolvedTitle,
        text: resolvedError,
        chip: '出错',
        publicText: 'AGY Go 出错了',
        accentColor: accentColor,
        sessionId: resolvedSessionId,
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
  final bgTitles = <String, String>{
    for (final s in sessions.sessions) s.sessionId: sessions.displayTitle(s),
  };

  return LiveActivityPush(
    enabled: true,
    activity: deriveLiveActivity(
      chat: chat,
      phone: phone,
      sessionTitle: title,
      settings: settings,
      foreground: foreground,
      ending: ending?.kind,
      endingTitle: ending?.title,
      endingError: ending?.error,
      endingSessionId: ending?.sessionId,
      backgroundTitles: bgTitles,
    ),
  );
});

/// Global bridge watched in [AgyGoApp]: tracks turn completion in background
/// and forwards deduplicated Live Activity updates to Android.
final liveActivityBridgeProvider = Provider<void>((ref) {
  final channel = ref.read(liveActivityChannelProvider);

  // Detect running -> idle transitions while backgrounded to flash 「完成」 / 「出错」.
  ref.listen<
    ({
      bool isBusy,
      String? error,
      String? sessionId,
      String? bgTitle,
    })
  >(
    chatProvider.select((c) {
      final bgId = c.backgroundRunningIds.isNotEmpty
          ? c.backgroundRunningIds.first
          : null;
      return (
        isBusy: c.hasAnyRunningSession,
        error: c.error,
        sessionId: c.isBusy ? c.sessionId : bgId,
        bgTitle: bgId != null ? c.backgroundSummaries[bgId]?.title : null,
      );
    }),
    (prev, next) {
      if (prev == null) return;
      if (!prev.isBusy && next.isBusy) {
        ref.read(_liveEndingProvider.notifier).clear();
      } else if (prev.isBusy && !next.isBusy) {
        final foreground = ref.read(appForegroundProvider);
        if (!foreground) {
          final currentChat = ref.read(chatProvider);
          final sessions = ref.read(sessionsProvider);
          final finishedId = prev.sessionId ?? currentChat.sessionId;
          final bgSummary = finishedId != null
              ? currentChat.backgroundSummaries[finishedId]
              : null;
          final effectiveError = (finishedId == currentChat.sessionId)
              ? currentChat.error
              : bgSummary?.error;
          String? finishedTitle;
          if (finishedId == currentChat.sessionId) {
            final cur = sessions.currentSession;
            finishedTitle =
                currentChat.transcript.title?.trim().isNotEmpty == true
                ? currentChat.transcript.title!.trim()
                : (cur != null ? sessions.displayTitle(cur) : null);
          } else {
            final info = finishedId != null
                ? sessions.sessions
                      .where((s) => s.sessionId == finishedId)
                      .firstOrNull
                : null;
            finishedTitle = bgSummary?.title?.trim().isNotEmpty == true
                ? bgSummary!.title!.trim()
                : (prev.bgTitle?.trim().isNotEmpty == true
                      ? prev.bgTitle!.trim()
                      : (info != null ? sessions.displayTitle(info) : null));
          }
          ref.read(_liveEndingProvider.notifier).flash(
            _LiveEndingSnapshot(
              kind: effectiveError != null
                  ? LiveEndingKind.failed
                  : LiveEndingKind.done,
              title: finishedTitle,
              error: effectiveError,
              sessionId: finishedId,
            ),
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
