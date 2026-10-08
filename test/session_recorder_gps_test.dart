import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/gps_block.dart';
import 'package:moto_mobile/models/session_meta.dart';
import 'package:moto_mobile/services/session_recorder.dart';

import 'gps_block_test.dart' show buildGpsBlockBytes;

const _meta = SessionMeta(sessionId: 'placeholder', createdUtc: 'placeholder');

void main() {
  late Directory tempDir;
  late SessionRecorder recorder;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_recorder_gps_test_');
    recorder = SessionRecorder(documentsDirProvider: () async => tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<List<String>> readCsv(String name) =>
      File('${recorder.sessionDir!.path}/$name').readAsLinesSync().map((l) => l.split(',')).toList();

  List<List<String>> events() => readCsv('events.csv').skip(1).toList();

  test('gps.csv header: the moto-server contract, schema names, no position column', () {
    expect(SessionRecorder.gpsCsvHeader, [
      'rx_utc_iso', 'rx_mono_ms', 'seq', 'lost_since_prev', 'raw_hex', //
      'device_time_ms', 'ground_speed', 'heading_of_motion', 'speed_accuracy', 'heading_accuracy',
      'fix_type', 'num_sv', 'flags',
      'ground_speed_mps', 'heading_of_motion_deg', 'speed_accuracy_mps', 'heading_accuracy_deg',
      'gnss_fix_ok', 'parse_error', 'uart_overflow',
    ]);
    for (final column in SessionRecorder.gpsCsvHeader) {
      for (final word in ['lat', 'lon', 'height', 'alt', 'hmsl', 'ecef', 'pos']) {
        expect(column.toLowerCase().contains(word), isFalse, reason: column);
      }
    }
  });

  test('meta.json carries gps_block_version', () async {
    await recorder.start(_meta);
    final meta = jsonDecode(File('${recorder.sessionDir!.path}/meta.json').readAsStringSync());
    expect(meta['gps_block_version'], BleGpsBlock.version);
  });

  test('gps.csv is created lazily; no GPS block means no file and zero summary counts', () async {
    await recorder.start(_meta);
    expect(File('${recorder.sessionDir!.path}/gps.csv').existsSync(), isFalse);
    final summary = await recorder.stop();
    expect(File('${recorder.sessionDir!.path}/gps.csv').existsSync(), isFalse);
    expect(summary.gpsBlockCount, 0);
    final json = jsonDecode(File('${recorder.sessionDir!.path}/summary.json').readAsStringSync());
    expect(json['gps_block_count'], 0);
    expect(json['gps_lost_or_skipped_blocks'], 0);
    expect(json['gps_lost_or_skipped_percent'], 0.0);
  });

  test('one row per block with raw_hex, raw, scaled and flag columns', () async {
    await recorder.start(_meta);
    final bytes = buildGpsBlockBytes(
      seq: 252,
      deviceTimeMs: 9200,
      groundSpeed: 11111,
      headingOfMotion: 9012345,
      speedAccuracy: 300,
      headingAccuracy: 50000,
      fixType: BleGpsFixType.fix3d,
      numSv: 9,
      flags: BleGpsFlagBits.gnssFixOk | BleGpsFlagBits.parseError,
    );
    recorder.handleRawGpsBlock(bytes);
    await recorder.stop();

    final rows = readCsv('gps.csv');
    expect(rows.first, SessionRecorder.gpsCsvHeader);
    expect(rows.length, 2);
    final row = Map.fromIterables(SessionRecorder.gpsCsvHeader, rows[1]);
    expect(row['seq'], '252');
    expect(row['lost_since_prev'], '0');
    expect(row['raw_hex'], bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
    expect(row['raw_hex']!.length, BleGpsBlock.totalBytes * 2);
    expect(row['device_time_ms'], '9200');
    expect(row['ground_speed'], '11111');
    expect(row['heading_of_motion'], '9012345');
    expect(row['speed_accuracy'], '300');
    expect(row['heading_accuracy'], '50000');
    expect(row['fix_type'], '${BleGpsFixType.fix3d}');
    expect(row['num_sv'], '9');
    expect(row['flags'], '${BleGpsFlagBits.gnssFixOk | BleGpsFlagBits.parseError}');
    expect(double.parse(row['ground_speed_mps']!), closeTo(11.111, 1e-9));
    expect(double.parse(row['heading_of_motion_deg']!), closeTo(90.12345, 1e-9));
    expect(double.parse(row['speed_accuracy_mps']!), closeTo(0.3, 1e-9));
    expect(double.parse(row['heading_accuracy_deg']!), closeTo(0.5, 1e-9));
    expect([row['gnss_fix_ok'], row['parse_error'], row['uart_overflow']], ['1', '1', '0']);
  });

  test('seq gaps: lost_since_prev, gps_gap event and summary (lost or MTU-skipped)', () async {
    await recorder.start(_meta);
    for (final seq in [250, 251, 254, 255, 0, 2]) {
      recorder.handleRawGpsBlock(buildGpsBlockBytes(seq: seq));
    }
    final summary = await recorder.stop();

    final lost = readCsv('gps.csv').skip(1).map((r) => r[3]).toList();
    expect(lost, ['0', '0', '2', '0', '0', '1']);
    final gaps = events().where((e) => e[2] == 'gps_gap').map((e) => e[3]).toList();
    expect(gaps, ['missing=2;seq=254', 'missing=1;seq=2']);

    expect(summary.gpsBlockCount, 6);
    expect(summary.gpsLostOrSkippedBlocks, 3);
    expect(summary.gpsLostOrSkippedPercent, closeTo(3 / 9 * 100, 1e-9));
    final json = jsonDecode(File('${recorder.sessionDir!.path}/summary.json').readAsStringSync());
    expect(json['gps_block_count'], 6);
    expect(json['gps_lost_or_skipped_blocks'], 3);
  });

  test('a bad block is a gps:-prefixed decode_error and gets no row', () async {
    await recorder.start(_meta);
    recorder.handleRawGpsBlock(Uint8List.fromList([BleGpsBlock.version, 1, 2]));
    recorder.handleRawGpsBlock(buildGpsBlockBytes(version: 9));
    await recorder.stop();

    expect(File('${recorder.sessionDir!.path}/gps.csv').existsSync(), isFalse);
    final errors = events().where((e) => e[2] == 'decode_error').map((e) => e[3]).toList();
    expect(errors.length, 2);
    expect(errors.every((d) => d.startsWith('gps: ')), isTrue);
    expect(recorder.decodeErrorCount, 2);
    expect(recorder.gpsBlockCount, 0);
  });

  test('GPS link: subscribed and failed are logged once per change, device ids redacted', () async {
    await recorder.start(_meta);
    recorder.handleGpsLinkStatus(const GpsLinkStatus(GpsLinkState.subscribing));
    recorder.handleGpsLinkStatus(const GpsLinkStatus(GpsLinkState.subscribed));
    recorder.handleGpsLinkStatus(const GpsLinkStatus(GpsLinkState.subscribed));
    recorder.handleGpsLinkStatus(GpsLinkStatus.disconnected);
    recorder.handleGpsLinkStatus(
        const GpsLinkStatus(GpsLinkState.failed, reason: 'bond failed for AA:BB:CC:DD:EE:FF'));
    await recorder.stop();

    final gpsEvents = events().where((e) => e[2].startsWith('gps_')).map((e) => '${e[2]}|${e[3]}').toList();
    expect(gpsEvents, ['gps_subscribed|', 'gps_subscribe_failed|reason=bond failed for <device>']);
  });

  test('GPS input is ignored while not recording', () {
    recorder.handleRawGpsBlock(buildGpsBlockBytes(seq: 1));
    recorder.handleGpsLinkStatus(const GpsLinkStatus(GpsLinkState.subscribed));
    expect(recorder.gpsBlockCount, 0);
    expect(recorder.lastGpsBlock, isNull);
  });

  test('a new recording resets the GPS state', () async {
    await recorder.start(_meta);
    recorder.handleRawGpsBlock(buildGpsBlockBytes(seq: 10));
    await recorder.stop();

    await recorder.start(_meta);
    recorder.handleRawGpsBlock(buildGpsBlockBytes(seq: 20)); // no gap across sessions
    final summary = await recorder.stop();
    expect(summary.gpsBlockCount, 1);
    expect(summary.gpsLostOrSkippedBlocks, 0);
  });

  test('SessionSummary and SessionMeta round-trip the GPS keys', () {
    const summary = SessionSummary(
      duration: Duration(seconds: 1),
      packetCount: 0,
      lostCount: 0,
      lossPercent: 0,
      decodeErrorCount: 0,
      disconnectCount: 0,
      firstPacketUtc: null,
      lastPacketUtc: null,
      gpsBlockCount: 7,
      gpsLostOrSkippedBlocks: 2,
      gpsLostOrSkippedPercent: 22.5,
    );
    final back = SessionSummary.fromJson(summary.toJson());
    expect(back.gpsBlockCount, 7);
    expect(back.gpsLostOrSkippedBlocks, 2);
    expect(back.gpsLostOrSkippedPercent, 22.5);

    expect(SessionMeta.fromJson(_meta.toJson()).gpsBlockVersion, BleGpsBlock.version);
    final old = Map<String, dynamic>.from(_meta.toJson())..remove('gps_block_version');
    expect(SessionMeta.fromJson(old).gpsBlockVersion, isNull);
  });
}
