// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../common/expand_reveal.dart';
import '../common/fade_in.dart';
import '../common/pressable.dart';
import '../shell/brand_mark.dart';
import '../theme/theme.dart';

enum SuggestionTint { teal, violet, amber, blue }

class ChatSuggestion {
  const ChatSuggestion({
    required this.icon,
    required this.label,
    required this.detail,
    required this.prompt,
    this.tint = SuggestionTint.blue,
  });

  final IconData icon;
  final String label;
  final String detail;
  final String prompt;
  final SuggestionTint tint;
}

const defaultAgySuggestions = <ChatSuggestion>[
  ChatSuggestion(
    icon: AppIcons.folderOpen,
    label: '看看工作区',
    detail: '列出当前目录与文件结构',
    prompt: '帮我检查当前工作区的目录结构和主要文件。',
    tint: SuggestionTint.teal,
  ),
  ChatSuggestion(
    icon: AppIcons.search,
    label: '检索文件内容',
    detail: '搜索代码或文档并总结要点',
    prompt: '帮我搜索当前工作区里的主要文本或代码文件，简要总结它们的用途。',
    tint: SuggestionTint.violet,
  ),
  ChatSuggestion(
    icon: AppIcons.files,
    label: '梳理工作区',
    detail: '统计当前目录分类与体积',
    prompt: '帮我梳理当前工作区里的文件分类和大小分布，只分析当前工作区不要改动原文件。',
    tint: SuggestionTint.amber,
  ),
  ChatSuggestion(
    icon: AppIcons.code,
    label: '写个 Shell 脚本',
    detail: '在本机终端实测运行 POSIX 脚本',
    prompt: '帮我写一个统计当前工作区文件数量和大小的 POSIX sh 脚本，并直接运行验证。',
    tint: SuggestionTint.blue,
  ),
];

const defaultAgyTips = <String>[
  '输入 / 打开斜杠命令面板，输入 @ 引用当前工作区里的文件',
  '点右上角模型按钮切换模型与思考深度，并查看 5 小时与周剩余额度',
  '对话中点顶部标题可查看工具轨迹、Diff 与详情；输入 /usage 查看完整额度',
  '左滑屏幕打开快捷面板，随时查看额度、文件、工作区或操控手机',
  '在左侧抽屉按工作区管理对话，授权手机存储后直接访问 /storage/emulated/0',
  '长按自己发的消息可复制、自由选字、引用追问或编辑重发',
];

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return '上午好';
  if (h >= 11 && h < 13) return '中午好';
  if (h >= 13 && h < 18) return '下午好';
  if (h >= 18 && h < 23) return '晚上好';
  return '夜深了';
}

class ChatIdleAction {
  const ChatIdleAction({
    required this.message,
    required this.label,
    required this.onTap,
    this.progress,
    this.progressDetail,
  });

  final String message;
  final String label;
  final VoidCallback? onTap;
  final double? progress;
  final String? progressDetail;
}

/// New-chat empty state mirroring DSH Go's exact layout:
/// Original AGY BrandMark → Greeting → Subtitle → Primary Pill or Workspace QuietChip
/// → SetupItem row (Permissions / Host) → 2×2 tinted SuggestionCards → rotating TipLine.
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({
    super.key,
    required this.connected,
    required this.onSuggestion,
    this.connecting = false,
    this.starting = false,
    this.onReconnect,
    this.idle,
    this.workspace,
    this.onWorkspace,
    this.options,
    this.suggestions = defaultAgySuggestions,
    this.tips = defaultAgyTips,
    this.now,
    this.tipStart,
  });

  final bool connected;
  final bool connecting;
  final bool starting;
  final VoidCallback? onReconnect;
  final ChatIdleAction? idle;
  final ValueChanged<ChatSuggestion> onSuggestion;
  final String? workspace;
  final VoidCallback? onWorkspace;
  final Widget? options;
  final List<ChatSuggestion> suggestions;
  final List<String> tips;
  final DateTime? now;
  final int? tipStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final retry = connected ? null : onReconnect;
    final idleAction = connected || retry != null ? null : idle;
    final subtitle = connected
        ? '今天想做点什么？'
        : retry != null
        ? '暂时连不上引擎，点击下方重试'
        : idleAction != null
        ? idleAction.message
        : starting
        ? '正在启动本机 Antigravity CLI…'
        : connecting
        ? '正在连接引擎…'
        : '本机引擎未连接';

    var order = 0;
    Widget enter(Widget child) => FadeSlideIn(index: order++, child: child);

    final Widget? slot = retry != null
        ? EmptyPrimaryPill(
            key: const ValueKey('reconnect'),
            label: '重新连接',
            onTap: retry,
          )
        : idleAction != null
        ? EmptyPrimaryPill(
            key: ValueKey(idleAction.label),
            label: idleAction.label,
            onTap: idleAction.onTap,
          )
        : workspace != null && connected
        ? ConstrainedBox(
            key: const ValueKey('workspace'),
            constraints: const BoxConstraints(maxWidth: 280),
            child: QuietChip(
              icon: AppIcons.workspace,
              label: '在「$workspace」中',
              trailing: onWorkspace == null ? null : AppIcons.expand,
              onTap: onWorkspace,
            ),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.floatInset),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpace.floatingWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              enter(
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: AgyBrandMark(
                      size: 40,
                      color: theme.colorScheme.primary.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.65 : 0.48,
                      ),
                    ),
                  ),
                ),
              ),
              enter(
                Text(
                  greetingFor(now ?? DateTime.now()),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              enter(
                AnimatedSwitcher(
                  duration: AppMotion.of(context, AppMotion.quick),
                  child: Text(
                    subtitle,
                    key: ValueKey(subtitle),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: dsh.textTertiary,
                    ),
                  ),
                ),
              ),
              if (idleAction?.progress case final p?) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: p.clamp(0.0, 1.0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      if (idleAction?.progressDetail != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          idleAction!.progressDetail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (slot != null) ...[
                const SizedBox(height: 12),
                enter(
                  Center(
                    child: AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.quick),
                      child: slot,
                    ),
                  ),
                ),
              ],
              if (options != null) ...[
                const SizedBox(height: 8),
                enter(Center(child: options!)),
              ],
              if (suggestions.isNotEmpty || tips.isNotEmpty)
                ExpandReveal(
                  open: connected,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (suggestions.isNotEmpty)
                          SuggestionCards(
                            suggestions: suggestions,
                            enabled: connected,
                            onSuggestion: onSuggestion,
                            firstIndex: order,
                          ),
                        if (connected && tips.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          FadeSlideIn(
                            index: order + suggestions.length,
                            child: TipLine(tips: tips, start: tipStart),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color quietChipFill(ThemeData theme) => theme.brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.07)
    : theme.colorScheme.onSurface.withValues(alpha: 0.05);

Color quietCardRim(ThemeData theme) => theme.brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.08)
    : theme.colorScheme.onSurface.withValues(alpha: 0.06);

class EmptyPrimaryPill extends StatelessWidget {
  const EmptyPrimaryPill({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      enabled: onTap != null,
      child: Material(
        color: onTap != null
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.12),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: onTap != null
                      ? scheme.onPrimary
                      : DshColors.of(context).textDisabled,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuietChip extends StatelessWidget {
  const QuietChip({
    super.key,
    required this.label,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Pressable(
      enabled: onTap != null,
      child: Material(
        color: quietChipFill(theme),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                icon != null ? 13 : 14,
                6,
                trailing != null ? 10 : 14,
                6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: muted),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 2),
                    Icon(trailing, size: 18, color: muted),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupItem extends StatelessWidget {
  const SetupItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final fg = accentColor ?? theme.colorScheme.onSurfaceVariant;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const SquircleBorder(borderRadius: AppShape.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: fg,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(AppIcons.expand, size: 14, color: dsh.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _tintColor(BuildContext context, SuggestionTint tint) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final dsh = DshColors.of(context);
  return switch (tint) {
    SuggestionTint.teal => dsh.success,
    SuggestionTint.violet => dark ? DshPalette.duskLift : DshPalette.dusk,
    SuggestionTint.amber => dsh.warning,
    SuggestionTint.blue => dsh.info,
  };
}

class SuggestionCards extends StatelessWidget {
  const SuggestionCards({
    super.key,
    required this.suggestions,
    required this.enabled,
    required this.onSuggestion,
    this.firstIndex = 0,
  });

  final List<ChatSuggestion> suggestions;
  final bool enabled;
  final ValueChanged<ChatSuggestion> onSuggestion;
  final int firstIndex;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final cell = (constraints.maxWidth - gap) / 2;
        final columns = cell >= 150.0 ? 2 : 1;

        Widget card(int i) {
          final s = suggestions[i];
          return FadeSlideIn(
            index: firstIndex + i,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.5,
              duration: AppMotion.of(context, AppMotion.quick),
              child: _SuggestionCard(
                suggestion: s,
                enabled: enabled,
                onTap: () => onSuggestion(s),
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < suggestions.length; i += columns) ...[
              if (i > 0) const SizedBox(height: gap),
              if (columns == 1)
                card(i)
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: card(i)),
                      const SizedBox(width: gap),
                      Expanded(
                        child: i + 1 < suggestions.length
                            ? card(i + 1)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.enabled,
    required this.onTap,
  });

  final ChatSuggestion suggestion;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final tint = _tintColor(context, suggestion.tint);
    final shape = AppShape.outlined(
      quietCardRim(theme),
      radius: AppShape.lg,
      width: 0.5,
    );
    final tap = enabled ? onTap : null;

    return Pressable(
      enabled: tap != null,
      child: Material(
        color: quietChipFill(theme),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: tint.withValues(alpha: 0.14),
                    shape: const SquircleBorder(
                      borderRadius: AppShape.radiusSm,
                    ),
                  ),
                  child: SizedBox.square(
                    dimension: 34,
                    child: Icon(suggestion.icon, size: 18, color: tint),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        suggestion.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: dsh.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TipLine extends StatefulWidget {
  const TipLine({super.key, required this.tips, this.start});

  final List<String> tips;
  final int? start;

  @override
  State<TipLine> createState() => _TipLineState();
}

class _TipLineState extends State<TipLine> {
  late int _index = widget.tips.isEmpty
      ? 0
      : (widget.start ?? math.Random().nextInt(widget.tips.length)) %
            widget.tips.length;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (widget.tips.length <= 1 || AppMotion.reduced(context)) return;
    _timer = Timer(const Duration(seconds: 7), () {
      if (mounted) _next();
    });
  }

  void _next() {
    setState(() => _index = (_index + 1) % widget.tips.length);
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tips.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final tip = widget.tips[_index];
    final style = theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.tips.length > 1 ? _next : null,
        customBorder: const SquircleBorder(borderRadius: AppShape.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(AppIcons.tip, size: 16, color: dsh.warning),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.of(context, AppMotion.slow),
                  switchInCurve: AppMotion.enter,
                  switchOutCurve: AppMotion.exit,
                  child: Text(
                    tip,
                    key: ValueKey(_index),
                    style: style,
                  ),
                ),
              ),
              if (widget.tips.length > 1) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    AppIcons.disclosure,
                    size: 14,
                    color: dsh.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
