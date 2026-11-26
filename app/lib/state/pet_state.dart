import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/chat/tool_format.dart';
import 'chat_state.dart';
import 'connection_state.dart';
import 'hosts_state.dart';
import 'live_activity_state.dart';
import 'phone_state.dart';
import 'runtime_state.dart';
import 'sessions_state.dart';
import 'workspaces_state.dart';

enum PetMood {
  idle('idle', '待命'),
  thinking('thinking', '思考中'),
  working('working', '执行工具中'),
  waitingApproval('waitingApproval', '等你确认'),
  happy('happy', '已完成'),
  sleeping('sleeping', '休眠中');

  const PetMood(this.wire, this.label);

  final String wire;
  final String label;
}

class PetSettingsState {
  const PetSettingsState({
    this.showInApp = true,
    this.showSystemOverlay = false,
    this.onlyOutsideApp = true,
    this.canDrawOverlays = false,
    this.canUseAccessibilityOverlay = false,
    this.permissionMode = 'none',
    this.showing = false,
    this.pendingPrefillText,
  });

  final bool showInApp;
  final bool showSystemOverlay;
  final bool onlyOutsideApp;
  final bool canDrawOverlays;
  final bool canUseAccessibilityOverlay;

  /// `'overlay'` | `'accessibility'` | `'none'`
  final String permissionMode;
  final bool showing;
  final String? pendingPrefillText;

  bool get hasAnyOverlayPermission =>
      canDrawOverlays || canUseAccessibilityOverlay;

  PetSettingsState copyWith({
    bool? showInApp,
    bool? showSystemOverlay,
    bool? onlyOutsideApp,
    bool? canDrawOverlays,
    bool? canUseAccessibilityOverlay,
    String? permissionMode,
    bool? showing,
    String? Function()? pendingPrefillText,
  }) => PetSettingsState(
    showInApp: showInApp ?? this.showInApp,
    showSystemOverlay: showSystemOverlay ?? this.showSystemOverlay,
    onlyOutsideApp: onlyOutsideApp ?? this.onlyOutsideApp,
    canDrawOverlays: canDrawOverlays ?? this.canDrawOverlays,
    canUseAccessibilityOverlay:
        canUseAccessibilityOverlay ?? this.canUseAccessibilityOverlay,
    permissionMode: permissionMode ?? this.permissionMode,
    showing: showing ?? this.showing,
    pendingPrefillText: pendingPrefillText != null
        ? pendingPrefillText()
        : this.pendingPrefillText,
  );
}

class PetController extends Notifier<PetSettingsState> {
  static const _channel = MethodChannel('agy/pet');
  static const _kInApp = 'agy.pet.inApp';
  static const _kOverlay = 'agy.pet.overlay';
  static const _kOnlyOutside = 'agy.pet.onlyOutsideApp';

  @override
  PetSettingsState build() {
    _channel.setMethodCallHandler(_handleNativeCall);
    ref.onDispose(() {
      _channel.setMethodCallHandler(null);
    });
    unawaited(_load());
    return const PetSettingsState();
  }

  /// Exposed for unit testing native → Dart callbacks from the floating ask bar.
  Future<Object?> handleNativeCallForTest(MethodCall call) =>
      _handleNativeCall(call);

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (!ref.mounted) return null;
    final args = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'askTarget':
        return _buildAskTarget();
      case 'askSend':
        return _handleAskSend(args);
      case 'askStop':
        await ref.read(chatProvider.notifier).cancel();
        return true;
      case 'resolvePhoneApproval':
        final id = args['id'] as String? ?? '';
        final approved = args['approved'] == true;
        if (id.isNotEmpty) {
          await ref
              .read(phoneControlProvider.notifier)
              .resolveApproval(id, approved: approved);
        }
        return true;
      case 'overlayHiddenByUser':
        state = state.copyWith(showSystemOverlay: false, showing: false);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kOverlay, false);
        return true;
      case 'statusChanged':
        if (args.isNotEmpty) _applyNativeStatus(args);
        return true;
      case 'prefillComposer':
        final text = (args['text'] as String?)?.trim() ?? '';
        if (text.isNotEmpty) {
          state = state.copyWith(pendingPrefillText: () => text);
        }
        return true;
      default:
        return null;
    }
  }

  Map<String, Object?> _buildAskTarget() {
    final conn = ref.read(activeConnectionProvider).value;
    final chat = ref.read(chatProvider);
    final sessions = ref.read(sessionsProvider);
    final hosts = ref.read(hostsProvider);
    final ws = ref.read(selectedWorkspaceProvider);
    final hostLabel = hosts.activeLabel();
    final wsLabel = ws?.title.trim().isNotEmpty == true
        ? ws!.title.trim()
        : hostLabel;

    String? currentLine;
    if (chat.sessionId != null && chat.sessionId!.isNotEmpty) {
      final info = sessions.currentSession;
      final title = chat.transcript.title?.trim().isNotEmpty == true
          ? chat.transcript.title!.trim()
          : (info != null ? sessions.displayTitle(info) : '当前对话');
      final shortTitle = title.length > 20 ? '${title.substring(0, 20)}…' : title;
      currentLine = '$shortTitle · $hostLabel';
    }

    final recent = <Map<String, Object?>>[];
    for (final item in chat.transcript.items.reversed) {
      if (recent.length >= 2) break;
      if (item is AssistantTranscriptItem && item.text.trim().isNotEmpty) {
        final clean = item.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        recent.insert(0, {
          'role': 'assistant',
          'text': clean.length > 140 ? '${clean.substring(0, 140)}…' : clean,
        });
      } else if (item is UserTranscriptItem && item.text.trim().isNotEmpty) {
        final clean = item.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        recent.insert(0, {
          'role': 'user',
          'text': clean.length > 120 ? '${clean.substring(0, 120)}…' : clean,
        });
      }
    }

    String? statusText;
    if (chat.isBusy) {
      final lastItem = chat.transcript.items.isNotEmpty
          ? chat.transcript.items.last
          : null;
      final assistant = lastItem is AssistantTranscriptItem ? lastItem : null;
      final activeTool = assistant?.toolCalls
          .where((t) => t.status.isActive)
          .lastOrNull;
      final activePlan = chat.transcript.plan
          .where((p) => p.status.toLowerCase() == 'in_progress')
          .firstOrNull;
      final nativeStatus = resolveNativeHeaderStatus(
        phase: chat.livePhase,
        activeToolStatus: activeTool != null
            ? formatNativeToolLiveStatus(
                activeTool,
                workspaceCwd: chat.sessionCwd,
              )
            : null,
        nativeStatusLabel: chat.liveStatusLabel,
        activePlanLabel: activePlan?.content,
        liveThoughtHeadline: chat.livePhase == TurnLivePhase.thinking
            ? latestAssistantThoughtHeadline(assistant)
            : null,
        activeRetry: chat.activeRetry,
      );
      statusText = '$nativeStatus（可点「新对话」并发提问或点停止）';
    } else if (chat.backgroundRunningIds.isNotEmpty) {
      statusText = '后台 ${chat.backgroundRunningIds.length} 个对话运行中';
    }

    return {
      if (chat.sessionId != null && currentLine != null)
        'current': {'sessionId': chat.sessionId, 'line': currentLine},
      'fresh': {'line': '新对话 · $wsLabel'},
      if (conn == null) 'problem': '引擎未连接，请先打开 AGY Go 启动本机引擎或连接主机',
      'isBusy': chat.isBusy,
      'statusText': ?statusText,
      'recent': recent,
    };
  }

  Future<Map<String, Object?>> _handleAskSend(Map<dynamic, dynamic> args) async {
    final text = (args['text'] as String?)?.trim() ?? '';
    final fresh = args['fresh'] == true;
    if (text.isEmpty) return {'problem': '请输入提问内容'};
    final conn = ref.read(activeConnectionProvider).value;
    if (conn == null) {
      return {'problem': '引擎未连接，请先启动本机引擎或连接主机'};
    }
    try {
      final chatCtrl = ref.read(chatProvider.notifier);
      if (fresh) {
        // Parks any running foreground turn cleanly in background without interrupting it!
        chatCtrl.startNewChat();
      }
      unawaited(chatCtrl.send(text));
      return {'sent': true};
    } catch (e) {
      return {'problem': '发送失败：$e'};
    }
  }

  void clearPendingPrefill() {
    if (state.pendingPrefillText != null) {
      state = state.copyWith(pendingPrefillText: () => null);
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final inApp = prefs.getBool(_kInApp) ?? true;
      final overlay = prefs.getBool(_kOverlay) ?? false;
      final onlyOutside = prefs.getBool(_kOnlyOutside) ?? true;
      final status = await _fetchNativeStatus();
      final pendingPrefill = await _takePendingPrefill();
      if (!ref.mounted) return;
      final canDraw = status?['canDrawOverlays'] == true;
      final canA11y = status?['canUseAccessibilityOverlay'] == true;
      final mode = (status?['permissionMode'] as String?) ??
          (canDraw ? 'overlay' : (canA11y ? 'accessibility' : 'none'));
      final hasPerm = canDraw || canA11y;
      state = PetSettingsState(
        showInApp: inApp,
        showSystemOverlay: overlay && hasPerm,
        onlyOutsideApp: onlyOutside,
        canDrawOverlays: canDraw,
        canUseAccessibilityOverlay: canA11y,
        permissionMode: mode,
        showing: status?['showing'] == true,
        pendingPrefillText: pendingPrefill,
      );
      if (overlay && hasPerm) {
        await _syncOverlayVisible(
          true,
          PetMood.idle,
          onlyOutsideApp: onlyOutside,
        );
      }
    } catch (_) {}
  }

  Future<void> refreshPermission() async {
    final status = await _fetchNativeStatus();
    if (!ref.mounted || status == null) return;
    _applyNativeStatus(status);
  }

  Future<void> setShowInApp(bool enabled) async {
    state = state.copyWith(showInApp: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInApp, enabled);
  }

  Future<void> setOnlyOutsideApp(bool onlyOutside) async {
    state = state.copyWith(onlyOutsideApp: onlyOutside);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnlyOutside, onlyOutside);
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'setOnlyOutsideApp',
        {'onlyOutsideApp': onlyOutside},
      );
      if (raw != null && ref.mounted) _applyNativeStatus(raw);
    } on MissingPluginException {
      // Non-Android environment.
    } catch (_) {}
  }

  Future<bool> setShowSystemOverlay(bool enabled) async {
    if (enabled) {
      final status = await _fetchNativeStatus();
      final hasPerm = status != null
          ? (status['canDrawOverlays'] == true ||
                status['canUseAccessibilityOverlay'] == true)
          : await _checkPermission();
      if (!hasPerm) {
        await requestOverlayPermission();
        return false;
      }
    }
    final ok = await _syncOverlayVisible(
      enabled,
      ref.read(petMoodProvider),
      onlyOutsideApp: state.onlyOutsideApp,
    );
    final latest = await _fetchNativeStatus();
    if (!ref.mounted) return ok;
    state = state.copyWith(
      showSystemOverlay: enabled ? ok : false,
      canDrawOverlays: latest?['canDrawOverlays'] == true || state.canDrawOverlays,
      canUseAccessibilityOverlay:
          latest?['canUseAccessibilityOverlay'] == true,
      permissionMode:
          (latest?['permissionMode'] as String?) ?? state.permissionMode,
      showing: latest?['showing'] == true,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOverlay, state.showSystemOverlay);
    return ok;
  }

  Future<bool> openFloatingAskBar({bool fresh = false}) async {
    try {
      return await _channel.invokeMethod<bool>('openAskBar', {'fresh': fresh}) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> openAppDetails() async {
    try {
      await _channel.invokeMethod<void>('openAppDetails');
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> pushMoodToOverlay(PetMood mood) async {
    if (!state.showSystemOverlay) return;
    try {
      await _channel.invokeMethod<void>('setPetMood', {'mood': mood.wire});
    } on MissingPluginException {
      // Non-Android environment.
    } catch (_) {}
  }

  Future<void> pushOverlayState({
    required PetMood mood,
    PhoneApprovalPrompt? approval,
    ({String id, String title, String body})? replyBubble,
  }) async {
    if (!state.showSystemOverlay) return;
    try {
      await _channel.invokeMethod<void>('pushOverlayState', {
        'mood': mood.wire,
        if (approval != null)
          'approval': {
            'id': approval.id,
            'tool': approval.tool,
            'summary': approval.summary,
            'highRisk': approval.isHighRisk,
          },
        if (replyBubble != null)
          'replyBubble': {
            'id': replyBubble.id,
            'title': replyBubble.title,
            'body': replyBubble.body,
          },
      });
    } on MissingPluginException {
      // Non-Android environment.
    } catch (_) {}
  }

  void _applyNativeStatus(Map<dynamic, dynamic> raw) {
    final canDraw = raw['canDrawOverlays'] == true;
    final canA11y = raw['canUseAccessibilityOverlay'] == true;
    final mode = (raw['permissionMode'] as String?) ??
        (canDraw ? 'overlay' : (canA11y ? 'accessibility' : 'none'));
    state = state.copyWith(
      canDrawOverlays: canDraw,
      canUseAccessibilityOverlay: canA11y,
      permissionMode: mode,
      showing: raw['showing'] == true,
      onlyOutsideApp: raw['onlyOutsideApp'] is bool
          ? raw['onlyOutsideApp'] as bool
          : state.onlyOutsideApp,
    );
  }

  Future<Map<Object?, Object?>?> _fetchNativeStatus() async {
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>('getStatus');
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _takePendingPrefill() async {
    try {
      final raw = await _channel.invokeMethod<String>('takePendingPrefill');
      return raw?.trim().isNotEmpty == true ? raw!.trim() : null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _checkPermission() async {
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> _syncOverlayVisible(
    bool visible,
    PetMood mood, {
    required bool onlyOutsideApp,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('setOverlayVisible', {
            'visible': visible,
            'mood': mood.wire,
            'onlyOutsideApp': onlyOutsideApp,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

final petSettingsProvider = NotifierProvider<PetController, PetSettingsState>(
  PetController.new,
);

/// Reactive companion mood driven by active approvals, tool calls, streaming, and runtime state.
final petMoodProvider = Provider<PetMood>((ref) {
  final chat = ref.watch(chatProvider);
  final phone = ref.watch(phoneControlProvider);
  final runtime = ref.watch(localRuntimeProvider);

  final PetMood mood;
  if (chat.pendingPermissions.isNotEmpty || phone.pendingApprovals.isNotEmpty) {
    mood = PetMood.waitingApproval;
  } else if (chat.isBusy || chat.hasAnyRunningSession) {
    final last =
        chat.transcript.items.isNotEmpty ? chat.transcript.items.last : null;
    final hasRunningTool = last is AssistantTranscriptItem &&
        last.toolCalls.any((t) => t.status.isActive);
    mood = hasRunningTool ? PetMood.working : PetMood.thinking;
  } else if (!runtime.status.isRunning && chat.transcript.items.isEmpty) {
    mood = PetMood.sleeping;
  } else if (chat.transcript.items.isNotEmpty) {
    mood = PetMood.happy;
  } else {
    mood = PetMood.idle;
  }

  return mood;
});

/// Keeps the Android out-of-app floating overlay synced with live mood, Phone Control approvals,
/// and completed reply bubbles whenever AGY Go is backgrounded.
final petOverlayBridgeProvider = Provider<void>((ref) {
  final enabled = ref.watch(
    petSettingsProvider.select((p) => p.showSystemOverlay),
  );
  if (!enabled) return;

  final mood = ref.watch(petMoodProvider);
  final foreground = ref.watch(appForegroundProvider);
  final approval = ref.watch(
    phoneControlProvider.select(
      (p) => p.pendingApprovals.isNotEmpty ? p.pendingApprovals.first : null,
    ),
  );
  final lastDoneReply = ref.watch(
    chatProvider.select((c) {
      if (c.transcript.items.isEmpty) return null;
      final last = c.transcript.items.last;
      if (last is! AssistantTranscriptItem || last.isStreaming) return null;
      final clean = last.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty) return null;
      return (
        id: '${c.sessionId ?? "chat"}:${last.id}',
        title: c.transcript.title?.trim().isNotEmpty == true
            ? c.transcript.title!.trim()
            : 'AGY Go 回复',
        body: clean.length > 120 ? '${clean.substring(0, 120)}…' : clean,
      );
    }),
  );

  unawaited(
    ref.read(petSettingsProvider.notifier).pushOverlayState(
          mood: mood,
          approval: approval,
          replyBubble: foreground ? null : lastDoneReply,
        ),
  );
});
