import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent palette identifiers matching DSH Go's six OKLCH presets.
enum AppAccentId {
  mist,
  daiqing,
  dusk,
  turquoise,
  amber,
  graphite;

  static AppAccentId parse(String? raw) => switch (raw) {
    'mist' || 'nebula' => AppAccentId.mist,
    'daiqing' || 'aurora' => AppAccentId.daiqing,
    'dusk' || 'rose' => AppAccentId.dusk,
    'turquoise' || 'emerald' => AppAccentId.turquoise,
    'amber' => AppAccentId.amber,
    'graphite' || 'slate' => AppAccentId.graphite,
    _ => AppAccentId.mist,
  };
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
    this.accent = AppAccentId.mist,
    this.glassBlur = true,
    this.fluidMotion = true,
    this.chatTextScale = 1.0,
    this.foldCompletedTurns = false,
    this.localeCode = 'system',
    this.authMode = LocalAuthMode.oauth,
    this.apiKey = '',
    this.customBaseUrl = '',
    this.autoStartLocalEngine = true,
    this.phoneStorage = false,
    this.autoApproveCommands = false,
    this.quickPanelSwipe = true,
  });

  final bool loaded;
  final ThemeMode themeMode;
  final AppAccentId accent;
  final bool glassBlur;
  final bool fluidMotion;
  final double chatTextScale;
  final bool foldCompletedTurns;
  final String localeCode; // 'system' | 'zh' | 'en'
  final LocalAuthMode authMode;
  final String apiKey;
  final String customBaseUrl;
  final bool autoStartLocalEngine;
  final bool phoneStorage;
  final bool autoApproveCommands;
  final bool quickPanelSwipe;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  Locale? get locale => switch (localeCode) {
    'zh' => const Locale('zh', 'CN'),
    'en' => const Locale('en'),
    _ => null,
  };

  AppSettings copyWith({
    bool? loaded,
    ThemeMode? themeMode,
    AppAccentId? accent,
    bool? glassBlur,
    bool? fluidMotion,
    double? chatTextScale,
    bool? foldCompletedTurns,
    String? localeCode,
    LocalAuthMode? authMode,
    String? apiKey,
    String? customBaseUrl,
    bool? autoStartLocalEngine,
    bool? phoneStorage,
    bool? autoApproveCommands,
    bool? quickPanelSwipe,
  }) => AppSettings(
    loaded: loaded ?? this.loaded,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    glassBlur: glassBlur ?? this.glassBlur,
    fluidMotion: fluidMotion ?? this.fluidMotion,
    chatTextScale: chatTextScale ?? this.chatTextScale,
    foldCompletedTurns: foldCompletedTurns ?? this.foldCompletedTurns,
    localeCode: localeCode ?? this.localeCode,
    authMode: authMode ?? this.authMode,
    apiKey: apiKey ?? this.apiKey,
    customBaseUrl: customBaseUrl ?? this.customBaseUrl,
    autoStartLocalEngine: autoStartLocalEngine ?? this.autoStartLocalEngine,
    phoneStorage: phoneStorage ?? this.phoneStorage,
    autoApproveCommands: autoApproveCommands ?? this.autoApproveCommands,
    quickPanelSwipe: quickPanelSwipe ?? this.quickPanelSwipe,
  );
}

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

class SettingsController extends Notifier<AppSettings> {
  static const _kThemeMode = 'agy.themeMode';
  static const _kAccent = 'agy.accent';
  static const _kGlassBlur = 'agy.glassBlur';
  static const _kFluidMotion = 'agy.fluidMotion';
  static const _kChatTextScale = 'agy.chatTextScale';
  static const _kFoldTurns = 'agy.foldCompletedTurns';
  static const _kLocaleCode = 'agy.localeCode';
  static const _kAuthMode = 'agy.authMode';
  static const _kBaseUrl = 'agy.customBaseUrl';
  static const _kAutoStart = 'agy.autoStartLocal';
  static const _kPhoneStorage = 'agy.phoneStorage';
  static const _kAutoApprove = 'agy.autoApproveCommands';
  static const _kQuickPanelSwipe = 'agy.quickPanelSwipe';
  static const _kApiKey = 'agy.secret.geminiApiKey';

  @override
  AppSettings build() {
    unawaited(_load());
    return const AppSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var apiKey = '';
      try {
        apiKey = await ref.read(secureStorageProvider).read(key: _kApiKey) ?? '';
      } catch (_) {}

      final themeIdx = prefs.getInt(_kThemeMode);
      final themeMode = themeIdx != null &&
              themeIdx >= 0 &&
              themeIdx < ThemeMode.values.length
          ? ThemeMode.values[themeIdx]
          : ThemeMode.system;

      if (!ref.mounted) return;
      state = AppSettings(
        loaded: true,
        themeMode: themeMode,
        accent: AppAccentId.parse(prefs.getString(_kAccent)),
        glassBlur: prefs.getBool(_kGlassBlur) ?? true,
        fluidMotion: prefs.getBool(_kFluidMotion) ?? true,
        chatTextScale: (prefs.getDouble(_kChatTextScale) ?? 1.0).clamp(0.85, 1.3),
        foldCompletedTurns: prefs.getBool(_kFoldTurns) ?? false,
        localeCode: prefs.getString(_kLocaleCode) ?? 'system',
        authMode: LocalAuthMode.parse(prefs.getString(_kAuthMode)),
        apiKey: apiKey,
        customBaseUrl: prefs.getString(_kBaseUrl) ?? '',
        autoStartLocalEngine: prefs.getBool(_kAutoStart) ?? true,
        phoneStorage: prefs.getBool(_kPhoneStorage) ?? false,
        autoApproveCommands: prefs.getBool(_kAutoApprove) ?? false,
        quickPanelSwipe: prefs.getBool(_kQuickPanelSwipe) ?? true,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> setLocaleCode(String code) async {
    state = state.copyWith(localeCode: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleCode, code);
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

  Future<void> setFluidMotion(bool enabled) async {
    state = state.copyWith(fluidMotion: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFluidMotion, enabled);
  }

  Future<void> setChatTextScale(double scale) async {
    final clamped = scale.clamp(0.85, 1.3);
    state = state.copyWith(chatTextScale: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kChatTextScale, clamped);
  }

  Future<void> setFoldCompletedTurns(bool enabled) async {
    state = state.copyWith(foldCompletedTurns: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFoldTurns, enabled);
  }

  Future<void> setAutoStartLocalEngine(bool enabled) async {
    state = state.copyWith(autoStartLocalEngine: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoStart, enabled);
  }

  Future<void> setPhoneStorage(bool enabled) async {
    state = state.copyWith(phoneStorage: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPhoneStorage, enabled);
  }

  Future<void> setAutoApproveCommands(bool enabled) async {
    state = state.copyWith(autoApproveCommands: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoApprove, enabled);
  }

  Future<void> setQuickPanelSwipe(bool enabled) async {
    state = state.copyWith(quickPanelSwipe: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kQuickPanelSwipe, enabled);
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
