import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppAccentId {
  nebula,
  aurora,
  slate,
  amber,
  emerald,
  rose;

  static AppAccentId parse(String? raw) => AppAccentId.values.firstWhere(
    (e) => e.name == raw,
    orElse: () => AppAccentId.nebula,
  );
}

enum LocalAuthMode {
  oauth,
  geminiApiKey;

  String get wireValue =>
      this == LocalAuthMode.geminiApiKey ? 'gemini_api_key' : 'oauth';

  static LocalAuthMode parse(String? raw) =>
      raw == 'gemini_api_key' ? LocalAuthMode.geminiApiKey : LocalAuthMode.oauth;
}

class AppSettings {
  const AppSettings({
    this.loaded = false,
    this.themeMode = ThemeMode.system,
    this.accent = AppAccentId.nebula,
    this.glassBlur = true,
    this.authMode = LocalAuthMode.oauth,
    this.apiKey = '',
    this.customBaseUrl = '',
    this.autoStartLocalEngine = true,
  });

  final bool loaded;
  final ThemeMode themeMode;
  final AppAccentId accent;
  final bool glassBlur;
  final LocalAuthMode authMode;
  final String apiKey;
  final String customBaseUrl;
  final bool autoStartLocalEngine;

  AppSettings copyWith({
    bool? loaded,
    ThemeMode? themeMode,
    AppAccentId? accent,
    bool? glassBlur,
    LocalAuthMode? authMode,
    String? apiKey,
    String? customBaseUrl,
    bool? autoStartLocalEngine,
  }) => AppSettings(
    loaded: loaded ?? this.loaded,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    glassBlur: glassBlur ?? this.glassBlur,
    authMode: authMode ?? this.authMode,
    apiKey: apiKey ?? this.apiKey,
    customBaseUrl: customBaseUrl ?? this.customBaseUrl,
    autoStartLocalEngine: autoStartLocalEngine ?? this.autoStartLocalEngine,
  );
}

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

class SettingsController extends Notifier<AppSettings> {
  static const _kThemeMode = 'agy.themeMode';
  static const _kAccent = 'agy.accent';
  static const _kGlassBlur = 'agy.glassBlur';
  static const _kAuthMode = 'agy.authMode';
  static const _kBaseUrl = 'agy.customBaseUrl';
  static const _kAutoStart = 'agy.autoStartLocal';
  static const _kApiKey = 'agy.secret.geminiApiKey';

  @override
  AppSettings build() {
    unawaited(_load());
    return const AppSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String apiKey = '';
      try {
        apiKey = await ref.read(secureStorageProvider).read(key: _kApiKey) ?? '';
      } catch (_) {}

      final themeIdx = prefs.getInt(_kThemeMode);
      final themeMode = themeIdx != null &&
              themeIdx >= 0 &&
              themeIdx < ThemeMode.values.length
          ? ThemeMode.values[themeIdx]
          : ThemeMode.system;

      state = AppSettings(
        loaded: true,
        themeMode: themeMode,
        accent: AppAccentId.parse(prefs.getString(_kAccent)),
        glassBlur: prefs.getBool(_kGlassBlur) ?? true,
        authMode: LocalAuthMode.parse(prefs.getString(_kAuthMode)),
        apiKey: apiKey,
        customBaseUrl: prefs.getString(_kBaseUrl) ?? '',
        autoStartLocalEngine: prefs.getBool(_kAutoStart) ?? true,
      );
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeMode, mode.index);
  }

  Future<void> setAccent(AppAccentId accent) async {
    state = state.copyWith(accent: accent);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, accent.name);
  }

  Future<void> setGlassBlur(bool enabled) async {
    state = state.copyWith(glassBlur: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGlassBlur, enabled);
  }

  Future<void> setAutoStartLocalEngine(bool enabled) async {
    state = state.copyWith(autoStartLocalEngine: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoStart, enabled);
  }

  Future<void> setAuthConfig({
    required LocalAuthMode mode,
    required String apiKey,
    required String customBaseUrl,
  }) async {
    state = state.copyWith(
      authMode: mode,
      apiKey: apiKey.trim(),
      customBaseUrl: customBaseUrl.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthMode, mode.wireValue);
    await prefs.setString(_kBaseUrl, customBaseUrl.trim());
    try {
      final storage = ref.read(secureStorageProvider);
      if (apiKey.trim().isEmpty) {
        await storage.delete(key: _kApiKey);
      } else {
        await storage.write(key: _kApiKey, value: apiKey.trim());
      }
    } catch (_) {}
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
