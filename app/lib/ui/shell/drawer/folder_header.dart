// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:material_ui/material_ui.dart';

import '../../../state/drawer_view_state.dart';
import '../../common/expand_reveal.dart';
import '../../theme/theme.dart';
import 'folder_mark.dart';
import 'session_tile.dart';

/// A folder's row: the mark on the 20 line, the name, the member count and a
/// chevron that turns as the folder opens. Same 44 height and 10 edges as a
/// conversation row. Tap: open or close. Long press: the folder's actions.
class DrawerFolderHeader extends StatelessWidget {
  const DrawerFolderHeader({
    super.key,
    required this.folder,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final DrawerFolder folder;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Mark slot (members' titles start [SessionTile.folderIndent] in).
  static const mark = 20.0;

  /// Optical shift of the chevron (its glyph carries its own air).
  static const chevronNudge = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final open = !folder.collapsed;
    return Semantics(
      button: true,
      expanded: open,
      label: count == 0
          ? '文件夹 ${folder.name}'
          : '文件夹 ${folder.name}，$count 个对话',
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: Squircle.border(AppShape.md),
          child: SizedBox(
            height: SessionTile.height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  FolderMarkGlyph.of(folder, size: mark),
                  const SizedBox(width: SessionTile.folderIndent - mark),
                  Expanded(
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.4,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: AppType.tabular(
                        theme.textTheme.bodySmall!.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Transform.translate(
                    offset: const Offset(chevronNudge, 0),
                    child: AnimatedRotation(
                      turns: open ? 0 : -0.25,
                      duration: AppMotion.of(context, AppMotion.collapse),
                      curve: AppMotion.collapseCurve,
                      child: Icon(
                        AppIcons.expand,
                        size: 18,
                        color: colors.textTertiary,
                      ),
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

/// A folder's members under its header, opening and closing with [ExpandReveal].
class DrawerFolderBody extends StatelessWidget {
  const DrawerFolderBody({
    super.key,
    required this.open,
    required this.childrenBuilder,
  });

  final bool open;
  final List<Widget> Function() childrenBuilder;

  @override
  Widget build(BuildContext context) {
    return ExpandReveal(
      open: open,
      child: Builder(
        builder: (_) {
          final children = childrenBuilder();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children.isEmpty ? const [_EmptyFolderLine()] : children,
          );
        },
      ),
    );
  }
}

class _EmptyFolderLine extends StatelessWidget {
  const _EmptyFolderLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.only(left: 10 + SessionTile.folderIndent),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '还没有对话',
            style: theme.textTheme.bodySmall?.copyWith(
              color: DshColors.of(context).textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
