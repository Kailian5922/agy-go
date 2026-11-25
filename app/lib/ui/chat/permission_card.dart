import 'package:acp_client/acp_client.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Interactive approval card for ACP `session/request_permission`.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.pending,
    required this.onSelect,
    required this.onCancel,
  });

  final PendingPermission pending;
  final void Function(String optionId) onSelect;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final req = pending.request;
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return GlassSurface(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: surfaces.warning),
              const SizedBox(width: 8),
              Text(
                '需要你的确认',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                req.toolCall.kind.name,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: surfaces.subtleText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            req.toolCall.title.isNotEmpty
                ? req.toolCall.title
                : (req.toolCall.name ?? '执行工具调用'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (req.toolCall.locations.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              req.toolCall.locations.map((l) => l.path).join(', '),
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: surfaces.subtleText,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in req.options)
                opt.kind.isAllow
                    ? FilledButton.tonal(
                        onPressed: () => onSelect(opt.optionId),
                        child: Text(opt.name),
                      )
                    : OutlinedButton(
                        onPressed: () => onSelect(opt.optionId),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: surfaces.danger,
                          side: BorderSide(
                            color: surfaces.danger.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(opt.name),
                      ),
              if (req.options.every((o) => o.kind.isAllow))
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('取消'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
