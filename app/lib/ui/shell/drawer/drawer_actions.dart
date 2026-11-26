// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/chat_state.dart';
import '../../../state/drawer_view_state.dart';
import '../../../state/hosts_state.dart';
import '../../../state/sessions_state.dart';
import '../../common/app_dialog.dart';
import '../../common/brief_notice.dart';
import '../../theme/theme.dart';
import '../session_search_page.dart' show showSessionSearch;
import 'folder_sheets.dart';

void _toast(
  ScaffoldMessengerState? messenger,
  String text, {
  String? undoLabel,
  VoidCallback? onUndo,
}) {
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      persist: false,
      action: onUndo == null
          ? null
          : SnackBarAction(label: undoLabel ?? '撤销', onPressed: onUndo),
    ),
  );
}

/// 「对话列表」: the sheet, then what was picked in it.
Future<void> openDrawerViewOptions(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onClose,
}) async {
  final action = await showDrawerViewSheet(context);
  if (!context.mounted || action == null) return;
  switch (action) {
    case DrawerViewAction.archived:
      final sessionId = await showSessionSearch(context, archivedOnly: true);
      if (sessionId == null || !context.mounted) return;
      ref.read(sessionsProvider.notifier).selectSession(sessionId);
      onClose?.call();
    case DrawerViewAction.newFolder:
      await createFolderFlow(context, ref);
    case DrawerViewAction.manageFolders:
      await showManageFolders(
        context,
        onEdit: (folder) => editFolderFlow(context, ref, folder),
      );
    case DrawerViewAction.select:
      ref.read(drawerSelectionProvider.notifier).start();
  }
}

/// 新建文件夹, filing [sessionIds] into it. Returns the new folder's id.
Future<String?> createFolderFlow(
  BuildContext context,
  WidgetRef ref, {
  List<String> sessionIds = const [],
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final owner = container.read(hostsProvider).active;
  var retired = false;
  final subscription = container.listen(
    hostsProvider.select((h) => h.active),
    (_, next) {
      if (next != owner) retired = true;
    },
  );
  bool owned() => !retired && !subscription.closed;
  try {
    final view = ref.read(drawerViewProvider.notifier);
    final draft = await showFolderEditor(
      context,
      takenNames: ref.read(drawerViewProvider).folders.map((f) => f.name),
    );
    if (!context.mounted || draft == null || !owned()) return null;
    return await view.createFolder(
      draft.name,
      tint: draft.tint,
      emoji: draft.emoji,
      sessionIds: sessionIds,
      isCurrent: owned,
    );
  } finally {
    subscription.close();
  }
}

/// 编辑 a folder's name and mark.
Future<void> editFolderFlow(
  BuildContext context,
  WidgetRef ref,
  DrawerFolder folder,
) async {
  final view = ref.read(drawerViewProvider.notifier);
  final draft = await showFolderEditor(
    context,
    initial: folder,
    takenNames: ref
        .read(drawerViewProvider)
        .folders
        .where((f) => f.id != folder.id)
        .map((f) => f.name),
  );
  if (draft == null) return;
  await view.updateFolder(
    folder.id,
    name: draft.name,
    tint: () => draft.tint,
    emoji: () => draft.emoji,
  );
}

/// Long press on a folder: start a chat inside it, edit, or delete (with undo).
Future<void> folderActionsFlow(
  BuildContext context,
  WidgetRef ref,
  DrawerFolder folder, {
  VoidCallback? onNewChat,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final owner = container.read(hostsProvider).active;
  var retired = false;
  final subscription = container.listen(
    hostsProvider.select((h) => h.active),
    (_, next) {
      if (next != owner) retired = true;
    },
  );
  bool owned() => !retired && !subscription.closed;
  Future<void>? undo;
  try {
    final action = await showFolderActionSheet(context, folder);
    if (!context.mounted || action == null || !owned()) return;
    switch (action) {
      case FolderAction.newChat:
        if (ref.read(drawerViewProvider).byId(folder.id) == null) return;
        ref.read(pendingSessionFolderProvider.notifier).select(folder.id);
        ref.read(chatProvider.notifier).startNewChat();
        onNewChat?.call();
      case FolderAction.edit:
        await editFolderFlow(context, ref, folder);
      case FolderAction.delete:
        final messenger = ScaffoldMessenger.maybeOf(context);
        final view = ref.read(drawerViewProvider.notifier);
        final removed = await view.deleteFolder(folder.id, isCurrent: owned);
        if (removed == null || !owned() || messenger == null || !messenger.mounted) {
          return;
        }
        final notice = messenger.showUndoNotice(
          '已删除文件夹「${folder.name}」',
          undoLabel: '撤销',
          window: const Duration(seconds: 4),
          onUndo: () {
            if (!owned()) return;
            undo = view.restoreFolder(removed.$1, removed.$2, isCurrent: owned);
          },
        );
        await notice.closed;
        await undo;
    }
  } finally {
    subscription.close();
  }
}

/// 移到文件夹 for [ids] (one row, or multi-select). Ends multi-select once moved.
Future<void> moveToFolderFlow(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  if (ids.isEmpty) return;
  final view = ref.read(drawerViewProvider);
  final viewNotifier = ref.read(drawerViewProvider.notifier);
  final selection = ref.read(drawerSelectionProvider.notifier);
  final folderOf = view.folderOf;
  final homes = {for (final id in ids) folderOf[id]};
  final listed = {
    for (final s in ref.read(drawerScopeProvider).sessions) s.sessionId,
  };
  final pick = await showMoveToFolderSheet(
    context,
    folders: view.folders,
    counts: {
      for (final f in view.folders)
        f.id: f.sessionIds.where(listed.contains).length,
    },
    currentFolder: homes.length == 1 ? homes.first : null,
    anyFiled: homes.any((h) => h != null),
  );
  if (!context.mounted || pick == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  String? target;
  switch (pick) {
    case PickFolder(:final folderId):
      target = folderId;
    case PickNoFolder():
      target = null;
    case PickNewFolder():
      final before = {for (final id in ids) id: folderOf[id]};
      final id = await createFolderFlow(context, ref, sessionIds: ids);
      if (id == null) return;
      selection.end();
      final name = ref.read(drawerViewProvider).byId(id)?.name ?? '';
      _toast(
        messenger,
        '已移至「$name」',
        onUndo: () => viewNotifier.restoreAssignments(before),
      );
      return;
  }
  final previous = await viewNotifier.moveSessions(ids, target);
  selection.end();
  final name = target == null
      ? null
      : ref.read(drawerViewProvider).byId(target)?.name;
  _toast(
    messenger,
    name == null ? '已移出文件夹' : '已移至「$name」',
    onUndo: () => viewNotifier.restoreAssignments(previous),
  );
}

/// Bulk 置顶: pins the chosen conversations, or unpins when all are pinned.
Future<void> pinSelectionFlow(BuildContext context, WidgetRef ref) async {
  final chosen = ref.read(drawerSelectionProvider);
  final ids = chosen?.toList() ?? const <String>[];
  if (ids.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sessionsNotifier = ref.read(sessionsProvider.notifier);
  final pinned = ref.read(sessionsProvider).pinnedIds.toSet();
  final unpin = ids.every(pinned.contains);
  await sessionsNotifier.batchSetPinned(ids.toSet(), !unpin);
  ref.read(drawerSelectionProvider.notifier).end();
  messenger?.showBriefNotice(
    unpin ? '已取消置顶 ${ids.length} 个对话' : '已置顶 ${ids.length} 个对话',
  );
}

/// Archive one or more conversations with a 4-second undo notice.
Future<void> archiveSessionsFlow(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  String? singleTitle,
}) async {
  if (ids.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sessionsNotifier = ref.read(sessionsProvider.notifier);
  final idSet = ids.toSet();
  await sessionsNotifier.batchArchive(idSet, true);
  final label = ids.length == 1 && singleTitle != null
      ? '已归档「$singleTitle」'
      : '已归档 ${ids.length} 个对话';
  messenger?.showUndoNotice(
    label,
    undoLabel: '撤销',
    window: const Duration(seconds: 4),
    onUndo: () => unawaited(sessionsNotifier.batchArchive(idSet, false)),
  );
}

/// Bulk 归档 for multi-select.
Future<void> archiveSelectionFlow(BuildContext context, WidgetRef ref) async {
  final ids = ref.read(drawerSelectionProvider)?.toList() ?? const <String>[];
  if (ids.isEmpty) return;
  await archiveSessionsFlow(context, ref, ids);
  ref.read(drawerSelectionProvider.notifier).end();
}

/// Permanent deletion with confirmation dialog (single or multi-select).
Future<bool> deleteSessionsFlow(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  String? singleTitle,
}) async {
  if (ids.isEmpty) return false;
  final title = ids.length == 1 && singleTitle != null
      ? '删除「$singleTitle」？'
      : '删除 ${ids.length} 个对话？';
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: const Text('删除后无法撤销，所选对话将从列表移除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: DshColors.of(d).danger,
            foregroundColor: DshColors.of(d).onDanger,
          ),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final idSet = ids.toSet();
  await ref.read(sessionsProvider.notifier).batchDelete(idSet);
  await ref.read(drawerViewProvider.notifier).forgetSessions(idSet);
  if (context.mounted) {
    showBriefNotice(
      context,
      ids.length == 1 ? '已删除对话' : '已删除 ${ids.length} 个对话',
    );
  }
  return true;
}

Future<void> deleteSelectionFlow(BuildContext context, WidgetRef ref) async {
  final ids = ref.read(drawerSelectionProvider)?.toList() ?? const <String>[];
  if (ids.isEmpty) return;
  final deleted = await deleteSessionsFlow(context, ref, ids);
  if (deleted) {
    ref.read(drawerSelectionProvider.notifier).end();
  }
}
