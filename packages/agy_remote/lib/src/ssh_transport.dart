import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acp_client/acp_client.dart';
import 'package:dartssh2/dartssh2.dart';

import 'host_config.dart';

/// Raised when an SSH host presents an unpinned or mismatched host key.
final class SshHostKeyException extends AcpTransportException {
  const SshHostKeyException({
    required this.host,
    required this.keyType,
    required this.fingerprint,
    required this.expectedFingerprint,
  }) : super(
         expectedFingerprint == null
             ? 'Unknown SSH host key for $host ($keyType $fingerprint)'
             : 'SSH host key mismatch for $host: got $fingerprint, expected $expectedFingerprint',
       );

  final String host;
  final String keyType;
  final String fingerprint;
  final String? expectedFingerprint;
}

/// Callback invoked when a host has no pinned fingerprint yet.
/// Return `true` to trust and proceed (caller should persist the fingerprint).
typedef UnknownHostKeyCallback =
    FutureOr<bool> Function(String keyType, String fingerprint);

/// Holds a live SSH connection and its `agy acp` stdio transport.
class SshAcpConnection {
  SshAcpConnection._({
    required this.sshClient,
    required this.execSession,
    required this.transport,
    required this.resolvedWorkingDirectory,
    required this.verifiedFingerprint,
    required this.agyCommand,
  });

  final SSHClient sshClient;
  final SSHSession execSession;
  final AcpTransport transport;
  final String resolvedWorkingDirectory;
  final String? verifiedFingerprint;
  final String agyCommand;

  /// Opens an interactive PTY shell over the same SSH connection (for embedded xterm).
  Future<SSHSession> openShell({int width = 80, int height = 24}) {
    return sshClient.shell(
      pty: SSHPtyConfig(width: width, height: height),
    );
  }

  /// Runs `agy -p /usage --output-format json` on the remote host to fetch 5h & weekly quota.
  Future<String> fetchQuotaJson({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final cmd = buildRemoteQuotaCommand(agyCommand);
    final raw = await sshClient.run(cmd).timeout(timeout);
    return utf8.decode(raw, allowMalformed: true);
  }

  Future<void> close() async {
    await transport.close();
    execSession.close();
    sshClient.close();
  }

  /// Connects via SSH, verifies host key, resolves default cwd, and spawns `agy acp`.
  static Future<SshAcpConnection> connect({
    required SshHostConfig config,
    required SshHostSecrets secrets,
    UnknownHostKeyCallback? onUnknownHostKey,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: timeout,
      );
    } catch (e) {
      throw AcpTransportException(
        'SSH connection to ${config.host}:${config.port} failed',
        cause: e,
      );
    }

    String? observedFingerprint;
    SshHostKeyException? hostKeyError;

    List<SSHKeyPair>? identities;
    if (config.authMethod == SshAuthMethod.privateKey) {
      final pem = secrets.privateKeyPem?.trim() ?? '';
      if (pem.isEmpty) {
        socket.destroy();
        throw const AcpTransportException('SSH private key is not configured');
      }
      try {
        identities = SSHKeyPair.fromPem(pem, secrets.passphrase);
      } catch (e) {
        socket.destroy();
        throw AcpTransportException('Invalid SSH private key or passphrase', cause: e);
      }
    }

    final client = SSHClient(
      socket,
      username: config.username,
      identities: identities,
      onPasswordRequest: config.authMethod == SshAuthMethod.password
          ? () => secrets.password ?? ''
          : null,
      onVerifyHostKey: (String type, Uint8List fingerprintBytes) async {
        final fp = formatHostKeyFingerprint(type, fingerprintBytes);
        observedFingerprint = fp;
        final pinned = config.pinnedHostKeySha256;
        if (pinned != null && pinned.isNotEmpty) {
          if (pinned == fp) return true;
          hostKeyError = SshHostKeyException(
            host: config.host,
            keyType: type,
            fingerprint: fp,
            expectedFingerprint: pinned,
          );
          return false;
        }
        if (onUnknownHostKey != null) {
          final allowed = await onUnknownHostKey(type, fp);
          if (!allowed) {
            hostKeyError = SshHostKeyException(
              host: config.host,
              keyType: type,
              fingerprint: fp,
              expectedFingerprint: null,
            );
          }
          return allowed;
        }
        // Fail closed when neither pinned nor interactively confirmed.
        hostKeyError = SshHostKeyException(
          host: config.host,
          keyType: type,
          fingerprint: fp,
          expectedFingerprint: null,
        );
        return false;
      },
      keepAliveInterval: const Duration(seconds: 20),
    );

    try {
      await client.authenticated.timeout(timeout);
    } catch (e) {
      client.close();
      if (hostKeyError != null) throw hostKeyError!;
      throw AcpTransportException('SSH authentication failed for ${config.authority}', cause: e);
    }

    // Resolve remote home / working directory before spawning `agy acp`.
    var cwd = config.workingDirectory?.trim() ?? '';
    if (cwd.isEmpty || cwd == '~') {
      try {
        final rawHome = await client.run('printf %s "\$HOME"').timeout(
          const Duration(seconds: 8),
        );
        final resolved = String.fromCharCodes(rawHome).trim();
        cwd = resolved.isNotEmpty ? resolved : '/';
      } catch (_) {
        cwd = '/';
      }
    } else if (cwd.startsWith('~/')) {
      try {
        final rawHome = await client.run('printf %s "\$HOME"').timeout(
          const Duration(seconds: 8),
        );
        final resolved = String.fromCharCodes(rawHome).trim();
        if (resolved.isNotEmpty) {
          cwd = '$resolved/${cwd.substring(2)}';
        }
      } catch (_) {}
    }

    final command = buildRemoteAcpCommand(config.agyCommand);
    final SSHSession session;
    try {
      session = await client.execute(command).timeout(timeout);
    } catch (e) {
      client.close();
      throw AcpTransportException(
        'Failed to launch remote "$command" on ${config.authority}',
        cause: e,
      );
    }

    final transport = LineStreamAcpTransport(
      kind: 'ssh',
      inputBytes: session.stdout,
      stderrBytes: session.stderr,
      writeBytes: (bytes) async {
        session.stdin.add(Uint8List.fromList(bytes));
      },
      onClose: () async {
        session.close();
        client.close();
      },
    );

    return SshAcpConnection._(
      sshClient: client,
      execSession: session,
      transport: transport,
      resolvedWorkingDirectory: cwd,
      verifiedFingerprint: observedFingerprint,
      agyCommand: config.agyCommand,
    );
  }

  /// Formats an SSH host key fingerprint deterministically for pinning.
  static String formatHostKeyFingerprint(String type, Uint8List bytes) {
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
    return '$type:$hex';
  }

  /// Builds a POSIX-safe shell command that ensures `~/.local/bin` is on PATH and execs `agy acp`.
  static String buildRemoteAcpCommand(String agyCommand) {
    final trimmed = agyCommand.trim().isEmpty ? 'agy' : agyCommand.trim();
    final quoted = "'${trimmed.replaceAll("'", "'\\''")}'";
    return 'export PATH="\$HOME/.local/bin:\$HOME/.gemini/antigravity-cli/bin:/usr/local/bin:\$PATH"; '
        'exec $quoted acp';
  }

  /// Builds a POSIX-safe command to fetch Antigravity 5h & weekly quota JSON on demand.
  static String buildRemoteQuotaCommand(String agyCommand) {
    final trimmed = agyCommand.trim().isEmpty ? 'agy' : agyCommand.trim();
    final quoted = "'${trimmed.replaceAll("'", "'\\''")}'";
    return 'export PATH="\$HOME/.local/bin:\$HOME/.gemini/antigravity-cli/bin:/usr/local/bin:\$PATH"; '
        'AGY_CLI_DISABLE_AUTO_UPDATE=true NO_BROWSER=1 $quoted -p /usage --output-format json </dev/null';
  }
}
