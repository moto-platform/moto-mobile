import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
  UploadClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

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
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

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
