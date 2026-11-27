// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:convert';

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../common/brief_notice.dart';
import '../common/expand_reveal.dart';
import '../theme/theme.dart';
import 'diff_and_output_page.dart';
import 'tool_format.dart';

/// 32dp single-line tool call row mirroring DSH Go's ToolRow, expanding
/// smoothly into a JetBrains Mono code/diff well, with optional live inline
/// diff preview for real-time file edits.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({
    super.key,
    required this.toolCall,
    this.workspaceCwd,
    this.showLiveDiffPreview = false,
  });

  final AcpToolCall toolCall;

  /// Active session / workspace working directory used to shorten file paths.
  final String? workspaceCwd;

  /// When true, renders a compact 4-line inline diff snippet underneath the
  /// row while the edit is live so file changes are immediately visible.
  final bool showLiveDiffPreview;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  String _verb(AcpToolKind kind) => switch (kind) {
    AcpToolKind.read => '读取',
    AcpToolKind.edit => '编辑',
    AcpToolKind.delete => '删除',
    AcpToolKind.move => '移动',
    AcpToolKind.search => '搜索',
    AcpToolKind.execute => '运行',
    AcpToolKind.fetch => '抓取',
    AcpToolKind.think => '思考',
    _ => '工具',
  };

  IconData _icon(AcpToolKind kind) => switch (kind) {
    AcpToolKind.read => AppIcons.document,
    AcpToolKind.edit => AppIcons.edit,
    AcpToolKind.delete => AppIcons.delete,
    AcpToolKind.move => AppIcons.moved,
    AcpToolKind.search => AppIcons.search,
    AcpToolKind.execute => AppIcons.terminal,
    AcpToolKind.fetch => AppIcons.web,
    AcpToolKind.think => AppIcons.askAi,
    _ => AppIcons.tool,
  };

  int _tint(AcpToolKind kind) => switch (kind) {
    AcpToolKind.read => 0,
    AcpToolKind.edit => 4,
    AcpToolKind.delete => 3,
    AcpToolKind.execute => 5,
    AcpToolKind.search => 1,
    AcpToolKind.fetch => 2,
    _ => 6,
  };

  (int added, int removed)? _diffCounts(List<AcpDiffToolContent> diffs) {
    if (diffs.isEmpty) return null;
    var added = 0;
    var removed = 0;
    for (final c in diffs) {
      removed += countDiffLines(c.oldText);
      added += countDiffLines(c.newText);
    }
    return (added, removed);
  }

  String _formatBlockOutput(AcpToolCall tc, String raw) {
    final cleaned = tc.kind == AcpToolKind.execute
        ? stripAgyCommandResultHeader(raw)
        : raw.trim();
    return cleaned;
  }

  String? _rawOutputText(AcpToolCall tc) {
    final raw = tc.rawOutput;
    if (raw == null) return null;
    if (raw is String) {
      final trimmed = _formatBlockOutput(tc, raw);
      return trimmed.isEmpty ? null : trimmed;
    }
    if (raw is Map) {
      for (final key in const ['output', 'stdout', 'text', 'message', 'error']) {
        final v = raw[key];
        if (v is String) {
          final trimmed = _formatBlockOutput(tc, v);
          if (trimmed.isNotEmpty) return trimmed;
        }
      }
    }
    return null;
  }

  String _contentBlockToPlainText(AcpToolCall tc, AcpContentBlock block) =>
      switch (block) {
        AcpTextBlock(:final text) => _formatBlockOutput(tc, text),
        AcpImageBlock(:final mimeType, :final uri) =>
          (uri != null && uri.isNotEmpty)
              ? '[图片 ($mimeType): $uri]'
              : '[图片: $mimeType]',
        AcpResourceLinkBlock(:final uri, :final name, :final title) =>
          '[资源: ${(title != null && title.isNotEmpty) ? title : name}] $uri',
      };

  Widget _buildContentBlockWidget(
    AcpToolCall tc,
    AcpContentBlock block,
    DshColors dsh,
    ColorScheme scheme,
  ) {
    switch (block) {
      case AcpTextBlock(:final text):
        return SelectableText(
          _formatBlockOutput(tc, text),
          style: AppType.monoSmall(color: dsh.codeWellFg),
        );
      case AcpImageBlock(:final data, :final mimeType):
        if (data.isNotEmpty) {
          try {
            final bytes = base64Decode(data);
            if (bytes.isNotEmpty) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, st) => Text(
                      '[图片: $mimeType]',
                      style: AppType.monoLabel(color: dsh.textTertiary),
                    ),
                  ),
                ),
              );
            }
          } catch (_) {
            // Malformed base64 payload: fall through to clean placeholder.
          }
        }
        return Text(
          '[图片: $mimeType]',
          style: AppType.monoLabel(color: dsh.textTertiary),
        );
      case AcpResourceLinkBlock(:final uri, :final name, :final title):
        final heading = (title != null && title.isNotEmpty) ? title : name;
        final text = heading == uri ? uri : '$heading\n$uri';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(AppIcons.link, size: 13, color: scheme.primary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                text,
                style: AppType.monoSmall(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.toolCall;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final cwd = widget.workspaceCwd;

    final diffs = tc.effectiveDiffs;
    final nonDiffBlocks = [
      for (final b in tc.content)
        if (b is! AcpDiffToolContent) b,
    ];
    final fallbackOutput = nonDiffBlocks.isEmpty ? _rawOutputText(tc) : null;
    final inputDetails = formatToolInputDetails(tc, workspaceCwd: cwd);
    final hasDetails =
        diffs.isNotEmpty ||
        nonDiffBlocks.isNotEmpty ||
        tc.locations.isNotEmpty ||
        fallbackOutput != null ||
        inputDetails != null;
    final hasTextOutput =
        nonDiffBlocks.any(
          (b) => b is AcpBlockToolContent && b.block is! AcpImageBlock,
        ) ||
        fallbackOutput != null;
    final nativeLabel = extractNativeToolLabel(tc, workspaceCwd: cwd);
    final summary = formatToolSummary(tc, workspaceCwd: cwd);
    final showSecondarySummary =
        nativeLabel != null &&
        summary.isNotEmpty &&
        !nativeLabel.toLowerCase().contains(summary.toLowerCase()) &&
        !summary.toLowerCase().contains(nativeLabel.toLowerCase());
    final tintIdx = _tint(tc.kind);
    final badgeBg = dsh.identity[tintIdx % dsh.identity.length];
    final badgeFg = dsh.onIdentity[tintIdx % dsh.onIdentity.length];
    final counts = _diffCounts(diffs);
    final failed = tc.status == AcpToolStatus.failed;
    final summaryColor = failed ? dsh.danger : dsh.textTertiary;

    Widget buildDiffCountsBadge((int, int) c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.$1 > 0 || c.$2 == 0)
          Text('+${c.$1}', style: AppType.monoLabel(color: dsh.success)),
        if (c.$1 > 0 && c.$2 > 0) const SizedBox(width: 4),
        if (c.$2 > 0)
          Text('−${c.$2}', style: AppType.monoLabel(color: dsh.danger)),
      ],
    );

    // Show live +N/-M counts immediately (even while in_progress!) alongside
    // the spinner so real-time file changes are unmistakable at a glance.
    final Widget? statusWidget = switch (tc.status) {
      AcpToolStatus.inProgress => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (counts != null) ...[
            buildDiffCountsBadge(counts),
            const SizedBox(width: 6),
          ],
          SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.7,
              color: scheme.primary,
            ),
          ),
        ],
      ),
      AcpToolStatus.paused => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (counts != null) ...[
            buildDiffCountsBadge(counts),
            const SizedBox(width: 6),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: ShapeDecoration(
              color: dsh.warning.withValues(alpha: 0.14),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.approval, size: 11, color: dsh.warning),
                const SizedBox(width: 3),
                Text(
                  '待确认',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: dsh.warning,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      AcpToolStatus.completed when counts != null => buildDiffCountsBadge(counts),
      AcpToolStatus.completed => null,
      AcpToolStatus.failed => Icon(
        AppIcons.failed,
        size: 14,
        color: dsh.danger,
      ),
      AcpToolStatus.cancelled => Icon(
        AppIcons.stopped,
        size: 14,
        color: dsh.textTertiary,
      ),
      _ => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (counts != null) ...[
            buildDiffCountsBadge(counts),
            const SizedBox(width: 6),
          ],
          Icon(AppIcons.waiting, size: 14, color: dsh.warning),
        ],
      ),
    };

    final isMonoSummary =
        tc.kind == AcpToolKind.execute ||
        tc.kind == AcpToolKind.read ||
        tc.kind == AcpToolKind.edit ||
        tc.kind == AcpToolKind.delete ||
        tc.kind == AcpToolKind.move ||
        tc.kind == AcpToolKind.search;

    final showCompactLiveDiff =
        widget.showLiveDiffPreview && !_expanded && diffs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: hasDetails
                ? () => setState(() => _expanded = !_expanded)
                : null,
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
                          color: badgeBg.withValues(alpha: dark ? 0.55 : 0.85),
                          shape: Squircle.border(7),
                        ),
                        child: Icon(_icon(tc.kind), size: 13, color: badgeFg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (nativeLabel != null && !showSecondarySummary)
                      Expanded(
                        child: Text(
                          nativeLabel,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: failed
                                ? dsh.danger
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (nativeLabel != null) ...[
                      Flexible(
                        child: Text(
                          nativeLabel,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: failed
                                ? dsh.danger
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
                          summary,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: isMonoSummary
                              ? AppType.monoLabel(
                                  color: summaryColor,
                                ).copyWith(fontSize: 12.5)
                              : theme.textTheme.bodySmall?.copyWith(
                                  color: summaryColor,
                                ),
                        ),
                      ),
                    ]
                    else ...[
                      Text(
                        _verb(tc.kind),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                          summary,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: isMonoSummary
                              ? AppType.monoLabel(color: summaryColor)
                                    .copyWith(fontSize: 12.5)
                              : theme.textTheme.bodySmall?.copyWith(
                                  color: summaryColor,
                                ),
                        ),
                      ),
                    ],
                    if (statusWidget != null) ...[
                      const SizedBox(width: 8),
                      statusWidget,
                    ],
                    if (hasDetails && _expanded) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: 0.5,
                        duration: AppMotion.of(context, AppMotion.quick),
                        child: Icon(
                          AppIcons.expand,
                          size: 14,
                          color: dsh.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showCompactLiveDiff)
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 2, bottom: 6),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: dsh.codeWellBg,
                  shape: AppShape.outlined(dsh.codeWellBorder, radius: 10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: _CompactLiveDiffPreview(diff: diffs.first),
                ),
              ),
            ),
          ),
        ExpandReveal(
          open: _expanded && hasDetails,
          child: Padding(
            padding: const EdgeInsets.only(left: 30, top: 4, bottom: 8),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: dsh.codeWellBg,
                shape: AppShape.outlined(dsh.codeWellBorder, radius: 12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final loc in tc.locations)
                      Builder(
                        builder: (_) {
                          final shownLoc = displayToolPath(
                            loc.path,
                            workspaceCwd: cwd,
                          );
                          final copyPath = normalizeToolPath(
                            loc.path,
                            baseCwd: cwd,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    loc.line != null
                                        ? '$shownLoc:${loc.line}'
                                        : shownLoc,
                                    style: AppType.monoLabel(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: copyPath),
                                    );
                                    showBriefNotice(context, '已复制路径');
                                  },
                                  child: Icon(
                                    AppIcons.copy,
                                    size: 14,
                                    color: dsh.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (inputDetails != null)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              (diffs.isNotEmpty ||
                                  nonDiffBlocks.isNotEmpty ||
                                  fallbackOutput != null)
                              ? 6
                              : 0,
                        ),
                        child: SelectableText(
                          inputDetails,
                          style: AppType.monoSmall(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final diff in diffs)
                      _DiffWell(
                        path: displayToolPath(
                          diff.path.isNotEmpty ? diff.path : summary,
                          workspaceCwd: cwd,
                        ),
                        oldText: diff.oldText,
                        newText: diff.newText,
                      ),
                    for (final block in nonDiffBlocks)
                      switch (block) {
                        AcpBlockToolContent(:final block) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _buildContentBlockWidget(
                            tc,
                            block,
                            dsh,
                            scheme,
                          ),
                        ),
                        AcpTerminalToolContent(:final terminalId) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '终端会话 #$terminalId',
                            style: AppType.monoLabel(color: dsh.textTertiary),
                          ),
                        ),
                        AcpDiffToolContent() => const SizedBox.shrink(),
                      },
                    if (fallbackOutput != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(
                          fallbackOutput,
                          style: AppType.monoSmall(color: dsh.codeWellFg),
                        ),
                      ),
                    if (counts != null || hasTextOutput) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (counts != null)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(AppIcons.diff, size: 14),
                              label: const Text('全屏 Diff'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DiffViewerPage.fromToolCall(
                                    tc,
                                    workspaceCwd: cwd,
                                  ),
                                ),
                              ),
                            ),
                          if (hasTextOutput)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(AppIcons.openExternal, size: 14),
                              label: const Text('完整输出'),
                              onPressed: () {
                                final fullText = nonDiffBlocks.isNotEmpty
                                    ? nonDiffBlocks
                                          .whereType<AcpBlockToolContent>()
                                          .map(
                                            (b) => _contentBlockToPlainText(
                                              tc,
                                              b.block,
                                            ),
                                          )
                                          .where((s) => s.isNotEmpty)
                                          .join('\n\n')
                                    : (fallbackOutput ?? '');
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => OutputViewerPage(
                                      title:
                                          nativeLabel ??
                                          formatToolSummary(
                                            tc,
                                            workspaceCwd: cwd,
                                            compact: false,
                                          ),
                                      subtitle: tc.locations.isNotEmpty
                                          ? displayToolPath(
                                              tc.locations.first.path,
                                              workspaceCwd: cwd,
                                            )
                                          : formatToolSummary(
                                              tc,
                                              workspaceCwd: cwd,
                                              compact: false,
                                            ),
                                      output: fullText,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactLiveDiffPreview extends StatelessWidget {
  const _CompactLiveDiffPreview({required this.diff});

  final AcpDiffToolContent diff;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final oldLines = (diff.oldText ?? '').isEmpty
        ? const <String>[]
        : diff.oldText!.split('\n');
    final newLines = diff.newText.isEmpty
        ? const <String>[]
        : diff.newText.split('\n');
    final delPreview = oldLines.take(2).toList();
    final addPreview = newLines.take(3).toList();
    final remaining =
        (oldLines.length - delPreview.length) +
        (newLines.length - addPreview.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in delPreview)
          Container(
            color: dsh.diffDelBg,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Text(
              '- $line',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.monoSmall(
                color: dsh.diffDelFg,
              ).copyWith(fontSize: 11),
            ),
          ),
        for (final line in addPreview)
          Container(
            color: dsh.diffAddBg,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Text(
              '+ $line',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.monoSmall(
                color: dsh.diffAddFg,
              ).copyWith(fontSize: 11),
            ),
          ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '… 还有 $remaining 行改动，点击展开',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: dsh.textTertiary,
                fontSize: 10.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _DiffWell extends StatelessWidget {
  const _DiffWell({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  final String path;
  final String? oldText;
  final String newText;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final oldLines = (oldText ?? '').isEmpty
        ? const <String>[]
        : oldText!.split('\n');
    final newLines = newText.isEmpty ? const <String>[] : newText.split('\n');

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            path,
            style: AppType.monoLabel(
              color: dsh.textTertiary,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final line in oldLines.take(24))
            Container(
              color: dsh.diffDelBg,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Text(
                '- $line',
                style: AppType.monoSmall(color: dsh.diffDelFg).copyWith(
                  fontSize: 11.5,
                ),
              ),
            ),
          for (final line in newLines.take(36))
            Container(
              color: dsh.diffAddBg,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Text(
                '+ $line',
                style: AppType.monoSmall(color: dsh.diffAddFg).copyWith(
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
