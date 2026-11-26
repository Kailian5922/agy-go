// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:acp_client/acp_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../runtime/runtime_models.dart';
import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../../state/phone_state.dart';
import '../../state/runtime_state.dart';
import '../../state/sessions_state.dart';
import '../../state/settings_state.dart';
import '../../state/workspaces_state.dart';
import '../common/status_dot.dart';
import '../engine/engine_screen.dart';
import '../phone/phone_control_screen.dart';
import '../shell/drawer_destination.dart';
import '../shell/sessions_drawer.dart';
import '../theme/theme.dart';
import 'activity_strip.dart';
import 'chat_header.dart';
import 'chat_list.dart';
import 'composer_bar.dart';
import 'permission_card.dart';
import 'permission_controls.dart';
import 'session_detail_page.dart';

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
  bool _showJumpDown = false;

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
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final nextFade = (pos.pixels / 24).clamp(0.0, 1.0);
    if (_scrolledUnder.value != nextFade) {
      _scrolledUnder.value = nextFade;
    }
    final farFromBottom =
        pos.maxScrollExtent > 120 && (pos.maxScrollExtent - pos.pixels) > 180;
    if (farFromBottom != _showJumpDown) {
      setState(() => _showJumpDown = farFromBottom);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.std,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider).status;
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
          livePhase: s.livePhase,
          activeToolKind: s.transcript.items.isNotEmpty &&
                  s.transcript.items.last is AssistantTranscriptItem
              ? (s.transcript.items.last as AssistantTranscriptItem)
                    .toolCalls
                    .where((t) => t.status.isActive)
                    .lastOrNull
                    ?.kind
              : null,
          backgroundRunningCount: s.backgroundRunningIds.length,
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
    final extraDock = (chat.isBusy || chat.hasPlan) ? 142 : 122;
    final dockReserve = keyboardInset + bottomPad + extraDock;

    final HeaderStatus headerStatus;
    if (chat.permissions.isNotEmpty || phoneApprovals.isNotEmpty) {
      headerStatus = const HeaderStatus(StatusTone.warn, '等你确认');
    } else if (chat.isBusy) {
      headerStatus = HeaderStatus(
        chat.livePhase == TurnLivePhase.retrying
            ? StatusTone.warn
            : StatusTone.busy,
        headerStatusLabelForPhase(
          chat.livePhase,
          activeToolKind: chat.activeToolKind,
        ),
      );
    } else if (chat.backgroundRunningCount > 0) {
      headerStatus = HeaderStatus(
        StatusTone.busy,
        '后台 ${chat.backgroundRunningCount} 个运行中',
      );
    } else if (connected) {
      headerStatus = HeaderStatus(StatusTone.ok, hosts.activeLabel());
    } else if (connAsync.isLoading || runtime.phase == RuntimePhase.starting) {
      headerStatus = const HeaderStatus(StatusTone.busy, '连接中');
    } else if (connAsync.hasError || runtime.phase == RuntimePhase.error) {
      headerStatus = const HeaderStatus(StatusTone.error, '连接异常');
    } else {
      headerStatus = const HeaderStatus(StatusTone.idle, '未连接');
    }

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
          child: ChatList(
            scrollController: _scrollController,
            bottomInset: dockReserve,
            onPickSuggestion: (prompt) =>
                ref.read(chatProvider.notifier).send(prompt),
            onEditDraft: (text) {
              _composerController.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
            },
          ),
        ),

        // Floating top chrome-glass header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ChatHeader(
            title: headerTitle,
            status: headerStatus,
            detail: selectedWs?.displayTitle,
            scrolledUnder: chat.hasItems ? _scrolledUnder : null,
            onOpenDrawer: widget.onOpenDrawer,
            onTitleTap: hasSession
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SessionDetailPage(),
                    ),
                  )
                : () => showHostSwitcherSheet(context, ref),
            trailing: ModelModeChip(
              compact: hasSession,
              iconOnly: hasSession && narrow,
            ),
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
              if (_showJumpDown && chat.hasItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox.square(
                    dimension: 40,
                    child: GlassSurface(
                      tier: GlassTier.chrome,
                      circle: true,
                      onTap: _scrollToBottom,
                      child: Center(
                        child: Icon(
                          AppIcons.scrollToBottom,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              Stack(
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
                                  style: DshSurfaces.of(context).card.copyWith(
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
                          onSend: (text) async {
                            await ref.read(chatProvider.notifier).send(text);
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _scrollToBottom(),
                            );
                          },
                          onCancel: () =>
                              ref.read(chatProvider.notifier).cancel(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Single horizontal status row directly above [ComposerBar] placing the live
/// activity capsule and the active permission capsule side-by-side.
class _ComposerStatusRow extends ConsumerWidget {
  const _ComposerStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final status = ref.watch(
      chatProvider.select(
        (c) => (
          showActivity: c.isBusy || c.transcript.plan.isNotEmpty,
          mode: c.sessionAgentMode,
          perm: c.sessionToolPermission,
          allowAll: c.allowAllForSession,
          extraDirs: c.additionalDirectories.length,
        ),
      ),
    );
    final effectiveMode = status.mode ?? settings.agentMode;
    final effectivePerm = status.perm ?? settings.toolPermission;
    final showPerm =
        effectivePerm != AgyToolPermission.requestReview ||
        effectiveMode == AgyAgentMode.plan ||
        status.allowAll ||
        status.extraDirs > 0;

    if (!status.showActivity && !showPerm) return const SizedBox.shrink();

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
              if (status.showActivity)
                const Expanded(child: ActivityStrip(inline: true)),
              if (status.showActivity && showPerm) const SizedBox(width: 8),
              if (showPerm) const PermissionStatusPill(inline: true),
            ],
          ),
        ),
      ),
    );
  }
}
