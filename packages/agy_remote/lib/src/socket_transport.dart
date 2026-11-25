import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_client/acp_client.dart';

/// Connects to the Android ForegroundService loopback TCP bridge hosting `agy acp`.
///
/// Protocol on the loopback socket:
/// 1. Client writes one auth line: `{"auth":"<token>"}\n`
/// 2. Bridge responds with one line: `{"ok":true}\n` or `{"ok":false,"error":"..."}\n`
/// 3. Thereafter the socket carries raw NDJSON ACP JSON-RPC 2.0 frames.
class LoopbackAcpTransport {
  LoopbackAcpTransport._();

  static Future<AcpTransport> connect({
    String host = '127.0.0.1',
    required int port,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } catch (e) {
      throw AcpTransportException(
        'Unable to reach local AGY runtime bridge at $host:$port',
        cause: e,
      );
    }

    final byteStream = socket.asBroadcastStream();
    final authCompleter = Completer<void>();
    final pendingAfterAuth = StreamController<List<int>>();
    var authed = false;
    final headerBuf = <int>[];

    late final StreamSubscription<List<int>> sub;
    sub = byteStream.listen(
      (chunk) {
        if (authed) {
          if (!pendingAfterAuth.isClosed) pendingAfterAuth.add(chunk);
          return;
        }
        final nl = chunk.indexOf(0x0A);
        if (nl < 0) {
          headerBuf.addAll(chunk);
          return;
        }
        headerBuf.addAll(chunk.sublist(0, nl));
        final line = utf8.decode(headerBuf, allowMalformed: true).trim();
        headerBuf.clear();
        try {
          final map = jsonDecode(line);
          if (map is Map && map['ok'] == true) {
            authed = true;
            if (!authCompleter.isCompleted) authCompleter.complete();
            if (nl + 1 < chunk.length && !pendingAfterAuth.isClosed) {
              pendingAfterAuth.add(chunk.sublist(nl + 1));
            }
          } else {
            final reason = map is Map ? map['error']?.toString() : line;
            if (!authCompleter.isCompleted) {
              authCompleter.completeError(
                AcpTransportException('Bridge auth rejected: $reason'),
              );
            }
          }
        } catch (e) {
          if (!authCompleter.isCompleted) {
            authCompleter.completeError(
              AcpTransportException('Invalid bridge auth response: $line', cause: e),
            );
          }
        }
      },
      onError: (Object err, StackTrace st) {
        if (!authCompleter.isCompleted) {
          authCompleter.completeError(
            AcpTransportException('Bridge socket error during auth', cause: err),
            st,
          );
        } else if (!pendingAfterAuth.isClosed) {
          pendingAfterAuth.addError(err, st);
        }
      },
      onDone: () {
        if (!authCompleter.isCompleted) {
          authCompleter.completeError(
            const AcpTransportException('Bridge closed connection before auth completed'),
          );
        }
        if (!pendingAfterAuth.isClosed) unawaited(pendingAfterAuth.close());
      },
    );

    socket.add(utf8.encode('${jsonEncode({'auth': token})}\n'));
    await socket.flush();

    try {
      await authCompleter.future.timeout(timeout);
    } catch (e) {
      await sub.cancel();
      socket.destroy();
      unawaited(pendingAfterAuth.close());
      if (e is AcpException) rethrow;
      throw AcpTransportException('Bridge auth handshake failed', cause: e);
    }

    return LineStreamAcpTransport(
      kind: 'loopback',
      inputBytes: pendingAfterAuth.stream,
      writeBytes: (bytes) async {
        socket.add(bytes);
        await socket.flush();
      },
      onClose: () async {
        await sub.cancel();
        socket.destroy();
        if (!pendingAfterAuth.isClosed) await pendingAfterAuth.close();
      },
    );
  }
}
