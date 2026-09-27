// The BLE packet schema has ONE source: moto-connectivity-node's
// docs/ble_telemetry_packet_schema.json. test/fixtures/ keeps a byte-identical copy
// that the decoder tests use; this test fails when the copy drifts from the source.
//
// Source location, in order:
//   1. MOTO_CONN_SCHEMA (path to the file; CI downloads it there)
//   2. ../moto-connectivity-node/docs/ble_telemetry_packet_schema.json (workspace layout)
// If neither exists the test is skipped, unless MOTO_SCHEMA_DRIFT_REQUIRED=1.
//
// The second group below re-checks the decoder's constants (telemetry
// version 3, its lowMtuFallback version 2, and the IMU block) against
// whichever copy of the schema is on disk -- the fixture when there is no
// external source, or the external source itself when
// MOTO_SCHEMA_DRIFT_REQUIRED=1 demands byte-identity with it anyway. This
// catches "the fixture was updated but the decoder wasn't" even when CI has
// no access to the external source.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mobile/models/imu_block.dart';
import 'package:moto_mobile/models/telemetry_data.dart';

const _fixturePath = 'test/fixtures/ble_telemetry_packet_schema.json';
const _workspacePath = '../moto-connectivity-node/docs/ble_telemetry_packet_schema.json';

File? _sourceSchema() {
  final fromEnv = Platform.environment['MOTO_CONN_SCHEMA'];
  for (final path in [if (fromEnv != null && fromEnv.isNotEmpty) fromEnv, _workspacePath]) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

void main() {
  final source = _sourceSchema();
  final required = Platform.environment['MOTO_SCHEMA_DRIFT_REQUIRED'] == '1';

  test(
    'fixture is a byte-identical copy of the connectivity-node schema',
    () {
      if (source == null) {
        fail('MOTO_SCHEMA_DRIFT_REQUIRED=1 but no source schema was found');
      }
      final fixture = File(_fixturePath).readAsBytesSync();
      expect(source.readAsBytesSync(), orderedEquals(fixture),
          reason: 'copy ${source.path} to $_fixturePath and update the decoder tests');
    },
    skip: source == null && !required
        ? 'source schema not available (set MOTO_CONN_SCHEMA or use the workspace layout)'
        : false,
  );

  group('decoder constants match the schema fixture', () {
    late Map<String, dynamic> schema;

    setUpAll(() {
      final raw = File(_fixturePath).readAsStringSync();
      schema = jsonDecode(raw) as Map<String, dynamic>;
    });

    test('telemetry version 3 (top-level fields)', () {
      expect(schema['version'], bleTelemetryV3Version);
      expect(schema['totalBytes'], bleTelemetryV3TotalBytes);

      final byName = {
        for (final f in (schema['fields'] as List).cast<Map<String, dynamic>>()) f['name'] as String: f,
      };
      final offsets = <String, int>{
        'version': BleTelemetryV3Offsets.version,
        'seq': BleTelemetryV3Offsets.seq,
        'deviceTimeMs': BleTelemetryV3Offsets.deviceTimeMs,
        'rpm': BleTelemetryV3Offsets.rpm,
        'speed': BleTelemetryV3Offsets.speed,
        'coolantTemp': BleTelemetryV3Offsets.coolantTemp,
        'throttlePos': BleTelemetryV3Offsets.throttlePos,
        'batteryVolt': BleTelemetryV3Offsets.batteryVolt,
        'leanAngle': BleTelemetryV3Offsets.leanAngle,
        'maxLeanRight': BleTelemetryV3Offsets.maxLeanRight,
        'maxLeanLeft': BleTelemetryV3Offsets.maxLeanLeft,
        'flags': BleTelemetryV3Offsets.flags,
        'rpmAgeMs': BleTelemetryV3Offsets.rpmAgeMs,
        'speedAgeMs': BleTelemetryV3Offsets.speedAgeMs,
        'coolantTempAgeMs': BleTelemetryV3Offsets.coolantTempAgeMs,
        'throttlePosAgeMs': BleTelemetryV3Offsets.throttlePosAgeMs,
        'batteryVoltAgeMs': BleTelemetryV3Offsets.batteryVoltAgeMs,
        'canBusState': BleTelemetryV3Offsets.canBusState,
        'canTxErrorCount': BleTelemetryV3Offsets.canTxErrorCount,
        'canRxErrorCount': BleTelemetryV3Offsets.canRxErrorCount,
        'canBusOffCount': BleTelemetryV3Offsets.canBusOffCount,
        'unansweredDidCount': BleTelemetryV3Offsets.unansweredDidCount,
        'canFlags': BleTelemetryV3Offsets.canFlags,
      };
      expect(byName.keys.toSet(), offsets.keys.toSet());
      offsets.forEach((name, offset) {
        expect(byName[name]!['offset'], offset, reason: name);
      });
    });

    test('telemetry version 2 (lowMtuFallback fields)', () {
      final fallback = schema['lowMtuFallback'] as Map<String, dynamic>;
      expect(fallback['version'], bleTelemetryV2Version);
      expect(fallback['totalBytes'], bleTelemetryV2TotalBytes);

      final byName = {
        for (final f in (fallback['fields'] as List).cast<Map<String, dynamic>>()) f['name'] as String: f,
      };
      final offsets = <String, int>{
        'version': BleTelemetryV2Offsets.version,
        'seq': BleTelemetryV2Offsets.seq,
        'rpm': BleTelemetryV2Offsets.rpm,
        'speed': BleTelemetryV2Offsets.speed,
        'coolantTemp': BleTelemetryV2Offsets.coolantTemp,
        'throttlePos': BleTelemetryV2Offsets.throttlePos,
        'batteryVolt': BleTelemetryV2Offsets.batteryVolt,
        'leanAngle': BleTelemetryV2Offsets.leanAngle,
        'maxLeanRight': BleTelemetryV2Offsets.maxLeanRight,
        'maxLeanLeft': BleTelemetryV2Offsets.maxLeanLeft,
        'flags': BleTelemetryV2Offsets.flags,
      };
      expect(byName.keys.toSet(), offsets.keys.toSet());
      offsets.forEach((name, offset) {
        expect(byName[name]!['offset'], offset, reason: name);
      });
    });

    test('shared flags bits (version 2 and version 3)', () {
      final byName = {
        for (final b in (schema['flags']['bits'] as List).cast<Map<String, dynamic>>()) b['name'] as String: b,
      };
      final bits = <String, int>{
        'rpmValid': BleTelemetryFlagBits.rpmValid,
        'speedValid': BleTelemetryFlagBits.speedValid,
        'coolantTempValid': BleTelemetryFlagBits.coolantTempValid,
        'throttlePosValid': BleTelemetryFlagBits.throttlePosValid,
        'batteryVoltValid': BleTelemetryFlagBits.batteryVoltValid,
        'leanValid': BleTelemetryFlagBits.leanValid,
        'ecuPresent': BleTelemetryFlagBits.ecuPresent,
        'imuActive': BleTelemetryFlagBits.imuActive,
      };
      bits.forEach((name, bit) {
        expect(byName[name]!['bit'], bit, reason: name);
      });
    });

    test('canHealth.busState and canFlags', () {
      final states = {
        for (final v in (schema['canHealth']['busState']['values'] as List).cast<Map<String, dynamic>>())
          v['name'] as String: v['value'] as int,
      };
      expect(states, {
        'notInstalled': CanBusState.notInstalled.value,
        'running': CanBusState.running.value,
        'errorWarning': CanBusState.errorWarning.value,
        'busOff': CanBusState.busOff.value,
        'stopped': CanBusState.stopped.value,
      });

      final flagBits = {
        for (final b in (schema['canHealth']['canFlags']['bits'] as List).cast<Map<String, dynamic>>())
          b['name'] as String: b['bit'] as int,
      };
      expect(flagBits['pollerEnabled'], CanFlagsBits.pollerEnabled);
      expect(flagBits['latchedForeignTester'], CanFlagsBits.latchedForeignTester);
      expect(flagBits['latchedBusOff'], CanFlagsBits.latchedBusOff);
      expect(flagBits['syntheticData'], CanFlagsBits.syntheticData);
    });

    test('IMU block header, samples and scale', () {
      final imu = schema['imuBlock'] as Map<String, dynamic>;
      expect(imu['version'], imuBlockVersion);
      expect(imu['headerBytes'], imuBlockHeaderBytes);
      expect(imu['sampleBytes'], imuBlockSampleBytes);
      expect(imu['maxSamples'], imuBlockMaxSamples);
      expect(imu['samplePeriodMs'], imuBlockSamplePeriodMsDefault);

      expect((imu['scale']['accel']['lsbPerUnit'] as num).toDouble(), ImuScale.accelLsbPerG);
      expect((imu['scale']['gyro']['lsbPerUnit'] as num).toDouble(), ImuScale.gyroLsbPerDps);

      final headerByName = {
        for (final f in (imu['headerFields'] as List).cast<Map<String, dynamic>>()) f['name'] as String: f,
      };
      final headerOffsets = <String, int>{
        'version': ImuBlockHeaderOffsets.version,
        'seq': ImuBlockHeaderOffsets.seq,
        'deviceTimeMs': ImuBlockHeaderOffsets.deviceTimeMs,
        'firstSampleIndex': ImuBlockHeaderOffsets.firstSampleIndex,
        'sampleCount': ImuBlockHeaderOffsets.sampleCount,
        'samplePeriodMs': ImuBlockHeaderOffsets.samplePeriodMs,
        'flags': ImuBlockHeaderOffsets.flags,
        'reserved': ImuBlockHeaderOffsets.reserved,
      };
      expect(headerByName.keys.toSet(), headerOffsets.keys.toSet());
      headerOffsets.forEach((name, offset) {
        expect(headerByName[name]!['offset'], offset, reason: name);
      });

      final sampleByName = {
        for (final f in (imu['sampleFields'] as List).cast<Map<String, dynamic>>()) f['name'] as String: f,
      };
      final sampleOffsets = <String, int>{
        'ax': ImuSampleOffsets.ax,
        'ay': ImuSampleOffsets.ay,
        'az': ImuSampleOffsets.az,
        'gx': ImuSampleOffsets.gx,
        'gy': ImuSampleOffsets.gy,
        'gz': ImuSampleOffsets.gz,
      };
      expect(sampleByName.keys.toSet(), sampleOffsets.keys.toSet());
      sampleOffsets.forEach((name, offset) {
        expect(sampleByName[name]!['offset'], offset, reason: name);
      });

      final flagByName = {
        for (final b in (imu['flags']['bits'] as List).cast<Map<String, dynamic>>())
          b['name'] as String: b['bit'] as int,
      };
      expect(flagByName['deviceOverflow'], ImuBlockFlagBits.deviceOverflow);
      expect(flagByName['readError'], ImuBlockFlagBits.readError);
      expect(flagByName['sensorReconfigured'], ImuBlockFlagBits.sensorReconfigured);
    });
  });
}
