// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:material_ui/material_ui.dart';

import '../../runtime/runtime_models.dart';
import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/settings_state.dart';
import '../../state/voice_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/expand_reveal.dart';
import '../common/list_page_row.dart';
import '../common/streaming_cursor.dart';
import '../share/share_screen.dart';
import '../shell/sessions_drawer.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';
import 'chat_header.dart';
import 'empty_state.dart';
import 'tool_call_card.dart';

class ChatList extends ConsumerWidget {
  const ChatList({
    super.key,
    required this.scrollController,
    required this.onPickSuggestion,
    required this.onEditDraft,
    required this.bottomInset,
  });

  final ScrollController scrollController;
  final void Function(String prompt) onPickSuggestion;
  final void Function(String text) onEditDraft;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final items = chat.transcript.items;
    final topPad = ChatHeader.heightOf(context) + 8;

    if (chat.isLoadingSession) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (items.isEmpty) {
      final hosts = ref.watch(hostsProvider);
      final runtime = ref.watch(localRuntimeProvider);
      final connAsync = ref.watch(activeConnectionProvider);
      final selectedWs = ref.watch(selectedWorkspaceProvider);
      final autoApprove = ref.watch(
        settingsProvider.select((s) => s.autoApproveCommands),
      );
      final connected = connAsync.value != null;
      final st = runtime.status;

      ChatIdleAction? idle;
      if (!connected && hosts.active.isLocal) {
        if (st.phase == RuntimePhase.notInstalled ||
            (st.phase == RuntimePhase.error && st.installedVersion == null)) {
          idle = ChatIdleAction(
            message: '本机 Antigravity CLI 尚未安装（免 Root、官方 arm64）',
            label: '一键安装官方 agy',
            onTap: () =>
                ref.read(localRuntimeProvider.notifier).installOrUpdate(),
          );
        } else if (st.phase == RuntimePhase.installing) {
          idle = ChatIdleAction(
            message: '正在下载并校验 Google 官方 Antigravity CLI…',
            label: '安装中…',
            onTap: null,
            progress: runtime.progress?.fraction,
            progressDetail: runtime.progress?.detail,
          );
        } else if (st.phase == RuntimePhase.installed ||
            st.phase == RuntimePhase.error) {
          idle = ChatIdleAction(
            message: st.error ?? '本机引擎已就绪（${st.installedVersion ?? ''}）',
            label: '启动本机引擎',
            onTap: () => ref.read(localRuntimeProvider.notifier).start(),
          );
        }
      }

      return SingleChildScrollView(
        controller: scrollController,
        physics: AppMotion.scrollPhysics(context),
        padding: EdgeInsets.fromLTRB(0, topPad + 16, 0, bottomInset + 24),
        child: ChatEmptyState(
          connected: connected,
          connecting: connAsync.isLoading,
          starting: st.phase == RuntimePhase.starting,
          idle: idle,
          onReconnect: !connected && connAsync.hasError
              ? () => ref.read(activeConnectionProvider.notifier).reconnect()
              : null,
          workspace: selectedWs?.displayTitle ?? '默认工作区',
          onWorkspace: () => showWorkspaceSheet(context, ref),
          options: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              SetupItem(
                icon: autoApprove ? AppIcons.permissionRisky : AppIcons.permissions,
                label: autoApprove ? '自动批准命令' : '标准审批',
                accentColor: autoApprove ? DshColors.of(context).warning : null,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setAutoApproveCommands(!autoApprove),
              ),
              SetupItem(
                icon: hosts.active.isLocal ? AppIcons.thisPhone : AppIcons.sshHost,
                label: hosts.activeLabel(),
                onTap: () => showHostSwitcherSheet(context, ref),
              ),
            ],
          ),
          onSuggestion: (s) => onPickSuggestion(s.prompt),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      physics: AppMotion.scrollPhysics(context),
      padding: EdgeInsets.fromLTRB(16, topPad, 16, bottomInset + 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Center(
          key: ValueKey(item.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpace.readingWidth),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: switch (item) {
                UserTranscriptItem() => _UserBubble(
                  item: item,
                  onQuote: (t) => ref.read(chatProvider.notifier).setQuote(t),
                  onEdit: onEditDraft,
                ),
                AssistantTranscriptItem() => _AssistantTurnView(
                  item: item,
                  onQuote: (t) => ref.read(chatProvider.notifier).setQuote(t),
                ),
              },
            ),
          ),
        );
      },
    );
  }
}

({String? quote, String body}) _splitQuote(String raw) {
  final lines = raw.split('\n');
  final quoteLines = <String>[];
  var i = 0;
  while (i < lines.length && lines[i].startsWith('>')) {
    quoteLines.add(lines[i].replaceFirst(RegExp(r'^>\s?'), ''));
    i++;
  }
  if (quoteLines.isEmpty) return (quote: null, body: raw);
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  return (quote: quoteLines.join('\n').trim(), body: lines.sublist(i).join('\n'));
}

/// Right-aligned soft tinted bubble mirroring DSH Go's UserBubble.
class _UserBubble extends ConsumerWidget {
  const _UserBubble({
    required this.item,
    required this.onQuote,
    required this.onEdit,
  });

  final UserTranscriptItem item;
  final ValueChanged<String> onQuote;
  final ValueChanged<String> onEdit;

  Future<void> _openMenu(BuildContext context) async {
    final split = _splitQuote(item.text);
    final action = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader('消息操作'),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: AppIcons.copy,
                  title: '复制',
                  onTap: () => Navigator.of(sheet).pop('copy'),
                ),
                ListPageRow(
                  icon: AppIcons.quote,
                  title: '引用追问',
                  onTap: () => Navigator.of(sheet).pop('quote'),
                ),
                ListPageRow(
                  icon: AppIcons.edit,
                  title: '编辑并重发',
                  onTap: () => Navigator.of(sheet).pop('edit'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: item.text));
        if (context.mounted) showBriefNotice(context, '已复制');
      case 'quote':
        onQuote(split.body.isNotEmpty ? split.body : item.text);
      case 'edit':
        onEdit(split.body.isNotEmpty ? split.body : item.text);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(settingsProvider.select((s) => s.chatTextScale));
    final surfaces = DshSurfaces.of(context);
    final split = _splitQuote(item.text);
    final bodyStyle = AppType.chatBody(
      context,
      scale: scale,
      color: surfaces.onUserBubble,
    );

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.82),
          child: GestureDetector(
            onLongPress: () => _openMenu(context),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: surfaces.userBubble,
                shape: AppShape.bubble,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (split.quote != null && split.quote!.isNotEmpty) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: surfaces.onUserBubble.withValues(
                                alpha: 0.28,
                              ),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            split.quote!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.chatBody(
                              context,
                              scale: scale * 0.88,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      if (split.body.isNotEmpty) const SizedBox(height: 6),
                    ],
                    if (split.body.isNotEmpty)
                      SelectableText(split.body, style: bodyStyle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Editorial assistant reading turn mirroring DSH Go's AssistantMessage + ThinkingPill + ToolRow.
class _AssistantTurnView extends ConsumerStatefulWidget {
  const _AssistantTurnView({required this.item, required this.onQuote});

  final AssistantTranscriptItem item;
  final ValueChanged<String> onQuote;

  @override
  ConsumerState<_AssistantTurnView> createState() => _AssistantTurnViewState();
}

class _AssistantTurnViewState extends ConsumerState<_AssistantTurnView> {
  bool? _processOpen;
  bool _thoughtOpen = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final scheme = theme.colorScheme;
    final scale = ref.watch(settingsProvider.select((s) => s.chatTextScale));
    final foldCompleted = ref.watch(
      settingsProvider.select((s) => s.foldCompletedTurns),
    );
    final isSpeaking = ref.watch(voiceProvider.select((v) => v.isSpeaking));

    final foldedByDefault =
        foldCompleted && !item.isStreaming && item.text.isNotEmpty;
    final processVisible = _processOpen ?? !foldedByDefault;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item.hasActivity) ...[
          if (foldedByDefault)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => setState(() => _processOpen = !processVisible),
                customBorder: const SquircleBorder(
                  borderRadius: AppShape.radiusSm,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.foldTurns,
                        size: 15,
                        color: dsh.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _processSummary(item),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: dsh.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: processVisible ? 0.5 : 0,
                        duration: AppMotion.of(context, AppMotion.quick),
                        child: Icon(
                          AppIcons.expand,
                          size: 14,
                          color: dsh.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ExpandReveal(
            open: processVisible,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item.thought.isNotEmpty)
                  _ThinkingRow(
                    reasoning: item.thought,
                    active: item.isStreaming && item.text.isEmpty,
                    expanded: _thoughtOpen,
                    onToggle: () =>
                        setState(() => _thoughtOpen = !_thoughtOpen),
                  ),
                for (final tc in item.toolCalls) ToolCallCard(toolCall: tc),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
        if (item.text.isNotEmpty) ...[
          SelectionArea(
            child: GptMarkdown(
              item.text,
              style: AppType.chatBody(
                context,
                scale: scale,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (item.isStreaming)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: StreamingCursor(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _ActionIcon(
                    icon: AppIcons.copy,
                    tooltip: '复制',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.text));
                      showBriefNotice(context, '已复制');
                    },
                  ),
                  _ActionIcon(
                    icon: isSpeaking
                        ? AppIcons.stopGenerating
                        : AppIcons.readAloud,
                    tooltip: isSpeaking ? '停止朗读' : '朗读',
                    onTap: () {
                      final v = ref.read(voiceProvider.notifier);
                      if (isSpeaking) {
                        v.stopSpeaking();
                      } else {
                        v.speak(item.text);
                      }
                    },
                  ),
                  _ActionIcon(
                    icon: AppIcons.quote,
                    tooltip: '引用追问',
                    onTap: () => widget.onQuote(item.text),
                  ),
                  _ActionIcon(
                    icon: AppIcons.share,
                    tooltip: '分享与导出',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ShareScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ] else if (item.isStreaming && !item.hasActivity)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StreamingCursor(),
                const SizedBox(width: 8),
                Text(
                  '思考中…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dsh.textTertiary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _processSummary(AssistantTranscriptItem item) {
    final parts = <String>[];
    if (item.thought.isNotEmpty) parts.add('思考过程');
    if (item.toolCalls.isNotEmpty) {
      parts.add('${item.toolCalls.length} 次工具调用');
    }
    return parts.join(' · ');
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow({
    required this.reasoning,
    required this.active,
    required this.expanded,
    required this.onToggle,
  });

  final String reasoning;
  final bool active;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final preview = reasoning
        .trimLeft()
        .split('\n')
        .first
        .replaceAll('**', '')
        .trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onToggle,
            customBorder: const SquircleBorder(borderRadius: AppShape.radiusSm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 22,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: scheme.primary.withValues(
                            alpha: dark ? 0.22 : 0.12,
                          ),
                          shape: Squircle.border(7),
                        ),
                        child: Center(
                          child: active
                              ? SizedBox.square(
                                  dimension: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    color: scheme.primary,
                                  ),
                                )
                              : Icon(
                                  AppIcons.askAi,
                                  size: 13,
                                  color: scheme.primary,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      active ? '思考中' : '思考',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!expanded && preview.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          '·',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppMotion.of(context, AppMotion.quick),
                      child: Icon(
                        AppIcons.expand,
                        size: 14,
                        color: dsh.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ExpandReveal(
          open: expanded || active,
          child: Padding(
            padding: const EdgeInsets.only(left: 11, top: 2, bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Text(
                  reasoning.trim(),
                  maxLines: expanded ? null : 3,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dsh.textTertiary,
                    height: 1.55,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = DshColors.of(context).textTertiary;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox.square(
          dimension: 34,
          child: Icon(icon, size: 16, color: muted),
        ),
      ),
    );
  }
}
