import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_state.dart';
import 'workspaces_state.dart';

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

  bool get hidden => name.startsWith('.');
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
/// workspace (including mounted phone storage) or the active remote SSH host (via SFTP).
class WorkspaceController extends Notifier<WorkspaceState> {
  SftpClient? _sftp;

  @override
  WorkspaceState build() {
    final conn = ref.watch(activeConnectionProvider).value;
    final root = ref.watch(effectiveWorkingDirProvider);

    _sftp?.close();
    _sftp = null;
    ref.onDispose(() {
      _sftp?.close();
      _sftp = null;
    });

    final isRemote = conn != null && conn.sshConnection != null;
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

  /// Lists subdirectories at any path (for the DSH Go DirectoryBrowserPage).
  Future<List<WorkspaceEntry>> listSubdirectories(String path) async {
    final entries = state.isRemote
        ? await _listRemote(path)
        : await _listLocal(path, createIfMissing: false);
    final dirs = entries.where((e) => e.isDirectory).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return dirs;
  }

  /// Creates a subdirectory inside an arbitrary parent path (for DirectoryBrowserPage).
  Future<String> createSubdirectoryAt(String parentPath, String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.contains('/')) {
      throw ArgumentError('无效文件夹名称');
    }
    final target = _join(parentPath, clean);
    if (state.isRemote) {
      final sftp = await _requireSftp();
      await sftp.mkdir(target);
    } else {
      await Directory(target).create(recursive: true);
    }
    return target;
  }

  Future<void> openDirectory(String path) async {
    if (!ref.mounted) return;
    state = state.copyWith(currentPath: path, loading: true, clearError: true);
    try {
      final list = state.isRemote
          ? await _listRemote(path)
          : await _listLocal(path, createIfMissing: path == state.rootPath);
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
    await createSubdirectoryAt(state.currentPath, clean);
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

  Future<List<WorkspaceEntry>> _listLocal(
    String path, {
    required bool createIfMissing,
  }) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      if (createIfMissing) {
        await dir.create(recursive: true);
      } else {
        throw FileSystemException('目录不存在或无访问权限', path);
      }
    }
    final result = <WorkspaceEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      try {
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
      } catch (_) {
        // Skip unreadable entries (e.g. Android/data restricted dirs).
      }
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

/// One candidate returned by `@` file-mention autocomplete.
class MentionCandidate {
  const MentionCandidate({
    required this.relativePath,
    required this.isDirectory,
  });

  final String relativePath;
  final bool isDirectory;
}

const _mentionSkipDirs = <String>{
  '.git',
  '.dart_tool',
  'node_modules',
  'build',
  '.gradle',
  '__pycache__',
  '.idea',
  '.vscode',
};

/// Bounded breadth-first scan of [rootPath] so `@` finds both top-level and nested
/// workspace files quickly without stalling on huge trees or restricted Android folders.
Future<List<MentionCandidate>> scanWorkspaceMentionCandidates(
  String rootPath, {
  int maxDepth = 3,
  int maxEntries = 200,
}) async {
  final cleanRoot = rootPath.endsWith('/') && rootPath.length > 1
      ? rootPath.substring(0, rootPath.length - 1)
      : rootPath;
  if (cleanRoot.isEmpty) return const [];
  final rootDir = Directory(cleanRoot);
  if (!await rootDir.exists()) return const [];

  final results = <MentionCandidate>[];
  final queue = <(Directory, String, int)>[(rootDir, '', 0)];

  while (queue.isNotEmpty && results.length < maxEntries) {
    final (dir, prefix, depth) = queue.removeAt(0);
    final children = <FileSystemEntity>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        children.add(entity);
      }
    } catch (_) {
      continue;
    }

    children.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final entity in children) {
      if (results.length >= maxEntries) break;
      final name = entity.path.split('/').last;
      if (name.isEmpty) continue;
      final isDir = entity is Directory;
      if (isDir && _mentionSkipDirs.contains(name)) continue;
      if (name.startsWith('.') && name != '.env' && name != '.gitignore') continue;

      final rel = prefix.isEmpty ? name : '$prefix/$name';
      results.add(MentionCandidate(relativePath: rel, isDirectory: isDir));
      if (isDir && depth + 1 < maxDepth) {
        queue.add((entity, rel, depth + 1));
      }
    }
  }

  return results;
}

