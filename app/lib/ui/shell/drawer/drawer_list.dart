// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/chat_state.dart';
import '../../../state/drawer_view_state.dart';
import '../../../state/sessions_state.dart';
import '../../common/empty_view.dart';
import '../../theme/theme.dart';
import 'drawer_actions.dart';
import 'folder_header.dart';
import 'session_tile.dart';

/// The drawer's conversation list mirroring DSH Go's DrawerConversationList:
/// 置顶 → 文件夹 (collapsible in place) → 今天 / 昨天 / 本周 / 更早;
/// or, under a status filter (运行中 / 待确认 / 未读), just the flat matches.
class DrawerConversationList extends ConsumerWidget {
  const DrawerConversationList({
    super.key,
    required this.onOpen,
    required this.onLongPress,
    this.onNewChat,
    this.now,
  });

  /// Opens a conversation (and closes the drawer).
  final ValueChanged<String> onOpen;

  /// Closes the drawer after choosing a folder for a new conversation.
  final VoidCallback? onNewChat;

  /// Opens a conversation's long-press action sheet.
  final void Function(AcpSessionInfo session) onLongPress;

  /// Clock override for calendar day grouping (tests).
  final DateTime? now;

  /// The list's padding: rows' edges sit on the drawer's 10 line.
  static const padding = EdgeInsets.fromLTRB(10, 4, 10, 16);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = watchDrawerBlocks(ref, now: now);
    final selecting = ref.watch(
      drawerSelectionProvider.select((s) => s != null),
    );
    final filter = ref.watch(drawerFilterProvider);
    final sessionsState = ref.watch(sessionsProvider);
    final current = sessionsState.currentSessionId;
    final runningIds = ref.watch(
      chatProvider.select((c) => c.runningSessionIds),
    );
    final pending = ref.watch(pendingSessionIdsProvider);
    final unread = ref.watch(unreadSessionIdsProvider);
    final pinned = sessionsState.pinnedIds.toSet();
    final selectionNotifier = ref.read(drawerSelectionProvider.notifier);

    Widget tile(AcpSessionInfo s, {bool inFolder = false}) {
      final id = s.sessionId;
      final title = sessionsState.displayTitle(s);
      return Consumer(
        key: ValueKey('session-$id'),
        builder: (context, ref, _) => SessionTile(
          title: title,
          running: runningIds.contains(id),
          current: id == current,
          pending: pending[id],
          unread: unread.contains(id),
          pinned: inFolder && pinned.contains(id),
          indent: inFolder ? SessionTile.folderIndent : 0,
          selecting: selecting,
          selected: ref.watch(
            drawerSelectionProvider.select((sel) => sel?.contains(id) ?? false),
          ),
          onTap: selecting
              ? () => selectionNotifier.toggle(id)
              : () => onOpen(id),
          onLongPress: selecting
              ? () => selectionNotifier.toggle(id)
              : () => onLongPress(s),
        ),
      );
    }

    final rows = <({Key key, WidgetBuilder builder})>[];
    void add(Key key, WidgetBuilder builder) =>
        rows.add((key: key, builder: builder));
    void addSessions(List<AcpSessionInfo> items) {
      for (final s in items) {
        add(ValueKey('session-${s.sessionId}'), (_) => tile(s));
      }
    }

    var foldersLabelled = false;
    for (final block in blocks) {
      switch (block) {
        case FilteredBlock(filter: final matching, :final items)
            when items.isEmpty:
          const key = ValueKey('filter-empty');
          add(key, (_) => _FilterEmpty(matching, key: key));
        case FilteredBlock(:final items):
          addSessions(items);
        case PinnedBlock(:final items):
          const key = ValueKey('pinned-label');
          add(key, (_) => const DrawerEyebrow('置顶', key: key));
          addSessions(items);
        case FolderBlock(:final folder, :final items):
          if (!foldersLabelled) {
            foldersLabelled = true;
            const key = ValueKey('folders-label');
            add(key, (_) => const DrawerEyebrow('文件夹', key: key));
          }
          final headerKey = ValueKey('folder-${folder.id}');
          add(
            headerKey,
            (_) => DrawerFolderHeader(
              key: headerKey,
              folder: folder,
              count: items.length,
              onTap: () => ref
                  .read(drawerViewProvider.notifier)
                  .toggleCollapsed(folder.id),
              onLongPress: () => folderActionsFlow(
                context,
                ref,
                folder,
                onNewChat: onNewChat,
              ),
            ),
          );
          final bodyKey = ValueKey('folder-body-${folder.id}');
          add(
            bodyKey,
            (_) => DrawerFolderBody(
              key: bodyKey,
              open: !folder.collapsed,
              childrenBuilder: () => [
                for (final s in items) tile(s, inFolder: true),
              ],
            ),
          );
        case DayBlock(:final day, :final items):
          final key = ValueKey('day-${day.name}');
          add(key, (_) => DrawerEyebrow(sessionDayLabels[day]!, key: key));
          addSessions(items);
      }
    }

    final indices = {for (var i = 0; i < rows.length; i++) rows[i].key: i};
    return ListView.builder(
      key: ValueKey(filter),
      physics: AppMotion.scrollPhysics(context),
      padding: padding,
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index].builder(context),
      findChildIndexCallback: (key) => indices[key],
    );
  }
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty(this.filter, {super.key});

  final DrawerFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title) = switch (filter) {
      DrawerFilter.running => (AppIcons.running, '没有运行中的对话'),
      DrawerFilter.pending => (AppIcons.toConfirm, '没有待确认的对话'),
      DrawerFilter.unread => (AppIcons.allRead, '没有未读对话'),
      DrawerFilter.all => (AppIcons.chat, '还没有对话'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: EmptyView(compact: true, icon: icon, title: title),
    );
  }
}
