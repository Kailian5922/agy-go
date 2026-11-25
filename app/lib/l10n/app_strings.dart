import 'package:material_ui/material_ui.dart';

/// Lightweight bilingual (zh / en) strings helper driven by user locale setting.
class AppStrings {
  const AppStrings._(this.isEnglish);

  final bool isEnglish;

  static AppStrings of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'zh';
    return AppStrings._(code.toLowerCase() == 'en');
  }

  String t(String zh, String en) => isEnglish ? en : zh;
}
