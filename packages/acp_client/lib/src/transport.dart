import 'dart:async';
import 'dart:convert';

import 'errors.dart';

/// Pluggable duplex JSON-RPC 2.0 transport for ACP (`agy acp` stdio, loopback socket, SSH exec).
abstract class AcpTransport {
  /// Short label for diagnostics (`loopback`, `ssh`, `memory`, ...).
  String get kind;

  /// Incoming decoded JSON-RPC objects (requests, responses, notifications).
  Stream<Map<String, Object?>> get incoming;

  /// Optional diagnostic lines emitted on stderr (not JSON-RPC frames).
  Stream<String> get stderrLines => const Stream.empty();

  /// Sends one JSON-RPC message object (serialized as a single NDJSON line).
  Future<void> send(Map<String, Object?> message);

  /// Closes the transport and releases underlying sockets/processes. Idempotent.
  Future<void> close();
}

/// NDJSON (`\n`-delimited UTF-8 JSON) framing adapter over raw byte streams.
///
/// Works identically for SSH exec channels, local TCP loopback sockets, or stdio pipes.
class LineStreamAcpTransport extends AcpTransport {
  LineStreamAcpTransport({
    required this.kind,
    required Stream<List<int>> inputBytes,
    required Future<void> Function(List<int> bytes) writeBytes,
    required Future<void> Function() onClose,
    Stream<List<int>>? stderrBytes,
    void Function(String nonJsonLine)? onNonJsonLine,
  }) : _writeBytes = writeBytes,
       _onClose = onClose,
       _onNonJsonLine = onNonJsonLine {
    _inSub = inputBytes
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: (Object error, StackTrace stack) {
            if (!_incoming.isClosed) {
              _incoming.addError(
                AcpTransportException('Transport read failed', cause: error),
                stack,
              );
            }
          },
          onDone: () {
            if (!_incoming.isClosed) unawaited(_incoming.close());
          },
        );

    if (stderrBytes != null) {
      _errSub = stderrBytes
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (!_stderr.isClosed) _stderr.add(line);
            },
            onError: (_) {},
            onDone: () {
              if (!_stderr.isClosed) unawaited(_stderr.close());
            },
          );
    }
  }

  @override
  final String kind;

  final Future<void> Function(List<int> bytes) _writeBytes;
  final Future<void> Function() _onClose;
  final void Function(String nonJsonLine)? _onNonJsonLine;

  final _incoming = StreamController<Map<String, Object?>>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  late final StreamSubscription<String> _inSub;
  StreamSubscription<String>? _errSub;
  bool _closed = false;

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  void _handleLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) return;
    if (!trimmed.startsWith('{')) {
      // Some shells / banners print plain text before JSON-RPC starts; route to stderr/callback.
      _onNonJsonLine?.call(rawLine);
      if (!_stderr.isClosed) _stderr.add(rawLine);
      return;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        if (!_incoming.isClosed) {
          _incoming.add(Map<String, Object?>.from(decoded));
        }
      } else {
        _onNonJsonLine?.call(rawLine);
      }
    } catch (_) {
      _onNonJsonLine?.call(rawLine);
      if (!_stderr.isClosed) _stderr.add(rawLine);
    }
  }

  @override
  Future<void> send(Map<String, Object?> message) async {
    if (_closed) {
      throw const AcpTransportException('Cannot send on a closed transport');
    }
    final payload = '${jsonEncode(message)}\n';
    try {
      await _writeBytes(utf8.encode(payload));
    } catch (e) {
      throw AcpTransportException('Transport write failed', cause: e);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inSub.cancel();
    await _errSub?.cancel();
    try {
      await _onClose();
    } catch (_) {}
    if (!_incoming.isClosed) await _incoming.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}

/// Connected pair of in-memory [AcpTransport] endpoints for deterministic tests.
class MemoryAcpTransport extends AcpTransport {
  MemoryAcpTransport._(this._incoming, this._peerIncoming);

  final StreamController<Map<String, Object?>> _incoming;
  final StreamController<Map<String, Object?>> _peerIncoming;
  bool _closed = false;

  static (MemoryAcpTransport client, MemoryAcpTransport agent) pair() {
    final toClient = StreamController<Map<String, Object?>>.broadcast();
    final toAgent = StreamController<Map<String, Object?>>.broadcast();
    return (
      MemoryAcpTransport._(toClient, toAgent),
      MemoryAcpTransport._(toAgent, toClient),
    );
  }

  @override
  String get kind => 'memory';

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  @override
  Future<void> send(Map<String, Object?> message) async {
    if (_closed || _peerIncoming.isClosed) {
      throw const AcpTransportException('Memory transport closed');
    }
    // Round-trip through JSON to enforce true wire fidelity in tests.
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(message)) as Map<String, dynamic>,
    );
    _peerIncoming.add(copy);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_incoming.isClosed) await _incoming.close();
    if (!_peerIncoming.isClosed) await _peerIncoming.close();
  }
}
