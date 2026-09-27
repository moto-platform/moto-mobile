import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_mobile/services/upload_client.dart';

void main() {
  group('UploadClient.uploadSession', () {
    test('sends a multipart POST to {baseUrl}/sessions with the archive field, filename and bearer token', () async {
      late http.Request captured;
      final client = UploadClient(
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('', 201);
        }),
      );

      final result = await client.uploadSession(
        baseUrl: 'https://moto-server.example.com',
        apiToken: 'secret-token',
        sessionId: '20260927-120000-ab12',
        archiveBytes: [1, 2, 3, 4],
      );

      expect(result.outcome, UploadOutcome.created);
      expect(result.isSuccess, isTrue);
      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://moto-server.example.com/sessions');
      expect(captured.headers['Authorization'], 'Bearer secret-token');
      expect(captured.headers['content-type'], contains('multipart/form-data'));

      final body = latin1.decode(captured.bodyBytes, allowInvalid: true);
      expect(body, contains('name="archive"'));
      expect(body, contains('filename="20260927-120000-ab12.zip"'));
    });

    test('strips a trailing slash from baseUrl', () async {
      late Uri capturedUrl;
      final client = UploadClient(
        httpClient: MockClient((request) async {
          capturedUrl = request.url;
          return http.Response('', 201);
        }),
      );
      await client.uploadSession(
        baseUrl: 'https://moto-server.example.com/',
        apiToken: 't',
        sessionId: 's',
        archiveBytes: [1],
      );
      expect(capturedUrl.toString(), 'https://moto-server.example.com/sessions');
    });

    test('200 is treated as success (already uploaded, idempotent)', () async {
      final client = UploadClient(httpClient: MockClient((_) async => http.Response('', 200)));
      final result = await client.uploadSession(
        baseUrl: 'https://s',
        apiToken: 't',
        sessionId: 'id',
        archiveBytes: [1],
      );
      expect(result.outcome, UploadOutcome.alreadyUploaded);
      expect(result.isSuccess, isTrue);
    });

    test('409 conflict is a failure with a message, never retried automatically', () async {
      final client = UploadClient(
        httpClient: MockClient((_) async => http.Response(jsonEncode({'message': 'content differs'}), 409)),
      );
      final result = await client.uploadSession(
        baseUrl: 'https://s',
        apiToken: 't',
        sessionId: 'id',
        archiveBytes: [1],
      );
      expect(result.outcome, UploadOutcome.conflict);
      expect(result.isSuccess, isFalse);
      expect(result.message, 'content differs');
    });

    test('401 unauthorized is a failure', () async {
      final client = UploadClient(httpClient: MockClient((_) async => http.Response('', 401)));
      final result = await client.uploadSession(
        baseUrl: 'https://s',
        apiToken: 'bad-token',
        sessionId: 'id',
        archiveBytes: [1],
      );
      expect(result.outcome, UploadOutcome.unauthorized);
      expect(result.isSuccess, isFalse);
    });

    test('413 and other unexpected statuses are generic failures', () async {
      final client = UploadClient(httpClient: MockClient((_) async => http.Response('', 413)));
      final result = await client.uploadSession(
        baseUrl: 'https://s',
        apiToken: 't',
        sessionId: 'id',
        archiveBytes: List.filled(100, 0),
      );
      expect(result.outcome, UploadOutcome.failed);
      expect(result.statusCode, 413);
    });

    test('a thrown exception from the client is reported as a failure, not propagated', () async {
      final client = UploadClient(httpClient: MockClient((_) async => throw Exception('boom')));
      final result = await client.uploadSession(
        baseUrl: 'https://s',
        apiToken: 't',
        sessionId: 'id',
        archiveBytes: [1],
      );
      expect(result.outcome, UploadOutcome.failed);
      expect(result.message, contains('boom'));
    });
  });
}
