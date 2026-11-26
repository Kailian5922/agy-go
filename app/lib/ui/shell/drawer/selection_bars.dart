// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/drawer_view_state.dart';
import '../../../state/sessions_state.dart';
import '../../common/pressable.dart';
import '../../theme/theme.dart';

/// Replaces the brand row in multi-select: 全选 on the 20 line, the count
/// centred, 完成 where 新对话 was (same 36 pill, same 10 edge).
class DrawerSelectionHeader extends ConsumerWidget {
  const DrawerSelectionHeader({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectable = drawerSelectableIds(watchDrawerBlocks(ref, now: now));
    return Consumer(
      builder: (context, ref, _) => _bar(context, ref, selectable),
    );
  }

  Widget _bar(BuildContext context, WidgetRef ref, List<String> selectable) {
    final theme = Theme.of(context);
    final selected = ref.watch(drawerSelectionProvider) ?? const {};
    final notifier = ref.read(drawerSelectionProvider.notifier);
    final all = selectable.isNotEmpty && selectable.every(selected.contains);
    final count = selected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: SizedBox(
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Semantics(
              liveRegion: true,
              child: AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.quick),
                child: Text(
                  count == 0 ? '选择对话' : '已选 $count 个',
                  key: ValueKey(count),
                  style: AppType.tabular(theme.textTheme.titleSmall!),
                ),
              ),
            ),
            Row(
              children: [
                _TextKey(
                  label: all ? '取消全选' : '全选',
                  onTap: selectable.isEmpty
                      ? null
                      : () => notifier.setAll(all ? const [] : selectable),
                ),
                const Spacer(),
                DoneButton(onTap: notifier.end),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TextKey extends StatelessWidget {
  const _TextKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: onTap == null
                      ? DshColors.of(context).textTertiary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「完成」: the 36 primary pill in 新对话's place, even padding on both sides.
class DoneButton extends StatelessWidget {
  const DoneButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '完成',
      onTap: onTap,
      excludeSemantics: true,
      child: Pressable(
        child: Material(
          color: scheme.primary,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    '完成',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the identity bar in multi-select: four equal keys (icon over label),
/// laid directly over IdentityBar so height never jumps.
class SelectionActionBar extends ConsumerWidget {
  const SelectionActionBar({
    super.key,
    required this.onMove,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
  });

  final VoidCallback onMove;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  static const keyHeight = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(drawerSelectionProvider) ?? const {};
    final pinned = ref.watch(sessionsProvider.select((s) => s.pinnedIds)).toSet();
    final none = selected.isEmpty;
    final allPinned = !none && selected.every(pinned.contains);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ActionKey(
              icon: AppIcons.moveToFolder,
              label: '移到文件夹',
              onTap: none ? null : onMove,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionKey(
              icon: allPinned ? AppIcons.pinActive : AppIcons.pin,
              label: allPinned ? '取消置顶' : '置顶',
              onTap: none ? null : onPin,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionKey(
              icon: AppIcons.archive,
              label: '归档',
              onTap: none ? null : onArchive,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: '删除后不可撤销',
              child: _ActionKey(
                icon: AppIcons.delete,
                label: '删除',
                onTap: none ? null : onDelete,
                destructive: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionKey extends StatelessWidget {
  const _ActionKey({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = onTap != null;
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      enabled: on,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: on ? 1 : 0.38,
        duration: AppMotion.of(context, AppMotion.quick),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: Squircle.border(AppShape.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SelectionActionBar.keyHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
