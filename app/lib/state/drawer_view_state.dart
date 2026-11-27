// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:convert';

import 'package:acp_client/acp_client.dart';
import 'package:agy_remote/agy_remote.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_state.dart';
import 'hosts_state.dart';
import 'phone_state.dart';
import 'sessions_state.dart';
import 'workspaces_state.dart';

// ── Folders ──────────────────────────────────────────────────────────────────

/// One user folder in the drawer. [tint] indexes `DshColors.identity` (0–7);
/// [emoji] replaces the folder glyph. Neither: the plain folder glyph.
class DrawerFolder {
  const DrawerFolder({
    required this.id,
    required this.name,
    this.tint,
    this.emoji,
    this.collapsed = false,
    this.sessionIds = const [],
  });

  static DrawerFolder? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty) {
      return null;
    }
    final tint = json['tint'];
    final emoji = json['emoji'];
    final ids = json['sessions'];
    return DrawerFolder(
      id: id,
      name: name.trim(),
      tint: tint is int && tint >= 0 && tint < markTints ? tint : null,
      emoji: emoji is String && emoji.isNotEmpty ? emoji : null,
      collapsed: json['collapsed'] == true,
      sessionIds: ids is List ? ids.whereType<String>().toList() : const [],
    );
  }

  /// Hues a folder can take (the identity palette).
  static const markTints = 8;

  final String id;
  final String name;
  final int? tint;
  final String? emoji;
  final bool collapsed;

  /// Members, most recently added first.
  final List<String> sessionIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tint': ?tint,
    'emoji': ?emoji,
    if (collapsed) 'collapsed': true,
    'sessions': sessionIds,
  };

  DrawerFolder copyWith({
    String? name,
    int? Function()? tint,
    String? Function()? emoji,
    bool? collapsed,
    List<String>? sessionIds,
  }) => DrawerFolder(
    id: id,
    name: name ?? this.name,
    tint: tint == null ? this.tint : tint(),
    emoji: emoji == null ? this.emoji : emoji(),
    collapsed: collapsed ?? this.collapsed,
    sessionIds: sessionIds ?? this.sessionIds,
  );
}

/// The drawer's list order.
enum DrawerSort {
  /// Latest activity first (`updatedAt`).
  activity,

  /// Newest conversation first (`createdAt`, falling back to `updatedAt`).
  created,
}

/// The drawer's view of one host: folders in display order and the sort.
class DrawerView {
  const DrawerView({
    this.loaded = false,
    this.folders = const [],
    this.sort = DrawerSort.activity,
  });

  factory DrawerView.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final folders = map['folders'];
    final seen = <String>{};
    return DrawerView(
      loaded: true,
      folders: [
        if (folders is List)
          for (final raw in folders)
            if (DrawerFolder.fromJson(raw) case final f? when seen.add(f.id)) f,
      ],
      sort: map['sort'] == 'created' ? DrawerSort.created : DrawerSort.activity,
    );
  }

  final bool loaded;
  final List<DrawerFolder> folders;
  final DrawerSort sort;

  Map<String, Object?> toJson() => {
    'folders': [for (final f in folders) f.toJson()],
    'sort': sort.name,
  };

  DrawerFolder? byId(String? id) {
    if (id == null) return null;
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Conversation id → the folder it is in.
  Map<String, String> get folderOf => {
    for (final f in folders)
      for (final id in f.sessionIds) id: f.id,
  };

  DrawerView copyWith({List<DrawerFolder>? folders, DrawerSort? sort}) =>
      DrawerView(
        loaded: loaded,
        folders: folders ?? this.folders,
        sort: sort ?? this.sort,
      );
}

/// [DrawerView] of the active host, persisted in SharedPreferences (per host).
class DrawerViewController extends Notifier<DrawerView> {
  String _key = '';
  Future<void> _loading = Future.value();
  int _seq = 0;

  static String keyFor(HostRef host) =>
      'agy.drawer.view.${host.kind.name}.${host.id}';

  /// Longest folder name (matching DSH Go).
  static const maxName = 20;

  @override
  DrawerView build() {
    final host = ref.watch(hostsProvider.select((h) => h.active));
    final key = keyFor(host);
    _key = key;
    _loading = _load(key, host);
    return const DrawerView();
  }

  Future<void> ready() => _loading;

  Future<void> _load(String key, HostRef host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (!ref.mounted || _key != key || state.loaded) return;
      if (raw != null && raw.isNotEmpty) {
        state = DrawerView.fromJson(jsonDecode(raw));
        return;
      }
      // Migrate legacy string-only folders stored inside `agy.sessions.meta.*`
      // once so existing users keep their folders seamlessly.
      final legacyKey = 'agy.sessions.meta.${host.kind.name}.${host.id}';
      final legacyRaw = prefs.getString(legacyKey);
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        final map = jsonDecode(legacyRaw) as Map<String, Object?>;
        final names = (map['folders'] as List?)?.whereType<String>().toList() ??
            const <String>[];
        final mapping = map['sessionFolders'] is Map
            ? Map<String, Object?>.from(map['sessionFolders'] as Map)
            : const <String, Object?>{};
        if (names.isNotEmpty || mapping.isNotEmpty) {
          final byName = <String, List<String>>{
            for (final n in names)
              if (n.trim().isNotEmpty) n.trim(): <String>[],
          };
          for (final e in mapping.entries) {
            final fname = (e.value as String?)?.trim();
            if (fname != null && fname.isNotEmpty) {
              byName.putIfAbsent(fname, () => <String>[]).add(e.key);
            }
          }
          final migrated = [
            for (final e in byName.entries)
              DrawerFolder(
                id: _newId(),
                name: _clean(e.key),
                sessionIds: e.value,
              ),
          ];
          final next = DrawerView(loaded: true, folders: migrated);
          state = next;
          await prefs.setString(key, jsonEncode(next.toJson()));
          return;
        }
      }
      state = const DrawerView(loaded: true);
    } catch (_) {
      if (ref.mounted && _key == key && !state.loaded) {
        state = const DrawerView(loaded: true);
      }
    }
  }

  Future<void> _update(
    DrawerView Function(DrawerView view) change, {
    bool Function()? isCurrent,
  }) async {
    final key = _key;
    await _loading;
    if (!ref.mounted || key != _key || (isCurrent != null && !isCurrent())) {
      return;
    }
    final next = change(state);
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(next.toJson()));
    } catch (_) {}
  }

  String _newId() {
    final taken = {for (final f in state.folders) f.id};
    String id;
    do {
      id =
          'f${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';
    } while (taken.contains(id));
    return id;
  }

  /// Adds a folder at the top and moves [sessionIds] into it; returns its id.
  Future<String?> createFolder(
    String name, {
    int? tint,
    String? emoji,
    Iterable<String> sessionIds = const [],
    bool Function()? isCurrent,
  }) async {
    String? id;
    await _update((view) {
      final created = _newId();
      id = created;
      final members = sessionIds.toSet();
      return view.copyWith(
        folders: [
          DrawerFolder(
            id: created,
            name: _clean(name),
            tint: tint,
            emoji: emoji,
            sessionIds: members.toList(),
          ),
          for (final f in view.folders) _without(f, members),
        ],
      );
    }, isCurrent: isCurrent);
    return id;
  }

  /// Renames or re-marks a folder. Pass `() => null` to clear a mark.
  Future<void> updateFolder(
    String id, {
    String? name,
    int? Function()? tint,
    String? Function()? emoji,
  }) => _update(
    (view) => view.copyWith(
      folders: [
        for (final f in view.folders)
          if (f.id == id)
            f.copyWith(
              name: name == null ? null : _clean(name),
              tint: tint,
              emoji: emoji,
            )
          else
            f,
      ],
    ),
  );

  /// Removes a folder (its conversations stay); returns it and its index for undo.
  Future<(DrawerFolder, int)?> deleteFolder(
    String id, {
    bool Function()? isCurrent,
  }) async {
    final key = _key;
    await _loading;
    if (!ref.mounted || key != _key || (isCurrent != null && !isCurrent())) {
      return null;
    }
    final index = state.folders.indexWhere((f) => f.id == id);
    if (index < 0) return null;
    final folder = state.folders[index];
    await _update(
      (view) => view.copyWith(
        folders: [...view.folders]..removeWhere((f) => f.id == id),
      ),
      isCurrent: isCurrent,
    );
    return (folder, index);
  }

  /// Restores a previously deleted folder for undo.
  Future<void> restoreFolder(
    DrawerFolder folder,
    int index, {
    bool Function()? isCurrent,
  }) => _update((view) {
    if (view.byId(folder.id) != null) return view;
    final taken = view.folderOf;
    final restored = folder.copyWith(
      sessionIds: [
        for (final id in folder.sessionIds)
          if (!taken.containsKey(id)) id,
      ],
    );
    final folders = [...view.folders]
      ..insert(index.clamp(0, view.folders.length), restored);
    return view.copyWith(folders: folders);
  }, isCurrent: isCurrent);

  Future<void> setCollapsed(String id, bool collapsed) => _update(
    (view) => view.copyWith(
      folders: [
        for (final f in view.folders)
          if (f.id == id) f.copyWith(collapsed: collapsed) else f,
      ],
    ),
  );

  Future<void> toggleCollapsed(String id) async {
    await _loading;
    final folder = state.byId(id);
    if (folder != null) await setCollapsed(id, !folder.collapsed);
  }

  /// Moves [ids] into [folderId] (null: out of any folder). Returns previous assignments.
  Future<Map<String, String?>> moveSessions(
    Iterable<String> ids,
    String? folderId, {
    bool Function()? isCurrent,
  }) async {
    final key = _key;
    await _loading;
    if (!ref.mounted || key != _key || (isCurrent != null && !isCurrent())) {
      return const {};
    }
    final moving = ids.toList();
    final before = state.folderOf;
    final previous = {for (final id in moving) id: before[id]};
    if (folderId != null && state.byId(folderId) == null) return const {};
    final set = moving.toSet();
    await _update(
      (view) => view.copyWith(
        folders: [
          for (final f in view.folders)
            if (f.id == folderId)
              f.copyWith(
                sessionIds: [
                  ...moving,
                  for (final id in f.sessionIds)
                    if (!set.contains(id)) id,
                ],
              )
            else
              _without(f, set),
        ],
      ),
      isCurrent: isCurrent,
    );
    return previous;
  }

  Future<void> restoreAssignments(Map<String, String?> previous) =>
      _update((view) {
        final set = previous.keys.toSet();
        return view.copyWith(
          folders: [
            for (final f in view.folders)
              f.copyWith(
                sessionIds: [
                  for (final MapEntry(:key, :value) in previous.entries)
                    if (value == f.id && !f.sessionIds.contains(key)) key,
                  for (final id in f.sessionIds)
                    if (!set.contains(id) || previous[id] == f.id) id,
                ],
              ),
          ],
        );
      });

  Future<void> reorderFolders(int oldIndex, int newIndex) => _update((view) {
    if (oldIndex < 0 || oldIndex >= view.folders.length) return view;
    final folders = [...view.folders];
    final moved = folders.removeAt(oldIndex);
    folders.insert(newIndex.clamp(0, folders.length), moved);
    return view.copyWith(folders: folders);
  });

  Future<void> setSort(DrawerSort sort) =>
      _update((view) => view.copyWith(sort: sort));

  Future<void> forgetSessions(Set<String> ids) => _update(
    (view) => view.copyWith(
      folders: [for (final folder in view.folders) _without(folder, ids)],
    ),
  );

  Future<void> forgetMissing(Set<String> known) async {
    await _loading;
    final stale = state.folders.any(
      (f) => f.sessionIds.any((id) => !known.contains(id)),
    );
    if (!stale) return;
    await _update(
      (view) => view.copyWith(
        folders: [
          for (final f in view.folders)
            f.copyWith(
              sessionIds: [
                for (final id in f.sessionIds)
                  if (known.contains(id)) id,
              ],
            ),
        ],
      ),
    );
  }

  static String _clean(String name) {
    final trimmed = name.trim();
    return trimmed.characters.take(maxName).toString();
  }

  static DrawerFolder _without(DrawerFolder f, Set<String> ids) =>
      f.sessionIds.any(ids.contains)
      ? f.copyWith(
          sessionIds: [
            for (final id in f.sessionIds)
              if (!ids.contains(id)) id,
          ],
        )
      : f;
}

final drawerViewProvider = NotifierProvider<DrawerViewController, DrawerView>(
  DrawerViewController.new,
);

/// Optional target folder for the next newly created conversation (when user
/// long-presses a folder → 新对话). Cleared once consumed or on host switch.
class PendingSessionFolderController extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(hostsProvider.select((h) => h.active));
    return null;
  }

  void select(String? folderId) => state = folderId;

  String? take() {
    final id = state;
    state = null;
    return id;
  }
}

final pendingSessionFolderProvider =
    NotifierProvider<PendingSessionFolderController, String?>(
      PendingSessionFolderController.new,
    );

// ── Filter, selection & attention markers (running / pending / unread) ───────

/// The 4 quiet status filter capsules above the drawer list (mirroring DSH Go).
enum DrawerFilter {
  all,
  running,
  pending,
  unread;

  String get label => switch (this) {
    all => '全部',
    running => '运行中',
    pending => '待确认',
    unread => '未读',
  };
}

class DrawerFilterController extends Notifier<DrawerFilter> {
  @override
  DrawerFilter build() {
    ref.watch(hostsProvider.select((h) => h.active));
    return DrawerFilter.all;
  }

  void set(DrawerFilter filter) => state = filter;
}

final drawerFilterProvider =
    NotifierProvider<DrawerFilterController, DrawerFilter>(
      DrawerFilterController.new,
    );

/// Multi-select: null when off, else the chosen conversation ids.
class DrawerSelectionController extends Notifier<Set<String>?> {
  @override
  Set<String>? build() {
    ref.watch(hostsProvider.select((h) => h.active));
    return null;
  }

  bool get active => state != null;

  void start([String? first]) => state = {?first};

  void toggle(String id) {
    final current = state;
    if (current == null) return;
    state = current.contains(id)
        ? ({...current}..remove(id))
        : {...current, id};
  }

  void setAll(Iterable<String> ids) {
    if (state != null) state = ids.toSet();
  }

  void end() => state = null;
}

final drawerSelectionProvider =
    NotifierProvider<DrawerSelectionController, Set<String>?>(
      DrawerSelectionController.new,
    );

/// What a conversation waits for (for the row marker & 「待确认」 filter).
enum PendingKind {
  approval;

  String get label => '待确认';
}

/// Session id → pending user interaction (tool permission or phone approval).
final pendingSessionIdsProvider = Provider<Map<String, PendingKind>>((ref) {
  final chatPending = ref.watch(
    chatProvider.select(
      (c) => (
        sessionId: c.sessionId,
        hasPerm: c.pendingPermissions.isNotEmpty,
        runningIds: c.runningSessionIds,
      ),
    ),
  );
  final hasPhoneApproval = ref.watch(
    phoneControlProvider.select((p) => p.pendingApprovals.isNotEmpty),
  );
  final out = <String, PendingKind>{};
  if (chatPending.hasPerm && chatPending.sessionId != null) {
    out[chatPending.sessionId!] = PendingKind.approval;
  }
  if (hasPhoneApproval) {
    final target =
        chatPending.sessionId ?? chatPending.runningIds.firstOrNull;
    if (target != null) {
      out[target] = PendingKind.approval;
    }
  }
  return out;
});

/// Tracks unread conversations per host (background replies or activity newer
/// than when the user last viewed that conversation).
class DrawerUnreadController extends Notifier<Set<String>> {
  final Map<String, DateTime> _seenAt = {};
  bool _seeded = false;

  @override
  Set<String> build() {
    ref.watch(hostsProvider.select((h) => h.active));
    _seenAt.clear();
    _seeded = false;

    // Opening a conversation immediately marks it read.
    ref.listen<String?>(
      sessionsProvider.select((s) => s.currentSessionId),
      (_, next) {
        if (next != null) markSeen(next);
      },
    );

    // When a background turn completes while the user is viewing another chat,
    // mark that completed conversation unread!
    ref.listen<Set<String>>(
      chatProvider.select((c) => c.backgroundRunningIds),
      (prev, next) {
        if (prev == null) return;
        final currentSid = ref.read(sessionsProvider).currentSessionId;
        final finished = prev.difference(next);
        if (finished.isEmpty) return;
        final added = {
          for (final id in finished)
            if (id != currentSid) id,
        };
        if (added.isNotEmpty) {
          state = {...state, ...added};
        }
      },
    );

    // Watch session list updates for newer timestamps on non-current chats.
    ref.listen<List<AcpSessionInfo>>(
      sessionsProvider.select((s) => s.sessions),
      (_, sessions) => _reconcile(sessions),
      fireImmediately: true,
    );

    return const {};
  }

  void _reconcile(List<AcpSessionInfo> sessions) {
    if (sessions.isEmpty) return;
    final currentSid = ref.read(sessionsProvider).currentSessionId;
    if (!_seeded) {
      _seeded = true;
      for (final s in sessions) {
        _seenAt[s.sessionId] = s.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return;
    }
    final nextUnread = {...state};
    for (final s in sessions) {
      final at = s.updatedAt;
      if (at == null) continue;
      if (s.sessionId == currentSid) {
        _seenAt[s.sessionId] = at;
        nextUnread.remove(s.sessionId);
        continue;
      }
      final prev = _seenAt[s.sessionId];
      if (prev == null) {
        _seenAt[s.sessionId] = at;
      } else if (at.isAfter(prev)) {
        nextUnread.add(s.sessionId);
      }
    }
    final known = {for (final s in sessions) s.sessionId};
    nextUnread.retainAll(known);
    if (nextUnread.length != state.length || !nextUnread.containsAll(state)) {
      state = nextUnread;
    }
  }

  void markSeen(String sessionId) {
    final sessions = ref.read(sessionsProvider).sessions;
    for (final s in sessions) {
      if (s.sessionId == sessionId) {
        _seenAt[sessionId] = s.updatedAt ?? DateTime.now();
        break;
      }
    }
    if (state.contains(sessionId)) {
      state = {...state}..remove(sessionId);
    }
  }
}

final unreadSessionIdsProvider =
    NotifierProvider<DrawerUnreadController, Set<String>>(
      DrawerUnreadController.new,
    );

// ── Day grouping & scope projection ──────────────────────────────────────────

enum SessionDay { today, yesterday, thisWeek, earlier }

/// Calendar grouping in local time; weeks start on Monday (matching DSH Go).
SessionDay sessionDayOf(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return SessionDay.today;
  if (diff == 1) return SessionDay.yesterday;
  final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
  if (!day.isBefore(monday)) return SessionDay.thisWeek;
  return SessionDay.earlier;
}

const sessionDayLabels = <SessionDay, String>{
  SessionDay.today: '今天',
  SessionDay.yesterday: '昨天',
  SessionDay.thisWeek: '本周',
  SessionDay.earlier: '更早',
};

/// Returns the owning workspace ID of [session] using longest-prefix matching
/// (or null if outside all registered workspaces).
WorkspaceItem? _owningWorkspace(
  AcpSessionInfo session,
  SessionsState sessionsState,
  WorkspacesState wsState,
) {
  final cwd = sessionsState.effectiveCwdOf(session);
  if (cwd.isNotEmpty) {
    return matchWorkspaceForCwd(cwd, wsState.workspaces);
  }
  return wsState.workspaces.where((w) => w.isDefault).firstOrNull ??
      wsState.workspaces.firstOrNull;
}

/// Conversation counts per workspace among non-archived, non-deleted sessions
/// (displayed in [WorkspaceSheet] matching DSH Go).
final workspaceCountsProvider = Provider<Map<String, int>>((ref) {
  final sessionsState = ref.watch(sessionsProvider);
  final wsState = ref.watch(workspacesProvider);
  final archived = sessionsState.archivedIds.toSet();
  final deleted = sessionsState.deletedIds.toSet();
  final counts = <String, int>{
    for (final w in wsState.workspaces) w.id: 0,
  };
  for (final s in sessionsState.sessions) {
    if (deleted.contains(s.sessionId) || archived.contains(s.sessionId)) {
      continue;
    }
    final owner = _owningWorkspace(s, sessionsState, wsState);
    if (owner != null) {
      counts[owner.id] = (counts[owner.id] ?? 0) + 1;
    }
  }
  return counts;
});

/// Total non-archived, non-deleted conversations on the active host.
final visibleSessionTotalProvider = Provider<int>((ref) {
  final sessionsState = ref.watch(sessionsProvider);
  final archived = sessionsState.archivedIds.toSet();
  final deleted = sessionsState.deletedIds.toSet();
  var count = 0;
  for (final s in sessionsState.sessions) {
    if (deleted.contains(s.sessionId) || archived.contains(s.sessionId)) {
      continue;
    }
    count++;
  }
  return count;
});

/// The drawer's active conversation scope after workspace filtering (non-archived).
class DrawerScope {
  const DrawerScope({
    required this.sessions,
    required this.scoped,
    this.workspaceLabel,
  });

  final List<AcpSessionInfo> sessions;

  /// True when filtered to one specific workspace (empty folders are hidden).
  final bool scoped;
  final String? workspaceLabel;
}

/// Active drawer scope: all non-archived chats (when selectedWorkspace == null),
/// or strictly the conversations belonging to the selected workspace.
final drawerScopeProvider = Provider<DrawerScope>((ref) {
  final sessionsState = ref.watch(sessionsProvider);
  final wsState = ref.watch(workspacesProvider);
  final selected = wsState.selected;
  final archived = sessionsState.archivedIds.toSet();
  final deleted = sessionsState.deletedIds.toSet();

  final inScope = <AcpSessionInfo>[];
  for (final s in sessionsState.sessions) {
    if (deleted.contains(s.sessionId) || archived.contains(s.sessionId)) {
      continue;
    }
    if (selected != null) {
      final owner = _owningWorkspace(s, sessionsState, wsState);
      if (owner?.id != selected.id) continue;
    }
    inScope.add(s);
  }

  return DrawerScope(
    sessions: inScope,
    scoped: selected != null,
    workspaceLabel: selected?.displayTitle,
  );
});

/// One block of the drawer list.
sealed class DrawerBlock {
  const DrawerBlock(this.items);

  final List<AcpSessionInfo> items;
}

/// Pinned conversations that are in no folder.
final class PinnedBlock extends DrawerBlock {
  const PinnedBlock(super.items);
}

/// A folder and its members in scope (pinned members first).
final class FolderBlock extends DrawerBlock {
  const FolderBlock(this.folder, super.items);

  final DrawerFolder folder;
}

/// Remaining conversations, grouped by local calendar day.
final class DayBlock extends DrawerBlock {
  const DayBlock(this.day, super.items);

  final SessionDay day;
}

/// A status filter's matches, flat (no folders or days).
final class FilteredBlock extends DrawerBlock {
  const FilteredBlock(this.filter, super.items);

  final DrawerFilter filter;
}

/// Computes the exact DSH Go drawer blocks:
/// Every conversation appears at most once — in its folder if it has one,
/// else under 置顶 if pinned, else under 今天 / 昨天 / 本周 / 更早.
/// Under a status filter (运行中 / 待确认 / 未读), matches render flat.
List<DrawerBlock> drawerBlocks({
  required List<AcpSessionInfo> sessions,
  required List<String> pinnedIds,
  required DrawerView view,
  required DrawerFilter filter,
  required Set<String> runningIds,
  required Map<String, PendingKind> pending,
  required Set<String> unread,
  required Map<String, DateTime> createdAt,
  required DateTime now,
  bool scoped = false,
}) {
  DateTime keyOf(AcpSessionInfo s) {
    if (view.sort == DrawerSort.created) {
      return createdAt[s.sessionId] ??
          s.updatedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return s.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool matches(AcpSessionInfo s) => switch (filter) {
    DrawerFilter.running => runningIds.contains(s.sessionId),
    DrawerFilter.pending => pending.containsKey(s.sessionId),
    DrawerFilter.unread => unread.contains(s.sessionId),
    DrawerFilter.all => true,
  };

  final sorted = (filter == DrawerFilter.all
      ? [...sessions]
      : sessions.where(matches).toList())
    ..sort((a, b) {
      final byKey = keyOf(b).compareTo(keyOf(a));
      return byKey != 0 ? byKey : a.sessionId.compareTo(b.sessionId);
    });

  if (filter != DrawerFilter.all) {
    return [FilteredBlock(filter, sorted)];
  }

  final folderOf = view.folderOf;
  final pinnedSet = pinnedIds.toSet();
  final byId = {for (final s in sorted) s.sessionId: s};
  final blocks = <DrawerBlock>[];

  final pinned = [
    for (final id in pinnedIds)
      if (byId[id] case final s? when !folderOf.containsKey(id)) s,
  ];
  if (pinned.isNotEmpty) blocks.add(PinnedBlock(pinned));

  final membersByFolder = <String, List<AcpSessionInfo>>{};
  for (final s in sorted) {
    final folderId = folderOf[s.sessionId];
    if (folderId != null) {
      membersByFolder.putIfAbsent(folderId, () => []).add(s);
    }
  }
  for (final folder in view.folders) {
    final members = membersByFolder[folder.id] ?? const <AcpSessionInfo>[];
    if (members.isEmpty && scoped) continue;
    blocks.add(
      FolderBlock(folder, [
        for (final s in members)
          if (pinnedSet.contains(s.sessionId)) s,
        for (final s in members)
          if (!pinnedSet.contains(s.sessionId)) s,
      ]),
    );
  }

  final days = <SessionDay, List<AcpSessionInfo>>{};
  for (final s in sorted) {
    if (folderOf.containsKey(s.sessionId) || pinnedSet.contains(s.sessionId)) {
      continue;
    }
    days.putIfAbsent(sessionDayOf(keyOf(s), now), () => []).add(s);
  }
  for (final day in SessionDay.values) {
    if (days[day] case final items?) blocks.add(DayBlock(day, items));
  }

  return blocks;
}

/// What 「全选」 picks: every visible conversation on screen (members of a
/// collapsed folder are skipped).
List<String> drawerSelectableIds(List<DrawerBlock> blocks) => [
  for (final block in blocks)
    if (block is! FolderBlock || !block.folder.collapsed)
      for (final s in block.items) s.sessionId,
];

/// Clock for day grouping (tests can override it).
final drawerClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Live [drawerBlocks] computed over Riverpod providers.
List<DrawerBlock> watchDrawerBlocks(WidgetRef ref, {DateTime? now}) {
  final scope = ref.watch(drawerScopeProvider);
  final view = ref.watch(drawerViewProvider);
  final pinnedIds = ref.watch(sessionsProvider.select((s) => s.pinnedIds));
  final createdAt = ref.watch(
    sessionsProvider.select((s) => s.sessionCreatedAt),
  );
  final runningIds = ref.watch(
    chatProvider.select((c) => c.runningSessionIds),
  );
  return drawerBlocks(
    sessions: scope.sessions,
    pinnedIds: pinnedIds,
    view: view,
    filter: ref.watch(drawerFilterProvider),
    runningIds: runningIds,
    pending: ref.watch(pendingSessionIdsProvider),
    unread: ref.watch(unreadSessionIdsProvider),
    createdAt: createdAt,
    now: now ?? ref.watch(drawerClockProvider)(),
    scoped: scope.scoped,
  );
}
