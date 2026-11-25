// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import 'pressable.dart';

/// iOS-style filled capsule search input, no outline.
class SearchCapsule extends StatelessWidget {
  const SearchCapsule({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final FocusNode? focusNode;
  final bool autofocus;

  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fill = dark
        ? Colors.white.withValues(alpha: 0.08)
        : theme.colorScheme.onSurface.withValues(alpha: 0.055);
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 15,
      height: 1.35,
    );
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: height,
              child: Center(
                child: Icon(
                  AppIcons.search,
                  size: 19,
                  color: colors.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                onChanged: onChanged,
                style: textStyle,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: textStyle?.copyWith(color: colors.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return const SizedBox(width: 14);
                }
                return SizedBox(
                  width: 44,
                  height: height,
                  child: IconButton(
                    icon: Icon(
                      AppIcons.clear,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                    tooltip: '清除',
                    onPressed: onClear,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable search capsule button (used on SettingsScreen & SessionsDrawer).
class SearchCapsuleButton extends StatelessWidget {
  const SearchCapsuleButton({
    super.key,
    required this.hint,
    required this.onTap,
  });

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fill = dark
        ? Colors.white.withValues(alpha: 0.08)
        : theme.colorScheme.onSurface.withValues(alpha: 0.055);
    final height = math.max(
      SearchCapsule.height,
      MediaQuery.textScalerOf(context).scale(15) * 1.35 + 18,
    );
    return Semantics(
      button: true,
      label: hint,
      onTap: onTap,
      excludeSemantics: true,
      child: Pressable(
        child: Material(
          color: fill,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(AppIcons.search, size: 18, color: colors.textTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.35,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
