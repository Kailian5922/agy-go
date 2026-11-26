// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.
// Native Antigravity CLI (`agy acp`) model card grid + capsule thought-level selector.

import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../common/app_sheet.dart';
import '../common/empty_view.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/segmented_pill.dart';
import '../common/smooth_size.dart';
import '../engine/engine_screen.dart';
import '../theme/theme.dart';

/// Translates ACP `thought_level` / `reasoning_effort` IDs into concise Chinese labels.
String thoughtLevelLabel(String id, [String? fallback]) =>
    switch (id.trim().toLowerCase()) {
      'off' || 'none' || 'disabled' => '不思考',
      'minimal' || 'min' => '极简',
      'low' => '低',
      'medium' || 'med' || 'normal' || 'balanced' => '中',
      'high' => '高',
      'xhigh' || 'extra_high' || 'extra-high' || 'extra' => '超高',
      'max' || 'maximum' => '最高',
      _ => (fallback != null && fallback.trim().isNotEmpty) ? fallback : id,
    };

/// Produces a crisp, legible model label from an ACP [AcpConfigOptionValue].
String formatModelName(AcpConfigOptionValue choice) {
  final rawName = choice.name.trim();
  if (rawName.isNotEmpty && rawName != choice.value) {
    return rawName;
  }
  final words = choice.value
      .replaceFirst(RegExp(r'^models/'), '')
      .split(RegExp(r'[-_]+'))
      .where((w) => w.isNotEmpty)
      .map((w) {
        final lower = w.toLowerCase();
        if (lower == 'gpt') return 'GPT';
        if (lower == 'oss') return 'OSS';
        if (lower == 'pro') return 'Pro';
        if (lower == 'flash') return 'Flash';
        if (lower == 'opus') return 'Opus';
        if (lower == 'sonnet') return 'Sonnet';
        if (lower == 'haiku') return 'Haiku';
        if (w.length == 1) return w.toUpperCase();
        return '${w[0].toUpperCase()}${w.substring(1)}';
      })
      .join(' ');
  return words.isEmpty ? choice.value : words;
}

String _inferModelGroup(AcpConfigOptionValue choice) {
  final explicit = choice.group?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final probe = '${choice.value} ${choice.name}'.toLowerCase();
  if (probe.contains('gemini')) return 'Gemini';
  if (probe.contains('claude')) return 'Claude';
  if (probe.contains('gpt') || probe.contains('openai') || probe.contains('o3') || probe.contains('o4')) {
    return 'OpenAI';
  }
  return '其他';
}

/// Top-right chrome-glass pill in [ChatHeader] mirroring DSH Go's ModelChip:
/// shows `✦ <Model Name> · <思考等级> ⌄` both BEFORE and DURING conversations.
class ModelModeChip extends ConsumerWidget {
  const ModelModeChip({super.key, this.grouped = true, this.compact = false});

  final bool grouped;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);
    final connected = ref.watch(
      activeConnectionProvider.select((a) => a.value != null),
    );
    final chat = ref.watch(
      chatProvider.select(
        (c) => (
          modelOpt: c.modelConfigOption,
          thoughtOpt: c.thoughtLevelOption,
          modes: c.transcript.modes,
          preparing: c.isPreparingModels,
          updating: c.isUpdatingModel,
          authRequired: c.authRequired,
        ),
      ),
    );

    String label;
    String? effort;

    if (chat.modelOpt != null && chat.modelOpt!.options.isNotEmpty) {
      final raw = '${chat.modelOpt!.currentValue ?? ''}';
      final matched = chat.modelOpt!.options
          .where((o) => o.value == raw)
          .firstOrNull;
      label = matched != null
          ? formatModelName(matched)
          : (raw.isNotEmpty ? raw : formatModelName(chat.modelOpt!.options.first));

      final tOpt = chat.thoughtOpt;
      if (tOpt != null && tOpt.options.length >= 2 && tOpt.currentValue != null) {
        final tRaw = '${tOpt.currentValue}';
        final tMatch = tOpt.options.where((o) => o.value == tRaw).firstOrNull;
        effort = thoughtLevelLabel(tRaw, tMatch?.name);
      }
    } else if (!connected) {
      label = '未连接';
    } else if (chat.preparing) {
      label = '加载模型';
    } else if (chat.authRequired) {
      label = '需登录';
    } else {
      label = '选择模型';
    }

    final textStyle = theme.textTheme.labelMedium?.copyWith(
      fontSize: 13,
      color: colors.onSurface,
      fontWeight: FontWeight.w500,
    );

    return GlassSurface(
      tier: GlassTier.chrome,
      stadium: true,
      grouped: grouped,
      onTap: () => unawaited(showModelModeSheet(context)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          child: SmoothSize(
            duration: AppMotion.of(context, AppMotion.standard),
            curve: AppMotion.std,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chat.preparing || chat.updating)
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: colors.primary,
                    ),
                  )
                else
                  Icon(AppIcons.providers, size: 15, color: colors.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compact ? 132 : 184,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle,
                          ),
                        ),
                        if (effort != null)
                          Text(
                            ' · $effort',
                            maxLines: 1,
                            style: textStyle?.copyWith(
                              color: dsh.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(AppIcons.expand, size: 16, color: dsh.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the Mist Glass Model & Thinking Effort bottom sheet.
///
/// Works both BEFORE starting a conversation (via the silent pre-warmed ACP draft
/// session) and mid-conversation. Tapping a model card keeps the sheet open and
/// live-updates its supported thinking levels; tapping a thinking level smoothly
/// glides the capsule thumb and auto-closes the sheet.
Future<void> showModelModeSheet(
  BuildContext context, {
  bool focusEffort = false,
}) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => _ModelSheetBody(focusEffort: focusEffort),
  );
}

class _ModelSheetBody extends ConsumerStatefulWidget {
  const _ModelSheetBody({this.focusEffort = false});

  final bool focusEffort;

  @override
  ConsumerState<_ModelSheetBody> createState() => _ModelSheetBodyState();
}

class _ModelSheetBodyState extends ConsumerState<_ModelSheetBody> {
  String? _activeGroup;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final conn = ref.read(activeConnectionProvider).value;
      final chat = ref.read(chatProvider);
      if (conn != null &&
          chat.modelConfigOption == null &&
          !chat.isPreparingModels) {
        unawaited(
          ref.read(chatProvider.notifier).prepareDraftSession(forceRefresh: true),
        );
      }
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickModel(AcpConfigOptionValue choice) async {
    HapticFeedback.selectionClick();
    _autoCloseTimer?.cancel();
    await ref.read(chatProvider.notifier).selectModel(choice.value);
  }

  Future<void> _pickEffort(String level) async {
    HapticFeedback.selectionClick();
    final ok = await ref.read(chatProvider.notifier).selectThoughtLevel(level);
    if (!mounted || !ok) return;
    _autoCloseTimer?.cancel();
    final settle = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.standard + const Duration(milliseconds: 110);
    _autoCloseTimer = Timer(settle, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _openEnginePage() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EngineScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(activeConnectionProvider).value;
    final chat = ref.watch(chatProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);

    final modelOpt = chat.modelConfigOption;
    final thoughtOpt = chat.thoughtLevelOption;
    final otherOpts = chat.otherConfigOptions;
    final modes = chat.transcript.modes;
    final models = modelOpt?.options ?? const <AcpConfigOptionValue>[];
    final currentModelVal = '${modelOpt?.currentValue ?? ''}';

    final groups = <String>[];
    for (final m in models) {
      final g = _inferModelGroup(m);
      if (!groups.contains(g)) groups.add(g);
    }
    final showGroupFilter = groups.length >= 2 && models.length > 4;
    final visibleModels = showGroupFilter && _activeGroup != null
        ? models.where((m) => _inferModelGroup(m) == _activeGroup).toList()
        : models;

    final efforts = thoughtOpt?.options ?? const <AcpConfigOptionValue>[];
    final currentEffort = '${thoughtOpt?.currentValue ?? ''}';
    final selectedEffort = efforts.any((e) => e.value == currentEffort)
        ? currentEffort
        : (efforts.isNotEmpty ? efforts.first.value : '');

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                widget.focusEffort ? '模型与思考深度' : '选择模型',
                actions: [
                  if (conn != null && chat.sessionId == null)
                    SheetIconButton(
                      icon: AppIcons.refresh,
                      tooltip: '刷新可用模型',
                      onPressed: chat.isPreparingModels
                          ? null
                          : () => unawaited(
                              ref
                                  .read(chatProvider.notifier)
                                  .prepareDraftSession(forceRefresh: true),
                            ),
                    ),
                ],
              ),
              if (conn == null)
                EmptyView(
                  compact: true,
                  icon: AppIcons.disconnected,
                  title: '引擎未连接',
                  message: '请先启动本机 Antigravity 引擎或切换 SSH 远程主机，连接后将自动读取可用模型。',
                  actionLabel: '前往本机引擎',
                  onAction: _openEnginePage,
                )
              else if (models.isEmpty && chat.isPreparingModels)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 34),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          strokeCap: StrokeCap.round,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '正在获取 Antigravity 可用模型…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: dsh.textTertiary,
                        ),
                      ),
                    ],
                  ),
                )
              else if (models.isEmpty && chat.authRequired)
                EmptyView(
                  compact: true,
                  icon: AppIcons.apiKey,
                  title: '尚未完成认证',
                  message: chat.modelError ?? '请先登录 Google 账号或填写 Gemini API Key。',
                  actionLabel: '前往认证',
                  onAction: _openEnginePage,
                )
              else if (models.isEmpty)
                EmptyView(
                  compact: true,
                  icon: AppIcons.model,
                  title: '暂未获取到模型列表',
                  message:
                      chat.modelError ?? '当前连接的 ACP 服务暂未返回可选模型列表，点击下方重试。',
                  actionLabel: '重新获取',
                  onAction: () => unawaited(
                    ref
                        .read(chatProvider.notifier)
                        .prepareDraftSession(forceRefresh: true),
                  ),
                )
              else ...[
                // Series / Group capsule filter bar (only shown when >4 models across >=2 families)
                if (showGroupFilter)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 14),
                    child: _GroupFilterBar(
                      groups: groups,
                      active: _activeGroup,
                      onChanged: (g) => setState(() => _activeGroup = g),
                    ),
                  ),

                // 2-column (or auto 1-column) Mist Glass model cards grid
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SheetTitleBar.inset,
                  ),
                  child: SmoothSize(
                    duration: AppMotion.of(context, AppMotion.standard),
                    curve: AppMotion.std,
                    alignment: Alignment.topCenter,
                    child: _ModelCardGrid(
                      models: visibleModels,
                      selectedValue: currentModelVal,
                      onPick: (m) => unawaited(_pickModel(m)),
                    ),
                  ),
                ),

                // Capsule Thinking Depth selector (live-updated per selected model!)
                SmoothSize(
                  duration: AppMotion.of(context, AppMotion.standard),
                  curve: AppMotion.std,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SheetTitleBar.inset + 4,
                          0,
                          SheetTitleBar.inset + 4,
                          8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '思考深度',
                              style: groupTitleStyle(context)?.copyWith(
                                color: widget.focusEffort
                                    ? colors.primary
                                    : dsh.textTertiary,
                              ),
                            ),
                            if (chat.isUpdatingModel) ...[
                              const SizedBox(width: 8),
                              SizedBox.square(
                                dimension: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (efforts.length >= 2)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SheetTitleBar.inset,
                          ),
                          child: _EffortSelector(
                            options: efforts,
                            selected: selectedEffort,
                            busy: chat.isUpdatingModel,
                            onSelected: (v) => unawaited(_pickEffort(v)),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SheetTitleBar.inset + 4,
                          ),
                          child: Text(
                            efforts.length == 1
                                ? '当前模型固定为「${thoughtLevelLabel(efforts.first.value, efforts.first.name)}」'
                                : '当前模型不支持手动调节思考深度',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: dsh.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                if (chat.modelError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SheetTitleBar.inset + 4,
                      12,
                      SheetTitleBar.inset + 4,
                      0,
                    ),
                    child: Text(
                      chat.modelError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dsh.danger,
                      ),
                    ),
                  ),

                // Additional ACP dynamic options (if any besides model & thought_level)
                for (final opt in otherOpts)
                  if (opt.options.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SheetGroup(
                      title: opt.name,
                      children: [
                        for (final choice in opt.options)
                          ListPageRow(
                            icon: AppIcons.configure,
                            title: choice.name,
                            subtitle: choice.description,
                            trailing: '${opt.currentValue}' == choice.value
                                ? Icon(
                                    AppIcons.selected,
                                    size: 18,
                                    color: colors.primary,
                                  )
                                : null,
                            chevron: false,
                            onTap: () => unawaited(
                              ref
                                  .read(chatProvider.notifier)
                                  .setConfigOption(opt.id, choice.value),
                            ),
                          ),
                      ],
                    ),
                  ],

                // ACP Session Modes (only if agent advertises > 1 mode)
                if (modes != null && modes.availableModes.length > 1) ...[
                  const SizedBox(height: 14),
                  SheetGroup(
                    title: '会话模式',
                    children: [
                      for (final m in modes.availableModes)
                        ListPageRow(
                          icon: AppIcons.modes,
                          title: m.name,
                          subtitle: m.description,
                          trailing: m.id == modes.currentModeId
                              ? Icon(
                                  AppIcons.selected,
                                  size: 18,
                                  color: colors.primary,
                                )
                              : null,
                          chevron: false,
                          onTap: () => unawaited(
                            ref.read(chatProvider.notifier).setMode(m.id),
                          ),
                        ),
                    ],
                  ),
                ],

                // Unobtrusive bottom link to Engine & Auth (matching DSH Go's ManageModelsLink)
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _openEnginePage,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '引擎与账号状态（${conn.label}）',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          AppIcons.disclosure,
                          size: 14,
                          color: dsh.textTertiary,
                        ),
                      ],
                    ),
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

class _GroupFilterBar extends StatelessWidget {
  const _GroupFilterBar({
    required this.groups,
    required this.active,
    required this.onChanged,
  });

  final List<String> groups;
  final String? active;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <(String?, String)>[
      (null, '全部'),
      for (final g in groups) (g, g),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: SheetTitleBar.inset),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (id, label) = items[i];
          return _CapsuleChip(
            label: label,
            selected: active == id,
            onTap: () => onChanged(id),
          );
        },
      ),
    );
  }
}

class _EffortSelector extends StatelessWidget {
  const _EffortSelector({
    required this.options,
    required this.selected,
    required this.busy,
    required this.onSelected,
  });

  final List<AcpConfigOptionValue> options;
  final String selected;
  final bool busy;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.length <= 5) {
      return Opacity(
        opacity: busy ? 0.65 : 1,
        child: SegmentedPill<String>(
          height: 40,
          segments: [
            for (final e in options)
              PillSegment(e.value, thoughtLevelLabel(e.value, e.name)),
          ],
          selected: selected,
          onChanged: busy ? (_) {} : onSelected,
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final e = options[i];
          return _CapsuleChip(
            label: thoughtLevelLabel(e.value, e.name),
            selected: e.value == selected,
            onTap: busy ? null : () => onSelected(e.value),
          );
        },
      ),
    );
  }
}

class _CapsuleChip extends StatelessWidget {
  const _CapsuleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final track = dark
        ? Colors.white.withValues(alpha: 0.07)
        : colors.onSurface.withValues(alpha: 0.06);
    final thumb = dark ? Colors.white.withValues(alpha: 0.20) : Colors.white;
    final quick = AppMotion.of(context, AppMotion.quick);

    return Pressable(
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: quick,
          curve: AppMotion.std,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected ? thumb : track,
            shape: const StadiumBorder(),
            shadows: selected && !dark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 2-column equal-height model card grid matching DSH Go's `_ModelGrid`.
/// Automatically falls back to 1-column if any model title exceeds 2 lines on half width.
class _ModelCardGrid extends StatelessWidget {
  const _ModelCardGrid({
    required this.models,
    required this.selectedValue,
    required this.onPick,
  });

  final List<AcpConfigOptionValue> models;
  final String selectedValue;
  final ValueChanged<AcpConfigOptionValue> onPick;

  static const gap = 10.0;

  bool _namesFitInTwoColumns(BuildContext context, double cardWidth) {
    final room = cardWidth - 2 * (_ModelCard.pad + _ModelCard.border) - 8 - _CheckCircle.size;
    if (room <= 40) return false;
    final painter = TextPainter(
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    try {
      final style = _ModelCard.titleStyle(Theme.of(context));
      for (final m in models) {
        painter.text = TextSpan(text: formatModelName(m), style: style);
        painter.layout(maxWidth: room);
        if (painter.didExceedMaxLines) return false;
      }
      return true;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget card(AcpConfigOptionValue m) => _ModelCard(
      key: ValueKey(m.value),
      choice: m,
      selected: m.value == selectedValue,
      onTap: () => onPick(m),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol =
            models.length >= 2 &&
            _namesFitInTwoColumns(context, (constraints.maxWidth - gap) / 2);
        if (!twoCol) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < models.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                card(models[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < models.length; i += 2) ...[
              if (i > 0) const SizedBox(height: gap),
              if (i + 1 < models.length)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: card(models[i])),
                      const SizedBox(width: gap),
                      Expanded(child: card(models[i + 1])),
                    ],
                  ),
                )
              else
                card(models[i]),
            ],
          ],
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    super.key,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AcpConfigOptionValue choice;
  final bool selected;
  final VoidCallback onTap;

  static const radius = BorderRadius.all(Radius.circular(AppShape.lg));
  static const pad = 14.0;
  static const border = 1.5;

  static TextStyle? titleStyle(ThemeData theme) =>
      theme.textTheme.titleSmall?.copyWith(height: 1.32);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = DshColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    final title = formatModelName(choice);
    final desc = choice.description?.trim();
    final duration = AppMotion.of(context, AppMotion.quick);

    return Pressable(
      child: GestureDetector(
        onTap: onTap,
        child: GlassSurface(
          tier: GlassTier.card,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.std,
            padding: const EdgeInsets.all(pad),
            decoration: ShapeDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: dark ? 0.16 : 0.08)
                  : Colors.transparent,
              shape: RoundedSuperellipseBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: selected
                      ? colors.primary.withValues(alpha: dark ? 0.72 : 0.58)
                      : Colors.transparent,
                  width: border,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle(theme),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CheckCircle(selected: selected),
                  ],
                ),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    desc,
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
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.selected});

  final bool selected;

  static const size = 20.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ring = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.22)
        : colors.onSurface.withValues(alpha: 0.18);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              shape: CircleBorder(side: BorderSide(color: ring, width: 1.5)),
            ),
          ),
          AnimatedScale(
            scale: selected ? 1 : 0.5,
            duration: AppMotion.of(context, AppMotion.quick),
            curve: AppMotion.std,
            child: AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: AppMotion.of(context, AppMotion.quick),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: colors.primary,
                  shape: const CircleBorder(),
                ),
                child: Icon(
                  AppIcons.selected,
                  size: 13,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
