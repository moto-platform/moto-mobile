import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'app_settings.dart';
import 'network_info.dart';
import 'session_recorder.dart' show DocumentsDirProvider, resolveSessionsRootDir;
import 'upload_client.dart';

/// Per-session upload state, persisted as `<session>/upload.json`. This file
/// is intentionally NOT one of the files zipped up for upload (see
/// [buildSessionArchiveBytes]) -- it is app-local bookkeeping, not session
/// data moto-server needs.
enum SessionUploadState { notUploaded, uploading, uploaded, failed }

class SessionUploadStatus {
  const SessionUploadStatus({
    this.state = SessionUploadState.notUploaded,
    this.reason,
    this.uploadedAtUtc,
  });

  final SessionUploadState state;

  /// Human-readable failure reason, e.g. an HTTP status or "not on Wi-Fi".
  /// `null` unless [state] is [SessionUploadState.failed].
  final String? reason;

  /// UTC ISO-8601 timestamp of the last successful upload, if any.
  final String? uploadedAtUtc;

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'reason': reason,
        'uploaded_at_utc': uploadedAtUtc,
      };

  factory SessionUploadStatus.fromJson(Map<String, dynamic> json) => SessionUploadStatus(
        state: SessionUploadState.values.firstWhere(
          (s) => s.name == json['state'],
          orElse: () => SessionUploadState.notUploaded,
        ),
        reason: json['reason'] as String?,
        uploadedAtUtc: json['uploaded_at_utc'] as String?,
      );
}

/// The session files that make up the upload archive, in a fixed order at
/// the zip root. `imu.csv` and `gps.csv` are only included when present
/// (older sessions, or sessions where no IMU / GPS block ever arrived, do not
/// have them).
const List<String> sessionArchiveFileNames = [
  'meta.json',
  'telemetry.csv',
  'events.csv',
  'summary.json',
  'imu.csv',
  'gps.csv',
];

/// Builds the store-only-or-deflated zip archive for one session directory,
/// containing exactly [sessionArchiveFileNames] (whichever of them exist) at
/// the zip root. Never includes `upload.json`.
Future<List<int>> buildSessionArchiveBytes(Directory sessionDir) async {
  final archive = Archive();
  for (final name in sessionArchiveFileNames) {
    final file = File('${sessionDir.path}/$name');
    if (!await file.exists()) continue;
    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  return encoded ?? const <int>[];
}

/// Uploads recorded sessions to moto-server and tracks each session's
/// upload status on disk (`upload.json`), independent of the app's process
/// lifetime.
class SessionUploader {
  SessionUploader({
    required DocumentsDirProvider documentsDirProvider,
    UploadClient? uploadClient,
    NetworkInfo? networkInfo,
  })  : _documentsDirProvider = documentsDirProvider,
        _uploadClient = uploadClient ?? UploadClient(),
        _networkInfo = networkInfo ?? ConnectivityPlusNetworkInfo();

  final DocumentsDirProvider _documentsDirProvider;
  final UploadClient _uploadClient;
  final NetworkInfo _networkInfo;

  Future<Directory> _sessionDir(String sessionId) async {
    final root = await resolveSessionsRootDir(_documentsDirProvider);
    return Directory('${root.path}/$sessionId');
  }

  Future<SessionUploadStatus> readStatus(String sessionId) async {
    final dir = await _sessionDir(sessionId);
    final file = File('${dir.path}/upload.json');
    if (!await file.exists()) return const SessionUploadStatus();
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SessionUploadStatus.fromJson(json);
    } catch (_) {
      return const SessionUploadStatus();
    }
  }

  Future<void> _writeStatus(String sessionId, SessionUploadStatus status) async {
    final dir = await _sessionDir(sessionId);
    final file = File('${dir.path}/upload.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(status.toJson()));
  }

  /// Uploads [sessionId] using [settings]. Always leaves a status behind on
  /// disk (uploading -> uploaded/failed), so a caller that dies mid-upload
  /// leaves a truthful "failed"/"uploading" state rather than nothing.
  Future<SessionUploadStatus> upload(String sessionId, AppSettings settings) async {
    if (!settings.isServerConfigured) {
      const status = SessionUploadStatus(
        state: SessionUploadState.failed,
        reason: 'no server configured (set it in Settings)',
      );
      await _writeStatus(sessionId, status);
      return status;
    }

    if (settings.uploadOnlyOnWifi) {
      final onWifi = await _networkInfo.isOnWifi;
      // "Unknown" is only ever allowed through when the Wi-Fi-only setting
      // is itself off; the setting is on here, so unknown blocks the upload
      // just like "known not on Wi-Fi" does.
      if (onWifi != true) {
        const status = SessionUploadStatus(
          state: SessionUploadState.failed,
          reason: 'not on Wi-Fi (Settings: upload only on Wi-Fi is on)',
        );
        await _writeStatus(sessionId, status);
        return status;
      }
    }

    await _writeStatus(sessionId, const SessionUploadStatus(state: SessionUploadState.uploading));

    final dir = await _sessionDir(sessionId);
    final archiveBytes = await buildSessionArchiveBytes(dir);

    final result = await _uploadClient.uploadSession(
      baseUrl: settings.serverBaseUrl!,
      apiToken: settings.apiToken ?? '',
      sessionId: sessionId,
      archiveBytes: archiveBytes,
    );

    final status = result.isSuccess
        ? SessionUploadStatus(
            state: SessionUploadState.uploaded,
            uploadedAtUtc: DateTime.now().toUtc().toIso8601String(),
          )
        : SessionUploadStatus(
            state: SessionUploadState.failed,
            reason: result.message ?? result.outcome.name,
          );

    await _writeStatus(sessionId, status);
    return status;
  }
}
