import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:agy_remote/agy_remote.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hosts_state.dart';
import 'runtime_state.dart';

/// Unified active connection to either the on-device Android runtime or a remote SSH host.
class HostConnection {
  const HostConnection({
    required this.host,
    required this.label,
    required this.client,
    required this.initResult,
    required this.defaultCwd,
    this.sshConnection,
  });

  final HostRef host;
  final String label;
  final AcpClient client;
  final AcpInitializeResult initResult;
  final String defaultCwd;

  /// Non-null only for SSH hosts; lets the Terminal screen reuse the live SSH link.
  final SshAcpConnection? sshConnection;

  bool get isLocal => host.isLocal;

  Future<void> close() async {
    await client.close();
    await sshConnection?.close();
  }
}

class ActiveConnectionController extends AsyncNotifier<HostConnection?> {
  @override
  Future<HostConnection?> build() async {
    final hosts = ref.watch(hostsProvider);
    if (!hosts.loaded) return null;
    final activeHost = hosts.active;

    if (activeHost.isLocal) {
      return _connectLocal();
    }
    final sshConfig = hosts.sshById(activeHost.id);
    if (sshConfig == null) return null;
    return _connectSsh(sshConfig);
  }

  Future<HostConnection?> _connectLocal() async {
    final endpoint = ref.watch(
      localRuntimeProvider.select((s) {
        final st = s.status;
        return st.isRunning
            ? (st.port, st.token, st.workspacePath)
            : (null, null, null);
      }),
    );
    final (port, token, workspacePath) = endpoint;
    if (port == null || token == null) return null;

    final transport = await LoopbackAcpTransport.connect(
      port: port,
      token: token,
    );
    final client = AcpClient(transport);
    try {
      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.local(),
        label: '本机引擎',
        client: client,
        initResult: init,
        defaultCwd: workspacePath ?? '/data/local/tmp',
      );
      ref.onDispose(() => unawaited(conn.close()));
      return conn;
    } catch (e) {
      await client.close();
      rethrow;
    }
  }

  Future<HostConnection?> _connectSsh(SshHostConfig config) async {
    final hostsCtrl = ref.read(hostsProvider.notifier);
    final secrets = await hostsCtrl.loadSecrets(config.id);
    final ssh = await SshAcpConnection.connect(
      config: config,
      secrets: secrets,
      // On first connect without a pinned key, pin the observed key automatically on explicit connect.
      onUnknownHostKey: (type, fingerprint) async {
        await hostsCtrl.pinHostKey(config.id, fingerprint);
        return true;
      },
    );
    final client = AcpClient(ssh.transport);
    try {
      final init = await client.initialize();
      final conn = HostConnection(
        host: HostRef.ssh(config.id),
        label: '${config.name} · SSH',
        client: client,
        initResult: init,
        defaultCwd: ssh.resolvedWorkingDirectory,
        sshConnection: ssh,
      );
      ref.onDispose(() => unawaited(conn.close()));
      return conn;
    } catch (e) {
      await client.close();
      await ssh.close();
      rethrow;
    }
  }

  void reconnect() {
    ref.invalidateSelf();
  }
}

final activeConnectionProvider =
    AsyncNotifierProvider<ActiveConnectionController, HostConnection?>(
      ActiveConnectionController.new,
    );
