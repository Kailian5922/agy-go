// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:acp_client/acp_client.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../share/conversation_export.dart';
import '../../state/chat_state.dart';
import '../../state/hosts_state.dart';
import '../../state/system_state.dart';
import '../common/app_dialog.dart';
import '../common/brief_notice.dart';
import '../common/settings_widgets.dart';
import '../shell/brand_mark.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

/// Share cards (PNG), redacted Markdown/JSON export, and local replay viewer.
class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  final _cardKey = GlobalKey();
  bool _capturing = false;
  ChatTranscript? _replaying;
  int _replayStep = 0;

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final hosts = ref.watch(hostsProvider);
    final transcript = _replaying ?? chat.transcript;
    final surfaces = DshSurfaces.of(context);
    final dsh = DshColors.of(context);
    final theme = Theme.of(context);

    final visibleItems = _replaying != null
        ? transcript.items
              .take(_replayStep.clamp(0, transcript.items.length))
              .toList()
        : transcript.items;

    return AppPage.list(
      title: _replaying != null ? '对话回放' : '分享与回放',
      subtitle: const Text('所有导出内容均自动脱敏密钥与个人凭据'),
      actions: [
        if (_replaying != null)
          GlassIconButton(
            icon: AppIcons.close,
            tooltip: '退出回放',
            onPressed: () => setState(() => _replaying = null),
          ),
      ],
      children: [
        if (_replaying != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: GlassSurface(
              tier: GlassTier.card,
              borderRadius: AppShape.radiusLg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      '回放进度：$_replayStep / ${transcript.items.length}',
                      style: AppType.tabular(theme.textTheme.labelLarge!),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(AppIcons.pagePrevious, size: 18),
                      onPressed: _replayStep > 1
                          ? () => setState(() => _replayStep--)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(AppIcons.pageNext, size: 18),
                      onPressed: _replayStep < transcript.items.length
                          ? () => setState(() => _replayStep++)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: RepaintBoundary(
            key: _cardKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: ShapeDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [surfaces.backdropTop, surfaces.backdropBottom],
                ),
                shape: AppShape.outlined(surfaces.card.hairline, radius: 22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AgyBrandMark(
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          transcript.title?.isNotEmpty == true
                              ? transcript.title!
                              : 'AGY Go 对话分享卡',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        hosts.activeLabel(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: dsh.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  if (visibleItems.isEmpty)
                    Text(
                      '当前会话暂无内容，发起对话或导入回放 JSON 后即可生成分享卡。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dsh.textTertiary,
                      ),
                    )
                  else
                    for (final item in visibleItems.take(6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: switch (item) {
                          UserTranscriptItem(:final text) => Align(
                            alignment: Alignment.centerRight,
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                color: surfaces.userBubble,
                                shape: AppShape.bubble,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Text(
                                  ConversationExport.redactSecrets(text),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: surfaces.onUserBubble,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AssistantTranscriptItem(
                            :final text,
                            :final toolCalls,
                          ) =>
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (toolCalls.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '执行了 ${toolCalls.length} 次工具调用',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: dsh.textTertiary),
                                    ),
                                  ),
                                Text(
                                  ConversationExport.redactSecrets(text),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                        },
                      ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(AppIcons.redacted, size: 13, color: dsh.success),
                      const SizedBox(width: 4),
                      Text(
                        'Generated by AGY Go · 已自动脱敏凭据',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: dsh.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SettingsSection(
          title: '导出与回放',
          children: [
            SettingsTile(
              icon: AppIcons.shareImage,
              tint: 0,
              title: _capturing ? '正在生成 PNG…' : '生成 PNG 分享卡',
              subtitle: '高清渲染并调用系统分享',
              onTap: _capturing ? null : _sharePngCard,
            ),
            SettingsTile(
              icon: AppIcons.shareText,
              tint: 4,
              title: '复制脱敏 Markdown',
              onTap: () {
                final md = ConversationExport.toMarkdown(
                  transcript,
                  hostLabel: hosts.activeLabel(),
                );
                Clipboard.setData(ClipboardData(text: md));
                showBriefNotice(context, '已复制脱敏 Markdown');
              },
            ),
            SettingsTile(
              icon: AppIcons.shareBundle,
              tint: 2,
              title: '导出回放包 JSON',
              subtitle: 'agy-go-replay/v1 格式',
              onTap: () async {
                final jsonText = ConversationExport.toReplayJson(
                  transcript,
                  hostLabel: hosts.activeLabel(),
                );
                try {
                  await ref.read(systemToolsProvider.notifier).shareBytes(
                    bytes: Uint8List.fromList(utf8.encode(jsonText)),
                    filename: 'agy-replay.json',
                    mimeType: 'application/json',
                    title: '导出 AGY Go 对话回放',
                  );
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: jsonText));
                  if (context.mounted) {
                    showBriefNotice(context, '已复制 JSON 回放包');
                  }
                }
              },
            ),
            SettingsTile(
              icon: AppIcons.replay,
              tint: 5,
              title: '导入 JSON 回放',
              subtitle: '粘贴回放包逐步重演对话过程',
              onTap: _importReplayDialog,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _sharePngCard() async {
    setState(() => _capturing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      await ref.read(systemToolsProvider.notifier).shareBytes(
        bytes: data.buffer.asUint8List(),
        filename: 'agy-share-card.png',
        mimeType: 'image/png',
        title: '分享 AGY Go 对话卡',
      );
    } catch (e) {
      if (mounted) showBriefNotice(context, '分享卡生成失败: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _importReplayDialog() async {
    final ctrl = TextEditingController();
    final raw = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入对话回放 JSON'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '粘贴 agy-go-replay/v1 格式的 JSON…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('开始回放'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (raw == null || raw.isEmpty) return;
    try {
      final parsed = ConversationExport.parseReplayJson(raw);
      setState(() {
        _replaying = parsed;
        _replayStep = parsed.items.isEmpty ? 0 : 1;
      });
    } catch (e) {
      if (mounted) showBriefNotice(context, '无法解析回放包: $e');
    }
  }
}
