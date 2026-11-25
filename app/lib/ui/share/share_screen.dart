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
import '../shell/page_frame.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Share cards (PNG), redacted Markdown/JSON export, and local conversation replay viewer.
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
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    final visibleItems = _replaying != null
        ? transcript.items.take(_replayStep.clamp(0, transcript.items.length)).toList()
        : transcript.items;

    return AgyPage(
      title: _replaying != null ? '对话回放' : '分享卡与导出回放',
      actions: [
        if (_replaying != null)
          TextButton(
            onPressed: () => setState(() => _replaying = null),
            child: const Text('退出回放'),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          if (_replaying != null) ...[
            HairlineCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    '回放进度：$_replayStep / ${transcript.items.length}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: _replayStep > 1
                        ? () => setState(() => _replayStep--)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: _replayStep < transcript.items.length
                        ? () => setState(() => _replayStep++)
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Visual frosted share card preview captured to high-DPI PNG
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [surfaces.bgTop, surfaces.bgBottom],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: surfaces.hairline, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.rocket_launch_rounded,
                        size: 18,
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
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        hosts.activeLabel(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: surfaces.subtleText,
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
                        color: surfaces.subtleText,
                      ),
                    )
                  else
                    for (final item in visibleItems.take(6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: switch (item) {
                          UserTranscriptItem(:final text) => Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              ConversationExport.redactSecrets(text),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          AssistantTranscriptItem(:final text, :final toolCalls) =>
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (toolCalls.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '执行了 ${toolCalls.length} 次工具调用',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: surfaces.subtleText,
                                      ),
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
                  const SizedBox(height: 6),
                  Text(
                    'Generated by AGY Go · 已自动脱敏密钥与凭据',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: surfaces.subtleText,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _capturing ? null : _sharePngCard,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(_capturing ? '生成中…' : '生成 PNG 分享卡'),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  final md = ConversationExport.toMarkdown(
                    transcript,
                    hostLabel: hosts.activeLabel(),
                  );
                  Clipboard.setData(ClipboardData(text: md));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制脱敏后的 Markdown 对话')),
                  );
                },
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('复制 Markdown'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
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
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制 JSON 回放包到剪贴板')),
                    );
                  }
                },
                icon: const Icon(Icons.data_object_rounded, size: 18),
                label: const Text('导出回放 JSON'),
              ),
              OutlinedButton.icon(
                onPressed: _importReplayDialog,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('导入 JSON 回放'),
              ),
            ],
          ),
        ],
      ),
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
      final bytes = data.buffer.asUint8List();
      await ref.read(systemToolsProvider.notifier).shareBytes(
        bytes: bytes,
        filename: 'agy-share-card.png',
        mimeType: 'image/png',
        title: '分享 AGY Go 对话卡',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享卡生成失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _importReplayDialog() async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入对话回放 JSON'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '粘贴 agy-go-replay/v1 格式的 JSON 内容…',
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法解析回放包: $e')),
      );
    }
  }
}
