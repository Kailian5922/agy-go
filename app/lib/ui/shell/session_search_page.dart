// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../../state/workspaces_state.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/search_capsule.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

/// Opens the full-page session search view and returns the chosen sessionId.
Future<String?> showSessionSearch(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const SessionSearchPage()),
    );

class SessionSearchPage extends ConsumerStatefulWidget {
  const SessionSearchPage({super.key});

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
    final q = _query.trim().toLowerCase();
    final matches = [
      for (final s in sessions.sessions)
        if (q.isEmpty ||
            sessions.displayTitle(s).toLowerCase().contains(q) ||
            s.cwd.toLowerCase().contains(q))
          s,
    ];

    return AppPage.list(
      title: '搜索对话',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SearchCapsule(
            controller: _ctrl,
            autofocus: true,
            hint: '搜索标题或工作区路径…',
            onChanged: (v) => setState(() => _query = v),
            onClear: () {
              _ctrl.clear();
              setState(() => _query = '');
            },
          ),
        ),
        if (matches.isEmpty)
          EmptyView(
            icon: AppIcons.search,
            title: q.isEmpty ? '暂无对话记录' : '未找到匹配的对话',
            message: q.isEmpty ? '开始对话后会显示在这里。' : '尝试使用其他关键词。',
          )
        else
          ListPageCard(
            title: q.isEmpty ? '最近对话' : '匹配结果 (${matches.length})',
            children: [
              for (final s in matches)
                ListPageRow(
                  icon: sessions.isPinned(s.sessionId)
                      ? AppIcons.pinActive
                      : AppIcons.chat,
                  title: sessions.displayTitle(s),
                  subtitle: s.cwd.isEmpty
                      ? null
                      : displayWorkspacePath(
                          s.cwd,
                          local: local,
                          homePath: runtime.homePath,
                          storageRoot: runtime.phoneStoragePath,
                        ),
                  onTap: () => Navigator.of(context).pop(s.sessionId),
                ),
            ],
          ),
      ],
    );
  }
}
