// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/drawer_view_state.dart';
import '../../common/capsule_chip.dart';
import '../../theme/theme.dart';

/// One row of quiet status filter capsules (全部 / 运行中 / 待确认 / 未读),
/// mirroring DSH Go's DrawerFilterBar. Hidden while the list is empty and
/// nothing is filtered.
class DrawerFilterBar extends ConsumerWidget {
  const DrawerFilterBar({super.key});

  /// Gap between capsules.
  static const gap = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(drawerFilterProvider);
    final scope = ref.watch(drawerScopeProvider);
    if (scope.sessions.isEmpty && filter == DrawerFilter.all) {
      return const SizedBox(width: double.infinity);
    }
    final listed = {for (final s in scope.sessions) s.sessionId};
    final pending = ref
        .watch(pendingSessionIdsProvider)
        .keys
        .where(listed.contains)
        .length;
    final unread = ref
        .watch(unreadSessionIdsProvider)
        .where(listed.contains)
        .length;
    String label(DrawerFilter f) => switch (f) {
      DrawerFilter.pending when pending > 0 => '${f.label} $pending',
      DrawerFilter.unread when unread > 0 => '${f.label} $unread',
      _ => f.label,
    };
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(canvasColor: Colors.transparent),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
        child: Row(
          children: [
            for (final (i, f) in DrawerFilter.values.indexed) ...[
              if (i > 0) const SizedBox(width: gap),
              Semantics(
                label: '筛选：${label(f)}',
                selected: f == filter,
                excludeSemantics: true,
                button: true,
                onTap: () => ref.read(drawerFilterProvider.notifier).set(f),
                child: CapsuleChoiceChip(
                  label: label(f),
                  selected: f == filter,
                  onSelected: () =>
                      ref.read(drawerFilterProvider.notifier).set(f),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「对话列表」 options: a round 36dp key at the end of the workspace row,
/// mirroring DSH Go's DrawerViewButton.
class DrawerViewButton extends StatelessWidget {
  const DrawerViewButton({super.key, required this.onTap});

  final VoidCallback onTap;

  static const size = 36.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '对话列表',
      child: Semantics(
        button: true,
        label: '对话列表',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                AppIcons.more,
                size: 20,
                color: DshColors.of(context).textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
