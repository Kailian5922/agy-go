import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_state.dart';
import 'phone_state.dart';
import 'runtime_state.dart';

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
    this.canDrawOverlays = false,
  });

  final bool showInApp;
  final bool showSystemOverlay;
  final bool canDrawOverlays;

  PetSettingsState copyWith({
    bool? showInApp,
    bool? showSystemOverlay,
    bool? canDrawOverlays,
  }) => PetSettingsState(
    showInApp: showInApp ?? this.showInApp,
    showSystemOverlay: showSystemOverlay ?? this.showSystemOverlay,
    canDrawOverlays: canDrawOverlays ?? this.canDrawOverlays,
  );
}

class PetController extends Notifier<PetSettingsState> {
  static const _channel = MethodChannel('agy/pet');
  static const _kInApp = 'agy.pet.inApp';
  static const _kOverlay = 'agy.pet.overlay';

  @override
  PetSettingsState build() {
    unawaited(_load());
    return const PetSettingsState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final inApp = prefs.getBool(_kInApp) ?? true;
      final overlay = prefs.getBool(_kOverlay) ?? false;
      final canDraw = await _checkPermission();
      if (!ref.mounted) return;
      state = PetSettingsState(
        showInApp: inApp,
        showSystemOverlay: overlay && canDraw,
        canDrawOverlays: canDraw,
      );
      if (overlay && canDraw) {
        await _syncOverlayVisible(true, PetMood.idle);
      }
    } catch (_) {}
  }

  Future<void> refreshPermission() async {
    final canDraw = await _checkPermission();
    if (!ref.mounted) return;
    state = state.copyWith(canDrawOverlays: canDraw);
  }

  Future<void> setShowInApp(bool enabled) async {
    state = state.copyWith(showInApp: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInApp, enabled);
  }

  Future<bool> setShowSystemOverlay(bool enabled) async {
    if (enabled) {
      final canDraw = await _checkPermission();
      if (!canDraw) {
        await requestOverlayPermission();
        return false;
      }
    }
    final ok = await _syncOverlayVisible(enabled, ref.read(petMoodProvider));
    state = state.copyWith(
      showSystemOverlay: enabled ? ok : false,
      canDrawOverlays: await _checkPermission(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOverlay, state.showSystemOverlay);
    return ok;
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
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
    }
  }

  Future<bool> _checkPermission() async {
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> _syncOverlayVisible(bool visible, PetMood mood) async {
    try {
      return await _channel.invokeMethod<bool>('setOverlayVisible', {
            'visible': visible,
            'mood': mood.wire,
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
  } else if (chat.isBusy) {
    final last = chat.transcript.items.isNotEmpty ? chat.transcript.items.last : null;
    final hasRunningTool = last != null &&
        last.runtimeType.toString() == 'AssistantTranscriptItem' &&
        (last as dynamic).toolCalls.any((dynamic t) => t.status.name == 'inProgress');
    mood = hasRunningTool ? PetMood.working : PetMood.thinking;
  } else if (!runtime.status.isRunning && chat.transcript.items.isEmpty) {
    mood = PetMood.sleeping;
  } else if (chat.transcript.items.isNotEmpty) {
    mood = PetMood.happy;
  } else {
    mood = PetMood.idle;
  }

  unawaited(ref.read(petSettingsProvider.notifier).pushMoodToOverlay(mood));
  return mood;
});
