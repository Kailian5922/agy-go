// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'state/chat_state.dart';
import 'state/live_activity_state.dart';
import 'state/settings_state.dart';
import 'ui/common/side_insets.dart';
import 'ui/shell/home_shell.dart';
import 'ui/theme/theme.dart';

class AgyGoApp extends ConsumerStatefulWidget {
  const AgyGoApp({super.key, this.home});

  /// Replaces [HomeShell] in widget tests.
  final Widget? home;

  @override
  ConsumerState<AgyGoApp> createState() => _AgyGoAppState();
}

class _AgyGoAppState extends ConsumerState<AgyGoApp>
    with WidgetsBindingObserver {
  static const _systemChannel = MethodChannel('agy/system');

  AppAccent? _accent;
  bool? _glassBlur;
  bool? _instantPages;
  bool? _fluid;
  bool? _hideStatusBar;
  bool? _keepScreenOn;
  late ThemeData _light;
  late ThemeData _dark;
  bool _settled = false;
  final _layersKey = GlobalKey(debugLabel: 'agy app layers');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (_keepScreenOn == true) {
      unawaited(
        _systemChannel
            .invokeMethod<bool>('setKeepScreenOn', {'enabled': false})
            .catchError((_) => false),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    ref.read(appForegroundProvider.notifier).setForeground(fg);
    if (fg) {
      ref.invalidate(liveActivityStatusProvider);
    }
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  void _syncStatusBar(bool hide) {
    if (_hideStatusBar == hide) return;
    _hideStatusBar = hide;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        hide ? SystemUiMode.manual : SystemUiMode.edgeToEdge,
        overlays: hide ? const [SystemUiOverlay.bottom] : SystemUiOverlay.values,
      ),
    );
    unawaited(
      _systemChannel
          .invokeMethod<bool>('setHideStatusBar', {'enabled': hide})
          .catchError((_) => false),
    );
  }

  void _syncKeepScreenOn(bool enabled) {
    if (_keepScreenOn == enabled) return;
    _keepScreenOn = enabled;
    unawaited(
      _systemChannel
          .invokeMethod<bool>('setKeepScreenOn', {'enabled': enabled})
          .catchError((_) => false),
    );
  }

  void _ensureThemes({
    required AppAccent accent,
    required bool glassBlur,
    required bool instantPages,
    required bool fluid,
  }) {
    if (accent == _accent &&
        glassBlur == _glassBlur &&
        instantPages == _instantPages &&
        fluid == _fluid) {
      return;
    }
    _accent = accent;
    _glassBlur = glassBlur;
    _instantPages = instantPages;
    _fluid = fluid;
    _light = buildLightTheme(
      accent: accent,
      glassBlur: glassBlur,
      glyphLocale: const Locale('zh', 'CN'),
      instantPages: instantPages,
      fluid: fluid,
    );
    _dark = buildDarkTheme(
      accent: accent,
      glassBlur: glassBlur,
      glyphLocale: const Locale('zh', 'CN'),
      instantPages: instantPages,
      fluid: fluid,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(liveActivityBridgeProvider);
    final settings = ref.watch(settingsProvider);
    final foreground = ref.watch(appForegroundProvider);
    final chatBusy = ref.watch(
      chatProvider.select((c) => c.hasAnyRunningSession),
    );
    final reduced = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final fluid = settings.fluidMotion && !reduced;

    _syncStatusBar(settings.hideStatusBar);
    _syncKeepScreenOn(
      settings.keepScreenOnWhileRunning && foreground && chatBusy,
    );
    _ensureThemes(
      accent: AppAccent.fromId(settings.accent),
      glassBlur: settings.glassBlur,
      instantPages: reduced,
      fluid: fluid,
    );

    if (settings.loaded && !_settled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _settled = true);
    }

    return MaterialApp(
      title: 'AGY Go',
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: settings.themeMode,
      themeAnimationStyle: _settled && !reduced
          ? const AnimationStyle(
              duration: AppMotion.standard,
              curve: AppMotion.std,
            )
          : const AnimationStyle(duration: Duration.zero),
      locale: settings.locale ?? const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => AppMotionScope(
        key: _layersKey,
        fluid: fluid,
        child: MirroredSideInsets(child: child!),
      ),
      home: widget.home ?? const HomeShell(),
    );
  }
}
