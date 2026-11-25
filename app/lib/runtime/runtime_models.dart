/// Lifecycle of the on-device Android Antigravity CLI runtime.
enum RuntimePhase {
  notInstalled,
  installing,
  installed,
  starting,
  running,
  stopping,
  error;

  static RuntimePhase parse(Object? raw) => RuntimePhase.values.firstWhere(
    (p) => p.name == raw,
    orElse: () => RuntimePhase.error,
  );

  bool get isBusy =>
      this == installing || this == starting || this == stopping;
}

class RuntimeProgress {
  const RuntimeProgress({
    required this.stage,
    required this.fraction,
    required this.detail,
  });

  final String stage;
  final double fraction;
  final String detail;
}

class PhoneStorageStatus {
  const PhoneStorageStatus({
    this.granted = false,
    this.permission = false,
    this.legacy = false,
    this.guestPath = '/sdcard',
    this.hostPath = '/storage/emulated/0',
    this.outputPath = '/storage/emulated/0/Download/AGY-Go',
    this.needsAllFilesFallback = false,
  });

  factory PhoneStorageStatus.fromMap(Map<Object?, Object?> raw) =>
      PhoneStorageStatus(
        granted: raw['granted'] == true,
        permission: raw['permission'] == true,
        legacy: raw['legacy'] == true,
        guestPath: raw['guestPath'] as String? ?? '/sdcard',
        hostPath: raw['hostPath'] as String? ?? '/storage/emulated/0',
        outputPath:
            raw['outputPath'] as String? ?? '/storage/emulated/0/Download/AGY-Go',
        needsAllFilesFallback: raw['needsAllFilesFallback'] == true,
      );

  final bool granted;
  final bool permission;
  final bool legacy;
  final String guestPath;
  final String hostPath;
  final String outputPath;
  final bool needsAllFilesFallback;
}

class RuntimeStatus {
  const RuntimeStatus({
    required this.phase,
    this.abi = 'unknown',
    this.nativeSupported = true,
    this.prootAvailable = false,
    this.preferProot = false,
    this.executionMode = 'native_bionic',
    this.installedVersion,
    this.workspacePath,
    this.homePath,
    this.phoneStorageEnabled = false,
    this.phoneStorageGranted = false,
    this.phoneStorageMounted = false,
    this.phoneStoragePath = '/storage/emulated/0',
    this.port,
    this.token,
    this.error,
    this.authMode = 'oauth',
  });

  const RuntimeStatus.initial() : this(phase: RuntimePhase.notInstalled);

  factory RuntimeStatus.fromMap(Map<Object?, Object?> raw) => RuntimeStatus(
    phase: RuntimePhase.parse(raw['phase']),
    abi: raw['abi'] as String? ?? 'unknown',
    nativeSupported: raw['nativeSupported'] == true,
    prootAvailable: raw['prootAvailable'] == true,
    preferProot: raw['preferProot'] == true,
    executionMode: raw['executionMode'] as String? ?? 'native_bionic',
    installedVersion: raw['installedVersion'] as String?,
    workspacePath: raw['workspacePath'] as String?,
    homePath: raw['homePath'] as String?,
    phoneStorageEnabled: raw['phoneStorageEnabled'] == true,
    phoneStorageGranted: raw['phoneStorageGranted'] == true,
    phoneStorageMounted: raw['phoneStorageMounted'] == true,
    phoneStoragePath: raw['phoneStoragePath'] as String? ?? '/storage/emulated/0',
    port: (raw['port'] as num?)?.toInt(),
    token: raw['token'] as String?,
    error: raw['error'] as String?,
    authMode: raw['authMode'] as String? ?? 'oauth',
  );

  final RuntimePhase phase;
  final String abi;
  final bool nativeSupported;
  final bool prootAvailable;
  final bool preferProot;
  final String executionMode;
  final String? installedVersion;
  final String? workspacePath;
  final String? homePath;
  final bool phoneStorageEnabled;
  final bool phoneStorageGranted;
  final bool phoneStorageMounted;
  final String phoneStoragePath;
  final int? port;
  final String? token;
  final String? error;
  final String authMode;

  bool get isRunning =>
      phase == RuntimePhase.running && port != null && token != null;
}

class RuntimeUpdateCheck {
  const RuntimeUpdateCheck({
    required this.latestVersion,
    required this.installedVersion,
    required this.platform,
    required this.updateAvailable,
  });

  factory RuntimeUpdateCheck.fromMap(Map<Object?, Object?> raw) =>
      RuntimeUpdateCheck(
        latestVersion: raw['latestVersion'] as String? ?? '',
        installedVersion: raw['installedVersion'] as String?,
        platform: raw['platform'] as String? ?? '',
        updateAvailable: raw['updateAvailable'] == true,
      );

  final String latestVersion;
  final String? installedVersion;
  final String platform;
  final bool updateAvailable;
}

sealed class RuntimeEvent {
  const RuntimeEvent();

  static RuntimeEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'status':
        final statusMap = raw['status'];
        if (statusMap is Map) {
          return RuntimeStatusEvent(RuntimeStatus.fromMap(statusMap));
        }
        return null;
      case 'progress':
        return RuntimeProgressEvent(
          RuntimeProgress(
            stage: raw['stage'] as String? ?? '',
            fraction: (raw['fraction'] as num?)?.toDouble() ?? 0.0,
            detail: raw['detail'] as String? ?? '',
          ),
        );
      case 'log':
        return RuntimeLogEvent(
          line: raw['line'] as String? ?? '',
          stream: raw['stream'] as String? ?? 'system',
        );
      case 'oauthUrl':
        final url = raw['url'] as String?;
        return url != null ? RuntimeOAuthUrlEvent(url) : null;
      case 'oauthDone':
        return RuntimeOAuthDoneEvent((raw['exitCode'] as num?)?.toInt() ?? -1);
      default:
        return null;
    }
  }
}

final class RuntimeStatusEvent extends RuntimeEvent {
  const RuntimeStatusEvent(this.status);
  final RuntimeStatus status;
}

final class RuntimeProgressEvent extends RuntimeEvent {
  const RuntimeProgressEvent(this.progress);
  final RuntimeProgress progress;
}

final class RuntimeLogEvent extends RuntimeEvent {
  const RuntimeLogEvent({required this.line, required this.stream});
  final String line;
  final String stream;
}

final class RuntimeOAuthUrlEvent extends RuntimeEvent {
  const RuntimeOAuthUrlEvent(this.url);
  final String url;
}

final class RuntimeOAuthDoneEvent extends RuntimeEvent {
  const RuntimeOAuthDoneEvent(this.exitCode);
  final int exitCode;
}
