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

  Future<void> start({
    bool? phoneStorage,
    List<String>? extraBinds,
    String? workingDir,
  }) async {
    await _methods.invokeMethod<void>('start', {
      'phoneStorage': ?phoneStorage,
      'extraBinds': ?extraBinds,
      'workingDir': ?workingDir,
    });
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

  Future<void> setExecutionPolicy({
    required String agentMode,
    required String toolPermission,
    required String artifactReviewPolicy,
    required bool allowNonWorkspaceAccess,
    required String queuedMessages,
  }) async {
    try {
      await _methods.invokeMethod<void>('setExecutionPolicy', {
        'agentMode': agentMode,
        'toolPermission': toolPermission,
        'artifactReviewPolicy': artifactReviewPolicy,
        'allowNonWorkspaceAccess': allowNonWorkspaceAccess,
        'queuedMessages': queuedMessages,
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

  Future<PhoneStorageStatus> storageStatus() async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>('storageStatus');
      return PhoneStorageStatus.fromMap(raw ?? const {});
    } on MissingPluginException {
      return const PhoneStorageStatus();
    }
  }

  Future<PhoneStorageStatus> requestStorage() async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>('requestStorage');
      return PhoneStorageStatus.fromMap(raw ?? const {});
    } on MissingPluginException {
      return const PhoneStorageStatus();
    }
  }

  Future<bool> openAllFilesAccess() async {
    try {
      return await _methods.invokeMethod<bool>('openAllFilesAccess') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<PhoneStorageStatus> setPhoneStorage(bool enabled) async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
        'setPhoneStorage',
        {'enabled': enabled},
      );
      return PhoneStorageStatus.fromMap(raw ?? const {});
    } on MissingPluginException {
      return const PhoneStorageStatus();
    }
  }

  Future<void> setWorkspaceBinds(List<String> paths) async {
    try {
      await _methods.invokeMethod<void>('setWorkspaceBinds', {'paths': paths});
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

  Future<Map<String, Object?>> fetchQuota() async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>('fetchQuota');
      if (raw == null) return const {};
      return {
        for (final entry in raw.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    } on MissingPluginException {
      return const {'unsupported': true};
    }
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
