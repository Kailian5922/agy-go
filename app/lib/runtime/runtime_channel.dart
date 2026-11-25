import 'dart:async';

import 'package:flutter/services.dart';

import 'runtime_models.dart';

/// Platform channel bridge to Android's Kotlin `RuntimePlugin`.
class RuntimeChannel {
  const RuntimeChannel();

  static const _methods = MethodChannel('agy/runtime');
  static const _events = EventChannel('agy/runtime/events');

  Future<RuntimeStatus> getStatus() async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>('getStatus');
      if (raw == null) return const RuntimeStatus.initial();
      return RuntimeStatus.fromMap(raw);
    } on MissingPluginException {
      return const RuntimeStatus(
        phase: RuntimePhase.notInstalled,
        nativeSupported: false,
        error: 'Local runtime is only available on Android devices.',
      );
    }
  }

  Future<List<String>> getLogs() async {
    try {
      final raw = await _methods.invokeMethod<List<Object?>>('getLogs');
      return raw?.whereType<String>().toList() ?? const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> install() async {
    await _methods.invokeMethod<void>('install');
  }

  Future<RuntimeUpdateCheck> checkUpdate() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>('checkUpdate');
    return RuntimeUpdateCheck.fromMap(raw ?? const {});
  }

  Future<void> start() async {
    await _methods.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    await _methods.invokeMethod<void>('stop');
  }

  Future<void> reset({bool keepHome = true}) async {
    await _methods.invokeMethod<void>('reset', {'keepHome': keepHome});
  }

  Future<void> setAuthConfig({
    required String mode,
    required String apiKey,
    required String baseUrl,
  }) async {
    try {
      await _methods.invokeMethod<void>('setAuthConfig', {
        'mode': mode,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
      });
    } on MissingPluginException {
      // Non-Android desktop/test environments.
    }
  }

  Future<void> setPreferProot(bool enabled) async {
    try {
      await _methods.invokeMethod<void>('setPreferProot', {'enabled': enabled});
    } on MissingPluginException {
      // Non-Android desktop/test environments.
    }
  }

  Future<void> startOAuthLogin() async {
    await _methods.invokeMethod<void>('startOAuthLogin');
  }

  Future<void> submitOAuthCode(String code) async {
    await _methods.invokeMethod<void>('submitOAuthCode', {'code': code});
  }

  Stream<RuntimeEvent> events() {
    try {
      return _events
          .receiveBroadcastStream()
          .map(RuntimeEvent.parse)
          .where((e) => e != null)
          .cast<RuntimeEvent>();
    } catch (_) {
      return const Stream.empty();
    }
  }
}
