import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/settings_state.dart';
import 'ui/shell/home_shell.dart';
import 'ui/theme/app_theme.dart';

class AgyGoApp extends ConsumerWidget {
  const AgyGoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'AGY Go',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildAgyTheme(
        brightness: Brightness.light,
        accentId: settings.accent,
        glassBlur: settings.glassBlur,
      ),
      darkTheme: buildAgyTheme(
        brightness: Brightness.dark,
        accentId: settings.accent,
        glassBlur: settings.glassBlur,
      ),
      home: const HomeShell(),
    );
  }
}
