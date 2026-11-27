// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/phone_state.dart';
import '../../state/runtime_state.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/smooth_size.dart';
import '../common/status_dot.dart';
import '../theme/theme.dart';
import 'tool_format.dart';

/// Floating chrome-glass live activity & plan progress bar above [ComposerBar].
///
/// Shows real-time turn liveness: live thinking/generation character growth,
/// active tool execution, transient network/429 retries, and prolonged silence warnings.
class ActivityStrip extends ConsumerStatefulWidget {
  const ActivityStrip({super.key, this.inline = false});

  /// When true, renders as a compact stadium capsule without outer horizontal
  /// padding so it can sit side-by-side with [PermissionStatusPill] in one row.
  final bool inline;

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
          isStopping: c.isStopping,
          pendingPermissions: c.pendingPermissions,
          startedAt: c.turnStartedAt,
          lastActivityAt: c.lastActivityAt,
          livePhase: c.livePhase,
          liveStatusLabel: c.liveStatusLabel,
          activeRetry: c.activeRetry,
          chars: c.turnChars,
          thoughtChars: c.thoughtChars,
          answerChars: c.answerChars,
          liveTokensPerSecond: c.liveTokensPerSecond,
          sessionCwd: c.sessionCwd,
          plan: c.transcript.plan,
          lastItem: c.transcript.items.isNotEmpty
              ? c.transcript.items.last
              : null,
        ),
      ),
    );
    final phoneApprovals = ref.watch(
      phoneControlProvider.select((p) => p.pendingApprovals),
    );
    final hasPendingApproval =
        chat.pendingPermissions.isNotEmpty || phoneApprovals.isNotEmpty;

    final show = chat.isBusy || chat.plan.isNotEmpty || hasPendingApproval;
    _syncTicker((chat.isBusy || hasPendingApproval) && chat.startedAt != null);

    if (!show) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dsh = DshColors.of(context);

    final lastAssistant = chat.lastItem is AssistantTranscriptItem
        ? chat.lastItem as AssistantTranscriptItem
        : null;
    final activeTools = lastAssistant != null
        ? lastAssistant.toolCalls.where((t) => t.status.isActive).toList()
        : const <AcpToolCall>[];

    final donePlan = chat.plan.where((p) => p.isCompleted).length;
    final totalPlan = chat.plan.length;
    final currentPlan = chat.plan.where((p) => p.isInProgress).firstOrNull;

    final activeToolLabel = activeTools.isNotEmpty
        ? formatNativeToolLiveStatus(
            activeTools.last,
            workspaceCwd: chat.sessionCwd,
          )
        : null;
    final pendingApprovalLabel = chat.pendingPermissions.isNotEmpty
        ? formatNativeToolLiveStatus(
            chat.pendingPermissions.first.request.toolCall,
            workspaceCwd: chat.sessionCwd,
          )
        : (phoneApprovals.isNotEmpty ? phoneApprovals.first.summary : null);
    final liveThoughtHeadline = chat.livePhase == TurnLivePhase.thinking
        ? latestAssistantThoughtHeadline(lastAssistant)
        : null;

    final health = (chat.isBusy || hasPendingApproval)
        ? deriveTurnHealth(
            startedAt: chat.startedAt,
            lastActivityAt: chat.lastActivityAt,
            phase: chat.livePhase,
            activeRetry: chat.activeRetry,
            thoughtChars: chat.thoughtChars,
            answerChars: chat.answerChars,
            hasActiveTool: activeTools.isNotEmpty,
            activeToolLabel: activeToolLabel,
            liveStatusLabel: chat.liveStatusLabel,
            liveThoughtHeadline: liveThoughtHeadline,
            activePlanLabel: currentPlan?.content,
            now: _now,
            liveTokensPerSecond: chat.liveTokensPerSecond,
            inline: widget.inline,
            isStopping: chat.isStopping,
            hasPendingApproval: hasPendingApproval,
            pendingApprovalLabel: pendingApprovalLabel,
            activeToolCount: activeTools.length,
            includeSpeedInPill: false,
          )
        : null;

    final primaryText = health != null
        ? health.pillText
        : '计划完成 $donePlan/$totalPlan';
    final isWarnTone =
        health != null &&
        (health.tone == TurnHealthTone.waitingApproval ||
            health.tone == TurnHealthTone.retrying ||
            health.tone == TurnHealthTone.suspectedStall);
    final dotTone = (!chat.isBusy && !hasPendingApproval)
        ? StatusTone.ok
        : (isWarnTone ? StatusTone.warn : StatusTone.busy);

    final speedLabel = health?.liveSpeedLabel;
    final elapsed =
        (chat.isBusy || hasPendingApproval) && chat.startedAt != null
        ? _formatElapsed(chat.startedAt!)
        : null;

    final capsule = SmoothSize(
      duration: AppMotion.of(context, AppMotion.quick),
      child: Pressable(
        child: GlassSurface(
          tier: GlassTier.chrome,
          stadium: widget.inline && totalPlan == 0,
          borderRadius: widget.inline && totalPlan == 0
              ? null
              : AppShape.radiusLg,
          onTap: () => unawaited(showPlanAndActivitySheet(context, ref)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.inline ? 11 : 13,
              vertical: widget.inline ? 6 : 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    StatusDot(tone: dotTone, size: 7),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        primaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isWarnTone ? dsh.warning : scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (speedLabel != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        speedLabel,
                        style: AppType.monoLabel(
                          color: scheme.primary,
                        ).copyWith(fontSize: 10.5),
                      ),
                    ],
                    if (totalPlan > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$donePlan/$totalPlan',
                        style: AppType.monoLabel(color: scheme.primary),
                      ),
                    ],
                    if (elapsed != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        elapsed,
                        style: AppType.monoLabel(
                          color: isWarnTone ? dsh.warning : dsh.textTertiary,
                        ),
                      ),
                    ],
                    const SizedBox(width: 3),
                    Icon(
                      AppIcons.disclosure,
                      size: 13,
                      color: isWarnTone ? dsh.warning : dsh.textTertiary,
                    ),
                  ],
                ),
                if (totalPlan > 0) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: donePlan / totalPlan,
                      minHeight: 3,
                      backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                      color: isWarnTone ? dsh.warning : scheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.inline) return capsule;

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
          child: capsule,
        ),
      ),
    );
  }
}

/// Compact floating alert strip shown directly above the composer ONLY when the
/// active turn is visibly retrying a transient network/429 error or has received
/// zero output for >= 60s without an active tool.
class TurnAlertBanner extends ConsumerStatefulWidget {
  const TurnAlertBanner({super.key});

  @override
  ConsumerState<TurnAlertBanner> createState() => _TurnAlertBannerState();
}

class _TurnAlertBannerState extends ConsumerState<TurnAlertBanner> {
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

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(
      chatProvider.select(
        (c) => (
          isBusy: c.isBusy,
          isStopping: c.isStopping,
          pendingPermissions: c.pendingPermissions,
          startedAt: c.turnStartedAt,
          lastActivityAt: c.lastActivityAt,
          livePhase: c.livePhase,
          liveStatusLabel: c.liveStatusLabel,
          activeRetry: c.activeRetry,
          thoughtChars: c.thoughtChars,
          answerChars: c.answerChars,
          liveTokensPerSecond: c.liveTokensPerSecond,
          sessionCwd: c.sessionCwd,
          plan: c.transcript.plan,
          lastItem: c.transcript.items.isNotEmpty
              ? c.transcript.items.last
              : null,
        ),
      ),
    );
    final phoneApprovals = ref.watch(
      phoneControlProvider.select((p) => p.pendingApprovals),
    );
    final hasPendingApproval =
        chat.pendingPermissions.isNotEmpty || phoneApprovals.isNotEmpty;

    _syncTicker(chat.isBusy && chat.startedAt != null);
    if (!chat.isBusy) return const SizedBox.shrink();

    final lastAssistant = chat.lastItem is AssistantTranscriptItem
        ? chat.lastItem as AssistantTranscriptItem
        : null;
    final activeTools = lastAssistant != null
        ? lastAssistant.toolCalls.where((t) => t.status.isActive).toList()
        : const <AcpToolCall>[];

    final activeToolLabel = activeTools.isNotEmpty
        ? formatNativeToolLiveStatus(
            activeTools.last,
            workspaceCwd: chat.sessionCwd,
          )
        : null;
    final pendingApprovalLabel = chat.pendingPermissions.isNotEmpty
        ? formatNativeToolLiveStatus(
            chat.pendingPermissions.first.request.toolCall,
            workspaceCwd: chat.sessionCwd,
          )
        : (phoneApprovals.isNotEmpty ? phoneApprovals.first.summary : null);
    final liveThoughtHeadline = chat.livePhase == TurnLivePhase.thinking
        ? latestAssistantThoughtHeadline(lastAssistant)
        : null;

    final health = deriveTurnHealth(
      startedAt: chat.startedAt,
      lastActivityAt: chat.lastActivityAt,
      phase: chat.livePhase,
      activeRetry: chat.activeRetry,
      thoughtChars: chat.thoughtChars,
      answerChars: chat.answerChars,
      hasActiveTool: activeTools.isNotEmpty,
      activeToolLabel: activeToolLabel,
      liveStatusLabel: chat.liveStatusLabel,
      liveThoughtHeadline: liveThoughtHeadline,
      activePlanLabel: chat.plan.where((p) => p.isInProgress).firstOrNull?.content,
      now: _now,
      liveTokensPerSecond: chat.liveTokensPerSecond,
      isStopping: chat.isStopping,
      hasPendingApproval: hasPendingApproval,
      pendingApprovalLabel: pendingApprovalLabel,
      activeToolCount: activeTools.length,
    );

    if (!health.showAlertBanner) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final isRetrying = health.tone == TurnHealthTone.retrying;

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
          child: GlassSurface(
            tier: GlassTier.chrome,
            borderRadius: AppShape.radiusMd,
            style: DshSurfaces.of(context).chrome.copyWith(
              hairline: dsh.warning.withValues(alpha: 0.48),
            ),
            onTap: () => unawaited(showPlanAndActivitySheet(context, ref)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    isRetrying ? AppIcons.retry : AppIcons.warning,
                    size: 15,
                    color: dsh.warning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      health.bannerText!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: dsh.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () =>
                        unawaited(showPlanAndActivitySheet(context, ref)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: ShapeDecoration(
                        color: dsh.warning.withValues(alpha: 0.14),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        '日志',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: dsh.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (!isRetrying) ...[
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () =>
                          unawaited(ref.read(chatProvider.notifier).cancel()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: ShapeDecoration(
                          color: dsh.danger.withValues(alpha: 0.12),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          '停止',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: dsh.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet displaying live turn health diagnostics, retry/engine logs,
/// `AcpPlanEntry` checklist, and recent tool calls.
Future<void> showPlanAndActivitySheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => const _PlanActivitySheetBody(),
  );
}

class _PlanActivitySheetBody extends ConsumerStatefulWidget {
  const _PlanActivitySheetBody();

  @override
  ConsumerState<_PlanActivitySheetBody> createState() =>
      _PlanActivitySheetBodyState();
}

class _PlanActivitySheetBodyState
    extends ConsumerState<_PlanActivitySheetBody> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  (IconData, Color) _planIcon(
    AcpPlanEntry entry,
    ColorScheme scheme,
    DshColors dsh,
  ) {
    if (entry.isCompleted) return (AppIcons.success, dsh.success);
    if (entry.isInProgress) return (AppIcons.inProgress, scheme.primary);
    if (entry.isFailed) return (AppIcons.stepFailed, dsh.danger);
    if (entry.isSkipped) return (AppIcons.stepSkipped, dsh.textTertiary);
    return (AppIcons.pending, dsh.textTertiary);
  }

  (IconData, Color, String) _toolStatusMeta(
    AcpToolStatus status,
    ColorScheme scheme,
    DshColors dsh,
  ) => switch (status) {
    AcpToolStatus.inProgress => (AppIcons.running, scheme.primary, '运行中'),
    AcpToolStatus.paused => (AppIcons.approval, dsh.warning, '待确认'),
    AcpToolStatus.pending => (AppIcons.waiting, dsh.warning, '等待中'),
    AcpToolStatus.failed => (AppIcons.failed, dsh.danger, '失败'),
    AcpToolStatus.cancelled => (AppIcons.stopped, dsh.textTertiary, '已取消'),
    AcpToolStatus.completed => (AppIcons.done, dsh.success, '已完成'),
  };

  String _fmtClock(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final phoneApprovals = ref.watch(
      phoneControlProvider.select((p) => p.pendingApprovals),
    );
    final runtimeLogs = ref.watch(localRuntimeProvider.select((s) => s.logs));
    final plan = chat.transcript.plan;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dsh = DshColors.of(context);
    final recentTools = chat.transcript.items
        .whereType<AssistantTranscriptItem>()
        .expand((item) => item.toolCalls)
        .toList()
        .reversed
        .take(12)
        .toList();

    final lastItem = chat.transcript.items.isNotEmpty
        ? chat.transcript.items.last
        : null;
    final lastAssistant = lastItem is AssistantTranscriptItem ? lastItem : null;
    final activeTools = lastAssistant != null
        ? lastAssistant.toolCalls.where((t) => t.status.isActive).toList()
        : const <AcpToolCall>[];
    final activeToolLabel = activeTools.isNotEmpty
        ? formatNativeToolLiveStatus(
            activeTools.last,
            workspaceCwd: chat.sessionCwd,
          )
        : null;
    final hasPendingApproval =
        chat.pendingPermissions.isNotEmpty || phoneApprovals.isNotEmpty;
    final pendingApprovalLabel = chat.pendingPermissions.isNotEmpty
        ? formatNativeToolLiveStatus(
            chat.pendingPermissions.first.request.toolCall,
            workspaceCwd: chat.sessionCwd,
          )
        : (phoneApprovals.isNotEmpty ? phoneApprovals.first.summary : null);
    final liveThoughtHeadline = chat.livePhase == TurnLivePhase.thinking
        ? latestAssistantThoughtHeadline(lastAssistant)
        : null;

    final health = (chat.isBusy || hasPendingApproval)
        ? deriveTurnHealth(
            startedAt: chat.turnStartedAt,
            lastActivityAt: chat.lastActivityAt,
            phase: chat.livePhase,
            activeRetry: chat.activeRetry,
            thoughtChars: chat.thoughtChars,
            answerChars: chat.answerChars,
            hasActiveTool: activeTools.isNotEmpty,
            activeToolLabel: activeToolLabel,
            liveStatusLabel: chat.liveStatusLabel,
            liveThoughtHeadline: liveThoughtHeadline,
            activePlanLabel: plan.where((p) => p.isInProgress).firstOrNull?.content,
            now: _now,
            liveTokensPerSecond: chat.liveTokensPerSecond,
            inline: false,
            isStopping: chat.isStopping,
            hasPendingApproval: hasPendingApproval,
            pendingApprovalLabel: pendingApprovalLabel,
            activeToolCount: activeTools.length,
          )
        : null;

    final elapsedSecs = chat.turnStartedAt != null
        ? _now.difference(chat.turnStartedAt!).inSeconds.clamp(0, 86400)
        : 0;
    final liveSpeedText =
        chat.liveTokensPerSecond != null && chat.liveTokensPerSecond! > 0
        ? formatTokensPerSecond(chat.liveTokensPerSecond!)
        : null;
    final throughputParts = <String>[
      if (liveSpeedText != null) '速度 $liveSpeedText',
      if (chat.estimatedTurnTokens > 0) '约 ${chat.estimatedTurnTokens} tok',
      '思考 ${formatCharCount(chat.thoughtChars)}',
      '正文 ${formatCharCount(chat.answerChars)}',
      '重试 ${chat.retryCount} 次',
    ];
    final displayLogs = chat.turnLogs.isNotEmpty
        ? chat.turnLogs.reversed.take(8).toList()
        : runtimeLogs.reversed
              .map(cleanEngineLogLine)
              .where((l) => l.isNotEmpty && !l.startsWith('[bridge]'))
              .take(6)
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
              (chat.isBusy || hasPendingApproval) ? '实时运行状态与进度' : '任务计划与进度',
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
            if ((chat.isBusy || hasPendingApproval) && health != null)
              SheetGroup(
                title: '实时状态（原生事件 / 重试 / 超时监测）',
                children: [
                  ListPageRow(
                    icon: health.tone == TurnHealthTone.waitingApproval
                        ? AppIcons.approval
                        : health.tone == TurnHealthTone.retrying
                        ? AppIcons.retry
                        : health.tone == TurnHealthTone.suspectedStall
                        ? AppIcons.warning
                        : AppIcons.running,
                    iconColor:
                        health.tone == TurnHealthTone.waitingApproval ||
                            health.tone == TurnHealthTone.retrying ||
                            health.tone == TurnHealthTone.suspectedStall
                        ? dsh.warning
                        : scheme.primary,
                    title: health.detailHeadline,
                    titleMaxLines: 3,
                    subtitle:
                        '本轮耗时 ${formatChineseDuration(elapsedSecs)} · 最近收到输出：${formatLastSignalAge(health.silentSeconds)}',
                    chevron: false,
                  ),
                  ListPageRow(
                    icon: AppIcons.askAi,
                    title: '实时吞吐统计',
                    subtitle: throughputParts.join(' · '),
                    subtitleMaxLines: 2,
                    chevron: false,
                  ),
                  if (chat.activeRetry != null)
                    ListPageRow(
                      icon: AppIcons.warning,
                      iconColor: dsh.warning,
                      title: '引擎重试原文',
                      subtitle: chat.activeRetry!.rawMessage,
                      subtitleMaxLines: 4,
                      chevron: false,
                    ),
                  if (health.tone == TurnHealthTone.retrying ||
                      health.tone == TurnHealthTone.suspectedStall)
                    ListPageRow(
                      icon: AppIcons.regenerate,
                      iconColor: dsh.warning,
                      title: '中止当前卡顿并重发上一条消息',
                      subtitle: '立刻结束本轮等待并重新向模型发起请求',
                      chevron: false,
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(
                          ref
                              .read(chatProvider.notifier)
                              .regenerateLast(forceImmediate: true),
                        );
                      },
                    ),
                ],
              ),
            if (chat.turnEvents.isNotEmpty)
              SheetGroup(
                title: '本轮时间线',
                children: [
                  for (final ev in chat.turnEvents.reversed.take(6))
                    ListPageRow(
                      icon: ev.isWarning ? AppIcons.warning : AppIcons.done,
                      iconColor: ev.isWarning ? dsh.warning : dsh.textTertiary,
                      title: ev.label,
                      titleMaxLines: 2,
                      subtitle: ev.detail,
                      subtitleMaxLines: 2,
                      meta: _fmtClock(ev.timestamp),
                      chevron: false,
                    ),
                ],
              ),
            if (displayLogs.isNotEmpty)
              SheetGroup(
                title: '最近引擎输出（ACP / stderr / 重试日志）',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: SelectableText(
                      displayLogs.join('\n'),
                      style: AppType.monoLabel(
                        color: dsh.textTertiary,
                      ).copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            if (plan.isNotEmpty)
              SheetGroup(
                title:
                    '计划清单（${plan.where((p) => p.isCompleted).length}/${plan.length}）',
                children: [
                  for (final entry in plan)
                    Builder(
                      builder: (ctx) {
                        final (ic, col) = _planIcon(entry, scheme, dsh);
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
                    Builder(
                      builder: (ctx) {
                        final (ic, col, statusText) = _toolStatusMeta(
                          tc.status,
                          scheme,
                          dsh,
                        );
                        return ListPageRow(
                          icon: ic,
                          iconColor: col,
                          title: formatNativeToolLiveStatus(
                            tc,
                            workspaceCwd: chat.sessionCwd,
                          ),
                          subtitle: tc.locations.isNotEmpty
                              ? displayToolPath(
                                  tc.locations.first.path,
                                  workspaceCwd: chat.sessionCwd,
                                )
                              : formatToolSummary(
                                  tc,
                                  workspaceCwd: chat.sessionCwd,
                                ),
                          meta: statusText,
                          chevron: false,
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
