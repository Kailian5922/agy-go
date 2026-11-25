import 'dart:async';

import 'errors.dart';
import 'transport.dart';

typedef JsonRpcRequestHandler =
    FutureOr<Map<String, Object?>> Function(Map<String, Object?> params);
typedef JsonRpcNotificationHandler = void Function(Map<String, Object?> params);

/// Bidirectional JSON-RPC 2.0 peer running over an [AcpTransport].
class AcpJsonRpcPeer {
  AcpJsonRpcPeer(this.transport) {
    _sub = transport.incoming.listen(
      _onMessage,
      onError: _onTransportError,
      onDone: _onTransportDone,
    );
  }

  final AcpTransport transport;

  int _nextId = 1;
  bool _closed = false;
  late final StreamSubscription<Map<String, Object?>> _sub;

  final _pending = <Object, _PendingCall>{};
  final _requestHandlers = <String, JsonRpcRequestHandler>{};
  final _notificationHandlers = <String, JsonRpcNotificationHandler>{};
  final _closedCompleter = Completer<void>();

  bool get isClosed => _closed;
  Future<void> get done => _closedCompleter.future;

  /// Registers a handler for incoming JSON-RPC requests from the peer (e.g. `session/request_permission`).
  void onRequest(String method, JsonRpcRequestHandler handler) {
    _requestHandlers[method] = handler;
  }

  /// Registers a handler for incoming JSON-RPC notifications (e.g. `session/update`).
  void onNotification(String method, JsonRpcNotificationHandler handler) {
    _notificationHandlers[method] = handler;
  }

  /// Sends a JSON-RPC request and awaits its response.
  Future<Map<String, Object?>> sendRequest(
    String method, [
    Map<String, Object?>? params,
    Duration? timeout,
  ]) async {
    if (_closed) {
      throw AcpTransportException('Peer is closed (method: $method)');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = _PendingCall(method, completer);

    final envelope = <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    try {
      await transport.send(envelope);
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }

    if (timeout == null) {
      return completer.future;
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw AcpTransportException(
          'Request "$method" timed out after ${timeout.inMilliseconds}ms',
        );
      },
    );
  }

  /// Sends a fire-and-forget JSON-RPC notification.
  Future<void> sendNotification(
    String method, [
    Map<String, Object?>? params,
  ]) async {
    if (_closed) {
      throw AcpTransportException('Peer is closed (notification: $method)');
    }
    await transport.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    });
  }

  void _onMessage(Map<String, Object?> msg) {
    final hasId = msg.containsKey('id') && msg['id'] != null;
    final method = msg['method'];

    if (method is String) {
      final rawParams = msg['params'];
      final params = rawParams is Map
          ? Map<String, Object?>.from(rawParams)
          : const <String, Object?>{};
      if (hasId) {
        unawaited(_dispatchIncomingRequest(msg['id']!, method, params));
      } else {
        final handler = _notificationHandlers[method];
        if (handler != null) {
          try {
            handler(params);
          } catch (_) {
            // Isolate notification handler errors from the transport loop.
          }
        }
      }
      return;
    }

    if (hasId) {
      final pending = _pending.remove(msg['id']!);
      if (pending == null) return;
      if (msg['error'] is Map) {
        final err = Map<String, Object?>.from(msg['error']! as Map);
        final code = (err['code'] as num?)?.toInt() ?? -32603;
        final message = err['message']?.toString() ?? 'Unknown JSON-RPC error';
        pending.completer.completeError(
          AcpRpcException(
            code: code,
            message: message,
            data: err['data'],
            method: pending.method,
          ),
        );
      } else {
        final result = msg['result'];
        pending.completer.complete(
          result is Map
              ? Map<String, Object?>.from(result)
              : const <String, Object?>{},
        );
      }
    }
  }

  Future<void> _dispatchIncomingRequest(
    Object id,
    String method,
    Map<String, Object?> params,
  ) async {
    final handler = _requestHandlers[method];
    if (handler == null) {
      await _safeSend(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': AcpRpcException.methodNotFoundCode,
          'message': 'Method not implemented by client: $method',
        },
      });
      return;
    }

    try {
      final result = await handler(params);
      await _safeSend(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      });
    } on AcpRpcException catch (e) {
      await _safeSend(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': e.code,
          'message': e.message,
          if (e.data != null) 'data': e.data,
        },
      });
    } catch (e) {
      await _safeSend(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': -32603,
          'message': e.toString(),
        },
      });
    }
  }

  Future<void> _safeSend(Map<String, Object?> message) async {
    if (_closed) return;
    try {
      await transport.send(message);
    } catch (_) {}
  }

  void _onTransportError(Object error, StackTrace stack) {
    _failAllPending(
      error is AcpException
          ? error
          : AcpTransportException('Transport error', cause: error),
    );
  }

  void _onTransportDone() {
    _closed = true;
    _failAllPending(const AcpTransportException('ACP connection closed'));
    if (!_closedCompleter.isCompleted) _closedCompleter.complete();
  }

  void _failAllPending(AcpException error) {
    if (_pending.isEmpty) return;
    final calls = _pending.values.toList();
    _pending.clear();
    for (final call in calls) {
      if (!call.completer.isCompleted) {
        call.completer.completeError(error);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    await transport.close();
    _failAllPending(const AcpTransportException('ACP peer closed'));
    if (!_closedCompleter.isCompleted) _closedCompleter.complete();
  }
}

class _PendingCall {
  _PendingCall(this.method, this.completer);
  final String method;
  final Completer<Map<String, Object?>> completer;
}
