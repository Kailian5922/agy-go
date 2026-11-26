// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/smooth_size.dart';
import '../common/status_dot.dart';
import '../theme/theme.dart';
import 'tool_format.dart';

/// Floating chrome-glass live activity & plan progress bar above [ComposerBar].
///
/// Mirrors DSH Go's ActivityStrip: shows active tool/thinking status, elapsed `m:ss`,
/// streaming char rate, and live `AcpPlanEntry` checklist completion (`done/total`).
class ActivityStrip extends ConsumerStatefulWidget {
  const ActivityStrip({super.key});

  @override
  ConsumerState<ActivityStrip> createState() => _ActivityStripState();
}

class _ActivityStripState extends ConsumerState<ActivityStrip> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  void _syncTicker(bool active) {
    if (active && _ticker == null) {
      _now = DateTime.now();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!active && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(DateTime started) {
    final secs = _now.difference(started).inSeconds.clamp(0, 35999);
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(
      chatProvider.select(
        (c) => (
          isBusy: c.isBusy,
          startedAt: c.turnStartedAt,
          chars: c.turnChars,
          sessionCwd: c.sessionCwd,
          plan: c.transcript.plan,
          lastItem: c.transcript.items.isNotEmpty
              ? c.transcript.items.last
              : null,
        ),
      ),
    );

    final show = chat.isBusy || chat.plan.isNotEmpty;
    _syncTicker(chat.isBusy && chat.startedAt != null);

    if (!show) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dsh = DshColors.of(context);

    final activeTools = chat.lastItem is AssistantTranscriptItem
        ? (chat.lastItem as AssistantTranscriptItem)
              .toolCalls
              .where(
                (t) =>
                    t.status == AcpToolStatus.inProgress ||
                    t.status == AcpToolStatus.pending,
              )
              .toList()
        : const <AcpToolCall>[];

    final donePlan = chat.plan
        .where((p) => p.status.toLowerCase() == 'completed')
        .length;
    final totalPlan = chat.plan.length;
    final currentPlan = chat.plan
        .where((p) => p.status.toLowerCase() == 'in_progress')
        .firstOrNull;

    String primaryText;
    if (activeTools.isNotEmpty) {
      final tc = activeTools.last;
      final formatted = formatToolSummary(tc, workspaceCwd: chat.sessionCwd);
      primaryText = formatted.isNotEmpty
          ? formatted
          : (tc.name ?? '正在执行 ${tc.kind.name}');
    } else if (currentPlan != null && currentPlan.content.isNotEmpty) {
      primaryText = currentPlan.content;
    } else if (chat.isBusy) {
      primaryText = 'Antigravity 思考与生成中…';
    } else {
      primaryText = '任务计划已完成 $donePlan/$totalPlan';
    }

    final elapsed = chat.isBusy && chat.startedAt != null
        ? _formatElapsed(chat.startedAt!)
        : null;
    final secs = chat.startedAt != null
        ? _now.difference(chat.startedAt!).inSeconds
        : 0;
    final rate = chat.isBusy && chat.chars > 0 && secs > 0
        ? '${(chat.chars / secs).round()} 字/秒'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.floatInset,
        0,
        AppSpace.floatInset,
        6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpace.floatingWidth),
          child: SmoothSize(
            duration: AppMotion.of(context, AppMotion.quick),
            child: Pressable(
              child: GlassSurface(
                tier: GlassTier.chrome,
                borderRadius: AppShape.radiusLg,
                onTap: () => unawaited(showPlanAndActivitySheet(context, ref)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          StatusDot(
                            tone: chat.isBusy ? StatusTone.busy : StatusTone.ok,
                            size: 7,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              primaryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (totalPlan > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '$donePlan/$totalPlan',
                              style: AppType.monoLabel(color: scheme.primary),
                            ),
                          ],
                          if (elapsed != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              elapsed,
                              style: AppType.monoLabel(color: dsh.textTertiary),
                            ),
                          ],
                          if (rate != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              rate,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: dsh.textTertiary,
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Icon(
                            AppIcons.disclosure,
                            size: 14,
                            color: dsh.textTertiary,
                          ),
                        ],
                      ),
                      if (totalPlan > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: donePlan / totalPlan,
                            minHeight: 3.5,
                            backgroundColor: scheme.onSurface.withValues(
                              alpha: 0.08,
                            ),
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ],
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

/// Bottom sheet displaying live Antigravity `AcpPlanEntry` checklist & active tool calls.
Future<void> showPlanAndActivitySheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => const _PlanActivitySheetBody(),
  );
}

class _PlanActivitySheetBody extends ConsumerWidget {
  const _PlanActivitySheetBody();

  (IconData, Color) _planIcon(
    String status,
    ColorScheme scheme,
    DshColors dsh,
  ) => switch (status.toLowerCase()) {
    'completed' => (AppIcons.success, dsh.success),
    'in_progress' => (AppIcons.inProgress, scheme.primary),
    'failed' => (AppIcons.stepFailed, dsh.danger),
    'skipped' || 'cancelled' => (AppIcons.stepSkipped, dsh.textTertiary),
    _ => (AppIcons.pending, dsh.textTertiary),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final plan = chat.transcript.plan;
    final scheme = Theme.of(context).colorScheme;
    final dsh = DshColors.of(context);
    final recentTools = chat.transcript.items
        .whereType<AssistantTranscriptItem>()
        .expand((item) => item.toolCalls)
        .toList()
        .reversed
        .take(12)
        .toList();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              chat.isBusy ? '执行进度与计划' : '任务计划',
              actions: [
                if (chat.isBusy)
                  SheetIconButton(
                    icon: AppIcons.stop,
                    tooltip: '停止当前轮次',
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(ref.read(chatProvider.notifier).cancel());
                    },
                  ),
              ],
            ),
            if (plan.isNotEmpty)
              SheetGroup(
                title:
                    '计划清单（${plan.where((p) => p.status.toLowerCase() == 'completed').length}/${plan.length}）',
                children: [
                  for (final entry in plan)
                    Builder(
                      builder: (ctx) {
                        final (ic, col) = _planIcon(entry.status, scheme, dsh);
                        return ListPageRow(
                          icon: ic,
                          iconColor: col,
                          title: entry.content,
                          titleMaxLines: 3,
                          meta: entry.priority,
                          chevron: false,
                        );
                      },
                    ),
                ],
              ),
            if (recentTools.isNotEmpty)
              SheetGroup(
                title: '最近工具调用',
                children: [
                  for (final tc in recentTools)
                    ListPageRow(
                      icon: tc.status == AcpToolStatus.inProgress
                          ? AppIcons.running
                          : tc.status == AcpToolStatus.failed
                          ? AppIcons.error
                          : AppIcons.done,
                      iconColor: tc.status == AcpToolStatus.inProgress
                          ? scheme.primary
                          : tc.status == AcpToolStatus.failed
                          ? dsh.danger
                          : dsh.success,
                      title: formatToolSummary(
                        tc,
                        workspaceCwd: chat.sessionCwd,
                      ),
                      subtitle: tc.locations.isNotEmpty
                          ? displayToolPath(
                              tc.locations.first.path,
                              workspaceCwd: chat.sessionCwd,
                            )
                          : tc.kind.name,
                      meta: tc.status.name,
                      chevron: false,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
