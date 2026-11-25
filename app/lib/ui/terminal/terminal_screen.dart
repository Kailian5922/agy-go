import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../state/connection_state.dart';
import '../../state/runtime_state.dart';
import '../shell/page_frame.dart';

/// Embedded interactive terminal using xterm (connects to SSH PTY or local Android `/system/bin/sh`).
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

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  Future<void> _attach() async {
    final conn = ref.read(activeConnectionProvider).value;
    if (conn != null && conn.sshConnection != null) {
      _terminal.write('Connecting SSH shell on ${conn.label}...\r\n');
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
        _terminal.write('SSH shell failed: $e\r\n');
      }
    }

    // Local Android workspace shell fallback
    final runtime = ref.read(localRuntimeProvider).status;
    final cwd = runtime.workspacePath;
    _terminal.write('Starting local shell (${cwd ?? Directory.current.path})...\r\n');
    try {
      final shellBin = File('/system/bin/sh').existsSync()
          ? '/system/bin/sh'
          : '/bin/sh';
      final proc = await Process.start(
        shellBin,
        const [],
        workingDirectory: cwd != null && Directory(cwd).existsSync() ? cwd : null,
        environment: {
          if (runtime.homePath != null) 'HOME': runtime.homePath!,
        },
      );
      _localShell = proc;
      _subs.add(
        proc.stdout.listen((bytes) {
          _terminal.write(utf8.decode(bytes, allowMalformed: true).replaceAll('\n', '\r\n'));
        }),
      );
      _subs.add(
        proc.stderr.listen((bytes) {
          _terminal.write(utf8.decode(bytes, allowMalformed: true).replaceAll('\n', '\r\n'));
        }),
      );
      _terminal.onOutput = (data) {
        final normalized = data == '\r' ? '\n' : data;
        proc.stdin.add(utf8.encode(normalized));
        _terminal.write(data == '\r' ? '\r\n' : data);
      };
    } catch (e) {
      _terminal.write('Unable to start local shell: $e\r\n');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _sshShell?.close();
    _localShell?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgyPage(
      title: '终端',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: TerminalView(
            _terminal,
            autofocus: true,
            padding: const EdgeInsets.all(10),
          ),
        ),
      ),
    );
  }
}
