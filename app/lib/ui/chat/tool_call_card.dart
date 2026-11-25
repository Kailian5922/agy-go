import 'package:acp_client/acp_client.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Displays an ACP tool call with kind icon, status dot, affected paths, and inline file diff.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({super.key, required this.toolCall});

  final AcpToolCall toolCall;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tc = widget.toolCall;
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    final statusColor = switch (tc.status) {
      AcpToolStatus.completed => surfaces.success,
      AcpToolStatus.failed => surfaces.danger,
      AcpToolStatus.cancelled => surfaces.subtleText,
      AcpToolStatus.inProgress => theme.colorScheme.primary,
      _ => surfaces.warning,
    };

    final icon = switch (tc.kind) {
      AcpToolKind.read => Icons.description_outlined,
      AcpToolKind.edit => Icons.edit_note_rounded,
      AcpToolKind.delete => Icons.delete_outline_rounded,
      AcpToolKind.move => Icons.drive_file_move_outlined,
      AcpToolKind.search => Icons.search_rounded,
      AcpToolKind.execute => Icons.terminal_rounded,
      AcpToolKind.fetch => Icons.public_rounded,
      AcpToolKind.think => Icons.psychology_outlined,
      _ => Icons.build_outlined,
    };

    final hasDetails = tc.content.isNotEmpty || tc.locations.isNotEmpty;

    return HairlineCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      borderRadius: BorderRadius.circular(14),
      onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tc.title.isNotEmpty ? tc.title : (tc.name ?? tc.kind.name),
                  maxLines: _expanded ? null : 1,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (tc.status == AcpToolStatus.inProgress)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: statusColor,
                  ),
                )
              else
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              if (hasDetails) ...[
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: surfaces.subtleText,
                ),
              ],
            ],
          ),
          if (_expanded && hasDetails) ...[
            const SizedBox(height: 8),
            for (final loc in tc.locations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  loc.line != null ? '${loc.path}:${loc.line}' : loc.path,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: surfaces.subtleText,
                  ),
                ),
              ),
            for (final block in tc.content)
              switch (block) {
                AcpDiffToolContent(:final path, :final oldText, :final newText) =>
                  _DiffPreview(path: path, oldText: oldText, newText: newText),
                AcpBlockToolContent(:final block) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    block is AcpTextBlock ? block.text : block.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                AcpTerminalToolContent(:final terminalId) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '终端会话 #$terminalId',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: surfaces.subtleText,
                    ),
                  ),
                ),
              },
          ],
        ],
      ),
    );
  }
}

class _DiffPreview extends StatelessWidget {
  const _DiffPreview({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  final String path;
  final String? oldText;
  final String newText;

  @override
  Widget build(BuildContext context) {
    final surfaces = AgySurfaces.of(context);
    final oldLines = (oldText ?? '').isEmpty ? const <String>[] : oldText!.split('\n');
    final newLines = newText.isEmpty ? const <String>[] : newText.split('\n');

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0A0E17)
            : const Color(0xFFF3F6FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: surfaces.hairline, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            path,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: surfaces.subtleText,
            ),
          ),
          const SizedBox(height: 4),
          for (final line in oldLines.take(20))
            Container(
              color: surfaces.danger.withValues(alpha: 0.14),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                '- $line',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: surfaces.danger,
                ),
              ),
            ),
          for (final line in newLines.take(30))
            Container(
              color: surfaces.success.withValues(alpha: 0.14),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                '+ $line',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: surfaces.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
