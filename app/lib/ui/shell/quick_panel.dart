import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Right-side quick panel: live ACP model / reasoning effort / mode switcher, plan & usage.
class QuickPanel extends ConsumerWidget {
  const QuickPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final connAsync = ref.watch(activeConnectionProvider);
    final conn = connAsync.value;
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return GlassSurface(
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(
              children: [
                Text(
                  '会话控制',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClose,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            HairlineCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '连接信息',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: surfaces.subtleText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    conn == null
                        ? '未连接主机'
                        : '${conn.label} · ${conn.initResult.agentInfo?.name ?? 'agy'} ${conn.initResult.agentInfo?.version ?? ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (conn != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '工作目录: ${conn.defaultCwd}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: surfaces.subtleText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (chat.transcript.modes != null &&
                chat.transcript.modes!.availableModes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '执行模式',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: surfaces.subtleText,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in chat.transcript.modes!.availableModes)
                    ChoiceChip(
                      label: Text(m.name),
                      selected: m.id == chat.transcript.modes!.currentModeId,
                      onSelected: (_) =>
                          ref.read(chatProvider.notifier).setMode(m.id),
                    ),
                ],
              ),
            ],
            for (final opt in chat.transcript.configOptions) ...[
              const SizedBox(height: 16),
              Text(
                opt.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: surfaces.subtleText,
                ),
              ),
              const SizedBox(height: 8),
              if (opt.options.isNotEmpty)
                HairlineCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: opt.options.any((v) => v.value == opt.currentValue)
                          ? opt.currentValue?.toString()
                          : null,
                      hint: Text(opt.currentValue?.toString() ?? '选择'),
                      items: [
                        for (final v in opt.options)
                          DropdownMenuItem(
                            value: v.value,
                            child: Text(
                              v.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref
                              .read(chatProvider.notifier)
                              .setConfigOption(opt.id, val);
                        }
                      },
                    ),
                  ),
                ),
            ],
            if (chat.transcript.plan.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                '执行计划',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: surfaces.subtleText,
                ),
              ),
              const SizedBox(height: 8),
              HairlineCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final entry in chat.transcript.plan)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              entry.status == 'completed'
                                  ? Icons.check_circle_rounded
                                  : entry.status == 'in_progress'
                                  ? Icons.timelapse_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 16,
                              color: entry.status == 'completed'
                                  ? surfaces.success
                                  : entry.status == 'in_progress'
                                  ? theme.colorScheme.primary
                                  : surfaces.subtleText,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.content,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (chat.transcript.usage != null) ...[
              const SizedBox(height: 16),
              HairlineCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.data_usage_rounded, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '上下文: ${chat.transcript.usage!.usedTokens ?? 0} / ${chat.transcript.usage!.sizeTokens ?? 0} tokens',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (chat.transcript.availableCommands.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '可用斜杠命令',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: surfaces.subtleText,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cmd in chat.transcript.availableCommands.take(12))
                    Chip(
                      label: Text('/${cmd.name}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
