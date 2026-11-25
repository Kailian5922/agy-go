/// Errors raised by the ACP transport or JSON-RPC layer.
sealed class AcpException implements Exception {
  const AcpException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// JSON-RPC error returned by the ACP agent.
final class AcpRpcException extends AcpException {
  const AcpRpcException({
    required this.code,
    required String message,
    this.data,
    this.method,
  }) : super(message);

  /// Standard ACP error: authentication is required before creating sessions.
  static const int authRequiredCode = -32000;

  /// Standard ACP error: session not found / unknown session.
  static const int unknownSessionCode = -32002;

  /// Standard JSON-RPC method not found.
  static const int methodNotFoundCode = -32601;

  /// Standard ACP request cancelled error.
  static const int cancelledCode = -32800;

  final int code;
  final Object? data;
  final String? method;

  bool get isAuthRequired => code == authRequiredCode;
  bool get isUnknownSession => code == unknownSessionCode;
  bool get isMethodNotFound => code == methodNotFoundCode;
  bool get isCancelled => code == cancelledCode;

  @override
  String toString() =>
      'AcpRpcException(code: $code, method: $method, message: $message)';
}

/// Underlying transport failed, closed unexpectedly, or timed out.
base class AcpTransportException extends AcpException {
  const AcpTransportException(super.message, {this.cause});

  final Object? cause;

  @override
  String toString() =>
      cause == null ? 'AcpTransportException: $message' : 'AcpTransportException: $message ($cause)';
}

/// Wire framing or schema violation from the peer.
final class AcpProtocolException extends AcpException {
  const AcpProtocolException(super.message);
}
