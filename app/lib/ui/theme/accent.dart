// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:material_ui/material_ui.dart';

import '../../state/settings_state.dart' show AppAccentId;
import 'palette.dart';

/// Accent palette: handcrafted light/dark tones plus OKLCH neutral tint hue & chroma.
@immutable
class AppAccent {
  const AppAccent({
    required this.id,
    required this.label,
    required this.labelEn,
    required this.seed,
    required this.pressed,
    required this.container,
    required this.onContainer,
    required this.bubble,
    required this.glow,
    required this.seedDark,
    required this.pressedDark,
    required this.onSeedDark,
    required this.containerDark,
    required this.onContainerDark,
    required this.bubbleDark,
    required this.glowDark,
    required this.tintHue,
    required this.tintChroma,
    required this.haze,
    required this.hazeDark,
  });

  final String id;
  final String label;
  final String labelEn;

  final Color seed;
  final Color pressed;
  final Color container;
  final Color onContainer;
  final Color bubble;
  final Color glow;

  final Color seedDark;
  final Color pressedDark;
  final Color onSeedDark;
  final Color containerDark;
  final Color onContainerDark;
  final Color bubbleDark;
  final Color glowDark;

  final double tintHue;
  final double tintChroma;
  final Color haze;
  final Color hazeDark;

  Color get onSeed => const Color(0xFFFFFFFF);
  Color seedFor(Brightness brightness) =>
      brightness == Brightness.dark ? seedDark : seed;

  static const mist = AppAccent(
    id: 'mist',
    label: '雾蓝',
    labelEn: 'Mist',
    seed: Color(0xFF4B67B4),
    pressed: Color(0xFF3D569D),
    container: Color(0xFFDEE8FF),
    onContainer: Color(0xFF213262),
    bubble: Color(0xFFD9E4FD),
    glow: Color(0xFFABC3FC),
    seedDark: Color(0xFF97B1F0),
    pressedDark: Color(0xFF859EDC),
    onSeedDark: Color(0xFF121C34),
    containerDark: Color(0xFF2E3C5F),
    onContainerDark: Color(0xFFD8E1F6),
    bubbleDark: Color(0xFF293144),
    glowDark: Color(0xFF51679D),
    tintHue: NeutralTones.baseHue,
    tintChroma: 1,
    haze: Color(0xFFD5CBEB),
    hazeDark: Color(0xFF514765),
  );

  static const daiqing = AppAccent(
    id: 'daiqing',
    label: '黛青',
    labelEn: 'Indigo',
    seed: Color(0xFF236185),
    pressed: Color(0xFF145071),
    container: Color(0xFFDBEAF5),
    onContainer: Color(0xFF123950),
    bubble: Color(0xFFD6E7F3),
    glow: Color(0xFFA2CAE5),
    seedDark: Color(0xFF8CB9D7),
    pressedDark: Color(0xFF79A6C4),
    onSeedDark: Color(0xFF0D1F2B),
    containerDark: Color(0xFF274152),
    onContainerDark: Color(0xFFD5E3ED),
    bubbleDark: Color(0xFF26333C),
    glowDark: Color(0xFF466E88),
    tintHue: 238,
    tintChroma: 0.9,
    haze: Color(0xFFC7D0EC),
    hazeDark: Color(0xFF444C66),
  );

  static const dusk = AppAccent(
    id: 'dusk',
    label: '暮紫',
    labelEn: 'Dusk',
    seed: Color(0xFF726291),
    pressed: Color(0xFF61517D),
    container: Color(0xFFEAE5F4),
    onContainer: Color(0xFF392F4C),
    bubble: Color(0xFFE6E1F1),
    glow: Color(0xFFC8BDE1),
    seedDark: Color(0xFFB8ABD2),
    pressedDark: Color(0xFFA598BF),
    onSeedDark: Color(0xFF1F1A29),
    containerDark: Color(0xFF40394F),
    onContainerDark: Color(0xFFE2DEEC),
    bubbleDark: Color(0xFF332F3B),
    glowDark: Color(0xFF6D6284),
    tintHue: 295,
    tintChroma: 0.85,
    haze: Color(0xFFE6C7D7),
    hazeDark: Color(0xFF5F4353),
  );

  static const turquoise = AppAccent(
    id: 'turquoise',
    label: '松石',
    labelEn: 'Turquoise',
    seed: Color(0xFF34766F),
    pressed: Color(0xFF296760),
    container: Color(0xFFDBECE9),
    onContainer: Color(0xFF123D39),
    bubble: Color(0xFFD6E8E6),
    glow: Color(0xFFA3CEC8),
    seedDark: Color(0xFF8DBEB7),
    pressedDark: Color(0xFF7BABA4),
    onSeedDark: Color(0xFF0D211F),
    containerDark: Color(0xFF274340),
    onContainerDark: Color(0xFFD6E5E2),
    bubbleDark: Color(0xFF263533),
    glowDark: Color(0xFF47726D),
    tintHue: 190,
    tintChroma: 0.7,
    haze: Color(0xFFB9D7E3),
    hazeDark: Color(0xFF34525E),
  );

  static const amber = AppAccent(
    id: 'amber',
    label: '琥珀',
    labelEn: 'Amber',
    seed: Color(0xFF8D6636),
    pressed: Color(0xFF7A5528),
    container: Color(0xFFF2E6D9),
    onContainer: Color(0xFF483011),
    bubble: Color(0xFFEEE2D3),
    glow: Color(0xFFDCBE9D),
    seedDark: Color(0xFFCCAC87),
    pressedDark: Color(0xFFB99975),
    onSeedDark: Color(0xFF271A0C),
    containerDark: Color(0xFF4C3A25),
    onContainerDark: Color(0xFFEADFD3),
    bubbleDark: Color(0xFF392F24),
    glowDark: Color(0xFF7F6343),
    tintHue: 75,
    tintChroma: 0.75,
    haze: Color(0xFFEAC8C1),
    hazeDark: Color(0xFF64443D),
  );

  static const graphite = AppAccent(
    id: 'graphite',
    label: '石墨',
    labelEn: 'Graphite',
    seed: Color(0xFF2C2E32),
    pressed: Color(0xFF1D1F23),
    container: Color(0xFFE3E6EC),
    onContainer: Color(0xFF2C2E32),
    bubble: Color(0xFFE0E3E8),
    glow: Color(0xFFBBBEC3),
    seedDark: Color(0xFFE5E8ED),
    pressedDark: Color(0xFFCED1D6),
    onSeedDark: Color(0xFF191B1E),
    containerDark: Color(0xFF3B3D41),
    onContainerDark: Color(0xFFDEE1E7),
    bubbleDark: Color(0xFF2E3034),
    glowDark: Color(0xFF616368),
    tintHue: 262,
    tintChroma: 0.25,
    haze: Color(0xFFCED1D6),
    hazeDark: Color(0xFF4A4D52),
  );

  static const presets = <AppAccent>[
    mist,
    daiqing,
    dusk,
    turquoise,
    amber,
    graphite,
  ];

  static AppAccent fromId(AppAccentId id) => switch (id) {
    AppAccentId.mist => mist,
    AppAccentId.daiqing => daiqing,
    AppAccentId.dusk => dusk,
    AppAccentId.turquoise => turquoise,
    AppAccentId.amber => amber,
    AppAccentId.graphite => graphite,
  };

  @override
  bool operator ==(Object other) => other is AppAccent && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
