enum HostKind {
  local,
  ssh;

  static HostKind parse(String? raw) =>
      raw == 'ssh' ? HostKind.ssh : HostKind.local;
}

/// Identifies the currently active host (either the on-device Android runtime or a saved SSH host).
class HostRef {
  const HostRef.local() : kind = HostKind.local, id = 'local';
  const HostRef.ssh(this.id) : kind = HostKind.ssh;

  factory HostRef.fromJson(Map<String, Object?> json) {
    final kind = HostKind.parse(json['kind'] as String?);
    if (kind == HostKind.ssh && json['id'] is String) {
      return HostRef.ssh(json['id']! as String);
    }
    return const HostRef.local();
  }

  final HostKind kind;
  final String id;

  bool get isLocal => kind == HostKind.local;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'id': id,
  };

  @override
  bool operator ==(Object other) =>
      other is HostRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

enum SshAuthMethod {
  password,
  privateKey;

  static SshAuthMethod parse(String? raw) =>
      raw == 'privateKey' ? SshAuthMethod.privateKey : SshAuthMethod.password;
}

/// Non-secret metadata for a remote SSH host running Antigravity CLI (`agy`).
///
/// Passwords and private keys are stored separately in secure storage via [SshHostSecrets].
class SshHostConfig {
  const SshHostConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = SshAuthMethod.password,
    this.workingDirectory,
    this.agyCommand = 'agy',
    this.pinnedHostKeySha256,
  });

  factory SshHostConfig.fromJson(Map<String, Object?> json) => SshHostConfig(
    id: json['id']! as String,
    name: json['name'] as String? ?? json['host']! as String,
    host: json['host']! as String,
    port: (json['port'] as num?)?.toInt() ?? 22,
    username: json['username']! as String,
    authMethod: SshAuthMethod.parse(json['authMethod'] as String?),
    workingDirectory: json['workingDirectory'] as String?,
    agyCommand: (json['agyCommand'] as String?)?.trim().isNotEmpty == true
        ? json['agyCommand']! as String
        : 'agy',
    pinnedHostKeySha256: json['pinnedHostKeySha256'] as String?,
  );

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;

  /// Default remote workspace directory passed as `cwd` to `session/new`.
  final String? workingDirectory;

  /// Remote CLI binary path or command name (defaults to `agy`).
  final String agyCommand;

  /// Pinned SHA-256 fingerprint (`SHA256:...`) verified on SSH handshake.
  final String? pinnedHostKeySha256;

  String get authority => port == 22 ? '$username@$host' : '$username@$host:$port';

  SshHostConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthMethod? authMethod,
    String? workingDirectory,
    String? agyCommand,
    String? pinnedHostKeySha256,
    bool clearPinnedKey = false,
  }) => SshHostConfig(
    id: id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    authMethod: authMethod ?? this.authMethod,
    workingDirectory: workingDirectory ?? this.workingDirectory,
    agyCommand: agyCommand ?? this.agyCommand,
    pinnedHostKeySha256: clearPinnedKey
        ? null
        : (pinnedHostKeySha256 ?? this.pinnedHostKeySha256),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'authMethod': authMethod.name,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
    'agyCommand': agyCommand,
    if (pinnedHostKeySha256 != null) 'pinnedHostKeySha256': pinnedHostKeySha256,
  };
}

class SshHostSecrets {
  const SshHostSecrets({
    this.password,
    this.privateKeyPem,
    this.passphrase,
  });

  final String? password;
  final String? privateKeyPem;
  final String? passphrase;
}
