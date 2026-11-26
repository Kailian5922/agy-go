// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:acp_client/acp_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/chat_state.dart';
import '../../state/commands_state.dart';
import '../../state/phone_state.dart';
import '../../state/sessions_state.dart';
import '../../state/settings_state.dart';
import '../../state/system_state.dart';
import '../../state/voice_state.dart';
import '../../state/workspace_state.dart';
import '../../state/workspaces_state.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/expand_reveal.dart';
import '../common/list_page_row.dart';
import '../common/pressable.dart';
import '../common/sheet_navigator.dart';
import '../common/smooth_size.dart';
import '../features/agy_extensions_pages.dart';
import '../shell/drawer_destination.dart';
import '../shell/session_search_page.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_ui.dart';
import 'chat_header.dart';
import 'diff_and_output_page.dart';
import 'permission_controls.dart';

/// Floating 28dp chrome-glass message composer mirroring DSH Go's Composer:
/// - Concentric 36dp `+` button opening nested SheetNavigator PlusPanel (相册/拍照/文件/指令/本对话审批)
/// - Expanding QuoteChip, multimodal attachments strip & queued messages strip
/// - Floating glass `/` SlashPalette (prefix-first + Chinese alias + Skills + PaletteHint) and `@` workspace picker
/// - Voice dictation status & 36dp right circle (mic / primary send / mid-turn steer or queue / stop square)
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
  static final _mentionTriggerRegex = RegExp(
    r'(?:^|[^A-Za-z0-9._+-])[@＠]([^\s@＠]*)$',
  );
  static final _mentionReplaceRegex = RegExp(r'[@＠][^\s@＠]*$');

  TextEditingController? _ownedController;
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _slashActive = false;
  String? _mentionQuery;
  String? _mentionRoot;
  List<MentionCandidate> _mentionCandidates = const [];
  bool _mentionLoading = false;
  int _mentionScanSeq = 0;

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
    String? mention;

    final trimmedLeft = text.trimLeft();
    final slashActive =
        trimmedLeft.startsWith('/') || trimmedLeft.startsWith('／');
    if (!slashActive) {
      final sel = _ctrl.selection.baseOffset;
      final prefix = sel >= 0 && sel <= text.length
          ? text.substring(0, sel)
          : text;
      final m = _mentionTriggerRegex.firstMatch(prefix);
      if (m != null) {
        mention = m.group(1)!.toLowerCase();
      }
    }

    final mentionJustOpened = _mentionQuery == null && mention != null;
    if (has != _hasText ||
        mention != _mentionQuery ||
        slashActive ||
        _slashActive) {
      setState(() {
        _hasText = has;
        _mentionQuery = mention;
        _slashActive = slashActive;
      });
    }
    if (mention != null && (mentionJustOpened || _mentionRoot == null)) {
      _scheduleMentionScan();
    }
  }

  void _scheduleMentionScan() {
    if (!mounted) return;
    if (ref.read(workspaceProvider).isRemote) return;
    final chatCwd = ref.read(chatProvider).sessionCwd;
    final targetRoot = (chatCwd != null && chatCwd.isNotEmpty)
        ? chatCwd
        : ref.read(effectiveWorkingDirProvider);
    if (targetRoot.isEmpty) return;

    final seq = ++_mentionScanSeq;
    final switchingRoot = _mentionRoot != targetRoot;
    _mentionRoot = targetRoot;
    if (switchingRoot) {
      _mentionCandidates = const [];
    }
    if (!_mentionLoading) {
      setState(() => _mentionLoading = true);
    }
    unawaited(
      scanWorkspaceMentionCandidates(targetRoot)
          .catchError((_) => const <MentionCandidate>[])
          .then((items) {
            if (!mounted || _mentionScanSeq != seq) return;
            setState(() {
              _mentionCandidates = items;
              _mentionLoading = false;
            });
          }),
    );
  }

  void _submit() {
    final hasAttachments = ref.read(chatProvider).attachments.isNotEmpty;
    final text = _ctrl.text.trim();
    if (text.isEmpty && !hasAttachments) return;

    // Intercept `/` (and full-width `／`) slash commands before sending to the engine.
    final commands = ref.read(slashCommandsProvider);
    final parsed = parseSlashInput(text);
    if (parsed != null) {
      final exact = resolveSlashCommand(commands, parsed.token);
      if (exact != null) {
        final args = parsed.rest?.trim() ?? '';
        if (exact.kind == SlashCommandKind.app) {
          _ctrl.clear();
          unawaited(_runAppCommand(exact.name, args));
          return;
        }
        if (exact.name == 'plan' && args.isEmpty) {
          _ctrl.clear();
          unawaited(_togglePlanMode());
          return;
        }
      } else if (!parsed.hasArgs && parsed.token.isNotEmpty) {
        // Pressing send with partial `/tok` executes the highlighted top match (DSH Go ergonomics).
        final matches = filterSlashCommands(commands, parsed.token);
        if (matches.isNotEmpty) {
          _pickSlash(matches.first);
          return;
        }
      }
    }

    if (!widget.enabled) return;
    HapticFeedback.lightImpact();
    _ctrl.clear();
    final outgoing = text.startsWith('／') ? '/${text.substring(1)}' : text;
    unawaited(widget.onSend(outgoing));
  }

  Future<void> _togglePlanMode() async {
    final notifier = ref.read(chatProvider.notifier);
    final next = notifier.effectiveAgentMode() == AgyAgentMode.plan
        ? AgyAgentMode.standard
        : AgyAgentMode.plan;
    await notifier.setExecutionMode(next);
    if (mounted) {
      showBriefNotice(
        context,
        next == AgyAgentMode.plan ? '已切换到计划模式（只读规划）' : '已退出计划模式',
      );
    }
  }

  Future<void> _runAppCommand(String name, String args) async {
    switch (name) {
      case 'new' || 'clear':
        ref.read(chatProvider.notifier).startNewChat();
        if (mounted) showBriefNotice(context, '已开启新对话');
      case 'permissions' || 'mode':
        await showApprovalModeSheet(context, ref);
      case 'model':
        await showModelModeSheet(context);
      case 'effort':
        await showModelModeSheet(context, focusEffort: true);
      case 'workspace':
        await showWorkspaceSheet(context, ref);
      case 'add-dir':
        final dir = await showDirectoryPicker(
          context,
          title: '选择额外挂载目录',
          confirmLabel: '挂载到本对话',
        );
        if (dir != null && dir.isNotEmpty && mounted) {
          ref.read(chatProvider.notifier).addAdditionalDirectory(dir);
          showBriefNotice(context, '已挂载额外目录：$dir');
        }
      case 'diff':
        final transcript = ref.read(chatProvider).transcript;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiffViewerPage.fromTranscript(transcript),
          ),
        );
      case 'context' || 'usage' || 'quota':
        await showContextUsageSheet(context, ref);
      case 'resume':
        final id = await showSessionSearch(context);
        if (id != null && mounted) {
          ref.read(sessionsProvider.notifier).selectSession(id);
        }
      case 'files':
        widget.onOpenDestination?.call(DrawerDestination.files);
      case 'terminal':
        widget.onOpenDestination?.call(DrawerDestination.terminal);
      case 'mcp':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const McpServersPage()),
        );
      case 'skills':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SkillsAndRulesPage(initialTab: 0),
          ),
        );
      case 'memory' || 'rules':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SkillsAndRulesPage(initialTab: 1),
          ),
        );
      case 'copy':
        final lastReply = ref
            .read(chatProvider)
            .transcript
            .items
            .whereType<AssistantTranscriptItem>()
            .where((i) => i.text.trim().isNotEmpty)
            .lastOrNull;
        if (lastReply == null) {
          if (mounted) showBriefNotice(context, '当前对话还没有可复制的 AI 回复');
        } else {
          await Clipboard.setData(ClipboardData(text: lastReply.text));
          if (mounted) showBriefNotice(context, '已复制上一条回复');
        }
      case 'rename':
        final sid = ref.read(chatProvider).sessionId;
        if (sid == null) {
          if (mounted) showBriefNotice(context, '请先发送消息创建对话后再重命名');
          return;
        }
        var nextTitle = args.trim();
        if (nextTitle.isEmpty && mounted) {
          final current = ref.read(sessionsProvider).currentSession;
          final currentTitle = current != null
              ? ref.read(sessionsProvider).displayTitle(current)
              : '';
          nextTitle = (await showTextPromptDialog(
                    context,
                    title: '重命名对话',
                    initial: currentTitle,
                    hint: '输入新标题',
                    confirmLabel: '保存',
                  ))
                  ?.trim() ??
              '';
        }
        if (nextTitle.isNotEmpty) {
          await ref.read(sessionsProvider.notifier).renameSession(sid, nextTitle);
          if (mounted) showBriefNotice(context, '已重命名为「$nextTitle」');
        }
      case 'phone':
        widget.onOpenDestination?.call(DrawerDestination.phone);
      case 'share' || 'export':
        widget.onOpenDestination?.call(DrawerDestination.share);
      case 'config' || 'settings':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AgyEngineParamsPage()),
        );
      case 'features':
        widget.onOpenDestination?.call(DrawerDestination.features);
      case 'logout':
        final ok = await ref.read(chatProvider.notifier).logoutAgent();
        if (mounted && ok) showBriefNotice(context, '已断开当前账号登录态');
    }
  }

  void _pickSlash(SlashCommand item) {
    if (item.kind == SlashCommandKind.app && !item.takesInput) {
      _ctrl.clear();
      unawaited(_runAppCommand(item.name, ''));
      return;
    }
    final next = '/${item.name} ';
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _focusNode.requestFocus();
  }

  void _pickMention(MentionCandidate item) {
    final text = _ctrl.text;
    final sel = _ctrl.selection.baseOffset;
    final end = sel >= 0 && sel <= text.length ? sel : text.length;
    final before = text.substring(0, end);
    final after = text.substring(end);
    final refPath = item.isDirectory
        ? '${item.relativePath}/'
        : item.relativePath;
    final formatted = refPath.contains(RegExp(r'\s'))
        ? '@"$refPath" '
        : '@$refPath ';
    final replaced = before.replaceFirst(_mentionReplaceRegex, formatted);
    _ctrl.value = TextEditingValue(
      text: '$replaced$after',
      selection: TextSelection.collapsed(offset: replaced.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _attachFrom(Future<PickedMediaItem?> Function() picker) async {
    final item = await picker();
    if (!mounted || item == null) return;
    ref.read(chatProvider.notifier).addAttachment(
      ChatAttachment(
        id: '${DateTime.now().microsecondsSinceEpoch}-${item.name}',
        name: item.name,
        path: item.path,
        mimeType: item.mimeType,
        sizeBytes: item.sizeBytes,
        bytes: item.bytes,
      ),
    );
  }

  Future<void> _openPlusPanel() async {
    _focusNode.unfocus();
    final choice = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => SheetNavigator(
        root: (_) => const _PlusPanelBody(),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'gallery':
        await _attachFrom(ref.read(systemToolsProvider.notifier).pickImage);
      case 'camera':
        await _attachFrom(ref.read(systemToolsProvider.notifier).capturePhoto);
      case 'pick_file':
        await _attachFrom(ref.read(systemToolsProvider.notifier).pickFile);
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
      case 'add_dir':
        unawaited(_runAppCommand('add-dir', ''));
      case 'usage':
        unawaited(showContextUsageSheet(context, ref));
      case 'phone':
        widget.onOpenDestination?.call(DrawerDestination.phone);
    }
  }

  void _previewAttachment(ChatAttachment item) {
    if (!item.isImage) return;
    unawaited(
      showAppDialog<void>(
        context: context,
        builder: (dialog) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: AppShape.radiusLg,
                child: InteractiveViewer(
                  child: item.bytes != null && item.bytes!.isNotEmpty
                      ? Image.memory(item.bytes!, fit: BoxFit.contain)
                      : Image.file(File(item.path), fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: GlassSurface(
                  tier: GlassTier.chrome,
                  circle: true,
                  onTap: () => Navigator.of(dialog).pop(),
                  child: const SizedBox.square(
                    dimension: 36,
                    child: Icon(AppIcons.close, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceProvider);
    final quoted = ref.watch(chatProvider.select((c) => c.quotedText));
    final attachments = ref.watch(chatProvider.select((c) => c.attachments));
    final queued = ref.watch(chatProvider.select((c) => c.queuedMessages));
    final queuedBehavior = ref.watch(
      settingsProvider.select((s) => s.queuedBehavior),
    );
    final commands = ref.watch(slashCommandsProvider);
    final slashContent = SlashPaletteContent.of(commands, _ctrl.text);

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

    final List<MentionCandidate> mentionMatches;
    final bool mentionLoading;
    if (_mentionQuery == null) {
      mentionMatches = const [];
      mentionLoading = false;
    } else {
      final wsState = ref.watch(workspaceProvider);
      final q = _mentionQuery!;
      final List<MentionCandidate> pool;
      if (wsState.isRemote) {
        pool = [
          for (final e in wsState.entries)
            MentionCandidate(relativePath: e.name, isDirectory: e.isDirectory),
        ];
        mentionLoading = wsState.loading && pool.isEmpty;
      } else {
        final chatCwd = ref.watch(chatProvider.select((c) => c.sessionCwd));
        final activeRoot = (chatCwd != null && chatCwd.isNotEmpty)
            ? chatCwd
            : ref.watch(effectiveWorkingDirProvider);
        if (_mentionRoot != activeRoot && !_mentionLoading) {
          Future.microtask(_scheduleMentionScan);
        }
        pool = _mentionCandidates;
        mentionLoading = _mentionLoading && pool.isEmpty;
      }
      if (q.isEmpty) {
        mentionMatches = pool.take(12).toList();
      } else {
        final prefixHits = <MentionCandidate>[];
        final containsHits = <MentionCandidate>[];
        for (final item in pool) {
          final relLower = item.relativePath.toLowerCase();
          final baseLower = relLower.split('/').last;
          if (baseLower.startsWith(q) || relLower.startsWith(q)) {
            prefixHits.add(item);
          } else if (relLower.contains(q)) {
            containsHits.add(item);
          }
        }
        mentionMatches = [...prefixHits, ...containsHits].take(12).toList();
      }
    }

    const keySize = 36.0;
    const keyGap = 6.0;
    const fontSize = 15.0;
    final line = MediaQuery.textScalerOf(context).scale(fontSize) * 1.45;
    final textPad = math.max(4.0, (keySize - line) / 2);

    final canSubmit = _hasText || attachments.isNotEmpty;
    final showStop = widget.isBusy && !canSubmit && !voice.isListening;
    final showMic = !widget.isBusy && !canSubmit && !voice.isListening;
    final isMidTurnSend = widget.isBusy && canSubmit && !voice.isListening;
    final contextFraction = ref.watch(
      chatProvider.select((c) {
        final u = c.transcript.usage;
        final used = u?.effectiveUsedTokens;
        final size = u?.sizeTokens;
        if (used == null || size == null || size <= 0) return null;
        return (used / size).clamp(0.0, 1.0);
      }),
    );

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
              // Floating `/` SlashPalette (matches or argument hint)
              if (slashContent != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FloatingPopover(
                    child: switch (slashContent) {
                      SlashPaletteMatches(:final commands, :final typed) =>
                        commands.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  '没有匹配的指令（输入 / 查看全部 agy 指令与 Skill）',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: dsh.textTertiary,
                                  ),
                                ),
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 280,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  itemCount: commands.length,
                                  itemBuilder: (ctx, i) {
                                    final item = commands[i];
                                    final highlight = typed && i == 0;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: highlight
                                          ? ShapeDecoration(
                                              color: scheme.primary.withValues(
                                                alpha: 0.12,
                                              ),
                                              shape: Squircle.border(12),
                                            )
                                          : null,
                                      child: ListPageRow(
                                        icon: item.icon,
                                        iconColor: highlight
                                            ? scheme.primary
                                            : null,
                                        title: item.label,
                                        titleNote:
                                            item.kind == SlashCommandKind.skill
                                            ? 'Skill'
                                            : null,
                                        subtitle: item.description,
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '/${item.name}',
                                              style: AppType.monoLabel(
                                                color: highlight
                                                    ? scheme.primary
                                                    : dsh.textTertiary,
                                              ),
                                            ),
                                            if (highlight) ...[
                                              const SizedBox(width: 6),
                                              Icon(
                                                AppIcons.enterKey,
                                                size: 13,
                                                color: scheme.primary,
                                              ),
                                            ],
                                          ],
                                        ),
                                        chevron: false,
                                        onTap: () => _pickSlash(item),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      SlashPaletteHint(:final command) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              command.icon,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '/${command.name}',
                              style: AppType.monoLabel(
                                color: scheme.primary,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                command.hint ?? command.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: dsh.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    },
                  ),
                ),

              // Floating `@` workspace file mention picker
              if (_mentionQuery != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FloatingPopover(
                    child: mentionLoading
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '正在扫描当前工作区文件…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: dsh.textTertiary,
                              ),
                            ),
                          )
                        : mentionMatches.isEmpty
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
                            constraints: const BoxConstraints(maxHeight: 240),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: mentionMatches.length,
                              itemBuilder: (ctx, i) {
                                final item = mentionMatches[i];
                                return ListPageRow(
                                  icon: item.isDirectory
                                      ? AppIcons.folder
                                      : AppIcons.file,
                                  title: item.isDirectory
                                      ? '${item.relativePath}/'
                                      : item.relativePath,
                                  chevron: false,
                                  onTap: () => _pickMention(item),
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

              // Queued mid-turn messages strip (with 1-tap 「立即发送」 & withdraw)
              if (queued.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (idx, msg) in queued.indexed)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: GlassSurface(
                            tier: GlassTier.chrome,
                            stadium: true,
                            child: SizedBox(
                              height: 34,
                              child: Row(
                                children: [
                                  const SizedBox(width: 10),
                                  Icon(
                                    AppIcons.queued,
                                    size: 14,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '排队 #${idx + 1}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      msg,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      unawaited(
                                        ref
                                            .read(chatProvider.notifier)
                                            .sendQueuedNow(idx),
                                      );
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: scheme.primary.withValues(
                                          alpha: 0.14,
                                        ),
                                        shape: const StadiumBorder(),
                                      ),
                                      child: Text(
                                        '立即发送',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => ref
                                        .read(chatProvider.notifier)
                                        .removeQueuedMessage(idx),
                                    behavior: HitTestBehavior.opaque,
                                    child: const SizedBox.square(
                                      dimension: 32,
                                      child: Icon(AppIcons.close, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
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
                        open: attachments.isNotEmpty,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                          child: SizedBox(
                            height: 58,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: attachments.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (ctx, i) {
                                final item = attachments[i];
                                return _AttachmentThumb(
                                  item: item,
                                  onTap: () => _previewAttachment(item),
                                  onRemove: () => ref
                                      .read(chatProvider.notifier)
                                      .removeAttachment(item.id),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
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
                                enabled: widget.enabled || canSubmit,
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
                                  hintText:
                                      widget.hintText ??
                                      (voice.isListening
                                          ? '正在聆听…'
                                          : widget.enabled
                                          ? (widget.isBusy
                                                ? (queuedBehavior ==
                                                          AgyQueuedMessageBehavior
                                                              .steer
                                                      ? '生成中… 发送将立即中断并发送'
                                                      : '生成中… 可排队或切换立即发送')
                                                : '给 Antigravity 发消息，或输入 / 与 @…')
                                          : '连接引擎后发送消息…'),
                                  hintMaxLines: 1,
                                  hintStyle: theme.textTheme.bodyLarge
                                      ?.copyWith(
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
                            if (isMidTurnSend) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: '点击切换「排队」或「立即发送」',
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    final next =
                                        queuedBehavior ==
                                            AgyQueuedMessageBehavior.queue
                                        ? AgyQueuedMessageBehavior.steer
                                        : AgyQueuedMessageBehavior.queue;
                                    unawaited(
                                      ref
                                          .read(settingsProvider.notifier)
                                          .setQueuedBehavior(next),
                                    );
                                  },
                                  child: Container(
                                    height: keySize,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: ShapeDecoration(
                                      color:
                                          queuedBehavior ==
                                              AgyQueuedMessageBehavior.steer
                                          ? scheme.primary.withValues(
                                              alpha: 0.14,
                                            )
                                          : scheme.onSurface.withValues(
                                              alpha: 0.06,
                                            ),
                                      shape: const StadiumBorder(),
                                    ),
                                    child: Text(
                                      queuedBehavior ==
                                              AgyQueuedMessageBehavior.steer
                                          ? '立即'
                                          : '排队',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color:
                                                queuedBehavior ==
                                                    AgyQueuedMessageBehavior
                                                        .steer
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (contextFraction != null &&
                                !isMidTurnSend &&
                                !voice.isListening) ...[
                              const SizedBox(width: 2),
                              ContextRing(
                                fraction: contextFraction,
                                onTap: () => unawaited(
                                  showContextUsageSheet(context, ref),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            // Concentric 36dp Send / Mid-turn Steer-or-Queue / Stop / Mic circle button
                            Pressable(
                              enabled:
                                  showMic ||
                                  showStop ||
                                  voice.isListening ||
                                  canSubmit,
                              child: Material(
                                color: showStop || voice.isListening
                                    ? scheme.primary
                                    : showMic
                                    ? scheme.onSurface.withValues(alpha: 0.06)
                                    : canSubmit
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
                                      : canSubmit
                                      ? _submit
                                      : null,
                                  child: SizedBox.square(
                                    dimension: keySize,
                                    child: Icon(
                                      showStop || voice.isListening
                                          ? AppIcons.stopGenerating
                                          : showMic
                                          ? AppIcons.voice
                                          : isMidTurnSend
                                          ? (queuedBehavior ==
                                                    AgyQueuedMessageBehavior
                                                        .steer
                                                ? AppIcons.send
                                                : AppIcons.queued)
                                          : AppIcons.send,
                                      size: showStop || voice.isListening
                                          ? 16
                                          : 19,
                                      color: showStop || voice.isListening
                                          ? scheme.onPrimary
                                          : showMic
                                          ? scheme.onSurfaceVariant
                                          : canSubmit
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

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final ChatAttachment item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dsh = DshColors.of(context);

    if (item.isImage) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.square(
                dimension: 54,
                child: item.bytes != null && item.bytes!.isNotEmpty
                    ? Image.memory(item.bytes!, fit: BoxFit.cover)
                    : Image.file(
                        File(item.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: const Icon(AppIcons.imageBroken, size: 20),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: scheme.inverseSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.close,
                  size: 12,
                  color: scheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 168),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: ShapeDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        shape: Squircle.border(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.file, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(AppIcons.close, size: 14, color: dsh.textTertiary),
            ),
          ),
        ],
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
    final settings = ref.watch(settingsProvider);
    final chat = ref.watch(chatProvider);
    final phoneOn = ref.watch(phoneControlProvider.select((p) => p.enabled));
    final dsh = DshColors.of(context);

    final activeMode = chat.sessionAgentMode ?? settings.agentMode;
    final activePerm = chat.sessionToolPermission ?? settings.toolPermission;
    final planOn = activeMode == AgyAgentMode.plan;
    final modeSummary = planOn
        ? '计划模式 · ${activePerm.label}'
        : activePerm.label;

    final primaryTiles = [
      ('gallery', AppIcons.gallery, '相册', 1),
      ('camera', AppIcons.camera, '拍照', 3),
      ('pick_file', AppIcons.fileNew, '附件', 4),
      ('slash', AppIcons.command, '指令 /', 0),
    ];

    final secondaryTiles = [
      ('mention', AppIcons.mention, '引用 @', 2),
      ('files', AppIcons.files, '工作区文件', 5),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                spacing: 8,
                children: [
                  for (final (id, icon, label, tint) in primaryTiles)
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                spacing: 8,
                children: [
                  for (final (id, icon, label, tint) in secondaryTiles)
                    Expanded(
                      child: _PlusTile(
                        icon: icon,
                        label: label,
                        tint: tint,
                        compact: true,
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
                  icon: activePerm.isHighRisk
                      ? AppIcons.permissionRisky
                      : AppIcons.permissions,
                  iconColor: activePerm.isHighRisk ? dsh.danger : null,
                  title: '权限层级',
                  subtitle: modeSummary,
                  subtitleColor: activePerm.isHighRisk ? dsh.danger : null,
                  onTap: () => SheetNavigator.of(context).push(
                    (_) => const ApprovalModeSheetBody(),
                  ),
                ),
                ListPageRow(
                  icon: AppIcons.planMode,
                  title: '计划模式 (Plan)',
                  subtitle: planOn ? '已开启：只读调研，先出方案再执行' : '先调研并生成可审核的实施方案',
                  trailing: Switch.adaptive(
                    value: planOn,
                    onChanged: (v) => unawaited(
                      ref
                          .read(chatProvider.notifier)
                          .setExecutionMode(
                            v ? AgyAgentMode.plan : AgyAgentMode.standard,
                          ),
                    ),
                  ),
                  onTap: () => unawaited(
                    ref
                        .read(chatProvider.notifier)
                        .setExecutionMode(
                          planOn ? AgyAgentMode.standard : AgyAgentMode.plan,
                        ),
                  ),
                ),
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
                  icon: AppIcons.newFolder,
                  title: '挂载额外目录 (--add-dir)',
                  value: chat.additionalDirectories.isEmpty
                      ? null
                      : '${chat.additionalDirectories.length} 个',
                  onTap: () => Navigator.of(context).pop('add_dir'),
                ),
                ListPageRow(
                  icon: AppIcons.diagnostics,
                  title: '订阅额度与上下文 (/usage)',
                  subtitle: '查看 5 小时 / 周剩余额度与上下文占用',
                  onTap: () => Navigator.of(context).pop('usage'),
                ),
                ListPageRow(
                  icon: AppIcons.phoneControl,
                  title: '手机操控 (MCP)',
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
                  onTap: () => Navigator.of(context).pop('phone'),
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
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final int tint;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final bg = dsh.identity[tint % dsh.identity.length];
    final fg = dsh.onIdentity[tint % dsh.onIdentity.length];
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Pressable(
      child: Material(
        color: bg.withValues(alpha: dark ? 0.35 : 0.65),
        shape: const RoundedSuperellipseBorder(borderRadius: AppShape.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: compact ? 10 : 14,
              horizontal: 6,
            ),
            child: compact
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 17, color: fg),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 22, color: fg),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w600,
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
