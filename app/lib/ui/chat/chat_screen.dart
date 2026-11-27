// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../runtime/runtime_models.dart';
import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../../state/pet_state.dart';
import '../../state/phone_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../../state/settings_state.dart';
import '../../state/workspaces_state.dart';
import '../common/status_dot.dart';
import '../engine/engine_screen.dart';
import '../phone/phone_control_screen.dart';
import '../shell/sessions_drawer.dart';
import '../theme/theme.dart';
import 'activity_strip.dart';
import 'chat_header.dart';
import 'chat_list.dart';
import 'composer_bar.dart';
import 'permission_card.dart';
import 'permission_controls.dart';
import 'session_detail_page.dart';
import 'tool_format.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.onOpenDrawer,
    required this.onOpenQuickPanel,
    required this.onOpenDestination,
  });

  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenQuickPanel;
  final ValueChanged<DrawerDestination> onOpenDestination;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  final _composerController = TextEditingController();
  final _scrolledUnder = ValueNotifier<double>(0);
  final _jumpPill = ValueNotifier<({bool show, bool unread})>(
    (show: false, unread: false),
  );
  ({bool show, bool unread})? _pendingJumpPill;
  bool _jumpPillPostFrameScheduled = false;
  bool _pinnedToBottom = true;
  bool _scrollFollowScheduled = false;
  int _programmaticScrollDepth = 0;
  double _lastMaxExtent = 0;
  double? _measuredDockHeight;

  ({bool show, bool unread}) get _currentJumpPill =>
      _pendingJumpPill ?? _jumpPill.value;

  void _setJumpPill({
    required bool show,
    required bool unread,
    bool defer = false,
  }) {
    final next = (show: show, unread: unread);
    if (_currentJumpPill == next) return;
    if (defer) {
      _pendingJumpPill = next;
      if (!_jumpPillPostFrameScheduled) {
        _jumpPillPostFrameScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpPillPostFrameScheduled = false;
          final pending = _pendingJumpPill;
          _pendingJumpPill = null;
          if (mounted && pending != null && _jumpPill.value != pending) {
            _jumpPill.value = pending;
          }
        });
      }
      return;
    }
    _pendingJumpPill = null;
    if (_jumpPill.value != next) {
      _jumpPill.value = next;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _composerController.dispose();
    _scrolledUnder.dispose();
    _jumpPill.dispose();
    super.dispose();
  }

  bool _isNearBottom(ScrollMetrics metrics, {double slop = 48}) =>
      (metrics.maxScrollExtent - metrics.pixels) <= slop;

  void _updateScrollFade(ScrollMetrics metrics) {
    final nextFade = (metrics.pixels / 24).clamp(0.0, 1.0);
    if (_scrolledUnder.value != nextFade) {
      _scrolledUnder.value = nextFade;
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _updateScrollFade(pos);
    final cur = _currentJumpPill;
    final farFromBottom =
        pos.maxScrollExtent > 120 &&
        (pos.maxScrollExtent - pos.pixels) > (cur.show ? 48 : 160);
    _setJumpPill(
      show: farFromBottom,
      unread: farFromBottom ? cur.unread : false,
    );
  }

  void _scheduleFollowBottom({bool animate = false}) {
    if (_scrollFollowScheduled) return;
    _scrollFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollFollowScheduled = false;
      if (!mounted || !_scrollController.hasClients || !_pinnedToBottom) return;
      final pos = _scrollController.position;
      final target = pos.maxScrollExtent;
      final delta = target - pos.pixels;
      if (delta <= 1.0) return;
      if (animate && delta < 600) {
        _programmaticScrollDepth++;
        unawaited(
          _scrollController
              .animateTo(
                target,
                duration: AppMotion.of(context, AppMotion.quick),
                curve: AppMotion.std,
              )
              .whenComplete(() {
                if (_programmaticScrollDepth > 0) _programmaticScrollDepth--;
              }),
        );
      } else {
        _programmaticScrollDepth++;
        try {
          _scrollController.jumpTo(target);
        } finally {
          if (_programmaticScrollDepth > 0) _programmaticScrollDepth--;
        }
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    _updateScrollFade(n.metrics);
    final cur = _currentJumpPill;
    var nextUnread = cur.unread;
    if (n is UserScrollNotification) {
      // Finger dragging downward = scrolling up toward history: disengage immediately.
      if (n.direction == ScrollDirection.forward) {
        _pinnedToBottom = false;
      }
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      if (!_isNearBottom(n.metrics)) {
        _pinnedToBottom = false;
      }
    } else if (n is ScrollEndNotification && _programmaticScrollDepth == 0) {
      final atBottom = _isNearBottom(n.metrics);
      _pinnedToBottom = atBottom;
      if (atBottom) nextUnread = false;
    }
    final far =
        n.metrics.maxScrollExtent > 120 &&
        (n.metrics.maxScrollExtent - n.metrics.pixels) >
            (cur.show ? 48 : 160);
    _setJumpPill(show: far, unread: far ? nextUnread : false);
    return false;
  }

  bool _handleScrollMetricsNotification(ScrollMetricsNotification n) {
    if (n.depth != 0) return false;
    final metrics = n.metrics;
    _updateScrollFade(metrics);
    final grew = metrics.maxScrollExtent > _lastMaxExtent + 2;
    _lastMaxExtent = metrics.maxScrollExtent;

    if (_pinnedToBottom) {
      if (metrics.maxScrollExtent - metrics.pixels > 2) {
        _scheduleFollowBottom();
      }
      _setJumpPill(show: false, unread: false, defer: true);
    } else {
      final cur = _currentJumpPill;
      final far =
          metrics.maxScrollExtent > 120 &&
          (metrics.maxScrollExtent - metrics.pixels) > (cur.show ? 48 : 160);
      _setJumpPill(
        show: far,
        unread: far ? (cur.unread || grew) : false,
        defer: true,
      );
    }
    return false;
  }

  void _jumpToBottom() {
    _pinnedToBottom = true;
    _setJumpPill(show: false, unread: false);
    if (!_scrollController.hasClients) return;
    _programmaticScrollDepth++;
    unawaited(
      _scrollController
          .animateTo(
            _scrollController.position.maxScrollExtent,
            duration: AppMotion.of(context, AppMotion.standard),
            curve: AppMotion.std,
          )
          .whenComplete(() {
            if (_programmaticScrollDepth > 0) _programmaticScrollDepth--;
          }),
    );
  }

  Future<void> _submitPrompt(String text) {
    _pinnedToBottom = true;
    _setJumpPill(show: false, unread: false);
    final future = ref.read(chatProvider.notifier).send(text);
    _scheduleFollowBottom(animate: true);
    return future;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      petSettingsProvider.select((p) => p.pendingPrefillText),
      (_, next) {
        if (next != null && next.isNotEmpty) {
          _composerController.value = TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          );
          ref.read(petSettingsProvider.notifier).clearPendingPrefill();
        }
      },
    );
    ref.listen<String?>(
      chatProvider.select((c) => c.sessionId),
      (prev, next) {
        if (prev == next) return;
        _pinnedToBottom = true;
        _lastMaxExtent = 0;
        _setJumpPill(show: false, unread: false);
        _scheduleFollowBottom();
      },
    );

    final connAsync = ref.watch(activeConnectionProvider);
    final selectedWs = ref.watch(selectedWorkspaceProvider);
    final currentSession = ref.watch(
      sessionsProvider.select((s) => s.currentSession),
    );
    final sessions = ref.watch(sessionsProvider);
    final phoneApprovals = ref.watch(
      phoneControlProvider.select((p) => p.pendingApprovals),
    );
    final chat = ref.watch(
      chatProvider.select(
        (s) => (
          sessionId: s.sessionId,
          title: s.transcript.title,
          isBusy: s.isBusy,
          hasPlan: s.transcript.plan.isNotEmpty,
          permissions: s.pendingPermissions,
          error: s.error,
          authRequired: s.authRequired,
          hasItems: s.transcript.items.isNotEmpty,
        ),
      ),
    );

    final connected = connAsync.value != null;
    final hasSession = chat.sessionId != null;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final fallbackDock =
        keyboardInset +
        bottomPad +
        ((chat.isBusy || chat.hasPlan) ? 142.0 : 122.0);
    final dockReserve = _measuredDockHeight ?? fallbackDock;

    final headerTitle = hasSession
        ? (chat.title?.isNotEmpty == true
              ? chat.title!
              : (currentSession != null
                    ? sessions.displayTitle(currentSession)
                    : '当前对话'))
        : 'AGY Go';

    return Stack(
      children: [
        // Main scrolling message stream or empty state
        Positioned.fill(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _handleScrollMetricsNotification,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: ChatList(
                scrollController: _scrollController,
                bottomInset: dockReserve,
                onPickSuggestion: (prompt) => unawaited(_submitPrompt(prompt)),
                onEditDraft: (text) {
                  _composerController.value = TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: text.length),
                  );
                },
              ),
            ),
          ),
        ),

        // Floating top chrome-glass header with live-ticking turn health sync
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _LiveChatHeader(
            title: headerTitle,
            detail: selectedWs?.displayTitle,
            scrolledUnder: chat.hasItems ? _scrolledUnder : null,
            hasSession: hasSession,
            narrow: narrow,
            onOpenDrawer: widget.onOpenDrawer,
            onTitleTap: hasSession
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SessionDetailPage(),
                    ),
                  )
                : () => showHostSwitcherSheet(context, ref),
            onNewChat: hasSession
                ? () => ref.read(chatProvider.notifier).startNewChat()
                : null,
          ),
        ),

        // Floating bottom composer dock with fade, approval cards, and jump-to-bottom pill
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chat.hasItems)
                ValueListenableBuilder<({bool show, bool unread})>(
                  valueListenable: _jumpPill,
                  builder: (context, pill, _) {
                    if (!pill.show) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: pill.unread
                          ? GlassSurface(
                              tier: GlassTier.chrome,
                              stadium: true,
                              style: DshSurfaces.of(context).chrome.copyWith(
                                hairline: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.45),
                              ),
                              onTap: _jumpToBottom,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.scrollToBottom,
                                      size: 15,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '新内容',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : SizedBox.square(
                              dimension: 40,
                              child: GlassSurface(
                                tier: GlassTier.chrome,
                                circle: true,
                                onTap: _jumpToBottom,
                                child: Center(
                                  child: Icon(
                                    AppIcons.scrollToBottom,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                    );
                  },
                ),
              _DockHeightObserver(
                onHeightChanged: (h) {
                  if (!mounted) return;
                  if (_measuredDockHeight == null ||
                      (_measuredDockHeight! - h).abs() > 1.0) {
                    setState(() => _measuredDockHeight = h);
                    if (_pinnedToBottom) _scheduleFollowBottom();
                  }
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: BottomFade(height: bottomPad + 96),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: keyboardInset > 0 ? keyboardInset : bottomPad,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (chat.error != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: AppSpace.floatingWidth,
                                  ),
                                  child: GlassSurface(
                                    tier: GlassTier.card,
                                    borderRadius: AppShape.radiusLg,
                                    style: DshSurfaces.of(context).card
                                        .copyWith(
                                          hairline: DshColors.of(
                                            context,
                                          ).danger.withValues(alpha: 0.45),
                                        ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            AppIcons.error,
                                            size: 18,
                                            color: DshColors.of(context).danger,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              chat.error!,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: DshColors.of(
                                                      context,
                                                    ).danger,
                                                  ),
                                            ),
                                          ),
                                          if (chat.authRequired)
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          const EngineScreen(),
                                                    ),
                                                  ),
                                              child: const Text('去认证'),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          for (final prompt in phoneApprovals)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: AppSpace.floatingWidth,
                                  ),
                                  child: PhoneApprovalCard(
                                    prompt: prompt,
                                    onApprove: () => ref
                                        .read(phoneControlProvider.notifier)
                                        .resolveApproval(
                                          prompt.id,
                                          approved: true,
                                        ),
                                    onDeny: () => ref
                                        .read(phoneControlProvider.notifier)
                                        .resolveApproval(
                                          prompt.id,
                                          approved: false,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          for (final perm in chat.permissions)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: AppSpace.floatingWidth,
                                  ),
                                  child: PermissionCard(
                                    pending: perm,
                                    onSelect: (optId) => ref
                                        .read(chatProvider.notifier)
                                        .respondPermission(perm, optId),
                                    onCancel: () => ref
                                        .read(chatProvider.notifier)
                                        .respondPermission(perm, null),
                                    onAllowAllForChat: (allowId) => ref
                                        .read(chatProvider.notifier)
                                        .respondPermission(
                                          perm,
                                          allowId,
                                          allowAllForChat: true,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          const TurnAlertBanner(),
                          const _ComposerStatusRow(),
                          ComposerBar(
                            controller: _composerController,
                            enabled: connected,
                            isBusy: chat.isBusy,
                            onOpenDestination: widget.onOpenDestination,
                            onSend: _submitPrompt,
                            onCancel: () =>
                                ref.read(chatProvider.notifier).cancel(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Live-ticking top header synced with [deriveTurnHealth], foreground & background
/// approvals, retries, stall tones, and connection status.
class _LiveChatHeader extends ConsumerStatefulWidget {
  const _LiveChatHeader({
    required this.title,
    required this.detail,
    required this.scrolledUnder,
    required this.hasSession,
    required this.narrow,
    required this.onOpenDrawer,
    required this.onTitleTap,
    required this.onNewChat,
  });

  final String title;
  final String? detail;
  final ValueNotifier<double>? scrolledUnder;
  final bool hasSession;
  final bool narrow;
  final VoidCallback onOpenDrawer;
  final VoidCallback onTitleTap;
  final VoidCallback? onNewChat;

  @override
  ConsumerState<_LiveChatHeader> createState() => _LiveChatHeaderState();
}

class _LiveChatHeaderState extends ConsumerState<_LiveChatHeader> {
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
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider.select((s) => s.status));
    final connAsync = ref.watch(activeConnectionProvider);
    final phoneApprovals = ref.watch(
      phoneControlProvider.select((p) => p.pendingApprovals),
    );
    final chat = ref.watch(
      chatProvider.select((s) {
        final lastItem = s.transcript.items.isNotEmpty
            ? s.transcript.items.last
            : null;
        final assistant = lastItem is AssistantTranscriptItem ? lastItem : null;
        final activeTools = assistant != null
            ? assistant.toolCalls.where((t) => t.status.isActive).toList()
            : const <AcpToolCall>[];
        final activePlan = s.transcript.plan
            .where((p) => p.isInProgress)
            .firstOrNull;
        final permTool = s.pendingPermissions.firstOrNull?.request.toolCall;
        return (
          isBusy: s.isBusy,
          isStopping: s.isStopping,
          startedAt: s.turnStartedAt,
          lastActivityAt: s.lastActivityAt,
          livePhase: s.livePhase,
          liveStatusLabel: s.liveStatusLabel,
          activeRetry: s.activeRetry,
          thoughtChars: s.thoughtChars,
          answerChars: s.answerChars,
          liveTokensPerSecond: s.liveTokensPerSecond,
          activeToolCount: activeTools.length,
          activeToolLabel: activeTools.isNotEmpty
              ? formatNativeToolLiveStatus(
                  activeTools.last,
                  workspaceCwd: s.sessionCwd,
                )
              : null,
          activePlanLabel: activePlan?.content,
          liveThoughtHeadline: s.livePhase == TurnLivePhase.thinking
              ? latestAssistantThoughtHeadline(assistant)
              : null,
          hasPerm: s.pendingPermissions.isNotEmpty,
          permLabel: permTool != null
              ? formatNativeToolLiveStatus(
                  permTool,
                  workspaceCwd: s.sessionCwd,
                )
              : null,
          bgRunningCount: s.backgroundRunningIds.length,
          bgPendingCount: s.backgroundPendingPermissionIds.length,
          bgSingleSummary: s.backgroundRunningIds.length == 1
              ? s.backgroundSummaries[s.backgroundRunningIds.first]
              : null,
        );
      }),
    );

    _syncTicker(chat.isBusy && chat.startedAt != null);

    final connected = connAsync.value != null;
    final hasPendingApproval = chat.hasPerm || phoneApprovals.isNotEmpty;
    final pendingLabel = phoneApprovals.isNotEmpty
        ? (phoneApprovals.first.summary.trim().isNotEmpty
              ? phoneApprovals.first.summary.trim()
              : phoneApprovals.first.tool)
        : chat.permLabel;

    final HeaderStatus headerStatus;
    if (hasPendingApproval) {
      headerStatus = const HeaderStatus(StatusTone.warn, '等你确认');
    } else if (chat.isBusy) {
      final health = deriveTurnHealth(
        startedAt: chat.startedAt,
        lastActivityAt: chat.lastActivityAt,
        phase: chat.livePhase,
        activeRetry: chat.activeRetry,
        thoughtChars: chat.thoughtChars,
        answerChars: chat.answerChars,
        hasActiveTool: chat.activeToolCount > 0,
        activeToolLabel: chat.activeToolLabel,
        activeToolCount: chat.activeToolCount,
        liveStatusLabel: chat.liveStatusLabel,
        liveThoughtHeadline: chat.liveThoughtHeadline,
        activePlanLabel: chat.activePlanLabel,
        now: _now,
        liveTokensPerSecond: chat.liveTokensPerSecond,
        isStopping: chat.isStopping,
        hasPendingApproval: hasPendingApproval,
        pendingApprovalLabel: pendingLabel,
        includeSpeedInPill: false,
      );
      final isWarn =
          health.tone == TurnHealthTone.retrying ||
          health.tone == TurnHealthTone.suspectedStall ||
          health.tone == TurnHealthTone.waitingApproval;
      final label = isWarn
          ? health.pillText
          : resolveNativeHeaderStatus(
              phase: chat.livePhase,
              activeToolStatus: chat.activeToolLabel,
              activeToolCount: chat.activeToolCount,
              nativeStatusLabel: chat.liveStatusLabel,
              activePlanLabel: chat.activePlanLabel,
              liveThoughtHeadline: chat.liveThoughtHeadline,
              activeRetry: chat.activeRetry,
              isStopping: chat.isStopping,
              hasPendingApproval: hasPendingApproval,
              pendingApprovalLabel: pendingLabel,
            );
      headerStatus = HeaderStatus(
        isWarn ? StatusTone.warn : StatusTone.busy,
        label,
      );
    } else if (chat.bgPendingCount > 0) {
      headerStatus = HeaderStatus(
        StatusTone.warn,
        chat.bgPendingCount == 1
            ? '后台有待确认'
            : '后台 ${chat.bgPendingCount} 个待确认',
      );
    } else if (chat.bgRunningCount > 0) {
      final single = chat.bgSingleSummary;
      final bgLabel = chat.bgRunningCount == 1 &&
              single != null &&
              single.activeToolLabel != null
          ? '后台 · ${single.activeToolLabel}'
          : '后台 ${chat.bgRunningCount} 个运行中';
      headerStatus = HeaderStatus(StatusTone.busy, bgLabel);
    } else if (connected) {
      headerStatus = HeaderStatus(StatusTone.ok, hosts.activeLabel());
    } else if (connAsync.isLoading || runtime.phase == RuntimePhase.starting) {
      headerStatus = const HeaderStatus(StatusTone.busy, '连接中');
    } else if (connAsync.hasError || runtime.phase == RuntimePhase.error) {
      headerStatus = const HeaderStatus(StatusTone.error, '连接异常');
    } else {
      headerStatus = const HeaderStatus(StatusTone.idle, '未连接');
    }

    return ChatHeader(
      title: widget.title,
      status: headerStatus,
      detail: widget.detail,
      scrolledUnder: widget.scrolledUnder,
      onOpenDrawer: widget.onOpenDrawer,
      onTitleTap: widget.onTitleTap,
      trailing: ModelModeChip(
        compact: widget.hasSession,
        iconOnly: widget.hasSession && widget.narrow,
      ),
      onNewChat: widget.onNewChat,
    );
  }
}

/// Reports the laid-out height of the floating bottom dock so [ChatList]
/// always reserves exact bottom padding even when approval cards, alerts,
/// queued messages, or multi-line drafts expand dynamically.
class _DockHeightObserver extends SingleChildRenderObjectWidget {
  const _DockHeightObserver({
    required this.onHeightChanged,
    required super.child,
  });

  final ValueChanged<double> onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDockHeightObserver(onHeightChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDockHeightObserver renderObject,
  ) {
    renderObject.onHeightChanged = onHeightChanged;
  }
}

class _RenderDockHeightObserver extends RenderProxyBox {
  _RenderDockHeightObserver(this.onHeightChanged);

  ValueChanged<double> onHeightChanged;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (_lastHeight == null || (_lastHeight! - h).abs() > 1.0) {
      _lastHeight = h;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHeightChanged(h);
      });
    }
  }
}

/// Single horizontal status row directly above [ComposerBar] placing the live
/// activity capsule and the active permission capsule side-by-side.
class _ComposerStatusRow extends ConsumerWidget {
  const _ComposerStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final hasPhoneApproval = ref.watch(
      phoneControlProvider.select((p) => p.pendingApprovals.isNotEmpty),
    );
    final status = ref.watch(
      chatProvider.select(
        (c) => (
          showActivity:
              c.isBusy ||
              c.transcript.plan.isNotEmpty ||
              c.pendingPermissions.isNotEmpty,
          mode: c.sessionAgentMode,
          perm: c.sessionToolPermission,
          allowAll: c.allowAllForSession,
          extraDirs: c.additionalDirectories.length,
        ),
      ),
    );
    final showActivity = status.showActivity || hasPhoneApproval;
    final effectiveMode = status.mode ?? settings.agentMode;
    final effectivePerm = status.perm ?? settings.toolPermission;
    final showPerm =
        effectivePerm != AgyToolPermission.requestReview ||
        effectiveMode == AgyAgentMode.plan ||
        status.allowAll ||
        status.extraDirs > 0;

    if (!showActivity && !showPerm) return const SizedBox.shrink();

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
          child: Row(
            children: [
              if (showActivity)
                const Expanded(child: ActivityStrip(inline: true)),
              if (showActivity && showPerm) const SizedBox(width: 8),
              if (showPerm) const PermissionStatusPill(inline: true),
            ],
          ),
        ),
      ),
    );
  }
}
