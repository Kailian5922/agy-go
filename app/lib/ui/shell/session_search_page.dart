// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../../state/workspaces_state.dart';
import '../common/brief_notice.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/search_capsule.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

/// "搜索对话" at the top of the sessions drawer (DSH Go 40dp pill capsule).
/// Opens [SessionSearchPage]; picking a result opens that conversation and
/// closes the drawer.
class SessionSearchBar extends ConsumerWidget {
  const SessionSearchBar({
    super.key,
    required this.onClose,
    this.padding = const EdgeInsets.fromLTRB(10, 2, 10, 6),
    this.trailing,
  });

  final VoidCallback onClose;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final sessionId = await showSessionSearch(context);
    if (sessionId == null || !context.mounted) return;
    ref.read(sessionsProvider.notifier).selectSession(sessionId);
    onClose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tertiary = DshColors.of(context).textTertiary;
    final bar = Semantics(
      button: true,
      label: '搜索对话',
      onTap: () => _open(context, ref),
      excludeSemantics: true,
      child: GlassSurface(
        tier: GlassTier.pill,
        stadium: true,
        onTap: () => _open(context, ref),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Icon(AppIcons.search, size: 20, color: tertiary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '搜索对话',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: tertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: padding,
      child: trailing == null
          ? bar
          : Row(
              children: [
                Expanded(child: bar),
                trailing!,
              ],
            ),
    );
  }
}

/// Opens the full-page session search view (or archived list when
/// [archivedOnly] is true) and returns the chosen sessionId.
Future<String?> showSessionSearch(
  BuildContext context, {
  bool archivedOnly = false,
}) => Navigator.of(context).push<String>(
  PageRouteBuilder<String>(
    transitionDuration: AppMotion.of(context, AppMotion.standard),
    reverseTransitionDuration: AppMotion.of(context, AppMotion.quick),
    pageBuilder: (_, _, _) => SessionSearchPage(archivedOnly: archivedOnly),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.enter,
        reverseCurve: AppMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  ),
);

class SessionSearchPage extends ConsumerStatefulWidget {
  const SessionSearchPage({super.key, this.archivedOnly = false});

  final bool archivedOnly;

  @override
  ConsumerState<SessionSearchPage> createState() => _SessionSearchPageState();
}

class _SessionSearchPageState extends ConsumerState<SessionSearchPage> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final local = ref.watch(hostsProvider.select((h) => h.active.isLocal));
    final runtime = ref.watch(localRuntimeProvider).status;
    final archivedSet = sessions.archivedIds.toSet();
    final deletedSet = sessions.deletedIds.toSet();
    final q = _query.trim().toLowerCase();
    final matches = [
      for (final s in sessions.sessions)
        if (!deletedSet.contains(s.sessionId) &&
            (widget.archivedOnly
                ? archivedSet.contains(s.sessionId)
                : !archivedSet.contains(s.sessionId)) &&
            (q.isEmpty ||
                sessions.displayTitle(s).toLowerCase().contains(q) ||
                sessions.effectiveCwdOf(s).toLowerCase().contains(q)))
          s,
    ];

    return AppPage.list(
      title: widget.archivedOnly ? '已归档对话' : '搜索对话',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SearchCapsule(
            controller: _ctrl,
            autofocus: !widget.archivedOnly,
            hint: widget.archivedOnly ? '搜索已归档对话…' : '搜索标题或工作区路径…',
            onChanged: (v) => setState(() => _query = v),
            onClear: () {
              _ctrl.clear();
              setState(() => _query = '');
            },
          ),
        ),
        if (matches.isEmpty)
          EmptyView(
            icon: widget.archivedOnly ? AppIcons.archive : AppIcons.search,
            title: q.isEmpty
                ? (widget.archivedOnly ? '暂无已归档对话' : '暂无对话记录')
                : '未找到匹配的对话',
            message: q.isEmpty
                ? (widget.archivedOnly
                      ? '归档后的对话会收在这里，不会占用主列表。'
                      : '开始对话后会显示在这里。')
                : '尝试使用其他关键词。',
          )
        else
          ListPageCard(
            title: q.isEmpty
                ? (widget.archivedOnly
                      ? '已归档 (${matches.length})'
                      : '最近对话')
                : '匹配结果 (${matches.length})',
            children: [
              for (final s in matches)
                ListPageRow(
                  icon: widget.archivedOnly
                      ? AppIcons.archive
                      : (sessions.isPinned(s.sessionId)
                            ? AppIcons.pinActive
                            : AppIcons.chat),
                  title: sessions.displayTitle(s),
                  subtitle: sessions.effectiveCwdOf(s).isEmpty
                      ? null
                      : displayWorkspacePath(
                          sessions.effectiveCwdOf(s),
                          local: local,
                          homePath: runtime.homePath,
                          storageRoot: runtime.phoneStoragePath,
                        ),
                  trailing: widget.archivedOnly
                      ? IconButton(
                          tooltip: '移出归档',
                          icon: Icon(
                            AppIcons.unarchive,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () {
                            unawaited(
                              ref
                                  .read(sessionsProvider.notifier)
                                  .setArchived(s.sessionId, false),
                            );
                            showBriefNotice(context, '已移出归档');
                          },
                        )
                      : null,
                  onTap: () {
                    if (widget.archivedOnly) {
                      unawaited(
                        ref
                            .read(sessionsProvider.notifier)
                            .setArchived(s.sessionId, false),
                      );
                    }
                    Navigator.of(context).pop(s.sessionId);
                  },
                ),
            ],
          ),
      ],
    );
  }
}
