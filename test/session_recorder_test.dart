import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mobile/models/session_meta.dart';
import 'package:moto_mobile/models/telemetry_data.dart';
import 'package:moto_mobile/services/session_recorder.dart';

/// Builds a raw 16-byte v2 packet from field values, matching
/// moto-connectivity-node/docs/ble_telemetry_packet_schema.json. Mirrors the
/// helper in test/telemetry_data_test.dart.
Uint8List _packet({
  int version = blePacketExpectedVersion,
  int seq = 0,
  int rpm = 0,
  int speed = 0,
  int coolantTemp = 0,
  int throttlePos = 0,
  int batteryVoltMv = 0,
  int leanAngleTenths = blePacketNotAvailable,
  int maxLeanRightTenths = blePacketNotAvailable,
  int maxLeanLeftTenths = blePacketNotAvailable,
  int flags = 0,
}) {
  final bytes = ByteData(16);
  bytes.setUint8(BlePacketFieldOffsets.version, version);
  bytes.setUint8(BlePacketFieldOffsets.seq, seq);
  bytes.setUint16(BlePacketFieldOffsets.rpm, rpm, Endian.little);
  bytes.setUint8(BlePacketFieldOffsets.speed, speed);
  bytes.setInt8(BlePacketFieldOffsets.coolantTemp, coolantTemp);
  bytes.setUint8(BlePacketFieldOffsets.throttlePos, throttlePos);
  bytes.setUint16(BlePacketFieldOffsets.batteryVolt, batteryVoltMv, Endian.little);
  bytes.setInt16(BlePacketFieldOffsets.leanAngle, leanAngleTenths, Endian.little);
  bytes.setInt16(BlePacketFieldOffsets.maxLeanRight, maxLeanRightTenths, Endian.little);
  bytes.setInt16(BlePacketFieldOffsets.maxLeanLeft, maxLeanLeftTenths, Endian.little);
  bytes.setUint8(BlePacketFieldOffsets.flags, flags);
  return bytes.buffer.asUint8List();
}

SessionMeta _testMeta() => const SessionMeta(
      sessionId: 'placeholder',
      createdUtc: 'placeholder',
      riderName: 'Ali',
      riderWeightKg: 78.0,
      extraLoadKg: 5.0,
      ambientTempC: 22.0,
      weather: 'dry',
      tirePressureFrontBar: 2.3,
      tirePressureRearBar: 2.5,
      fuelLevel: 'full',
      vehicleConfig: 'stock gearing, stock exhaust',
      conditionLabel: 'healthy',
      routeType: 'urban',
      note: 'workshop test ride',
      deviceName: 'Honda-CL250',
    );

void main() {
  late Directory tempDir;
  late SessionRecorder recorder;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_recorder_test_');
    recorder = SessionRecorder(documentsDirProvider: () async => tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('start()', () {
    test('creates the session directory and writes meta.json immediately', () async {
      final meta = await recorder.start(_testMeta());

      expect(meta.sessionId, matches(RegExp(r'^\d{8}-\d{6}-[0-9a-f]{4}$')));
      expect(recorder.sessionDir!.existsSync(), isTrue);

      final metaFile = File('${recorder.sessionDir!.path}/meta.json');
      expect(metaFile.existsSync(), isTrue);
      final decoded = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['session_id'], meta.sessionId);
      expect(decoded['rider_name'], 'Ali');
      expect(decoded['ble_schema_version'], blePacketExpectedVersion);

      await recorder.stop();
    });

    test('throws if a recording is already in progress', () async {
      await recorder.start(_testMeta());
      expect(() => recorder.start(_testMeta()), throwsStateError);
      await recorder.stop();
    });
  });

  test('telemetry.csv header matches the documented columns', () async {
    await recorder.start(_testMeta());
    final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
    expect(lines.first.split(','), SessionRecorder.telemetryCsvHeader);
    await recorder.stop();
  });

  test('events.csv header matches the documented columns', () async {
    await recorder.start(_testMeta());
    final lines = File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync();
    expect(lines.first.split(','), SessionRecorder.eventsCsvHeader);
    await recorder.stop();
  });

  test('a valid packet is written with all decoded fields and no decode_error', () async {
    await recorder.start(_testMeta());
    recorder.handleRawPacket(_packet(seq: 5, rpm: 4500, speed: 80, flags: 0x7F));
    await recorder.stop();

    final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
    expect(lines.length, 2); // header + 1 row
    const header = SessionRecorder.telemetryCsvHeader;
    final row = lines[1].split(',');
    final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

    expect(byName['seq'], '5');
    expect(byName['lost_since_prev'], '0');
    expect(byName['rpm'], '4500.0');
    expect(byName['speed_kmh'], '80');
    expect(byName['decode_error'], '');
    expect(byName['raw_hex']!.length, 32); // 16 bytes -> 32 hex chars
  });

  group('lost_since_prev (rolling seq, mod 256)', () {
    test('consecutive seq numbers count no loss', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(_packet(seq: 10));
      recorder.handleRawPacket(_packet(seq: 11));
      final summary = await recorder.stop();

      expect(summary.lostCount, 0);
    });

    test('a gap between seq numbers is counted as lost packets', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(_packet(seq: 10));
      recorder.handleRawPacket(_packet(seq: 15));
      final summary = await recorder.stop();

      expect(summary.lostCount, 4); // seq 11, 12, 13, 14 missed
    });

    test('a gap across the 254->1 rollover counts as 2 lost', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(_packet(seq: 254));
      recorder.handleRawPacket(_packet(seq: 1));
      final summary = await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      final lostIdx = SessionRecorder.telemetryCsvHeader.indexOf('lost_since_prev');
      final row2 = lines[2].split(',');

      expect(row2[lostIdx], '2');
      expect(summary.lostCount, 2);
    });
  });

  group('decode-error rows are kept, never dropped', () {
    test('a bad version is written with decode_error and blank decoded fields', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(_packet(version: 1, seq: 9));
      final summary = await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      expect(lines.length, 2);
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['decode_error'], contains('version mismatch'));
      expect(byName['seq'], '9');
      expect(byName['rpm'], '');
      expect(summary.decodeErrorCount, 1);
      expect(summary.packetCount, 1);
    });

    test('a too-short packet is written with decode_error and its raw hex', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(Uint8List.fromList([blePacketExpectedVersion, 3]));
      final summary = await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['decode_error'], contains('short packet'));
      expect(byName['seq'], '3');
      expect(byName['raw_hex'], '0203');
      expect(summary.decodeErrorCount, 1);
    });

    test('an events.csv decode_error row is logged for every failed packet', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(_packet(version: 1, seq: 1));
      await recorder.stop();

      final events =
          File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync().skip(1).map((l) => l.split(',')[2]).toList();
      expect(events, contains('decode_error'));
    });
  });

  test('events.csv logs recording_started, packet_gap and recording_stopped', () async {
    await recorder.start(_testMeta());
    recorder.handleRawPacket(_packet(seq: 0));
    recorder.handleRawPacket(_packet(seq: 5)); // gap of 4
    await recorder.stop();

    final events =
        File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync().skip(1).map((l) => l.split(',')[2]).toList();
    expect(events, containsAll(['recording_started', 'packet_gap', 'recording_stopped']));
  });

  test('ble connection changes log connected, disconnected and reconnected', () async {
    await recorder.start(_testMeta());
    recorder.handleConnectionChange(true);
    recorder.handleConnectionChange(false);
    recorder.handleConnectionChange(true);
    final summary = await recorder.stop();

    final events =
        File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync().skip(1).map((l) => l.split(',')[2]).toList();
    expect(events, containsAll(['ble_connected', 'ble_disconnected', 'ble_reconnected']));
    expect(summary.disconnectCount, 1);
  });

  test('summary.json reports duration, packet/lost counts, loss percent and disconnects', () async {
    await recorder.start(_testMeta());
    recorder.handleConnectionChange(true);
    recorder.handleRawPacket(_packet(seq: 0));
    recorder.handleRawPacket(_packet(seq: 2)); // 1 lost
    recorder.handleConnectionChange(false);
    final summary = await recorder.stop();

    expect(summary.packetCount, 2);
    expect(summary.lostCount, 1);
    expect(summary.lossPercent, closeTo(100 / 3, 0.01));
    expect(summary.disconnectCount, 1);
    expect(summary.firstPacketUtc, isNotNull);
    expect(summary.lastPacketUtc, isNotNull);

    final summaryFile = File('${recorder.sessionDir!.path}/summary.json');
    expect(summaryFile.existsSync(), isTrue);
    final decoded = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['packet_count'], 2);
    expect(decoded['lost_count'], 1);
    expect(decoded['disconnect_count'], 1);
  });

  test('SessionMeta round-trips through JSON', () {
    final meta = _testMeta().copyWith(
      sessionId: '20260927-120000-ab12',
      createdUtc: '2026-09-27T12:00:00.000Z',
    );
    final roundTripped = SessionMeta.fromJson(jsonDecode(jsonEncode(meta.toJson())) as Map<String, dynamic>);
    expect(roundTripped.toJson(), meta.toJson());
  });
}
