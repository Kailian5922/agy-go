// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';

/// Approval card mirroring DSH Go's ApprovalCard:
/// 1px warning hairline, shield header, monospace command/path well,
/// equal-width Decline / Allow Once buttons, and low-emphasis Allow All link.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.pending,
    required this.onSelect,
    required this.onCancel,
    this.onAllowAllForChat,
  });

  final PendingPermission pending;
  final void Function(String optionId) onSelect;
  final VoidCallback onCancel;
  final void Function(String allowOptionId)? onAllowAllForChat;

  String _title(AcpToolCall tc) => switch (tc.kind) {
    AcpToolKind.execute => '允许运行这条命令？',
    AcpToolKind.edit => '允许修改这个文件？',
    AcpToolKind.delete => '允许删除文件？',
    AcpToolKind.fetch => '允许访问外部网络？',
    _ => '允许执行此操作？',
  };

  @override
  Widget build(BuildContext context) {
    final req = pending.request;
    final tc = req.toolCall;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);
    final surfaces = DshSurfaces.of(context);

    final allowOpt = req.options.where((o) => o.kind.isAllow).firstOrNull;
    final rejectOpt = req.options.where((o) => !o.kind.isAllow).firstOrNull;
    final codeSummary = tc.title.isNotEmpty
        ? tc.title
        : (tc.locations.isNotEmpty
              ? tc.locations.map((l) => l.path).join('\n')
              : (tc.name ?? '执行工具调用'));

    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: AppShape.radiusLg,
      style: surfaces.card.copyWith(
        hairline: dsh.warning.withValues(alpha: 0.55),
        hairlineWidth: 1.0,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(AppIcons.approval, size: 18, color: dsh.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title(tc),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Text(
                  tc.kind.name,
                  style: AppType.monoLabel(color: dsh.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: ShapeDecoration(
                color: dsh.codeWellBg,
                shape: AppShape.outlined(dsh.codeWellBorder, radius: 12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Text(
                  tc.kind == AcpToolKind.execute ? '\$ $codeSummary' : codeSummary,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.monoSmall(color: dsh.codeWellFg).copyWith(
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
            if (tc.locations.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                tc.locations.map((l) => l.path).join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.monoLabel(color: dsh.textTertiary),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      if (rejectOpt != null) {
                        onSelect(rejectOpt.optionId);
                      } else {
                        onCancel();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(
                        color: colors.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(rejectOpt?.name ?? '拒绝'),
                  ),
                ),
                if (allowOpt != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onSelect(allowOpt.optionId);
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(allowOpt.name),
                    ),
                  ),
                ],
              ],
            ),
            if (allowOpt != null && onAllowAllForChat != null) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onAllowAllForChat!(allowOpt.optionId);
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    foregroundColor: dsh.textTertiary,
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  child: const Text('本对话都允许'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
