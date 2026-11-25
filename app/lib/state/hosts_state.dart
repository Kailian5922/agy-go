import 'dart:async';
import 'dart:convert';

import 'package:agy_remote/agy_remote.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_state.dart';

class HostsState {
  const HostsState({
    this.loaded = false,
    this.active = const HostRef.local(),
    this.sshHosts = const [],
  });

  final bool loaded;
  final HostRef active;
  final List<SshHostConfig> sshHosts;

  SshHostConfig? sshById(String id) {
    for (final h in sshHosts) {
      if (h.id == id) return h;
    }
    return null;
  }

  String activeLabel() {
    if (active.isLocal) return '本机引擎';
    final ssh = sshById(active.id);
    return ssh != null ? '${ssh.name} · SSH' : 'SSH 远程';
  }

  HostsState copyWith({
    bool? loaded,
    HostRef? active,
    List<SshHostConfig>? sshHosts,
  }) => HostsState(
    loaded: loaded ?? this.loaded,
    active: active ?? this.active,
    sshHosts: sshHosts ?? this.sshHosts,
  );
}

class HostsController extends Notifier<HostsState> {
  static const _kHosts = 'agy.sshHosts';
  static const _kActive = 'agy.activeHost';

  @override
  HostsState build() {
    unawaited(_load());
    return const HostsState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getString(_kHosts);
      final hosts = <SshHostConfig>[];
      if (rawList != null && rawList.isNotEmpty) {
        final decoded = jsonDecode(rawList);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            hosts.add(SshHostConfig.fromJson(Map<String, Object?>.from(item)));
          }
        }
      }

      HostRef active = const HostRef.local();
      final rawActive = prefs.getString(_kActive);
      if (rawActive != null && rawActive.isNotEmpty) {
        final parsed = HostRef.fromJson(
          Map<String, Object?>.from(jsonDecode(rawActive) as Map),
        );
        if (parsed.isLocal || hosts.any((h) => h.id == parsed.id)) {
          active = parsed;
        }
      }

      state = HostsState(loaded: true, active: active, sshHosts: hosts);
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> selectHost(HostRef host) async {
    if (state.active == host) return;
    state = state.copyWith(active: host);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActive, jsonEncode(host.toJson()));
  }

  Future<void> saveSshHost(
    SshHostConfig config, {
    SshHostSecrets? secrets,
  }) async {
    final next = List<SshHostConfig>.from(state.sshHosts);
    final idx = next.indexWhere((h) => h.id == config.id);
    if (idx >= 0) {
      next[idx] = config;
    } else {
      next.add(config);
    }
    state = state.copyWith(sshHosts: next);
    await _persistList(next);

    if (secrets != null) {
      final storage = ref.read(secureStorageProvider);
      if (secrets.password != null) {
        await storage.write(
          key: _secretKey(config.id, 'password'),
          value: secrets.password,
        );
      }
      if (secrets.privateKeyPem != null) {
        await storage.write(
          key: _secretKey(config.id, 'key'),
          value: secrets.privateKeyPem,
        );
      }
      if (secrets.passphrase != null) {
        await storage.write(
          key: _secretKey(config.id, 'passphrase'),
          value: secrets.passphrase,
        );
      }
    }
  }

  Future<void> pinHostKey(String hostId, String fingerprint) async {
    final existing = state.sshById(hostId);
    if (existing == null) return;
    await saveSshHost(existing.copyWith(pinnedHostKeySha256: fingerprint));
  }

  Future<void> deleteSshHost(String hostId) async {
    final next = state.sshHosts.where((h) => h.id != hostId).toList();
    final nextActive =
        (!state.active.isLocal && state.active.id == hostId)
            ? const HostRef.local()
            : state.active;
    state = state.copyWith(sshHosts: next, active: nextActive);
    await _persistList(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActive, jsonEncode(nextActive.toJson()));
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _secretKey(hostId, 'password'));
    await storage.delete(key: _secretKey(hostId, 'key'));
    await storage.delete(key: _secretKey(hostId, 'passphrase'));
  }

  Future<SshHostSecrets> loadSecrets(String hostId) async {
    final storage = ref.read(secureStorageProvider);
    return SshHostSecrets(
      password: await storage.read(key: _secretKey(hostId, 'password')),
      privateKeyPem: await storage.read(key: _secretKey(hostId, 'key')),
      passphrase: await storage.read(key: _secretKey(hostId, 'passphrase')),
    );
  }

  Future<void> _persistList(List<SshHostConfig> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kHosts,
      jsonEncode([for (final h in list) h.toJson()]),
    );
  }

  static String _secretKey(String id, String field) => 'agy.ssh.$id.$field';
}

final hostsProvider = NotifierProvider<HostsController, HostsState>(
  HostsController.new,
);
