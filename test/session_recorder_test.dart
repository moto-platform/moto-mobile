import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/session_meta.dart';
import 'package:moto_mobile/models/telemetry_data.dart';
import 'package:moto_mobile/services/session_recorder.dart';

import 'imu_block_test.dart' show buildImuBlockBytes;
import 'telemetry_data_test.dart' show buildV2Packet, buildV3Packet, buildV4Packet;

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
      requestedMtu: 185,
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
      expect(decoded['ble_schema_version'], BleTelemetry.currentVersion);
      expect(decoded['ble_schema_version'], 4);
      expect(decoded['imu_block_version'], BleImuBlock.version);
      expect(decoded['requested_mtu'], 185);

      await recorder.stop();
    });

    test('throws if a recording is already in progress', () async {
      await recorder.start(_testMeta());
      expect(() => recorder.start(_testMeta()), throwsStateError);
      await recorder.stop();
    });
  });

  test('telemetry.csv header matches the documented 43 columns', () async {
    await recorder.start(_testMeta());
    final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
    expect(lines.first.split(','), SessionRecorder.telemetryCsvHeader);
    expect(SessionRecorder.telemetryCsvHeader, hasLength(43));
    await recorder.stop();
  });

  test('telemetry.csv ends with the eight version-4 tester-stats columns', () {
    expect(SessionRecorder.telemetryCsvHeader.sublist(35), [
      'step_gap_max_ms',
      'step_gap_over_count',
      'rtt_did',
      'rtt_min_ms',
      'rtt_max_ms',
      'rtt_sum_ms',
      'rtt_count',
      'rtt_nrc78_count',
    ]);
  });

  test('events.csv header matches the documented columns', () async {
    await recorder.start(_testMeta());
    final lines = File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync();
    expect(lines.first.split(','), SessionRecorder.eventsCsvHeader);
    await recorder.stop();
  });

  const v4Columns = [
    'step_gap_max_ms',
    'step_gap_over_count',
    'rtt_did',
    'rtt_min_ms',
    'rtt_max_ms',
    'rtt_sum_ms',
    'rtt_count',
    'rtt_nrc78_count',
  ];

  group('version 4 telemetry rows', () {
    test('a valid v4 packet fills the v3 columns and all eight tester-stats columns', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV4Packet(
        seq: 7,
        deviceTimeMs: 99,
        rpm: 2500,
        speed: 30,
        rpmAgeMs: 5,
        canBusState: BleCanBusState.running,
        canFlags: BleCanFlagsBits.pollerEnabled,
        stepGapMaxMs: 250,
        stepGapOverCount: 4,
        rttDid: 0xF40C,
        rttMinMs: 20,
        rttMaxMs: 300,
        rttSumMs: 4000000000,
        rttCount: 100,
        rttNrc78Count: 2,
      ));
      await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      expect(lines.length, 2);
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      expect(row.length, header.length);
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['seq'], '7');
      expect(byName['decode_error'], '');
      expect(byName['raw_hex']!.length, BleTelemetry.totalBytesV4 * 2);
      expect(byName['packet_version'], '4');
      expect(byName['device_time_ms'], '99');
      expect(byName['rpm_age_ms'], '5');
      expect(byName['can_bus_state'], '1');
      expect(byName['can_flags'], '1');
      expect(byName['step_gap_max_ms'], '250');
      expect(byName['step_gap_over_count'], '4');
      expect(byName['rtt_did'], '${0xF40C}');
      expect(byName['rtt_min_ms'], '20');
      expect(byName['rtt_max_ms'], '300');
      expect(byName['rtt_sum_ms'], '4000000000');
      expect(byName['rtt_count'], '100');
      expect(byName['rtt_nrc78_count'], '2');
    });

    test('a v4 packet with no round-trip record writes the raw sentinels', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV4Packet(seq: 1, rttDid: 0, rttMinMs: 65535, rttMaxMs: 0));
      await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['rtt_did'], '0');
      expect(byName['rtt_min_ms'], '65535');
      expect(byName['rtt_max_ms'], '0');
      expect(byName['rtt_sum_ms'], '0');
      expect(byName['rtt_count'], '0');
    });

    test('a v4 byte with the wrong length keeps the row with a size-mismatch error and empty v4 columns', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(Uint8List.fromList([TelemetryVersion.v4, 3]));
      final summary = await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['decode_error'], contains('size mismatch'));
      expect(byName['decode_error'], contains('${BleTelemetry.totalBytesV4}'));
      for (final column in v4Columns) {
        expect(byName[column], '', reason: column);
      }
      expect(summary.decodeErrorCount, 1);
    });

    test('v4 packets feed the can_health and did_unanswered events like v3', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV4Packet(seq: 0, canBusState: BleCanBusState.running, unansweredDidCount: 1));
      recorder.handleRawPacket(buildV4Packet(seq: 1, canBusState: BleCanBusState.busOff, unansweredDidCount: 3));
      await recorder.stop();

      final events =
          File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync().skip(1).map((l) => l.split(',')).toList();
      expect(events.where((e) => e[2] == 'can_health'), hasLength(2));
      expect(events.where((e) => e[2] == 'did_unanswered').map((e) => e[3]), ['count=3;delta=2']);
    });

    test('a v4 packet counts as a full-layout packet, not as a reason to recommend a firmware update', () async {
      await recorder.start(_testMeta());
      for (var i = 0; i < 19; i++) {
        recorder.handleRawPacket(buildV2Packet(seq: i));
      }
      recorder.handleRawPacket(buildV4Packet(seq: 19));
      expect(recorder.firmwareUpdateRecommended, isFalse);
      final summary = await recorder.stop();

      expect(summary.packetVersions, {2: 19, 4: 1});
    });
  });

  group('version 3 telemetry rows', () {
    test('a valid v3 packet fills every v3-only column', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(
        seq: 5,
        deviceTimeMs: 42,
        rpm: 4500,
        speed: 80,
        flags: 0xFF,
        rpmAgeMs: 10,
        speedAgeMs: 20,
        coolantTempAgeMs: 30,
        throttlePosAgeMs: 40,
        batteryVoltAgeMs: 50,
        canBusState: 1,
        canTxErrorCount: 2,
        canRxErrorCount: 3,
        canBusOffCount: 0,
        unansweredDidCount: 4,
        canFlags: 0x01,
      ));
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
      expect(byName['raw_hex']!.length, BleTelemetry.totalBytesV3 * 2);
      expect(byName['packet_version'], '3');
      expect(byName['device_time_ms'], '42');
      expect(byName['rpm_age_ms'], '10');
      expect(byName['speed_age_ms'], '20');
      expect(byName['coolant_age_ms'], '30');
      expect(byName['tps_age_ms'], '40');
      expect(byName['battery_age_ms'], '50');
      expect(byName['imu_active'], '1');
      expect(byName['can_bus_state'], '1');
      expect(byName['can_tec'], '2');
      expect(byName['can_rec'], '3');
      expect(byName['can_bus_off_count'], '0');
      expect(byName['unanswered_did_count'], '4');
      expect(byName['can_flags'], '1');
      // Version-4-only columns stay empty on a version 3 row.
      for (final column in v4Columns) {
        expect(byName[column], '', reason: column);
      }
      // Lean columns: deprecated, always empty for v3.
      expect(byName['lean_deg'], '');
      expect(byName['max_lean_right_deg'], '');
      expect(byName['max_lean_left_deg'], '');
    });

    test('an age of 65535 (neverReceived) writes an empty age column', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 1, rpmAgeMs: BleTelemetry.ageNeverReceived));
      await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};
      expect(byName['rpm_age_ms'], '');
    });
  });

  group('version 2 telemetry rows (old firmware or low MTU)', () {
    test('v2 packets are still written, with packet_version=2 and the v3/v4-only columns empty', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV2Packet(seq: 9, rpm: 3000, speed: 40, flags: 0x7F));
      await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['rpm'], '3000.0');
      expect(byName['speed_kmh'], '40');
      expect(byName['raw_hex']!.length, BleTelemetry.totalBytesV2 * 2);
      expect(byName['packet_version'], '2');
      expect(byName['device_time_ms'], '');
      expect(byName['rpm_age_ms'], '');
      expect(byName['speed_age_ms'], '');
      expect(byName['coolant_age_ms'], '');
      expect(byName['tps_age_ms'], '');
      expect(byName['battery_age_ms'], '');
      expect(byName['imu_active'], '');
      expect(byName['can_bus_state'], '');
      expect(byName['can_tec'], '');
      expect(byName['can_rec'], '');
      expect(byName['can_bus_off_count'], '');
      expect(byName['unanswered_did_count'], '');
      expect(byName['can_flags'], '');
      for (final column in v4Columns) {
        expect(byName[column], '', reason: column);
      }
    });
  });

  group('lost_since_prev (rolling seq, mod 256)', () {
    test('consecutive seq numbers count no loss', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 10));
      recorder.handleRawPacket(buildV3Packet(seq: 11));
      final summary = await recorder.stop();

      expect(summary.lostCount, 0);
    });

    test('a gap between seq numbers is counted as lost packets', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 10));
      recorder.handleRawPacket(buildV3Packet(seq: 15));
      final summary = await recorder.stop();

      expect(summary.lostCount, 4); // seq 11, 12, 13, 14 missed
    });

    test('a gap across the 254->1 rollover counts as 2 lost', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 254));
      recorder.handleRawPacket(buildV3Packet(seq: 1));
      final summary = await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      final lostIdx = SessionRecorder.telemetryCsvHeader.indexOf('lost_since_prev');
      final row2 = lines[2].split(',');

      expect(row2[lostIdx], '2');
      expect(summary.lostCount, 2);
    });
  });

  group('decode-error rows are kept, never dropped', () {
    test('an unrecognized version is written with decode_error and blank decoded fields', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV2Packet(version: 1, seq: 9));
      final summary = await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      expect(lines.length, 2);
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['decode_error'], contains('version mismatch'));
      expect(byName['seq'], '9');
      expect(byName['rpm'], '');
      expect(byName['packet_version'], '');
      expect(summary.decodeErrorCount, 1);
      expect(summary.packetCount, 1);
    });

    test('a version-3 byte with the wrong length is written with a size-mismatch decode_error', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(Uint8List.fromList([TelemetryVersion.v3, 3]));
      final summary = await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/telemetry.csv').readAsLinesSync();
      const header = SessionRecorder.telemetryCsvHeader;
      final row = lines[1].split(',');
      final byName = {for (var i = 0; i < header.length; i++) header[i]: row[i]};

      expect(byName['decode_error'], contains('size mismatch'));
      expect(byName['seq'], '3');
      expect(byName['raw_hex'], '0303');
      expect(summary.decodeErrorCount, 1);
    });

    test('an events.csv decode_error row is logged for every failed packet', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV2Packet(version: 1, seq: 1));
      await recorder.stop();

      final events =
          File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync().skip(1).map((l) => l.split(',')[2]).toList();
      expect(events, contains('decode_error'));
    });
  });

  test('events.csv logs recording_started, packet_gap and recording_stopped', () async {
    await recorder.start(_testMeta());
    recorder.handleRawPacket(buildV3Packet(seq: 0));
    recorder.handleRawPacket(buildV3Packet(seq: 5)); // gap of 4
    await recorder.stop();

    final events =
        File('${recorder.sessionDir!.path}/events.csv').readAsLinesSync().skip(1).map((l) => l.split(',')[2]).toList();
    expect(events, containsAll(['recording_started', 'packet_gap', 'recording_stopped']));
  });

  group('packet_version event', () {
    test('is logged once for the first packet and again only when the version changes', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 0));
      recorder.handleRawPacket(buildV3Packet(seq: 1)); // same version: no new event
      recorder.handleRawPacket(buildV2Packet(seq: 2)); // version changes: new event
      recorder.handleRawPacket(buildV2Packet(seq: 3)); // same version: no new event
      await recorder.stop();

      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'packet_version')
          .map((l) => l.split(',')[3])
          .toList();
      expect(events, ['version=3', 'version=2']);
    });

    test('logs version=4 for a v4 packet and counts it in the summary', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV4Packet(seq: 0));
      recorder.handleRawPacket(buildV4Packet(seq: 1));
      final summary = await recorder.stop();

      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'packet_version')
          .map((l) => l.split(',')[3])
          .toList();
      expect(events, ['version=4']);
      expect(summary.packetVersions, {4: 2});
    });
  });

  group('can_health event', () {
    test('is logged for the first v3 packet, and again only when state/flags/busOffCount change', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 0, canBusState: 1, canFlags: 0x01, canBusOffCount: 0));
      recorder.handleRawPacket(buildV3Packet(seq: 1, canBusState: 1, canFlags: 0x01, canBusOffCount: 0)); // unchanged
      recorder.handleRawPacket(buildV3Packet(seq: 2, canBusState: 3, canFlags: 0x01, canBusOffCount: 0)); // busState changed
      recorder.handleRawPacket(buildV3Packet(seq: 3, canBusState: 3, canFlags: 0x01, canBusOffCount: 1)); // busOffCount changed
      await recorder.stop();

      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'can_health')
          .toList();
      expect(events, hasLength(3));
      expect(events[0].split(',')[3], contains('state=running'));
      expect(events[1].split(',')[3], contains('state=busOff'));
      expect(events[2].split(',')[3], contains('bus_off=1'));
    });
  });

  group('did_unanswered event', () {
    test('is logged only when unansweredDidCount increases', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 0, unansweredDidCount: 2));
      recorder.handleRawPacket(buildV3Packet(seq: 1, unansweredDidCount: 2)); // no increase
      recorder.handleRawPacket(buildV3Packet(seq: 2, unansweredDidCount: 5)); // +3
      await recorder.stop();

      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'did_unanswered')
          .map((l) => l.split(',')[3])
          .toList();
      expect(events, ['count=5;delta=3']);
    });
  });

  group('firmware_update_recommended event', () {
    test('fires once after the first 20 packets are all v2 with mtu unknown', () async {
      await recorder.start(_testMeta());
      for (var i = 0; i < 20; i++) {
        recorder.handleRawPacket(buildV2Packet(seq: i));
      }
      expect(recorder.firmwareUpdateRecommended, isTrue);
      // A 21st v2 packet must not log the event again.
      recorder.handleRawPacket(buildV2Packet(seq: 20));
      await recorder.stop();

      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'firmware_update_recommended')
          .toList();
      expect(events, hasLength(1));
      expect(events.single.split(',')[3], 'only v2 packets received');
    });

    test('does not fire when the mtu is known to be too small for v3', () async {
      await recorder.start(_testMeta());
      recorder.handleMtuNegotiated(23); // default/minimum MTU: v2 is expected here
      for (var i = 0; i < 20; i++) {
        recorder.handleRawPacket(buildV2Packet(seq: i));
      }
      expect(recorder.firmwareUpdateRecommended, isFalse);
      await recorder.stop();
    });

    test('does not fire when at least one v3 packet is seen in the first 20', () async {
      await recorder.start(_testMeta());
      for (var i = 0; i < 19; i++) {
        recorder.handleRawPacket(buildV2Packet(seq: i));
      }
      recorder.handleRawPacket(buildV3Packet(seq: 19));
      expect(recorder.firmwareUpdateRecommended, isFalse);
      await recorder.stop();
    });
  });

  group('mtu_negotiated event', () {
    test('is logged with the negotiated value and tracked on the recorder', () async {
      await recorder.start(_testMeta());
      recorder.handleMtuNegotiated(185);
      expect(recorder.currentMtu, 185);
      final summary = await recorder.stop();

      expect(summary.mtu, 185);
      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'mtu_negotiated')
          .map((l) => l.split(',')[3])
          .toList();
      expect(events, ['mtu=185']);
    });
  });

  group('IMU blocks', () {
    test('imu.csv is created lazily and has the documented header', () async {
      await recorder.start(_testMeta());
      expect(File('${recorder.sessionDir!.path}/imu.csv').existsSync(), isFalse);

      recorder.handleRawImuBlock(buildImuBlockBytes(sampleCount: 2, ax: 4096));
      await recorder.stop();

      final imuFile = File('${recorder.sessionDir!.path}/imu.csv');
      expect(imuFile.existsSync(), isTrue);
      final lines = imuFile.readAsLinesSync();
      expect(lines.first.split(','), SessionRecorder.imuCsvHeader);
      expect(lines.length, 3); // header + 2 sample rows
    });

    test('writes one row per sample with raw and scaled columns, and the block missing count on row 0 only',
        () async {
      await recorder.start(_testMeta());
      recorder.handleRawImuBlock(buildImuBlockBytes(
        seq: 3,
        firstSampleIndex: 100,
        sampleCount: 3,
        deviceTimeMs: 1000,
        samplePeriodMs: 10,
        ax: 4096,
        gy: 655,
      ));
      await recorder.stop();

      final lines = File('${recorder.sessionDir!.path}/imu.csv').readAsLinesSync();
      const header = SessionRecorder.imuCsvHeader;
      final rows = lines.skip(1).map((l) => l.split(',')).toList();
      expect(rows, hasLength(3));

      final row0 = {for (var i = 0; i < header.length; i++) header[i]: rows[0][i]};
      expect(row0['block_seq'], '3');
      expect(row0['block_missing_samples'], '0'); // first block of the session
      expect(row0['sample_index'], '100');
      expect(row0['device_time_ms'], '1000');
      expect(row0['ax_raw'], '4096');
      expect(row0['ax_g'], '1.0');
      expect(double.parse(row0['gy_dps']!), closeTo(10.0, 0.01));

      final row1 = {for (var i = 0; i < header.length; i++) header[i]: rows[1][i]};
      expect(row1['sample_index'], '101');
      expect(row1['device_time_ms'], '1010');
      expect(row1['block_missing_samples'], '0'); // not the first row of the block
    });

    test('a gap between blocks logs imu_gap with the missing count on the first row only', () async {
      await recorder.start(_testMeta());
      recorder.handleRawImuBlock(buildImuBlockBytes(firstSampleIndex: 0, sampleCount: 5));
      recorder.handleRawImuBlock(buildImuBlockBytes(firstSampleIndex: 8, sampleCount: 2)); // 3 missing
      final summary = await recorder.stop();

      expect(summary.imuBlockCount, 2);
      expect(summary.imuSampleCount, 7);
      expect(summary.imuMissingSamples, 3);
      expect(summary.imuLossPercent, closeTo(3 / 10 * 100, 0.01));

      final lines = File('${recorder.sessionDir!.path}/imu.csv').readAsLinesSync();
      const header = SessionRecorder.imuCsvHeader;
      final rows = lines.skip(1).map((l) => l.split(',')).toList();
      final missingIdx = header.indexOf('block_missing_samples');
      // Rows: 5 from the first block (all 0), then 2 from the second (3, 0).
      expect(rows[5][missingIdx], '3');
      expect(rows[6][missingIdx], '0');

      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'imu_gap')
          .map((l) => l.split(',')[3])
          .toList();
      expect(events, ['missing=3;sample_index=8']);
    });

    test('a malformed IMU block is counted as a decode error with an imu:-prefixed detail, and writes no rows',
        () async {
      await recorder.start(_testMeta());
      recorder.handleRawImuBlock(Uint8List(4)); // too short for even the header
      final summary = await recorder.stop();

      expect(summary.decodeErrorCount, 1);
      expect(File('${recorder.sessionDir!.path}/imu.csv').existsSync(), isFalse);

      final events = File('${recorder.sessionDir!.path}/events.csv')
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.split(',')[2] == 'decode_error')
          .map((l) => l.split(',')[3])
          .toList();
      expect(events, hasLength(1));
      expect(events.single, startsWith('imu:'));
    });

    test('a session with no IMU blocks never creates imu.csv', () async {
      await recorder.start(_testMeta());
      recorder.handleRawPacket(buildV3Packet(seq: 0));
      final summary = await recorder.stop();

      expect(File('${recorder.sessionDir!.path}/imu.csv').existsSync(), isFalse);
      expect(summary.imuBlockCount, 0);
      expect(summary.imuSampleCount, 0);
      expect(summary.imuLossPercent, 0.0);
    });
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

  test('summary.json reports duration, packet/lost counts, loss percent, disconnects and packet_versions', () async {
    await recorder.start(_testMeta());
    recorder.handleConnectionChange(true);
    recorder.handleRawPacket(buildV3Packet(seq: 0));
    recorder.handleRawPacket(buildV3Packet(seq: 2)); // 1 lost
    recorder.handleRawPacket(buildV2Packet(seq: 3));
    recorder.handleConnectionChange(false);
    final summary = await recorder.stop();

    expect(summary.packetCount, 3);
    expect(summary.lostCount, 1);
    expect(summary.lossPercent, closeTo(1 / 4 * 100, 0.01));
    expect(summary.disconnectCount, 1);
    expect(summary.firstPacketUtc, isNotNull);
    expect(summary.lastPacketUtc, isNotNull);
    expect(summary.packetVersions, {3: 2, 2: 1});

    final summaryFile = File('${recorder.sessionDir!.path}/summary.json');
    expect(summaryFile.existsSync(), isTrue);
    final decoded = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['packet_count'], 3);
    expect(decoded['lost_count'], 1);
    expect(decoded['disconnect_count'], 1);
    expect(decoded['packet_versions'], {'3': 2, '2': 1});
    expect(decoded.containsKey('imu_block_count'), isTrue);
    expect(decoded.containsKey('imu_sample_count'), isTrue);
    expect(decoded.containsKey('imu_missing_samples'), isTrue);
    expect(decoded.containsKey('imu_loss_percent'), isTrue);
    expect(decoded.containsKey('mtu'), isTrue);
  });

  test('SessionMeta defaults to the current schema version, and to 3 for old meta.json files', () {
    expect(_testMeta().bleSchemaVersion, BleTelemetry.currentVersion);

    final legacyJson = _testMeta().toJson()..remove('ble_schema_version');
    expect(SessionMeta.fromJson(legacyJson).bleSchemaVersion, TelemetryVersion.v3);
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
