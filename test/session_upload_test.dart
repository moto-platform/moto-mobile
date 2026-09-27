import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moto_mobile/services/app_settings.dart';
import 'package:moto_mobile/services/network_info.dart';
import 'package:moto_mobile/services/session_upload.dart';
import 'package:moto_mobile/services/upload_client.dart';

class _FixedNetworkInfo implements NetworkInfo {
  _FixedNetworkInfo(this._value);
  final bool? _value;
  @override
  Future<bool?> get isOnWifi async => _value;
}

void main() {
  late Directory tempDir;
  late Directory sessionDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('session_upload_test_');
    sessionDir = Directory('${tempDir.path}/sessions/20260927-120000-ab12');
    await sessionDir.create(recursive: true);
    await File('${sessionDir.path}/meta.json').writeAsString('{"session_id":"x"}');
    await File('${sessionDir.path}/telemetry.csv').writeAsString('a,b\n1,2\n');
    await File('${sessionDir.path}/events.csv').writeAsString('a,b\n1,2\n');
    await File('${sessionDir.path}/summary.json').writeAsString('{"packet_count":1}');
    // upload.json must never end up in the archive, even if present.
    await File('${sessionDir.path}/upload.json').writeAsString('{"state":"notUploaded"}');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('buildSessionArchiveBytes', () {
    test('zips exactly the known session files that exist, and never upload.json', () async {
      final bytes = await buildSessionArchiveBytes(sessionDir);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();

      expect(names, {'meta.json', 'telemetry.csv', 'events.csv', 'summary.json'});
      expect(names.contains('upload.json'), isFalse);
      expect(names.contains('imu.csv'), isFalse); // not present on disk
    });

    test('includes imu.csv when present', () async {
      await File('${sessionDir.path}/imu.csv').writeAsString('a,b\n1,2\n');
      final bytes = await buildSessionArchiveBytes(sessionDir);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names.contains('imu.csv'), isTrue);
    });

    test('archived file contents round-trip byte-for-byte', () async {
      final bytes = await buildSessionArchiveBytes(sessionDir);
      final archive = ZipDecoder().decodeBytes(bytes);
      final meta = archive.files.firstWhere((f) => f.name == 'meta.json');
      expect(utf8.decode(meta.content as List<int>), '{"session_id":"x"}');
    });
  });

  group('SessionUploader', () {
    test('readStatus returns notUploaded when no upload.json-equivalent state has been written yet', () async {
      // Overwrite the pre-seeded upload.json from setUp with nothing written
      // by the uploader itself -- readStatus should still parse it fine.
      final uploader = SessionUploader(documentsDirProvider: () async => tempDir);
      final status = await uploader.readStatus('20260927-120000-ab12');
      expect(status.state, SessionUploadState.notUploaded);
    });

    test('a successful upload (201) is persisted as uploaded with a timestamp', () async {
      final uploader = SessionUploader(
        documentsDirProvider: () async => tempDir,
        uploadClient: UploadClient(httpClient: MockClient((_) async => http.Response('', 201))),
        networkInfo: _FixedNetworkInfo(true),
      );

      final status = await uploader.upload('20260927-120000-ab12', const AppSettings(serverBaseUrl: 'https://s', apiToken: 't'));
      expect(status.state, SessionUploadState.uploaded);
      expect(status.uploadedAtUtc, isNotNull);

      final persisted = await uploader.readStatus('20260927-120000-ab12');
      expect(persisted.state, SessionUploadState.uploaded);
    });

    test('a 409 conflict is persisted as failed with the server message', () async {
      final uploader = SessionUploader(
        documentsDirProvider: () async => tempDir,
        uploadClient: UploadClient(
          httpClient: MockClient((_) async => http.Response(jsonEncode({'message': 'content differs'}), 409)),
        ),
        networkInfo: _FixedNetworkInfo(true),
      );

      final status = await uploader.upload('20260927-120000-ab12', const AppSettings(serverBaseUrl: 'https://s', apiToken: 't'));
      expect(status.state, SessionUploadState.failed);
      expect(status.reason, contains('content differs'));
    });

    test('no server configured fails without making a network call', () async {
      var called = false;
      final uploader = SessionUploader(
        documentsDirProvider: () async => tempDir,
        uploadClient: UploadClient(httpClient: MockClient((_) async {
          called = true;
          return http.Response('', 201);
        })),
        networkInfo: _FixedNetworkInfo(true),
      );

      final status = await uploader.upload('20260927-120000-ab12', const AppSettings());
      expect(status.state, SessionUploadState.failed);
      expect(called, isFalse);
    });

    test('Wi-Fi-only setting blocks upload when known to be off Wi-Fi', () async {
      var called = false;
      final uploader = SessionUploader(
        documentsDirProvider: () async => tempDir,
        uploadClient: UploadClient(httpClient: MockClient((_) async {
          called = true;
          return http.Response('', 201);
        })),
        networkInfo: _FixedNetworkInfo(false),
      );

      final status = await uploader.upload(
        '20260927-120000-ab12',
        const AppSettings(serverBaseUrl: 'https://s', apiToken: 't', uploadOnlyOnWifi: true),
      );
      expect(status.state, SessionUploadState.failed);
      expect(called, isFalse);
    });

    test('Wi-Fi-only setting blocks upload when Wi-Fi state is unknown', () async {
      final uploader = SessionUploader(
        documentsDirProvider: () async => tempDir,
        uploadClient: UploadClient(httpClient: MockClient((_) async => http.Response('', 201))),
        networkInfo: _FixedNetworkInfo(null),
      );

      final status = await uploader.upload(
        '20260927-120000-ab12',
        const AppSettings(serverBaseUrl: 'https://s', apiToken: 't', uploadOnlyOnWifi: true),
      );
      expect(status.state, SessionUploadState.failed);
    });

    test('an unknown Wi-Fi state is allowed through when the Wi-Fi-only setting is off', () async {
      final uploader = SessionUploader(
        documentsDirProvider: () async => tempDir,
        uploadClient: UploadClient(httpClient: MockClient((_) async => http.Response('', 201))),
        networkInfo: _FixedNetworkInfo(null),
      );

      final status = await uploader.upload(
        '20260927-120000-ab12',
        const AppSettings(serverBaseUrl: 'https://s', apiToken: 't', uploadOnlyOnWifi: false),
      );
      expect(status.state, SessionUploadState.uploaded);
    });
  });

  group('AppSettingsStore', () {
    // shared_preferences needs its platform channel mocked; the widget test
    // binding used by flutter_test provides a working in-memory default for
    // it in recent versions, so a plain round-trip works here.
    test('round-trips through shared_preferences, and empty strings become null', () async {
      SharedPreferences.setMockInitialValues({});
      const store = AppSettingsStore();
      await store.save(const AppSettings(serverBaseUrl: 'https://s', apiToken: 'tok', uploadOnlyOnWifi: false));
      final loaded = await store.load();
      expect(loaded.serverBaseUrl, 'https://s');
      expect(loaded.apiToken, 'tok');
      expect(loaded.uploadOnlyOnWifi, isFalse);
      expect(loaded.isServerConfigured, isTrue);

      await store.save(const AppSettings());
      final cleared = await store.load();
      expect(cleared.serverBaseUrl, isNull);
      expect(cleared.isServerConfigured, isFalse);
    });
  });
}
