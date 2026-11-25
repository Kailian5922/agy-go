enum HostLinkPhase {
  idle,
  connecting,
  connected,
  reconnecting,
  failed,
}

class HostLinkStatus {
  const HostLinkStatus({
    required this.phase,
    this.detail,
    this.error,
  });

  static const idle = HostLinkStatus(phase: HostLinkPhase.idle);

  final HostLinkPhase phase;
  final String? detail;
  final String? error;

  bool get isConnected => phase == HostLinkPhase.connected;
}
