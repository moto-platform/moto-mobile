import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// TCP connect limit of the default client. A server that is unreachable from
/// this network (wrong IP after a DHCP change, client isolation on a school or
/// guest Wi-Fi) drops the SYN silently; without this limit the OS retries for
/// minutes and the session stays in "uploading".
const Duration uploadConnectTimeout = Duration(seconds: 10);

/// Upper bound for one whole upload (connect, body, response). Generous so a
/// large session on a slow link still completes.
const Duration uploadTotalTimeout = Duration(minutes: 5);

/// Outcome of one upload attempt against moto-server's ingestion API
/// (`POST {baseUrl}/sessions`).
enum UploadOutcome {
  /// 201: the archive was accepted and stored for the first time.
  created,

  /// 200: this session id was already uploaded with the same content --
  /// idempotent, treated as success.
  alreadyUploaded,

  /// 409: this session id already exists on the server with *different*
  /// content. Never retried automatically.
  conflict,

  /// 401: bad/missing API token.
  unauthorized,

  /// Anything else (413 payload too large, 5xx, network failure, ...).
  failed,
}

class UploadResult {
  const UploadResult(this.outcome, {this.message, this.statusCode});

  final UploadOutcome outcome;
  final String? message;
  final int? statusCode;

  bool get isSuccess => outcome == UploadOutcome.created || outcome == UploadOutcome.alreadyUploaded;
}

/// Uploads a session archive to moto-server.
///
/// `multipart/form-data`, field name `archive`, filename `<session_id>.zip`,
/// header `Authorization: Bearer <token>`. The [http.Client] is injectable so
/// this is unit-testable with `package:http/testing.dart`'s `MockClient`
/// instead of a real network call.
class UploadClient {
  UploadClient({http.Client? httpClient, Duration totalTimeout = uploadTotalTimeout})
      : _httpClient = httpClient ?? IOClient(HttpClient()..connectionTimeout = uploadConnectTimeout),
        _totalTimeout = totalTimeout;

  final http.Client _httpClient;
  final Duration _totalTimeout;

  Future<UploadResult> uploadSession({
    required String baseUrl,
    required String apiToken,
    required String sessionId,
    required List<int> archiveBytes,
  }) async {
    final uri = Uri.parse('${_withoutTrailingSlash(baseUrl)}/sessions');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiToken';
    request.files.add(http.MultipartFile.fromBytes(
      'archive',
      archiveBytes,
      filename: '$sessionId.zip',
    ));

    try {
      final response = await _httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_totalTimeout);

      switch (response.statusCode) {
        case 201:
          return const UploadResult(UploadOutcome.created, statusCode: 201);
        case 200:
          return const UploadResult(UploadOutcome.alreadyUploaded, statusCode: 200);
        case 409:
          return UploadResult(
            UploadOutcome.conflict,
            statusCode: 409,
            message: _extractMessage(response) ?? 'session id already exists with different content',
          );
        case 401:
          return UploadResult(
            UploadOutcome.unauthorized,
            statusCode: 401,
            message: _extractMessage(response) ?? 'unauthorized (check the API token in Settings)',
          );
        default:
          return UploadResult(
            UploadOutcome.failed,
            statusCode: response.statusCode,
            message: _extractMessage(response) ?? 'HTTP ${response.statusCode}',
          );
      }
    } on TimeoutException {
      return UploadResult(
        UploadOutcome.failed,
        message: 'timed out after ${_totalTimeout.inSeconds} s (is the server reachable from this network?)',
      );
    } on SocketException catch (e) {
      return UploadResult(UploadOutcome.failed, message: 'network error: ${e.message}');
    } catch (e) {
      return UploadResult(UploadOutcome.failed, message: e.toString());
    }
  }

  String? _extractMessage(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['detail'] ?? decoded['error'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Not JSON: fall through to the raw body.
    }
    return response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body;
  }
}

String _withoutTrailingSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;
