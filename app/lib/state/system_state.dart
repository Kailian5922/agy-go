import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PickedMediaItem {
  const PickedMediaItem({
    required this.name,
    required this.path,
    required this.mimeType,
    this.sizeBytes = 0,
    this.bytes,
  });

  factory PickedMediaItem.fromMap(Map<Object?, Object?> raw) => PickedMediaItem(
    name: raw['name'] as String? ?? 'attachment',
    path: raw['path'] as String? ?? '',
    mimeType: raw['mimeType'] as String? ?? 'application/octet-stream',
    sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
    bytes: raw['bytes'] is Uint8List ? raw['bytes'] as Uint8List : null,
  );

  final String name;
  final String path;
  final String mimeType;
  final int sizeBytes;
  final Uint8List? bytes;

  bool get isImage => mimeType.toLowerCase().startsWith('image/');
}

class DeviceSystemInfo {
  const DeviceSystemInfo({
    this.manufacturer = 'Android',
    this.brand = '',
    this.model = '',
    this.sdkInt = 0,
    this.ignoringBatteryOptimizations = false,
    this.versionName = '0.1.0',
    this.versionCode = 1,
  });

  factory DeviceSystemInfo.fromMap(Map<Object?, Object?> raw) =>
      DeviceSystemInfo(
        manufacturer: raw['manufacturer'] as String? ?? 'Android',
        brand: raw['brand'] as String? ?? '',
        model: raw['model'] as String? ?? '',
        sdkInt: (raw['sdkInt'] as num?)?.toInt() ?? 0,
        ignoringBatteryOptimizations:
            raw['ignoringBatteryOptimizations'] == true,
        versionName: raw['versionName'] as String? ?? '0.1.0',
        versionCode: (raw['versionCode'] as num?)?.toInt() ?? 1,
      );

  final String manufacturer;
  final String brand;
  final String model;
  final int sdkInt;
  final bool ignoringBatteryOptimizations;
  final String versionName;
  final int versionCode;
}

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.releaseNotes,
    this.apkUrl,
    this.htmlUrl,
    required this.isNewer,
  });

  final String tagName;
  final String releaseNotes;
  final String? apkUrl;
  final String? htmlUrl;
  final bool isNewer;
}

class SystemToolsState {
  const SystemToolsState({
    this.device = const DeviceSystemInfo(),
    this.checkingUpdate = false,
    this.installingUpdate = false,
    this.latestRelease,
    this.updateError,
  });

  final DeviceSystemInfo device;
  final bool checkingUpdate;
  final bool installingUpdate;
  final AppReleaseInfo? latestRelease;
  final String? updateError;

  SystemToolsState copyWith({
    DeviceSystemInfo? device,
    bool? checkingUpdate,
    bool? installingUpdate,
    AppReleaseInfo? latestRelease,
    String? updateError,
    bool clearError = false,
  }) => SystemToolsState(
    device: device ?? this.device,
    checkingUpdate: checkingUpdate ?? this.checkingUpdate,
    installingUpdate: installingUpdate ?? this.installingUpdate,
    latestRelease: latestRelease ?? this.latestRelease,
    updateError: clearError ? null : (updateError ?? this.updateError),
  );
}

class SystemToolsController extends Notifier<SystemToolsState> {
  static const _channel = MethodChannel('agy/system');
  static const _latestReleaseApi =
      'https://api.github.com/repos/Kailian5922/agy-go/releases/latest';

  @override
  SystemToolsState build() {
    unawaited(refreshDeviceInfo());
    return const SystemToolsState();
  }

  Future<void> refreshDeviceInfo() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getDeviceInfo',
      );
      if (raw != null && ref.mounted) {
        state = state.copyWith(device: DeviceSystemInfo.fromMap(raw));
      }
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> requestIgnoreBatteryOptimization() async {
    try {
      await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimization');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await refreshDeviceInfo();
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> openVendorBackgroundSettings() async {
    try {
      await _channel.invokeMethod<bool>('openVendorBackgroundSettings');
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> shareBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String title = '分享',
  }) async {
    await _channel.invokeMethod<String>('shareBytes', {
      'bytes': bytes,
      'filename': filename,
      'mimeType': mimeType,
      'title': title,
    });
  }

  Future<PickedMediaItem?> pickImage() => _invokePicker('pickImage');

  Future<PickedMediaItem?> capturePhoto() => _invokePicker('capturePhoto');

  Future<PickedMediaItem?> pickFile() => _invokePicker('pickFile');

  Future<PickedMediaItem?> _invokePicker(String method) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(method);
      if (raw == null) return null;
      return PickedMediaItem.fromMap(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> notifyTurnEvent({
    required String title,
    required String body,
    bool urgent = false,
  }) async {
    try {
      await _channel.invokeMethod<bool>('notifyTurnEvent', {
        'title': title,
        'body': body,
        'urgent': urgent,
      });
    } on MissingPluginException {
      // Non-Android environment.
    }
  }

  Future<void> checkAppUpdate() async {
    state = state.copyWith(checkingUpdate: true, clearError: true);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(_latestReleaseApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'agy-go/${state.device.versionName}');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 404) {
        if (!ref.mounted) return;
        state = state.copyWith(
          checkingUpdate: false,
          latestRelease: AppReleaseInfo(
            tagName: 'v${state.device.versionName}',
            releaseNotes: '当前仓库尚未发布 GitHub Release，你正在使用最新开发版。',
            isNewer: false,
          ),
        );
        return;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException('GitHub API 返回 HTTP ${resp.statusCode}');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final notes = (json['body'] as String? ?? '').trim();
      final htmlUrl = json['html_url'] as String?;
      String? apkUrl;
      final assets = json['assets'];
      if (assets is List) {
        for (final a in assets.whereType<Map>()) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk') && (name.contains('arm64') || apkUrl == null)) {
            apkUrl = a['browser_download_url'] as String?;
          }
        }
      }
      final newer = isVersionNewer(tag, state.device.versionName);
      if (!ref.mounted) return;
      state = state.copyWith(
        checkingUpdate: false,
        latestRelease: AppReleaseInfo(
          tagName: tag,
          releaseNotes: notes,
          apkUrl: apkUrl,
          htmlUrl: htmlUrl,
          isNewer: newer,
        ),
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(checkingUpdate: false, updateError: e.toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadAndInstallUpdate() async {
    final apkUrl = state.latestRelease?.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) return;
    state = state.copyWith(installingUpdate: true, clearError: true);
    try {
      await _channel.invokeMethod<String>('downloadAndInstallApk', {
        'url': apkUrl,
      });
      if (!ref.mounted) return;
      state = state.copyWith(installingUpdate: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        installingUpdate: false,
        updateError: e.toString(),
      );
    }
  }

  static bool isVersionNewer(String remoteTag, String localVersion) {
    List<int> parseParts(String v) => v
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .split('-')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();

    final r = parseParts(remoteTag);
    final l = parseParts(localVersion);
    final len = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < len; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }
}

final systemToolsProvider =
    NotifierProvider<SystemToolsController, SystemToolsState>(
      SystemToolsController.new,
    );
