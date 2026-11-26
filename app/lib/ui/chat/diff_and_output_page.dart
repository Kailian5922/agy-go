// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/hosts_state.dart';
import '../../state/runtime_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';
import 'tool_format.dart';

/// Concise preview header strip for message action sheets (mirroring DSH Go's MenuTextPreview).
class MenuTextPreview extends StatelessWidget {
  const MenuTextPreview({
    super.key,
    required this.text,
    this.label = '消息内容',
  });

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: dsh.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            singleLine.isEmpty ? '（空内容）' : singleLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen free text selection page (自由选字), mirroring DSH Go's SelectTextPage.
class SelectTextPage extends StatelessWidget {
  const SelectTextPage({
    super.key,
    required this.text,
    this.title = '自由选字',
  });

  final String text;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPage.list(
      title: title,
      subtitle: const Text('长按或拖动可自由选择局部片段复制'),
      actions: [
        GlassIconButton(
          icon: AppIcons.copy,
          tooltip: '复制全文',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            showBriefNotice(context, '已复制全部文字');
          },
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: GlassSurface(
            tier: GlassTier.card,
            borderRadius: AppShape.radiusLg,
            padding: const EdgeInsets.all(18),
            child: SelectableText(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16.5,
                height: 1.7,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen monospace output viewer with line-wrap toggle and copy button.
class OutputViewerPage extends StatefulWidget {
  const OutputViewerPage({
    super.key,
    required this.title,
    required this.output,
    this.subtitle,
  });

  final String title;
  final String output;
  final String? subtitle;

  @override
  State<OutputViewerPage> createState() => _OutputViewerPageState();
}

class _OutputViewerPageState extends State<OutputViewerPage> {
  bool _wrap = true;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final code = SelectableText(
      widget.output.isEmpty ? '（无输出内容）' : widget.output,
      style: AppType.monoSmall(color: dsh.codeWellFg).copyWith(
        fontSize: 12.5,
        height: 1.55,
      ),
    );

    return AppPage.list(
      title: widget.title,
      subtitle: widget.subtitle != null ? Text(widget.subtitle!) : null,
      actions: [
        GlassIconButton(
          icon: AppIcons.wrapLines,
          tooltip: _wrap ? '关闭自动换行' : '开启自动换行',
          onPressed: () => setState(() => _wrap = !_wrap),
        ),
        GlassIconButton(
          icon: AppIcons.copy,
          tooltip: '复制输出',
          onPressed: widget.output.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: widget.output));
                  showBriefNotice(context, '已复制输出');
                },
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: dsh.codeWellBg,
              shape: AppShape.outlined(dsh.codeWellBorder, radius: 16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _wrap
                  ? code
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: code,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A collected file diff item shown in [DiffViewerPage].
class DiffEntry {
  const DiffEntry({
    required this.path,
    required this.newText,
    this.oldText,
    this.toolTitle,
  });

  final String path;
  final String? oldText;
  final String newText;
  final String? toolTitle;

  int get addedLines => newText.isEmpty ? 0 : newText.split('\n').length;
  int get removedLines =>
      (oldText == null || oldText!.isEmpty) ? 0 : oldText!.split('\n').length;

  String toUnifiedText() {
    final buf = StringBuffer()
      ..writeln('--- a/$path')
      ..writeln('+++ b/$path');
    if (oldText != null && oldText!.isNotEmpty) {
      for (final l in oldText!.split('\n')) {
        buf.writeln('-$l');
      }
    }
    if (newText.isNotEmpty) {
      for (final l in newText.split('\n')) {
        buf.writeln('+$l');
      }
    }
    return buf.toString();
  }
}

/// Collects all [DiffEntry] records produced by tool calls in [transcript].
List<DiffEntry> collectTranscriptDiffs(
  ChatTranscript transcript, {
  String? workspaceCwd,
}) {
  final out = <DiffEntry>[];
  for (final item in transcript.items) {
    if (item is! AssistantTranscriptItem) continue;
    for (final tc in item.toolCalls) {
      for (final block in tc.content) {
        if (block case AcpDiffToolContent(
          :final path,
          :final oldText,
          :final newText,
        )) {
          out.add(
            DiffEntry(
              path: displayToolPath(path, workspaceCwd: workspaceCwd),
              oldText: oldText,
              newText: newText,
              toolTitle: formatToolSummary(
                tc,
                workspaceCwd: workspaceCwd,
                compact: false,
              ),
            ),
          );
        }
      }
    }
  }
  return out;
}

/// Full-screen file Diff viewer (`/diff` or per-tool diff expansion).
class DiffViewerPage extends StatefulWidget {
  const DiffViewerPage({
    super.key,
    required this.entries,
    this.title = '变更 Diff',
  });

  factory DiffViewerPage.fromToolCall(
    AcpToolCall tc, {
    String? workspaceCwd,
  }) {
    final entries = <DiffEntry>[
      for (final block in tc.content)
        if (block case AcpDiffToolContent(
          :final path,
          :final oldText,
          :final newText,
        ))
          DiffEntry(
            path: displayToolPath(path, workspaceCwd: workspaceCwd),
            oldText: oldText,
            newText: newText,
            toolTitle: formatToolSummary(
              tc,
              workspaceCwd: workspaceCwd,
              compact: false,
            ),
          ),
    ];
    final cleanTitle = formatToolSummary(
      tc,
      workspaceCwd: workspaceCwd,
      compact: false,
    );
    return DiffViewerPage(
      entries: entries,
      title: cleanTitle.isNotEmpty ? cleanTitle : '文件变更',
    );
  }

  factory DiffViewerPage.fromTranscript(
    ChatTranscript transcript, {
    String? workspaceCwd,
  }) {
    return DiffViewerPage(
      entries: collectTranscriptDiffs(transcript, workspaceCwd: workspaceCwd),
      title: '本对话变更 Diff',
    );
  }

  final List<DiffEntry> entries;
  final String title;

  @override
  State<DiffViewerPage> createState() => _DiffViewerPageState();
}

class _DiffViewerPageState extends State<DiffViewerPage> {
  bool _wrap = false;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final totalAdd = widget.entries.fold<int>(0, (s, e) => s + e.addedLines);
    final totalDel = widget.entries.fold<int>(0, (s, e) => s + e.removedLines);

    return AppPage.list(
      title: widget.title,
      subtitle: widget.entries.isEmpty
          ? const Text('当前对话暂未记录文件 Diff')
          : Text(
              '${widget.entries.length} 处文件变更  +$totalAdd / −$totalDel',
              style: AppType.monoLabel(color: dsh.textTertiary),
            ),
      actions: [
        GlassIconButton(
          icon: AppIcons.wrapLines,
          tooltip: _wrap ? '关闭自动换行' : '开启自动换行',
          onPressed: () => setState(() => _wrap = !_wrap),
        ),
        GlassIconButton(
          icon: AppIcons.copy,
          tooltip: '复制全部 Diff',
          onPressed: widget.entries.isEmpty
              ? null
              : () {
                  final text = widget.entries
                      .map((e) => e.toUnifiedText())
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  showBriefNotice(context, '已复制 Diff 文本');
                },
        ),
      ],
      children: [
        if (widget.entries.isEmpty)
          const EmptyView(
            icon: AppIcons.diff,
            title: '还没有文件变更',
            message: '当 Antigravity 修改或创建工作区文件时，所有差异会自动汇总到这里。',
          )
        else
          for (final entry in widget.entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _FullDiffCard(entry: entry, wrap: _wrap),
            ),
      ],
    );
  }
}

class _FullDiffCard extends StatelessWidget {
  const _FullDiffCard({required this.entry, required this.wrap});

  final DiffEntry entry;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final oldLines = (entry.oldText == null || entry.oldText!.isEmpty)
        ? const <String>[]
        : entry.oldText!.split('\n');
    final newLines = entry.newText.isEmpty
        ? const <String>[]
        : entry.newText.split('\n');

    final minWidth = (MediaQuery.sizeOf(context).width - 32).clamp(240.0, 4096.0);

    Widget buildLine({
      required int lineNumber,
      required String prefix,
      required String text,
      required Color bg,
      required Color fg,
    }) {
      final row = Row(
        mainAxisSize: wrap ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: AppType.monoSmall(
                color: fg.withValues(alpha: 0.55),
              ).copyWith(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            prefix,
            style: AppType.monoSmall(
              color: fg,
            ).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          if (wrap)
            Expanded(
              child: SelectableText(
                text,
                style: AppType.monoSmall(
                  color: fg,
                ).copyWith(fontSize: 12, height: 1.45),
              ),
            )
          else
            SelectableText(
              text,
              style: AppType.monoSmall(
                color: fg,
              ).copyWith(fontSize: 12, height: 1.45),
            ),
        ],
      );
      return Container(
        constraints: wrap ? null : BoxConstraints(minWidth: minWidth),
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: row,
      );
    }

    Widget diffLines() => Column(
      crossAxisAlignment:
          wrap ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        for (final (i, line) in oldLines.indexed)
          buildLine(
            lineNumber: i + 1,
            prefix: '-',
            text: line,
            bg: dsh.diffDelBg,
            fg: dsh.diffDelFg,
          ),
        for (final (i, line) in newLines.indexed)
          buildLine(
            lineNumber: i + 1,
            prefix: '+',
            text: line,
            bg: dsh.diffAddBg,
            fg: dsh.diffAddFg,
          ),
      ],
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: dsh.codeWellBg,
        shape: AppShape.outlined(dsh.codeWellBorder, radius: 16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              color: scheme.onSurface.withValues(alpha: 0.04),
              child: Row(
                children: [
                  Icon(AppIcons.diff, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.monoLabel(
                        color: scheme.onSurface,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (entry.addedLines > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '+${entry.addedLines}',
                      style: AppType.monoLabel(color: dsh.success),
                    ),
                  ],
                  if (entry.removedLines > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '−${entry.removedLines}',
                      style: AppType.monoLabel(color: dsh.danger),
                    ),
                  ],
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: entry.toUnifiedText()),
                      );
                      showBriefNotice(context, '已复制 ${entry.path} 的 Diff');
                    },
                    child: Icon(
                      AppIcons.copy,
                      size: 15,
                      color: dsh.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (wrap)
              diffLines()
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: diffLines(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Context & Token Usage sheet (`/context`, `/usage`) with 1-tap `/compact`.
Future<void> showContextUsageSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => const _ContextUsageSheetBody(),
  );
}

class _ContextUsageSheetBody extends ConsumerWidget {
  const _ContextUsageSheetBody();

  String _fmtTokens(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final hosts = ref.watch(hostsProvider);
    final runtime = ref.watch(localRuntimeProvider).status;
    final usage = chat.transcript.usage;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dsh = DshColors.of(context);

    final used = usage?.usedTokens ?? 0;
    final limit = usage?.sizeTokens ?? 0;
    final ratio = limit > 0 ? (used / limit).clamp(0.0, 1.0) : null;
    final toolCount = chat.transcript.items
        .whereType<AssistantTranscriptItem>()
        .fold<int>(0, (s, item) => s + item.toolCalls.length);
    final diffCount = collectTranscriptDiffs(chat.transcript).length;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader('上下文与用量'),
            if (ratio != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '上下文窗口占用',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
                        Text(
                          '${_fmtTokens(used)} / ${_fmtTokens(limit)} (${(ratio * 100).round()}%)',
                          style: AppType.monoLabel(
                            color: ratio > 0.85
                                ? dsh.danger
                                : ratio > 0.65
                                ? dsh.warning
                                : scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: scheme.onSurface.withValues(
                          alpha: 0.08,
                        ),
                        color: ratio > 0.85
                            ? dsh.danger
                            : ratio > 0.65
                            ? dsh.warning
                            : scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            SheetGroup(
              title: '会话统计',
              children: [
                InfoRow(
                  label: '消息 / 工具调用',
                  value: '${chat.transcript.items.length} 条 · $toolCount 次工具',
                ),
                if (usage?.usedTokens != null)
                  InfoRow(
                    label: '已用 Token',
                    value: '${usage!.usedTokens}',
                    mono: true,
                  ),
                if (usage?.sizeTokens != null)
                  InfoRow(
                    label: '窗口上限',
                    value: '${usage!.sizeTokens}',
                    mono: true,
                  ),
                if (usage?.costAmount != null)
                  InfoRow(
                    label: '估算费用',
                    value:
                        '${usage!.costAmount!.toStringAsFixed(4)} ${usage.costCurrency ?? ''}'
                            .trim(),
                    mono: true,
                  ),
                InfoRow(
                  label: '工作区目录',
                  value: displayWorkspacePath(
                    chat.sessionCwd ?? ref.read(effectiveWorkingDirProvider),
                    local: hosts.active.isLocal,
                    homePath: runtime.homePath,
                    storageRoot: runtime.phoneStoragePath,
                  ),
                  mono: true,
                ),
                if (chat.additionalDirectories.isNotEmpty)
                  InfoRow(
                    label: '额外挂载目录',
                    value: '${chat.additionalDirectories.length} 个',
                  ),
              ],
            ),
            SheetGroup(
              title: '快捷操作',
              children: [
                ListPageRow(
                  icon: AppIcons.compact,
                  title: '立即压缩上下文 (/compact)',
                  subtitle: '让 Antigravity 总结前文以释放上下文空间',
                  onTap: chat.sessionId == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          unawaited(
                            ref.read(chatProvider.notifier).send('/compact'),
                          );
                        },
                ),
                if (diffCount > 0)
                  ListPageRow(
                    icon: AppIcons.diff,
                    title: '查看本对话变更 Diff',
                    value: '$diffCount 处',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DiffViewerPage.fromTranscript(
                            chat.transcript,
                          ),
                        ),
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
