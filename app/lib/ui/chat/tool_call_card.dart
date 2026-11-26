// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../common/brief_notice.dart';
import '../common/expand_reveal.dart';
import '../theme/theme.dart';
import 'diff_and_output_page.dart';

/// 32dp single-line tool call row mirroring DSH Go's ToolRow, expanding
/// smoothly into a JetBrains Mono code/diff well.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({super.key, required this.toolCall});

  final AcpToolCall toolCall;

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

  (int added, int removed)? _diffCounts(AcpToolCall tc) {
    var added = 0;
    var removed = 0;
    var found = false;
    for (final c in tc.content) {
      if (c case AcpDiffToolContent(:final oldText, :final newText)) {
        found = true;
        if (oldText != null && oldText.isNotEmpty) {
          removed += oldText.split('\n').length;
        }
        if (newText.isNotEmpty) {
          added += newText.split('\n').length;
        }
      }
    }
    return found ? (added, removed) : null;
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.toolCall;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    final hasDetails = tc.content.isNotEmpty || tc.locations.isNotEmpty;
    final summary = tc.title.isNotEmpty
        ? tc.title
        : (tc.locations.isNotEmpty
              ? tc.locations.first.path
              : (tc.name ?? tc.kind.name));
    final tintIdx = _tint(tc.kind);
    final badgeBg = dsh.identity[tintIdx % dsh.identity.length];
    final badgeFg = dsh.onIdentity[tintIdx % dsh.onIdentity.length];
    final counts = _diffCounts(tc);

    final statusWidget = switch (tc.status) {
      AcpToolStatus.inProgress => SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: scheme.primary,
        ),
      ),
      AcpToolStatus.completed when counts != null => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (counts.$1 > 0)
            Text(
              '+${counts.$1}',
              style: AppType.monoLabel(color: dsh.success),
            ),
          if (counts.$1 > 0 && counts.$2 > 0) const SizedBox(width: 4),
          if (counts.$2 > 0)
            Text(
              '−${counts.$2}',
              style: AppType.monoLabel(color: dsh.danger),
            ),
        ],
      ),
      AcpToolStatus.completed => Icon(
        AppIcons.done,
        size: 14,
        color: dsh.success,
      ),
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
      _ => Icon(AppIcons.waiting, size: 14, color: dsh.warning),
    };

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
                        overflow: TextOverflow.ellipsis,
                        style: tc.kind == AcpToolKind.execute ||
                                tc.kind == AcpToolKind.read ||
                                tc.kind == AcpToolKind.edit
                            ? AppType.monoLabel(color: dsh.textTertiary)
                                  .copyWith(fontSize: 12.5)
                            : theme.textTheme.bodySmall?.copyWith(
                                color: dsh.textTertiary,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    statusWidget,
                    if (hasDetails) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                loc.line != null
                                    ? '${loc.path}:${loc.line}'
                                    : loc.path,
                                style: AppType.monoLabel(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: loc.path),
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
                      ),
                    for (final block in tc.content)
                      switch (block) {
                        AcpDiffToolContent(
                          :final path,
                          :final oldText,
                          :final newText,
                        ) =>
                          _DiffWell(
                            path: path,
                            oldText: oldText,
                            newText: newText,
                          ),
                        AcpBlockToolContent(:final block) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText(
                            block is AcpTextBlock
                                ? block.text
                                : block.toString(),
                            style: AppType.monoSmall(color: dsh.codeWellFg),
                          ),
                        ),
                        AcpTerminalToolContent(:final terminalId) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '终端会话 #$terminalId',
                            style: AppType.monoLabel(color: dsh.textTertiary),
                          ),
                        ),
                      },
                    if (counts != null ||
                        tc.content.any((b) => b is AcpBlockToolContent)) ...[
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
                                  builder: (_) =>
                                      DiffViewerPage.fromToolCall(tc),
                                ),
                              ),
                            ),
                          if (tc.content.any((b) => b is AcpBlockToolContent))
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
                                final fullText = tc.content
                                    .whereType<AcpBlockToolContent>()
                                    .map((b) => b.block is AcpTextBlock
                                        ? (b.block as AcpTextBlock).text
                                        : b.block.toString())
                                    .join('\n\n');
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => OutputViewerPage(
                                      title: tc.title.isNotEmpty
                                          ? tc.title
                                          : (tc.name ?? '工具输出'),
                                      subtitle: tc.locations.isNotEmpty
                                          ? tc.locations.first.path
                                          : tc.kind.name,
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
