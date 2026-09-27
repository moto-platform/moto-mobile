import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/session_meta.dart';
import 'session_recorder.dart' show DocumentsDirProvider, resolveSessionsRootDir;

/// Read-only view of one recorded session's directory, combining `meta.json`
/// and `summary.json` (either may be missing, e.g. a session that crashed
/// mid-recording before `stop()` ran).
class SessionInfo {
  final String sessionId;
  final Directory dir;
  final SessionMeta? meta;
  final Map<String, dynamic>? summary;

  const SessionInfo({
    required this.sessionId,
    required this.dir,
    this.meta,
    this.summary,
  });

  DateTime? get createdUtc {
    final raw = meta?.createdUtc;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Duration? get duration {
    final ms = summary?['duration_ms'] as int?;
    return ms == null ? null : Duration(milliseconds: ms);
  }

  int? get packetCount => summary?['packet_count'] as int?;

  double? get lossPercent => (summary?['loss_percent'] as num?)?.toDouble();
}

/// Lists, shares and deletes recorded ride sessions from
/// `<documents>/sessions/`.
class SessionStore {
  SessionStore({DocumentsDirProvider? documentsDirProvider})
      : _documentsDirProvider = documentsDirProvider ?? getApplicationDocumentsDirectory;

  final DocumentsDirProvider _documentsDirProvider;

  Future<Directory> rootDir() => resolveSessionsRootDir(_documentsDirProvider);

  /// Lists all sessions on disk, newest first (session ids sort
  /// chronologically because they start with `YYYYMMDD-HHMMSS`).
  Future<List<SessionInfo>> listSessions() async {
    final root = await rootDir();
    if (!await root.exists()) return [];

    final entries = <SessionInfo>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final sessionId = entity.path.split(Platform.pathSeparator).last;

      SessionMeta? meta;
      final metaFile = File('${entity.path}/meta.json');
      if (await metaFile.exists()) {
        try {
          meta = SessionMeta.fromJson(jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>);
        } catch (_) {
          // Corrupt/partial meta.json: still list the session by directory name.
        }
      }

      Map<String, dynamic>? summary;
      final summaryFile = File('${entity.path}/summary.json');
      if (await summaryFile.exists()) {
        try {
          summary = jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          // Corrupt/partial summary.json: leave live numbers unavailable.
        }
      }

      entries.add(SessionInfo(sessionId: sessionId, dir: entity, meta: meta, summary: summary));
    }

    entries.sort((a, b) => b.sessionId.compareTo(a.sessionId));
    return entries;
  }

  Future<void> deleteSession(String sessionId) async {
    final root = await rootDir();
    final dir = Directory('${root.path}/$sessionId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// The session's files that exist, in a sensible share order: meta.json,
  /// telemetry.csv, events.csv, summary.json.
  Future<List<File>> shareableFiles(String sessionId) async {
    final root = await rootDir();
    final dir = Directory('${root.path}/$sessionId');
    const candidates = ['meta.json', 'telemetry.csv', 'events.csv', 'summary.json'];
    final files = <File>[];
    for (final name in candidates) {
      final file = File('${dir.path}/$name');
      if (await file.exists()) files.add(file);
    }
    return files;
  }
}
