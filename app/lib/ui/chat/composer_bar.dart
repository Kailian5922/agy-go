import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/voice_state.dart';
import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Floating frosted-glass message composer bar with voice input, send, and cancel controls.
class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({
    super.key,
    required this.enabled,
    required this.isBusy,
    required this.onSend,
    required this.onCancel,
    this.hintText,
  });

  final bool enabled;
  final bool isBusy;
  final Future<void> Function(String text) onSend;
  final VoidCallback onCancel;
  final String? hintText;

  @override
  ConsumerState<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends ConsumerState<ComposerBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.enabled || widget.isBusy) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceProvider);
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    ref.listen<String?>(
      voiceProvider.select((v) => v.lastFinalTranscript),
      (prev, next) {
        if (next != null && next.isNotEmpty && next != prev) {
          final existing = _controller.text.trim();
          _controller.text = existing.isEmpty ? next : '$existing $next';
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
          ref.read(voiceProvider.notifier).consumeFinalTranscript();
        }
      },
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (voice.isListening || voice.partialTranscript.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
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
            GlassSurface(
              borderRadius: BorderRadius.circular(24),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconButton(
                      tooltip: voice.isListening ? '停止语音输入' : '语音输入',
                      onPressed: () =>
                          ref.read(voiceProvider.notifier).toggleListening(),
                      icon: Icon(
                        voice.isListening
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        size: 21,
                        color: voice.isListening
                            ? surfaces.danger
                            : surfaces.subtleText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: widget.hintText ??
                            (widget.enabled
                                ? '给 Antigravity 下达指令，或输入 / 命令…'
                                : '请先安装并启动本机引擎，或连接 SSH 主机'),
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: surfaces.subtleText,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: widget.isBusy
                        ? IconButton.filled(
                            onPressed: widget.onCancel,
                            tooltip: '停止生成',
                            style: IconButton.styleFrom(
                              backgroundColor: surfaces.danger,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.stop_rounded, size: 20),
                          )
                        : IconButton.filled(
                            onPressed: widget.enabled && _hasText ? _submit : null,
                            tooltip: '发送',
                            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
