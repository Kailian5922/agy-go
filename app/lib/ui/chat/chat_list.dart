// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

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
import 'diff_and_output_page.dart';
import 'empty_state.dart';
import 'permission_controls.dart';
import 'tool_call_card.dart';
import 'tool_format.dart';

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
      final settings = ref.watch(settingsProvider);
      final activeMode = chat.sessionAgentMode ?? settings.agentMode;
      final activePerm = chat.sessionToolPermission ?? settings.toolPermission;
      final isRisky = activePerm.isHighRisk;
      final isPlan = activeMode == AgyAgentMode.plan;
      final modePillLabel = isPlan
          ? '计划模式 · ${activePerm.label}'
          : activePerm.label;
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
                icon: isRisky
                    ? AppIcons.permissionRisky
                    : isPlan
                    ? AppIcons.planMode
                    : AppIcons.permissions,
                label: modePillLabel,
                accentColor: isRisky
                    ? DshColors.of(context).danger
                    : activePerm == AgyToolPermission.proceedInSandbox
                    ? DshColors.of(context).success
                    : null,
                onTap: () => unawaited(showApprovalModeSheet(context, ref)),
              ),
              SetupItem(
                icon: hosts.active.isLocal
                    ? AppIcons.thisPhone
                    : AppIcons.sshHost,
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

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final split = _splitQuote(item.text);
    final cleanText = split.body.isNotEmpty ? split.body : item.text;
    final action = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MenuTextPreview(text: cleanText, label: '我的消息'),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: AppIcons.copy,
                  title: '复制',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('copy'),
                ),
                ListPageRow(
                  icon: AppIcons.selectText,
                  title: '自由选字',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('select'),
                ),
                ListPageRow(
                  icon: AppIcons.quote,
                  title: '引用追问',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('quote'),
                ),
                ListPageRow(
                  icon: AppIcons.edit,
                  title: '编辑并重发',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('edit'),
                ),
                ListPageRow(
                  icon: AppIcons.fork,
                  title: '从此处分支新对话',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('fork'),
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
      case 'select':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SelectTextPage(text: cleanText),
          ),
        );
      case 'quote':
        onQuote(cleanText);
      case 'edit':
        onEdit(cleanText);
      case 'fork':
        await ref.read(chatProvider.notifier).forkFromText(cleanText);
        if (context.mounted) showBriefNotice(context, '已创建新分支并载入引用上下文');
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
            onLongPress: () => unawaited(_openMenu(context, ref)),
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
                      Text(split.body, style: bodyStyle),
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
  final Set<String> _expandedThoughts = {};

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
    final workspaceCwd =
        ref.watch(chatProvider.select((c) => c.sessionCwd)) ??
        ref.watch(effectiveWorkingDirProvider);

    final timeline = item.effectiveTimeline;
    final trailingMessage =
        timeline.isNotEmpty && timeline.last is MessageTimelineEntry
        ? timeline.last as MessageTimelineEntry
        : null;
    final processEntries = trailingMessage != null
        ? timeline.sublist(0, timeline.length - 1)
        : timeline;
    final hasProcess = processEntries.isNotEmpty;
    final finalReplyText = trailingMessage?.text ?? '';

    final foldedByDefault =
        foldCompleted && !item.isStreaming && finalReplyText.isNotEmpty;
    final processVisible = _processOpen ?? !foldedByDefault;

    final hasActiveTool = item.toolCalls.any((t) => t.status.isActive);
    final thoughtEntries = processEntries
        .whereType<ThoughtTimelineEntry>()
        .toList();
    final lastThoughtId = thoughtEntries.isNotEmpty
        ? thoughtEntries.last.id
        : null;
    final thoughtCount = thoughtEntries.length;

    // Preview compact inline diffs on active edits and the latest 2 live edits
    // so file changes appear immediately underneath thinking steps.
    final livePreviewToolIds = <String>{};
    if (item.isStreaming) {
      final diffTools = [
        for (final tc in item.toolCalls)
          if (tc.effectiveDiffs.isNotEmpty) tc,
      ];
      for (final tc in diffTools) {
        if (tc.status.isActive) livePreviewToolIds.add(tc.toolCallId);
      }
      for (final tc in diffTools.reversed.take(2)) {
        livePreviewToolIds.add(tc.toolCallId);
      }
    }

    final liveFileChanges = _collectLiveFileChanges(
      item.toolCalls,
      workspaceCwd: workspaceCwd,
    );
    final hasActiveThoughtRow =
        item.isStreaming &&
        trailingMessage == null &&
        !hasActiveTool &&
        lastThoughtId != null;

    var thoughtOrdinal = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasProcess) ...[
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
                        _processSummary(item, thoughtCount: thoughtCount),
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
                for (final entry in processEntries)
                  switch (entry) {
                    ThoughtTimelineEntry(:final id, :final text) => () {
                      final ordinal = ++thoughtOrdinal;
                      final isLiveThought =
                          hasActiveThoughtRow && id == lastThoughtId;
                      final isSubThought = ordinal > 1;
                      final isOpen = _expandedThoughts.contains(id);
                      return _ThinkingRow(
                        key: ValueKey(id),
                        reasoning: text,
                        active: isLiveThought,
                        isSubThought: isSubThought,
                        expanded: isOpen,
                        onToggle: () => setState(() {
                          if (!_expandedThoughts.add(id)) {
                            _expandedThoughts.remove(id);
                          }
                        }),
                      );
                    }(),
                    ToolTimelineEntry(:final toolCallId) => () {
                      final tc = item.toolCallById(toolCallId);
                      if (tc == null) return const SizedBox.shrink();
                      return ToolCallCard(
                        key: ValueKey('tc_${tc.toolCallId}'),
                        toolCall: tc,
                        workspaceCwd: workspaceCwd,
                        showLiveDiffPreview: livePreviewToolIds.contains(
                          tc.toolCallId,
                        ),
                      );
                    }(),
                    MessageTimelineEntry(:final id, :final text) => Padding(
                      key: ValueKey(id),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SelectionArea(
                        child: GptMarkdown(
                          text,
                          style: AppType.chatBody(
                            context,
                            scale: scale * 0.94,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  },
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
        if (liveFileChanges.isNotEmpty) ...[
          _LiveFileChangesCard(
            files: liveFileChanges,
            workspaceCwd: workspaceCwd,
          ),
          const SizedBox(height: 8),
        ],
        if (finalReplyText.isNotEmpty) ...[
          SelectionArea(
            child: GptMarkdown(
              finalReplyText,
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
              child: _StreamingRateCursor(),
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
                    icon: AppIcons.regenerate,
                    tooltip: '重新生成',
                    onTap: () => unawaited(
                      ref.read(chatProvider.notifier).regenerateLast(),
                    ),
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
                  _ActionIcon(
                    icon: AppIcons.more,
                    tooltip: '更多操作',
                    onTap: () => unawaited(_openMoreMenu(context, item.text)),
                  ),
                  if (item.metrics != null &&
                      item.metrics!.tokensPerSecond > 0) ...[
                    const Spacer(),
                    _TurnSpeedBadge(metrics: item.metrics!),
                  ],
                ],
              ),
            ),
        ] else if (item.isStreaming)
          _LiveTurnFooter(
            item: item,
            hasActiveTool: hasActiveTool,
            hasActiveThoughtRow: hasActiveThoughtRow,
          ),
      ],
    );
  }

  Future<void> _openMoreMenu(BuildContext context, String text) async {
    final isSpeaking = ref.read(voiceProvider).isSpeaking;
    final action = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MenuTextPreview(text: text, label: 'Antigravity 回复'),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: AppIcons.copy,
                  title: '复制全文',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('copy'),
                ),
                ListPageRow(
                  icon: AppIcons.selectText,
                  title: '自由选字',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('select'),
                ),
                ListPageRow(
                  icon: AppIcons.regenerate,
                  title: '重新生成',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('regen'),
                ),
                ListPageRow(
                  icon: AppIcons.quote,
                  title: '引用追问',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('quote'),
                ),
                ListPageRow(
                  icon: AppIcons.fork,
                  title: '从此处分支新对话',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('fork'),
                ),
                ListPageRow(
                  icon: isSpeaking
                      ? AppIcons.stopGenerating
                      : AppIcons.readAloud,
                  title: isSpeaking ? '停止朗读' : '语音朗读',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('speak'),
                ),
                ListPageRow(
                  icon: AppIcons.share,
                  title: '分享长图 / 导出',
                  chevron: false,
                  onTap: () => Navigator.of(sheet).pop('share'),
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
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) showBriefNotice(context, '已复制');
      case 'select':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SelectTextPage(text: text)),
        );
      case 'regen':
        await ref.read(chatProvider.notifier).regenerateLast();
      case 'quote':
        widget.onQuote(text);
      case 'fork':
        await ref.read(chatProvider.notifier).forkFromText(text);
        if (context.mounted) showBriefNotice(context, '已创建新分支并载入引用上下文');
      case 'speak':
        final v = ref.read(voiceProvider.notifier);
        if (isSpeaking) {
          v.stopSpeaking();
        } else {
          v.speak(text);
        }
      case 'share':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ShareScreen()),
        );
    }
  }

  String _processSummary(AssistantTranscriptItem item, {int thoughtCount = 0}) {
    final parts = <String>[];
    if (thoughtCount > 1) {
      parts.add('$thoughtCount 段思考');
    } else if (item.thought.isNotEmpty) {
      parts.add('思考过程');
    }
    if (item.toolCalls.isNotEmpty) {
      parts.add('${item.toolCalls.length} 次工具调用');
    }
    return parts.join(' · ');
  }
}

class _LiveFileChangeSummary {
  const _LiveFileChangeSummary({
    required this.displayPath,
    required this.rawPath,
    required this.added,
    required this.removed,
    required this.isNew,
    required this.isDeleted,
    required this.isActive,
    required this.diffs,
  });

  final String displayPath;
  final String rawPath;
  final int added;
  final int removed;
  final bool isNew;
  final bool isDeleted;
  final bool isActive;
  final List<DiffEntry> diffs;

  String get fileName {
    final slash = displayPath.lastIndexOf('/');
    return slash < 0 ? displayPath : displayPath.substring(slash + 1);
  }

  String get directory {
    final slash = displayPath.lastIndexOf('/');
    return slash <= 0 ? '' : displayPath.substring(0, slash);
  }
}

List<_LiveFileChangeSummary> _collectLiveFileChanges(
  List<AcpToolCall> toolCalls, {
  String? workspaceCwd,
}) {
  final order = <String>[];
  final acc =
      <
        String,
        ({
          String rawPath,
          int added,
          int removed,
          bool isNew,
          bool isDeleted,
          bool isActive,
          List<DiffEntry> diffs,
        })
      >{};

  for (final tc in toolCalls) {
    if (!tc.modifiesFiles) continue;
    if (tc.status == AcpToolStatus.failed ||
        tc.status == AcpToolStatus.cancelled) {
      continue;
    }

    final diffs = tc.effectiveDiffs;
    final toolTitle = formatToolSummary(
      tc,
      workspaceCwd: workspaceCwd,
      compact: false,
    );
    if (diffs.isNotEmpty) {
      for (final d in diffs) {
        final rawPath = d.path.isNotEmpty
            ? d.path
            : (tc.locations.isNotEmpty ? tc.locations.first.path : tc.title);
        final shown = displayToolPath(rawPath, workspaceCwd: workspaceCwd);
        if (shown.isEmpty) continue;
        final add = countDiffLines(d.newText);
        final del = countDiffLines(d.oldText);
        final entry = DiffEntry(
          path: shown,
          oldText: d.oldText,
          newText: d.newText,
          toolTitle: toolTitle,
        );
        final prev = acc[shown];
        if (prev == null) {
          order.add(shown);
          acc[shown] = (
            rawPath: rawPath,
            added: add,
            removed: del,
            isNew: d.oldText == null,
            isDeleted: tc.kind == AcpToolKind.delete,
            isActive: tc.status.isActive,
            diffs: [entry],
          );
        } else {
          acc[shown] = (
            rawPath: prev.rawPath,
            added: prev.added + add,
            removed: prev.removed + del,
            isNew: prev.isNew,
            isDeleted: tc.kind == AcpToolKind.delete,
            isActive: prev.isActive || tc.status.isActive,
            diffs: [...prev.diffs, entry],
          );
        }
      }
    } else {
      final rawPath = tc.locations.isNotEmpty
          ? tc.locations.first.path
          : tc.title;
      final shown = displayToolPath(rawPath, workspaceCwd: workspaceCwd);
      if (shown.isEmpty) continue;
      final prev = acc[shown];
      if (prev == null) {
        order.add(shown);
        acc[shown] = (
          rawPath: rawPath,
          added: 0,
          removed: 0,
          isNew: false,
          isDeleted: tc.kind == AcpToolKind.delete,
          isActive: tc.status.isActive,
          diffs: const [],
        );
      } else {
        acc[shown] = (
          rawPath: prev.rawPath,
          added: prev.added,
          removed: prev.removed,
          isNew: prev.isNew,
          isDeleted: tc.kind == AcpToolKind.delete,
          isActive: prev.isActive || tc.status.isActive,
          diffs: prev.diffs,
        );
      }
    }
  }

  return [
    for (final key in order)
      _LiveFileChangeSummary(
        displayPath: key,
        rawPath: acc[key]!.rawPath,
        added: acc[key]!.added,
        removed: acc[key]!.removed,
        isNew: acc[key]!.isNew,
        isDeleted: acc[key]!.isDeleted,
        isActive: acc[key]!.isActive,
        diffs: acc[key]!.diffs,
      ),
  ];
}

/// Real-time per-turn File Changes card ("文件变更"), updating live as each file
/// is created/edited/deleted and opening full-screen DiffViewerPage on tap.
class _LiveFileChangesCard extends StatelessWidget {
  const _LiveFileChangesCard({
    required this.files,
    required this.workspaceCwd,
  });

  final List<_LiveFileChangeSummary> files;
  final String? workspaceCwd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dsh = DshColors.of(context);
    final anyActive = files.any((f) => f.isActive);
    final totalAdd = files.fold<int>(0, (s, f) => s + f.added);
    final totalDel = files.fold<int>(0, (s, f) => s + f.removed);
    final allDiffs = [for (final f in files) ...f.diffs];
    final shown = files.take(4).toList();
    final hidden = files.length - shown.length;

    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: AppShape.radiusMd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (anyActive)
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: scheme.primary,
                    ),
                  )
                else
                  Icon(AppIcons.diff, size: 15, color: scheme.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    anyActive
                        ? '正在修改文件 · ${files.length} 个'
                        : '文件变更 · ${files.length} 个文件',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (totalAdd > 0 || totalDel > 0) ...[
                  if (totalAdd > 0)
                    Text(
                      '+$totalAdd',
                      style: AppType.monoLabel(color: dsh.success),
                    ),
                  if (totalAdd > 0 && totalDel > 0) const SizedBox(width: 4),
                  if (totalDel > 0)
                    Text(
                      '−$totalDel',
                      style: AppType.monoLabel(color: dsh.danger),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            for (final f in shown)
              InkWell(
                onTap: f.diffs.isNotEmpty
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DiffViewerPage(
                            entries: f.diffs,
                            title: f.fileName,
                          ),
                        ),
                      )
                    : null,
                onLongPress: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: normalizeToolPath(
                        f.rawPath,
                        baseCwd: workspaceCwd,
                      ),
                    ),
                  );
                  showBriefNotice(context, '已复制路径');
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      if (f.isActive)
                        SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: scheme.primary,
                          ),
                        )
                      else
                        Icon(
                          f.isDeleted
                              ? AppIcons.delete
                              : f.isNew
                              ? AppIcons.add
                              : AppIcons.document,
                          size: 14,
                          color: f.isDeleted
                              ? dsh.danger
                              : f.isNew
                              ? dsh.success
                              : dsh.textTertiary,
                        ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: f.fileName,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (f.isNew)
                                TextSpan(
                                  text: ' 新建',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: dsh.success,
                                  ),
                                ),
                              if (f.isDeleted)
                                TextSpan(
                                  text: ' 删除',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: dsh.danger,
                                  ),
                                ),
                              if (f.directory.isNotEmpty)
                                TextSpan(
                                  text: '  ${f.directory}',
                                  style: AppType.monoLabel(
                                    color: dsh.textTertiary,
                                  ).copyWith(fontSize: 11),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (f.added > 0 || f.removed > 0) ...[
                        const SizedBox(width: 6),
                        if (f.added > 0)
                          Text(
                            '+${f.added}',
                            style: AppType.monoLabel(color: dsh.success),
                          ),
                        if (f.added > 0 && f.removed > 0)
                          const SizedBox(width: 3),
                        if (f.removed > 0)
                          Text(
                            '−${f.removed}',
                            style: AppType.monoLabel(color: dsh.danger),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            if (allDiffs.isNotEmpty && (files.length > 1 || hidden > 0)) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DiffViewerPage(
                      entries: allDiffs,
                      title: '本轮文件变更',
                    ),
                  ),
                ),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        hidden > 0 ? '查看全部改动（还有 $hidden 个文件）' : '查看全部 Diff',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        AppIcons.disclosure,
                        size: 13,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StreamingRateCursor extends ConsumerWidget {
  const _StreamingRateCursor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tps = ref.watch(chatProvider.select((c) => c.liveTokensPerSecond));
    final speedLabel = tps != null && tps > 0
        ? formatTokensPerSecond(tps)
        : null;
    final muted = DshColors.of(context).textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StreamingCursor(),
        if (speedLabel != null) ...[
          const SizedBox(width: 8),
          Text(speedLabel, style: AppType.monoLabel(color: muted)),
        ],
      ],
    );
  }
}

class _TurnSpeedBadge extends StatelessWidget {
  const _TurnSpeedBadge({required this.metrics});

  final AcpTurnMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final muted = DshColors.of(context).textTertiary;
    final label = formatTokensPerSecond(metrics.tokensPerSecond);
    if (label.isEmpty) return const SizedBox.shrink();
    final approxPrefix = metrics.estimated ? '约 ' : '';
    final detail =
        '本轮速度 $label · $approxPrefix${metrics.tokens} tokens · 生成 ${metrics.generationSeconds.toStringAsFixed(1)} 秒';
    return Tooltip(
      message: detail,
      child: InkWell(
        onTap: () => showBriefNotice(context, detail),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            label,
            style: AppType.monoLabel(color: muted),
          ),
        ),
      ),
    );
  }
}

class _LiveTurnFooter extends ConsumerStatefulWidget {
  const _LiveTurnFooter({
    required this.item,
    required this.hasActiveTool,
    required this.hasActiveThoughtRow,
  });

  final AssistantTranscriptItem item;
  final bool hasActiveTool;
  final bool hasActiveThoughtRow;

  @override
  ConsumerState<_LiveTurnFooter> createState() => _LiveTurnFooterState();
}

class _LiveTurnFooterState extends ConsumerState<_LiveTurnFooter> {
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

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(
      chatProvider.select(
        (c) => (
          isBusy: c.isBusy,
          startedAt: c.turnStartedAt,
          lastActivityAt: c.lastActivityAt,
          livePhase: c.livePhase,
          liveStatusLabel: c.liveStatusLabel,
          activeRetry: c.activeRetry,
          thoughtChars: c.thoughtChars,
          answerChars: c.answerChars,
          liveTokensPerSecond: c.liveTokensPerSecond,
        ),
      ),
    );
    if (!live.isBusy) return const SizedBox.shrink();
    // When a tool card is visibly running and no retry is active, avoid duplicating it.
    if (widget.hasActiveTool && live.activeRetry == null) {
      return const SizedBox.shrink();
    }

    final health = deriveTurnHealth(
      startedAt: live.startedAt,
      lastActivityAt: live.lastActivityAt,
      phase: live.livePhase,
      activeRetry: live.activeRetry,
      thoughtChars: live.thoughtChars,
      answerChars: live.answerChars,
      hasActiveTool: widget.hasActiveTool,
      activeToolLabel: null,
      liveStatusLabel: live.liveStatusLabel,
      activePlanLabel: null,
      now: _now,
      liveTokensPerSecond: live.liveTokensPerSecond,
      inline: false,
    );

    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final isWarn =
        health.tone == TurnHealthTone.retrying ||
        health.tone == TurnHealthTone.suspectedStall;
    final speedTag =
        live.liveTokensPerSecond != null && live.liveTokensPerSecond! > 0
        ? ' · ${formatTokensPerSecond(live.liveTokensPerSecond!)}'
        : '';

    // Avoid duplicating the active thinking spinner row unless we have live
    // tok/s throughput, a phase change (analyzing/working), or a warning.
    if (widget.hasActiveThoughtRow &&
        !isWarn &&
        health.tone == TurnHealthTone.active &&
        live.livePhase == TurnLivePhase.thinking &&
        speedTag.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasTools = widget.item.toolCalls.isNotEmpty;
    final showText = switch (health.tone) {
      TurnHealthTone.retrying => health.detailHeadline,
      TurnHealthTone.suspectedStall => health.detailHeadline,
      TurnHealthTone.waiting => health.detailHeadline,
      TurnHealthTone.active => switch (live.livePhase) {
        TurnLivePhase.analyzing =>
          live.liveStatusLabel?.trim().isNotEmpty == true
              ? '分析中 · ${live.liveStatusLabel!.trim()}'
              : '正在分析文件与工具结果…',
        TurnLivePhase.working =>
          live.liveStatusLabel?.trim().isNotEmpty == true
              ? 'Working · ${live.liveStatusLabel!.trim()}'
              : 'Working…',
        TurnLivePhase.thinking =>
          hasTools
              ? (live.thoughtChars > 0
                    ? '继续思考中$speedTag · ${formatCharCount(live.thoughtChars)}（${formatLastSignalAge(health.silentSeconds)}更新）'
                    : '分析工具结果中…')
              : (live.thoughtChars > 0
                    ? '思考中$speedTag · ${formatCharCount(live.thoughtChars)}'
                    : '思考中…'),
        _ => hasTools ? '分析工具结果中…' : 'Working…',
      },
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isWarn)
            Icon(
              health.tone == TurnHealthTone.retrying
                  ? AppIcons.retry
                  : AppIcons.warning,
              size: 14,
              color: dsh.warning,
            )
          else
            const StreamingCursor(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              showText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isWarn ? dsh.warning : dsh.textTertiary,
                fontWeight: isWarn ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow({
    super.key,
    required this.reasoning,
    required this.active,
    required this.expanded,
    required this.onToggle,
    this.isSubThought = false,
  });

  final String reasoning;
  final bool active;
  final bool expanded;
  final VoidCallback onToggle;
  final bool isSubThought;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final preview = active
        ? latestThoughtHeadline(reasoning)
        : reasoning
              .trimLeft()
              .split('\n')
              .first
              .replaceAll('**', '')
              .trim();
    final bodyText = expanded
        ? reasoning.trim()
        : (active ? tailPreviewLines(reasoning, maxLines: 3) : reasoning.trim());
    final charTag = reasoning.trim().isNotEmpty
        ? formatCharCount(reasoning.trim().length)
        : null;
    final title = active
        ? (isSubThought ? '小思考中' : '思考中')
        : (isSubThought ? '小思考' : '思考');
    final badgeDim = isSubThought ? 18.0 : 22.0;

    return Padding(
      padding: EdgeInsets.only(left: isSubThought ? 10 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onToggle,
              customBorder: const SquircleBorder(
                borderRadius: AppShape.radiusSm,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: isSubThought ? 30 : 34),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: badgeDim,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: scheme.primary.withValues(
                              alpha: isSubThought
                                  ? (dark ? 0.16 : 0.09)
                                  : (dark ? 0.22 : 0.12),
                            ),
                            shape: Squircle.border(isSubThought ? 6 : 7),
                          ),
                          child: Center(
                            child: active
                                ? SizedBox.square(
                                    dimension: isSubThought ? 9 : 11,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      color: scheme.primary,
                                    ),
                                  )
                                : Icon(
                                    AppIcons.askAi,
                                    size: isSubThought ? 11 : 13,
                                    color: scheme.primary,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isSubThought
                              ? dsh.textTertiary
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (active && charTag != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          charTag,
                          style: AppType.monoLabel(color: scheme.primary),
                        ),
                      ],
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
            padding: EdgeInsets.only(
              left: isSubThought ? 9 : 11,
              top: 2,
              bottom: 8,
            ),
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
                  bodyText,
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
      ),
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
