import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../state/settings_state.dart';

class AccentSpec {
  const AccentSpec({
    required this.id,
    required this.label,
    required this.lightPrimary,
    required this.darkPrimary,
    required this.lightBgTop,
    required this.lightBgBottom,
    required this.darkBgTop,
    required this.darkBgBottom,
  });

  final AppAccentId id;
  final String label;
  final Color lightPrimary;
  final Color darkPrimary;
  final Color lightBgTop;
  final Color lightBgBottom;
  final Color darkBgTop;
  final Color darkBgBottom;

  static const all = <AccentSpec>[
    AccentSpec(
      id: AppAccentId.nebula,
      label: '星云蓝',
      lightPrimary: Color(0xFF3E63DD),
      darkPrimary: Color(0xFF7AA2FF),
      lightBgTop: Color(0xFFEEF3FF),
      lightBgBottom: Color(0xFFF8FAFF),
      darkBgTop: Color(0xFF0C1222),
      darkBgBottom: Color(0xFF121A2F),
    ),
    AccentSpec(
      id: AppAccentId.aurora,
      label: '极光紫',
      lightPrimary: Color(0xFF6E56CF),
      darkPrimary: Color(0xFFA78BFA),
      lightBgTop: Color(0xFFF3EEFF),
      lightBgBottom: Color(0xFFFAF8FF),
      darkBgTop: Color(0xFF130F24),
      darkBgBottom: Color(0xFF1B1531),
    ),
    AccentSpec(
      id: AppAccentId.slate,
      label: '静谧灰',
      lightPrimary: Color(0xFF3A4A5E),
      darkPrimary: Color(0xFF94A3B8),
      lightBgTop: Color(0xFFF1F4F8),
      lightBgBottom: Color(0xFFF9FAFB),
      darkBgTop: Color(0xFF0E1116),
      darkBgBottom: Color(0xFF161B22),
    ),
    AccentSpec(
      id: AppAccentId.emerald,
      label: '松石绿',
      lightPrimary: Color(0xFF0E8A6D),
      darkPrimary: Color(0xFF34D399),
      lightBgTop: Color(0xFFECFDF7),
      lightBgBottom: Color(0xFFF7FCFA),
      darkBgTop: Color(0xFF0A1916),
      darkBgBottom: Color(0xFF102420),
    ),
    AccentSpec(
      id: AppAccentId.amber,
      label: '暖日琥珀',
      lightPrimary: Color(0xFFC26D18),
      darkPrimary: Color(0xFFFBBF24),
      lightBgTop: Color(0xFFFFF6EB),
      lightBgBottom: Color(0xFFFFFCF7),
      darkBgTop: Color(0xFF1B140C),
      darkBgBottom: Color(0xFF241B11),
    ),
    AccentSpec(
      id: AppAccentId.rose,
      label: '暮色玫瑰',
      lightPrimary: Color(0xFFCC4B6B),
      darkPrimary: Color(0xFFFB7185),
      lightBgTop: Color(0xFFFFF0F4),
      lightBgBottom: Color(0xFFFFF9FA),
      darkBgTop: Color(0xFF1D0E14),
      darkBgBottom: Color(0xFF27141C),
    ),
  ];

  static AccentSpec of(AppAccentId id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);
}

class AgySurfaces extends ThemeExtension<AgySurfaces> {
  const AgySurfaces({
    required this.bgTop,
    required this.bgBottom,
    required this.glassFill,
    required this.cardFill,
    required this.hairline,
    required this.subtleText,
    required this.blurEnabled,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color bgTop;
  final Color bgBottom;
  final Color glassFill;
  final Color cardFill;
  final Color hairline;
  final Color subtleText;
  final bool blurEnabled;
  final Color success;
  final Color warning;
  final Color danger;

  static AgySurfaces of(BuildContext context) =>
      Theme.of(context).extension<AgySurfaces>()!;

  @override
  AgySurfaces copyWith({
    Color? bgTop,
    Color? bgBottom,
    Color? glassFill,
    Color? cardFill,
    Color? hairline,
    Color? subtleText,
    bool? blurEnabled,
    Color? success,
    Color? warning,
    Color? danger,
  }) => AgySurfaces(
    bgTop: bgTop ?? this.bgTop,
    bgBottom: bgBottom ?? this.bgBottom,
    glassFill: glassFill ?? this.glassFill,
    cardFill: cardFill ?? this.cardFill,
    hairline: hairline ?? this.hairline,
    subtleText: subtleText ?? this.subtleText,
    blurEnabled: blurEnabled ?? this.blurEnabled,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
  );

  @override
  AgySurfaces lerp(ThemeExtension<AgySurfaces>? other, double t) {
    if (other is! AgySurfaces) return this;
    return AgySurfaces(
      bgTop: Color.lerp(bgTop, other.bgTop, t)!,
      bgBottom: Color.lerp(bgBottom, other.bgBottom, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      cardFill: Color.lerp(cardFill, other.cardFill, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      subtleText: Color.lerp(subtleText, other.subtleText, t)!,
      blurEnabled: t < 0.5 ? blurEnabled : other.blurEnabled,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

SystemUiOverlayStyle agySystemOverlay(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}

ThemeData buildAgyTheme({
  required Brightness brightness,
  required AppAccentId accentId,
  required bool glassBlur,
}) {
  final spec = AccentSpec.of(accentId);
  final dark = brightness == Brightness.dark;
  final primary = dark ? spec.darkPrimary : spec.lightPrimary;

  final surfaces = AgySurfaces(
    bgTop: dark ? spec.darkBgTop : spec.lightBgTop,
    bgBottom: dark ? spec.darkBgBottom : spec.lightBgBottom,
    glassFill: dark
        ? Color.fromRGBO(22, 27, 42, glassBlur ? 0.72 : 0.94)
        : Color.fromRGBO(255, 255, 255, glassBlur ? 0.74 : 0.95),
    cardFill: dark
        ? const Color.fromRGBO(255, 255, 255, 0.055)
        : const Color.fromRGBO(255, 255, 255, 0.72),
    hairline: dark
        ? const Color.fromRGBO(255, 255, 255, 0.10)
        : const Color.fromRGBO(15, 23, 42, 0.09),
    subtleText: dark ? const Color(0xFF94A3B8) : const Color(0xFF5B677A),
    blurEnabled: glassBlur,
    success: dark ? const Color(0xFF34D399) : const Color(0xFF0E9F6E),
    warning: dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
    danger: dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
  );

  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    primary: primary,
    surface: surfaces.bgBottom,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surfaces.cardFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: surfaces.hairline, width: 0.75),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: dark ? const Color(0xFF171E31) : const Color(0xFFFAFCFF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: surfaces.hairline, width: 0.8),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: surfaces.hairline,
      thickness: 0.75,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaces.cardFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: surfaces.hairline, width: 0.75),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: surfaces.hairline, width: 0.75),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 1.25),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    extensions: [surfaces],
  );
}
