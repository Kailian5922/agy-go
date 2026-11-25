// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/phone_state.dart';
import '../../state/settings_state.dart';
import '../../state/voice_state.dart';
import '../../state/workspace_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_sheet.dart';
import '../common/expand_reveal.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/smooth_size.dart';
import '../phone/phone_control_screen.dart';
import '../shell/drawer_destination.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';

class _SlashItem {
  const _SlashItem({
    required this.name,
    required this.label,
    required this.description,
    required this.icon,
    this.local = false,
  });

  final String name;
  final String label;
  final String description;
  final IconData icon;
  final bool local;
}

const _localSlashItems = <_SlashItem>[
  _SlashItem(
    name: 'new',
    label: '新对话',
    description: '回到新对话界面',
    icon: AppIcons.newChat,
    local: true,
  ),
  _SlashItem(
    name: 'workspace',
    label: '切换工作区',
    description: '选择本机目录或已挂载手机存储',
    icon: AppIcons.workspace,
    local: true,
  ),
  _SlashItem(
    name: 'files',
    label: '打开工作区文件',
    description: '浏览、编辑或新建文件',
    icon: AppIcons.files,
    local: true,
  ),
  _SlashItem(
    name: 'terminal',
    label: '打开终端',
    description: '启动本机或 SSH 交互终端',
    icon: AppIcons.terminal,
    local: true,
  ),
  _SlashItem(
    name: 'phone',
    label: '手机操控',
    description: '配置无障碍 MCP 服务与安全闸门',
    icon: AppIcons.phoneControl,
    local: true,
  ),
  _SlashItem(
    name: 'share',
    label: '分享与导出',
    description: '生成脱敏分享卡、Markdown 或回放包',
    icon: AppIcons.share,
    local: true,
  ),
];

/// Floating 28dp chrome-glass message composer mirroring DSH Go's Composer:
/// - Concentric 36dp `+` button opening the frosted PlusPanel
/// - Expanding QuoteChip tray when quoting a message
/// - Floating glass `/` SlashPalette and `@` workspace file mention picker
/// - Voice dictation status & 36dp right circle (mic / primary send / stop square)
class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({
    super.key,
    required this.enabled,
    required this.isBusy,
    required this.onSend,
    required this.onCancel,
    this.controller,
    this.onOpenDestination,
    this.hintText,
  });

  final bool enabled;
  final bool isBusy;
  final Future<void> Function(String text) onSend;
  final VoidCallback onCancel;
  final TextEditingController? controller;
  final ValueChanged<DrawerDestination>? onOpenDestination;
  final String? hintText;

  @override
  ConsumerState<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends ConsumerState<ComposerBar> {
  TextEditingController? _ownedController;
  final _focusNode = FocusNode();
  bool _hasText = false;
  String? _slashQuery;
  String? _mentionQuery;

  TextEditingController get _ctrl =>
      widget.controller ?? (_ownedController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)?.removeListener(_onTextChanged);
      _ctrl.addListener(_onTextChanged);
      _onTextChanged();
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ownedController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    final has = text.trim().isNotEmpty;
    String? slash;
    String? mention;

    final trimmedLeft = text.trimLeft();
    if (trimmedLeft.startsWith('/') && !trimmedLeft.contains(' ') && !trimmedLeft.contains('\n')) {
      slash = trimmedLeft.substring(1).toLowerCase();
    } else {
      final sel = _ctrl.selection.baseOffset;
      final prefix = sel >= 0 && sel <= text.length ? text.substring(0, sel) : text;
      final m = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(prefix);
      if (m != null) {
        mention = m.group(1)!.toLowerCase();
      }
    }

    if (has != _hasText || slash != _slashQuery || mention != _mentionQuery) {
      setState(() {
        _hasText = has;
        _slashQuery = slash;
        _mentionQuery = mention;
      });
    }
  }

  void _submit() {
    if (!widget.enabled || widget.isBusy) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    // Handle local slash shortcuts directly.
    if (text.startsWith('/')) {
      final cmd = text.substring(1).trim().toLowerCase();
      final local = _localSlashItems.where((i) => i.name == cmd).firstOrNull;
      if (local != null) {
        _ctrl.clear();
        _runLocalCommand(local);
        return;
      }
    }

    HapticFeedback.lightImpact();
    _ctrl.clear();
    unawaited(widget.onSend(text));
  }

  void _runLocalCommand(_SlashItem item) {
    switch (item.name) {
      case 'new':
        ref.read(chatProvider.notifier).startNewChat();
      case 'workspace':
        unawaited(showWorkspaceSheet(context, ref));
      case 'files':
        widget.onOpenDestination?.call(DrawerDestination.files);
      case 'terminal':
        widget.onOpenDestination?.call(DrawerDestination.terminal);
      case 'phone':
        widget.onOpenDestination?.call(DrawerDestination.phone);
      case 'share':
        widget.onOpenDestination?.call(DrawerDestination.share);
    }
  }

  void _pickSlash(_SlashItem item) {
    if (item.local) {
      _ctrl.clear();
      _runLocalCommand(item);
    } else {
      final next = '/${item.name} ';
      _ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      _focusNode.requestFocus();
    }
  }

  void _pickMention(String relativePath) {
    final text = _ctrl.text;
    final sel = _ctrl.selection.baseOffset;
    final end = sel >= 0 && sel <= text.length ? sel : text.length;
    final before = text.substring(0, end);
    final after = text.substring(end);
    final replaced = before.replaceFirst(
      RegExp(r'(@[^\s@]*)$'),
      '@$relativePath ',
    );
    _ctrl.value = TextEditingValue(
      text: '$replaced$after',
      selection: TextSelection.collapsed(offset: replaced.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _openPlusPanel() async {
    _focusNode.unfocus();
    final choice = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => const _PlusPanelBody(),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'mention':
        final cur = _ctrl.text;
        final next = cur.isEmpty || cur.endsWith(' ') ? '$cur@' : '$cur @';
        _ctrl.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
        _focusNode.requestFocus();
      case 'slash':
        _ctrl.value = const TextEditingValue(
          text: '/',
          selection: TextSelection.collapsed(offset: 1),
        );
        _focusNode.requestFocus();
      case 'files':
        widget.onOpenDestination?.call(DrawerDestination.files);
      case 'terminal':
        widget.onOpenDestination?.call(DrawerDestination.terminal);
      case 'workspace':
        unawaited(showWorkspaceSheet(context, ref));
      case 'phone':
        widget.onOpenDestination?.call(DrawerDestination.phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceProvider);
    final quoted = ref.watch(chatProvider.select((c) => c.quotedText));
    final acpCommands = ref.watch(
      chatProvider.select((c) => c.transcript.availableCommands),
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dsh = DshColors.of(context);
    final surfaces = DshSurfaces.of(context);

    ref.listen<String?>(
      voiceProvider.select((v) => v.lastFinalTranscript),
      (prev, next) {
        if (next != null && next.isNotEmpty && next != prev) {
          final existing = _ctrl.text.trim();
          final merged = existing.isEmpty ? next : '$existing $next';
          _ctrl.value = TextEditingValue(
            text: merged,
            selection: TextSelection.collapsed(offset: merged.length),
          );
          ref.read(voiceProvider.notifier).consumeFinalTranscript();
        }
      },
    );

    final slashMatches = _slashQuery == null
        ? const <_SlashItem>[]
        : [
            for (final c in acpCommands)
              _SlashItem(
                name: c.name,
                label: '/${c.name}',
                description: c.description ?? c.inputHint ?? '引擎指令',
                icon: AppIcons.command,
              ),
            ..._localSlashItems,
          ]
              .where(
                (i) =>
                    _slashQuery!.isEmpty ||
                    i.name.toLowerCase().contains(_slashQuery!) ||
                    i.label.toLowerCase().contains(_slashQuery!),
              )
              .toList();

    final workspaceFiles = _mentionQuery == null
        ? const <String>[]
        : ref
              .watch(workspaceProvider)
              .entries
              .where(
                (e) =>
                    _mentionQuery!.isEmpty ||
                    e.name.toLowerCase().contains(_mentionQuery!),
              )
              .take(8)
              .map((e) => e.name)
              .toList();

    const keySize = 36.0;
    const keyGap = 6.0;
    const fontSize = 15.0;
    final line = MediaQuery.textScalerOf(context).scale(fontSize) * 1.45;
    final textPad = math.max(4.0, (keySize - line) / 2);

    final showStop = widget.isBusy && !_hasText && !voice.isListening;
    final showMic = !widget.isBusy && !_hasText && !voice.isListening;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.floatInset,
        4,
        AppSpace.floatInset,
        8,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpace.floatingWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Floating `/` SlashPalette
              if (_slashQuery != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FloatingPopover(
                    child: slashMatches.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '没有匹配的指令',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: dsh.textTertiary,
                              ),
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: slashMatches.length,
                              itemBuilder: (ctx, i) {
                                final item = slashMatches[i];
                                return ListPageRow(
                                  icon: item.icon,
                                  title: item.label,
                                  subtitle: item.description,
                                  trailing: Text(
                                    '/${item.name}',
                                    style: AppType.monoLabel(
                                      color: dsh.textTertiary,
                                    ),
                                  ),
                                  onTap: () => _pickSlash(item),
                                );
                              },
                            ),
                          ),
                  ),
                ),

              // Floating `@` workspace file mention picker
              if (_mentionQuery != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FloatingPopover(
                    child: workspaceFiles.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '当前工作区暂无匹配文件',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: dsh.textTertiary,
                              ),
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: workspaceFiles.length,
                              itemBuilder: (ctx, i) {
                                final name = workspaceFiles[i];
                                return ListPageRow(
                                  icon: AppIcons.file,
                                  title: name,
                                  onTap: () => _pickMention(name),
                                );
                              },
                            ),
                          ),
                  ),
                ),

              // Voice listening pill
              if (voice.isListening || voice.partialTranscript.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GlassSurface(
                    tier: GlassTier.chrome,
                    stadium: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            AppIcons.voice,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              voice.partialTranscript.isNotEmpty
                                  ? voice.partialTranscript
                                  : '正在聆听语音输入…',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Main 28dp chrome-glass composer capsule
              GlassSurface(
                tier: GlassTier.chrome,
                borderRadius: AppShape.radiusXl,
                child: Padding(
                  padding: const EdgeInsets.all(keyGap),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExpandReveal(
                        open: quoted != null && quoted.isNotEmpty,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                          child: _QuoteChip(
                            quote: quoted ?? '',
                            onRemove: () =>
                                ref.read(chatProvider.notifier).setQuote(null),
                          ),
                        ),
                      ),
                      SmoothSize(
                        duration: AppMotion.of(context, AppMotion.quick),
                        curve: AppMotion.std,
                        alignment: Alignment.bottomCenter,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Concentric 36dp '+' or voice cancel button
                            Pressable(
                              child: Material(
                                color: scheme.onSurface.withValues(alpha: 0.06),
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: voice.isListening
                                      ? () => ref
                                            .read(voiceProvider.notifier)
                                            .toggleListening()
                                      : _openPlusPanel,
                                  customBorder: const CircleBorder(),
                                  child: SizedBox.square(
                                    dimension: keySize,
                                    child: Icon(
                                      voice.isListening
                                          ? AppIcons.close
                                          : AppIcons.add,
                                      size: 20,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                focusNode: _focusNode,
                                enabled: widget.enabled || _hasText,
                                minLines: 1,
                                maxLines: 6,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontSize: fontSize,
                                  height: 1.45,
                                ),
                                cursorColor: scheme.primary,
                                decoration: InputDecoration(
                                  hintText: widget.hintText ??
                                      (voice.isListening
                                          ? '正在聆听…'
                                          : widget.enabled
                                          ? (widget.isBusy
                                                ? '生成中… 输入可补充或点击右侧停止'
                                                : '给 Antigravity 发消息，或输入 / 与 @…')
                                          : '连接引擎后发送消息…'),
                                  hintMaxLines: 1,
                                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                    fontSize: fontSize,
                                    color: dsh.textTertiary,
                                    height: 1.45,
                                  ),
                                  filled: false,
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: textPad,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Concentric 36dp Send / Stop / Mic circle button
                            Pressable(
                              enabled: showMic ||
                                  showStop ||
                                  voice.isListening ||
                                  (widget.enabled && _hasText),
                              child: Material(
                                color: showStop || voice.isListening
                                    ? scheme.primary
                                    : showMic
                                    ? scheme.onSurface.withValues(alpha: 0.06)
                                    : (widget.enabled && _hasText)
                                    ? scheme.primary
                                    : surfaces.card.fallbackFill,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: voice.isListening
                                      ? () => ref
                                            .read(voiceProvider.notifier)
                                            .toggleListening()
                                      : showStop
                                      ? () {
                                          HapticFeedback.mediumImpact();
                                          widget.onCancel();
                                        }
                                      : showMic
                                      ? () => ref
                                            .read(voiceProvider.notifier)
                                            .toggleListening()
                                      : (widget.enabled && _hasText)
                                      ? _submit
                                      : null,
                                  child: SizedBox.square(
                                    dimension: keySize,
                                    child: Icon(
                                      showStop || voice.isListening
                                          ? AppIcons.stopGenerating
                                          : showMic
                                          ? AppIcons.voice
                                          : AppIcons.send,
                                      size: showStop || voice.isListening
                                          ? 16
                                          : 19,
                                      color: showStop || voice.isListening
                                          ? scheme.onPrimary
                                          : showMic
                                          ? scheme.onSurfaceVariant
                                          : (widget.enabled && _hasText)
                                          ? scheme.onPrimary
                                          : dsh.textDisabled,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _FloatingPopover extends StatelessWidget {
  const _FloatingPopover({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaces = DshSurfaces.of(context);
    return GlassSurface(
      tier: GlassTier.sheet,
      borderRadius: AppShape.radiusXl,
      child: Material(
        color: surfaces.backdropTop.withValues(alpha: 0.94),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedSuperellipseBorder(borderRadius: AppShape.radiusXl),
        child: child,
      ),
    );
  }
}

class _QuoteChip extends StatelessWidget {
  const _QuoteChip({required this.quote, required this.onRemove});

  final String quote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = DshColors.of(context).textTertiary;
    final line = quote.replaceAll(RegExp(r'\s+'), ' ').trim();

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.onSurface.withValues(alpha: 0.05),
        shape: const StadiumBorder(),
      ),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 32,
              child: Icon(AppIcons.quote, size: 15, color: muted),
            ),
            Expanded(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: SizedBox.square(
                dimension: 32,
                child: Icon(
                  AppIcons.close,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlusPanelBody extends ConsumerWidget {
  const _PlusPanelBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWs = ref.watch(selectedWorkspaceProvider);
    final autoApprove = ref.watch(
      settingsProvider.select((s) => s.autoApproveCommands),
    );
    final phoneOn = ref.watch(phoneControlProvider.select((p) => p.enabled));
    final dsh = DshColors.of(context);

    final tiles = [
      ('mention', AppIcons.mention, '引用文件', 0),
      ('slash', AppIcons.command, '斜杠指令', 2),
      ('files', AppIcons.files, '工作区文件', 4),
      ('terminal', AppIcons.terminal, '终端', 6),
    ];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                spacing: 8,
                children: [
                  for (final (id, icon, label, tint) in tiles)
                    Expanded(
                      child: _PlusTile(
                        icon: icon,
                        label: label,
                        tint: tint,
                        onTap: () => Navigator.of(context).pop(id),
                      ),
                    ),
                ],
              ),
            ),
            SheetGroup(
              title: '本对话',
              children: [
                ListPageRow(
                  icon: AppIcons.workspace,
                  title: '工作区目录',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedWs?.displayTitle ?? '默认工作区',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: dsh.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(AppIcons.disclosure, size: 16),
                    ],
                  ),
                  onTap: () => Navigator.of(context).pop('workspace'),
                ),
                ListPageRow(
                  icon: AppIcons.permissions,
                  title: '命令自动批准',
                  subtitle: autoApprove ? '高风险操作仍建议审慎确认' : '敏感工具调用前弹出确认卡',
                  trailing: Switch.adaptive(
                    value: autoApprove,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setAutoApproveCommands(v),
                  ),
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setAutoApproveCommands(!autoApprove),
                ),
                ListPageRow(
                  icon: AppIcons.phoneControl,
                  title: '手机操控（MCP）',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        phoneOn ? '已开启' : '未开启',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: phoneOn ? dsh.success : dsh.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(AppIcons.disclosure, size: 16),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PhoneControlScreen(),
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

class _PlusTile extends StatelessWidget {
  const _PlusTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final bg = dsh.identity[tint % dsh.identity.length];
    final fg = dsh.onIdentity[tint % dsh.onIdentity.length];
    return Pressable(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const SquircleBorder(borderRadius: AppShape.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: bg,
                    shape: const SquircleBorder(
                      borderRadius: AppShape.radiusLg,
                    ),
                  ),
                  child: SizedBox.square(
                    dimension: 56,
                    child: Icon(icon, size: 24, color: fg),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
