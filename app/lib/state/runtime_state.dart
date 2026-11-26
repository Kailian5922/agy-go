import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../runtime/runtime_channel.dart';
import '../runtime/runtime_models.dart';
import 'settings_state.dart';

final runtimeChannelProvider = Provider<RuntimeChannel>(
  (ref) => const RuntimeChannel(),
);

class LocalRuntimeState {
  const LocalRuntimeState({
    this.status = const RuntimeStatus.initial(),
    this.storage = const PhoneStorageStatus(),
    this.progress,
    this.logs = const [],
    this.logSeq = 0,
    this.lastLogLine,
    this.pendingOAuthUrl,
    this.updateCheck,
    this.checkingUpdate = false,
  });

  final RuntimeStatus status;
  final PhoneStorageStatus storage;
  final RuntimeProgress? progress;
  final List<String> logs;
  final int logSeq;
  final String? lastLogLine;
  final String? pendingOAuthUrl;
  final RuntimeUpdateCheck? updateCheck;
  final bool checkingUpdate;

  LocalRuntimeState copyWith({
    RuntimeStatus? status,
    PhoneStorageStatus? storage,
    RuntimeProgress? progress,
    bool clearProgress = false,
    List<String>? logs,
    int? logSeq,
    String? lastLogLine,
    String? pendingOAuthUrl,
    bool clearOAuthUrl = false,
    RuntimeUpdateCheck? updateCheck,
    bool? checkingUpdate,
  }) => LocalRuntimeState(
    status: status ?? this.status,
    storage: storage ?? this.storage,
    progress: clearProgress ? null : (progress ?? this.progress),
    logs: logs ?? this.logs,
    logSeq: logSeq ?? this.logSeq,
    lastLogLine: lastLogLine ?? this.lastLogLine,
    pendingOAuthUrl: clearOAuthUrl
        ? null
        : (pendingOAuthUrl ?? this.pendingOAuthUrl),
    updateCheck: updateCheck ?? this.updateCheck,
    checkingUpdate: checkingUpdate ?? this.checkingUpdate,
  );
}

class LocalRuntimeController extends Notifier<LocalRuntimeState> {
  static const _maxLogs = 400;
  StreamSubscription<RuntimeEvent>? _sub;
  bool _autoStartTried = false;

  @override
  LocalRuntimeState build() {
    final channel = ref.read(runtimeChannelProvider);

    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if (!next.loaded) return;
      if (prev == null ||
          prev.loaded != next.loaded ||
          prev.authMode != next.authMode ||
          prev.apiKey != next.apiKey ||
          prev.customBaseUrl != next.customBaseUrl) {
        unawaited(
          channel.setAuthConfig(
            mode: next.authMode.wireValue,
            apiKey: next.apiKey,
            baseUrl: next.customBaseUrl,
          ),
        );
      }
      if (prev == null ||
          prev.loaded != next.loaded ||
          prev.agentMode != next.agentMode ||
          prev.toolPermission != next.toolPermission ||
          prev.artifactReviewPolicy != next.artifactReviewPolicy ||
          prev.allowNonWorkspaceAccess != next.allowNonWorkspaceAccess ||
          prev.queuedBehavior != next.queuedBehavior) {
        unawaited(
          channel.setExecutionPolicy(
            agentMode: next.agentMode.wireValue,
            toolPermission: next.toolPermission.wireValue,
            artifactReviewPolicy: next.artifactReviewPolicy.wireValue,
            allowNonWorkspaceAccess: next.allowNonWorkspaceAccess,
            queuedMessages: next.queuedBehavior.wireValue,
          ),
        );
      }
      if (prev == null || prev.phoneStorage != next.phoneStorage) {
        unawaited(channel.setPhoneStorage(next.phoneStorage));
      }
    });

    _sub = channel.events().listen(_onEvent, onError: (_) {});
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sub = null;
    });

    unawaited(_hydrate(channel));
    return const LocalRuntimeState();
  }

  Future<void> _hydrate(RuntimeChannel channel) async {
    final status = await channel.getStatus();
    final logs = await channel.getLogs();
    final storage = await channel.storageStatus();
    if (!ref.mounted) return;
    state = state.copyWith(status: status, logs: logs, storage: storage);

    final settings = ref.read(settingsProvider);
    if (settings.loaded) {
      await channel.setAuthConfig(
        mode: settings.authMode.wireValue,
        apiKey: settings.apiKey,
        baseUrl: settings.customBaseUrl,
      );
      await channel.setExecutionPolicy(
        agentMode: settings.agentMode.wireValue,
        toolPermission: settings.toolPermission.wireValue,
        artifactReviewPolicy: settings.artifactReviewPolicy.wireValue,
        allowNonWorkspaceAccess: settings.allowNonWorkspaceAccess,
        queuedMessages: settings.queuedBehavior.wireValue,
      );
      await channel.setPhoneStorage(settings.phoneStorage);
    }

    if (!_autoStartTried &&
        settings.autoStartLocalEngine &&
        status.phase == RuntimePhase.installed) {
      _autoStartTried = true;
      await start();
    }
  }

  void _onEvent(RuntimeEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case RuntimeStatusEvent(:final status):
        state = state.copyWith(
          status: status,
          storage: state.storage.copyWith(
            granted: status.phoneStorageGranted,
            hostPath: status.phoneStoragePath,
          ),
          clearProgress: status.phase != RuntimePhase.installing,
        );
      case RuntimeProgressEvent(:final progress):
        state = state.copyWith(progress: progress);
      case RuntimeLogEvent(:final line):
        final next = List<String>.from(state.logs)..add(line);
        if (next.length > _maxLogs) {
          next.removeRange(0, next.length - _maxLogs);
        }
        state = state.copyWith(
          logs: next,
          logSeq: state.logSeq + 1,
          lastLogLine: line,
        );
      case RuntimeOAuthUrlEvent(:final url):
        state = state.copyWith(pendingOAuthUrl: url);
      case RuntimeOAuthDoneEvent():
        state = state.copyWith(clearOAuthUrl: true);
    }
  }

  Future<void> refreshStorage() async {
    final channel = ref.read(runtimeChannelProvider);
    final storage = await channel.storageStatus();
    final status = await channel.getStatus();
    if (!ref.mounted) return;
    state = state.copyWith(storage: storage, status: status);
  }

  Future<PhoneStorageStatus> requestStorage() async {
    final channel = ref.read(runtimeChannelProvider);
    final storage = await channel.requestStorage();
    final status = await channel.getStatus();
    if (ref.mounted) {
      state = state.copyWith(storage: storage, status: status);
    }
    return storage;
  }

  Future<bool> openAllFilesAccess() =>
      ref.read(runtimeChannelProvider).openAllFilesAccess();

  Future<void> setPhoneStorage(bool enabled) async {
    await ref.read(settingsProvider.notifier).setPhoneStorage(enabled);
    final channel = ref.read(runtimeChannelProvider);
    final storage = await channel.setPhoneStorage(enabled);
    final status = await channel.getStatus();
    if (!ref.mounted) return;
    state = state.copyWith(storage: storage, status: status);
    // In PRoot mode bind mounts are fixed at launch; restart so new mounts apply immediately.
    if (status.phase == RuntimePhase.running &&
        status.executionMode == 'proot') {
      await stop();
      await start();
    }
  }

  Future<void> installOrUpdate() async {
    await ref.read(runtimeChannelProvider).install();
  }

  Future<void> start({List<String>? extraBinds, String? workingDir}) async {
    final settings = ref.read(settingsProvider);
    final channel = ref.read(runtimeChannelProvider);
    final resolvedDir =
        workingDir ?? await _resolvePersistedLocalWorkingDir();
    await channel.setAuthConfig(
      mode: settings.authMode.wireValue,
      apiKey: settings.apiKey,
      baseUrl: settings.customBaseUrl,
    );
    await channel.start(
      phoneStorage: settings.phoneStorage,
      extraBinds: extraBinds,
      workingDir: resolvedDir,
    );
  }

  Future<String?> _resolvePersistedLocalWorkingDir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('agy.workspaces.local.local');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final selectedId = map['selectedId'] as String?;
      final list = map['workspaces'];
      if (list is! List) return null;
      String? firstPath;
      for (final item in list.whereType<Map>()) {
        final path = (item['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) continue;
        firstPath ??= path;
        if (selectedId != null && item['id'] == selectedId) {
          return path;
        }
      }
      return firstPath;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    await ref.read(runtimeChannelProvider).stop();
  }

  Future<void> restart({List<String>? extraBinds, String? workingDir}) async {
    await stop();
    await start(extraBinds: extraBinds, workingDir: workingDir);
  }

  Future<void> reset({bool keepHome = true}) async {
    await ref.read(runtimeChannelProvider).reset(keepHome: keepHome);
  }

  Future<void> setPreferProot(bool enabled) async {
    await ref.read(runtimeChannelProvider).setPreferProot(enabled);
  }

  Future<void> startOAuthLogin() async {
    state = state.copyWith(clearOAuthUrl: true);
    await ref.read(runtimeChannelProvider).startOAuthLogin();
  }

  Future<void> submitOAuthCode(String code) async {
    await ref.read(runtimeChannelProvider).submitOAuthCode(code);
  }

  Future<void> checkUpdate() async {
    state = state.copyWith(checkingUpdate: true);
    try {
      final result = await ref.read(runtimeChannelProvider).checkUpdate();
      if (!ref.mounted) return;
      state = state.copyWith(updateCheck: result, checkingUpdate: false);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(checkingUpdate: false);
    }
  }
}

final localRuntimeProvider =
    NotifierProvider<LocalRuntimeController, LocalRuntimeState>(
      LocalRuntimeController.new,
    );
