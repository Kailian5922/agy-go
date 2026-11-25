import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_state.dart';
import 'runtime_state.dart';

class WorkspaceEntry {
  const WorkspaceEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedAt,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedAt;
}

class WorkspaceState {
  const WorkspaceState({
    this.currentPath = '',
    this.rootPath = '',
    this.entries = const [],
    this.loading = false,
    this.isRemote = false,
    this.error,
  });

  final String currentPath;
  final String rootPath;
  final List<WorkspaceEntry> entries;
  final bool loading;
  final bool isRemote;
  final String? error;

  bool get canGoUp =>
      currentPath.isNotEmpty &&
      currentPath != '/' &&
      currentPath != rootPath;

  WorkspaceState copyWith({
    String? currentPath,
    String? rootPath,
    List<WorkspaceEntry>? entries,
    bool? loading,
    bool? isRemote,
    String? error,
    bool clearError = false,
  }) => WorkspaceState(
    currentPath: currentPath ?? this.currentPath,
    rootPath: rootPath ?? this.rootPath,
    entries: entries ?? this.entries,
    loading: loading ?? this.loading,
    isRemote: isRemote ?? this.isRemote,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Browses, reads, edits, creates, and deletes files in either the on-device Android
/// workspace or the active remote SSH host (via SFTP).
class WorkspaceController extends Notifier<WorkspaceState> {
  SftpClient? _sftp;

  @override
  WorkspaceState build() {
    final conn = ref.watch(activeConnectionProvider).value;
    final runtime = ref.watch(localRuntimeProvider).status;

    _sftp?.close();
    _sftp = null;
    ref.onDispose(() {
      _sftp?.close();
      _sftp = null;
    });

    final isRemote = conn != null && conn.sshConnection != null;
    final root = isRemote
        ? conn.defaultCwd
        : (runtime.workspacePath ?? Directory.current.path);

    Future.microtask(() => openDirectory(root));
    return WorkspaceState(
      currentPath: root,
      rootPath: root,
      isRemote: isRemote,
      loading: true,
    );
  }

  Future<SftpClient> _requireSftp() async {
    final existing = _sftp;
    if (existing != null) return existing;
    final conn = ref.read(activeConnectionProvider).value;
    final ssh = conn?.sshConnection?.sshClient;
    if (ssh == null) {
      throw StateError('SSH connection is not active');
    }
    final client = await ssh.sftp();
    _sftp = client;
    return client;
  }

  Future<void> openDirectory(String path) async {
    if (!ref.mounted) return;
    state = state.copyWith(currentPath: path, loading: true, clearError: true);
    try {
      final list = state.isRemote
          ? await _listRemote(path)
          : await _listLocal(path);
      list.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!ref.mounted) return;
      state = state.copyWith(entries: list, loading: false, clearError: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refresh() => openDirectory(state.currentPath);

  Future<void> goUp() async {
    final cur = state.currentPath;
    if (!state.canGoUp) return;
    final idx = cur.lastIndexOf('/');
    final parent = idx <= 0 ? '/' : cur.substring(0, idx);
    await openDirectory(parent);
  }

  Future<String> readTextFile(String path) async {
    if (state.isRemote) {
      final sftp = await _requireSftp();
      final file = await sftp.open(path);
      try {
        final bytes = await file.readBytes();
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        await file.close();
      }
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeTextFile(String path, String content) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (state.isRemote) {
      final sftp = await _requireSftp();
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.writeBytes(bytes);
      } finally {
        await file.close();
      }
    } else {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    await refresh();
  }

  Future<void> createDirectory(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.contains('/')) return;
    final target = _join(state.currentPath, clean);
    if (state.isRemote) {
      final sftp = await _requireSftp();
      await sftp.mkdir(target);
    } else {
      await Directory(target).create(recursive: true);
    }
    await refresh();
  }

  Future<void> createFile(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.contains('/')) return;
    final target = _join(state.currentPath, clean);
    await writeTextFile(target, '');
  }

  Future<void> deleteEntry(WorkspaceEntry entry) async {
    if (state.isRemote) {
      final sftp = await _requireSftp();
      if (entry.isDirectory) {
        await sftp.rmdir(entry.path);
      } else {
        await sftp.remove(entry.path);
      }
    } else {
      if (entry.isDirectory) {
        await Directory(entry.path).delete(recursive: true);
      } else {
        await File(entry.path).delete();
      }
    }
    await refresh();
  }

  Future<List<WorkspaceEntry>> _listLocal(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final result = <WorkspaceEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final stat = await entity.stat();
      final name = entity.path.split('/').last;
      if (name.isEmpty) continue;
      result.add(
        WorkspaceEntry(
          name: name,
          path: entity.path,
          isDirectory: stat.type == FileSystemEntityType.directory,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    return result;
  }

  Future<List<WorkspaceEntry>> _listRemote(String path) async {
    final sftp = await _requireSftp();
    final items = await sftp.listdir(path);
    final result = <WorkspaceEntry>[];
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final isDir = item.attr.isDirectory;
      result.add(
        WorkspaceEntry(
          name: item.filename,
          path: _join(path, item.filename),
          isDirectory: isDir,
          sizeBytes: item.attr.size ?? 0,
          modifiedAt: item.attr.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
              : null,
        ),
      );
    }
    return result;
  }

  static String _join(String base, String name) =>
      base.endsWith('/') ? '$base$name' : '$base/$name';
}

final workspaceProvider =
    NotifierProvider<WorkspaceController, WorkspaceState>(
      WorkspaceController.new,
    );
