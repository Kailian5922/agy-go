// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../../state/connection_state.dart';
import '../../state/runtime_state.dart';
import '../../state/workspaces_state.dart';
import '../common/brief_notice.dart';
import '../common/segmented_pill.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';

enum _TerminalMode { local, ssh }

/// Embedded interactive terminal using xterm:
/// - Supports switching between Local Android Shell (with `agy` `binDir` on `PATH`) and SSH PTY
/// - Mobile terminal shortcut toolbar (`Esc`, `Tab`, `Ctrl+C`, arrows, `|`, `/`, `~`, `粘贴`)
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _terminal = Terminal(maxLines: 5000);
  SSHSession? _sshShell;
  Process? _localShell;
  final _subs = <StreamSubscription<Object?>>[];
  _TerminalMode _mode = _TerminalMode.local;

  @override
  void initState() {
    super.initState();
    final conn = ref.read(activeConnectionProvider).value;
    _mode = conn?.sshConnection != null ? _TerminalMode.ssh : _TerminalMode.local;
    unawaited(_attach(_mode));
  }

  Future<void> _detach() async {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _sshShell?.close();
    _sshShell = null;
    _localShell?.kill();
    _localShell = null;
    _terminal.onOutput = null;
    _terminal.onResize = null;
  }

  Future<void> _switchMode(_TerminalMode next) async {
    if (_mode == next) return;
    setState(() => _mode = next);
    await _detach();
    _terminal.write('\r\n--- 切换终端会话 ---\r\n');
    await _attach(next);
  }

  Future<void> _attach(_TerminalMode mode) async {
    final conn = ref.read(activeConnectionProvider).value;
    if (mode == _TerminalMode.ssh && conn != null && conn.sshConnection != null) {
      _terminal.write('正在连接 SSH 终端 (${conn.label})...\r\n');
      try {
        final shell = await conn.sshConnection!.openShell();
        _sshShell = shell;
        _subs.add(
          shell.stdout.listen((bytes) {
            _terminal.write(utf8.decode(bytes, allowMalformed: true));
          }),
        );
        _subs.add(
          shell.stderr.listen((bytes) {
            _terminal.write(utf8.decode(bytes, allowMalformed: true));
          }),
        );
        _terminal.onOutput = (data) {
          shell.stdin.add(Uint8List.fromList(utf8.encode(data)));
        };
        _terminal.onResize = (w, h, pw, ph) {
          shell.resizeTerminal(w, h, pw, ph);
        };
        return;
      } catch (e) {
        _terminal.write('SSH 终端启动失败：$e\r\n');
        return;
      }
    }

    final runtime = ref.read(localRuntimeProvider).status;
    final cwd = ref.read(effectiveWorkingDirProvider);
    _terminal.write('本机 Shell · 工作区: $cwd\r\n');
    if (runtime.binPath != null && runtime.binPath!.isNotEmpty) {
      _terminal.write('已将 agy 加入 PATH，可直接输入 agy --version 等命令。\r\n');
    }
    try {
      final shellBin = File('/system/bin/sh').existsSync()
          ? '/system/bin/sh'
          : '/bin/sh';
      final sysPath =
          Platform.environment['PATH'] ?? '/system/bin:/system/xbin:/bin';
      final env = <String, String>{
        if (runtime.homePath != null && runtime.homePath!.isNotEmpty)
          'HOME': runtime.homePath!,
        'PATH': runtime.binPath != null && runtime.binPath!.isNotEmpty
            ? '${runtime.binPath}:$sysPath'
            : sysPath,
        'TERM': 'xterm-256color',
      };
      final proc = await Process.start(
        shellBin,
        const [],
        workingDirectory: Directory(cwd).existsSync() ? cwd : null,
        environment: env,
      );
      _localShell = proc;
      _subs.add(
        proc.stdout.listen((bytes) {
          _terminal.write(
            utf8.decode(bytes, allowMalformed: true).replaceAll('\n', '\r\n'),
          );
        }),
      );
      _subs.add(
        proc.stderr.listen((bytes) {
          _terminal.write(
            utf8.decode(bytes, allowMalformed: true).replaceAll('\n', '\r\n'),
          );
        }),
      );
      _terminal.onOutput = (data) {
        final normalized = data == '\r' ? '\n' : data;
        proc.stdin.add(utf8.encode(normalized));
        // Local /system/bin/sh is non-PTY so echo printable input cleanly.
        if (data == '\x03') {
          _terminal.write('^C\r\n');
        } else if (data == '\r') {
          _terminal.write('\r\n');
        } else if (data == '\x7f' || data == '\b') {
          _terminal.write('\b \b');
        } else if (data.codeUnits.every((c) => c >= 32 || c == 9)) {
          _terminal.write(data);
        }
      };
    } catch (e) {
      _terminal.write('无法启动本机 Shell：$e\r\n');
    }
  }

  void _sendRaw(String seq) {
    HapticFeedback.selectionClick();
    _terminal.onOutput?.call(seq);
  }

  Future<void> _pasteClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text;
    if (text == null || text.isEmpty) {
      if (mounted) showBriefNotice(context, '剪贴板为空');
      return;
    }
    _sendRaw(text);
  }

  @override
  void dispose() {
    unawaited(_detach());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSsh = ref.watch(
      activeConnectionProvider.select((c) => c.value?.sshConnection != null),
    );
    final top = math.max(MediaQuery.paddingOf(context).top, 8.0);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottomInset = keyboard > 0 ? keyboard : bottom;
    final scheme = Theme.of(context).colorScheme;

    const shortcuts = <(String, String)>[
      ('Esc', '\x1b'),
      ('Tab', '\t'),
      ('Ctrl+C', '\x03'),
      ('↑', '\x1b[A'),
      ('↓', '\x1b[B'),
      ('←', '\x1b[D'),
      ('→', '\x1b[C'),
      ('|', '|'),
      ('/', '/'),
      ('~', '~'),
      ('-', '-'),
    ];

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  top + 60,
                  12,
                  bottomInset + 54,
                ),
                child: ClipRRect(
                  borderRadius: AppShape.radiusLg,
                  child: TerminalView(
                    _terminal,
                    autofocus: true,
                    padding: const EdgeInsets.all(10),
                  ),
                ),
              ),
            ),
            // Floating mobile shortcut key bar
            Positioned(
              left: 12,
              right: 12,
              bottom: bottomInset + 8,
              height: 40,
              child: GlassSurface(
                tier: GlassTier.chrome,
                borderRadius: AppShape.radiusMd,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  children: [
                    for (final (label, seq) in shortcuts)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _TermKeyChip(
                          label: label,
                          danger: label == 'Ctrl+C',
                          onTap: () => _sendRaw(seq),
                        ),
                      ),
                    _TermKeyChip(
                      label: '粘贴',
                      onTap: () => unawaited(_pasteClipboard()),
                    ),
                  ],
                ),
              ),
            ),
            // Floating glass top toolbar with Local / SSH toggle
            Positioned(
              left: 12,
              right: 12,
              top: top,
              height: 56,
              child: BackdropGroup(
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: AppIcons.back,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Center(
                        child: hasSsh
                            ? SizedBox(
                                width: 220,
                                child: SegmentedPill<_TerminalMode>(
                                  selected: _mode,
                                  onChanged: (m) => unawaited(_switchMode(m)),
                                  segments: const [
                                    PillSegment(_TerminalMode.local, '本机 Shell'),
                                    PillSegment(_TerminalMode.ssh, 'SSH 终端'),
                                  ],
                                ),
                              )
                            : Text(
                                '本机终端',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: scheme.onSurface),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: AppIcons.restart,
                      tooltip: '重启当前终端',
                      onPressed: () async {
                        await _detach();
                        _terminal.write('\r\n--- 已重启终端 ---\r\n');
                        await _attach(_mode);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermKeyChip extends StatelessWidget {
  const _TermKeyChip({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dsh = DshColors.of(context);
    return Material(
      color: danger
          ? dsh.danger.withValues(alpha: 0.14)
          : scheme.onSurface.withValues(alpha: 0.06),
      shape: Squircle.border(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Center(
            child: Text(
              label,
              style: AppType.monoLabel(
                color: danger ? dsh.danger : scheme.onSurface,
              ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
