import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/glass_widgets.dart';

/// Floating frosted-glass message composer bar with send and cancel controls.
class ComposerBar extends StatefulWidget {
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
  State<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<ComposerBar> {
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
    final surfaces = AgySurfaces.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
      ),
    );
  }
}
