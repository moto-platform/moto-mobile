import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/telemetry_data.dart';

// The packet layout comes from the generated `moto_defs` package (D-061,
// moto-vehicle-defs `ble/ble_schema.json`); these tests build packets byte by
// byte from the generated offsets and check the decoder against them. There
// is no schema copy in this repo.

/// Builds a raw version-4 (57-byte) packet from field values, byte by byte
/// from [BleTelemetryV4Offsets], little-endian.
Uint8List buildV4Packet({
  int version = TelemetryVersion.v4,
  int seq = 0,
  int deviceTimeMs = 0,
  int rpm = 0,
  int speed = 0,
  int coolantTemp = 0,
  int throttlePos = 0,
  int batteryVoltMv = 0,
  int leanAngleTenths = BleTelemetry.notAvailableInt16,
  int maxLeanRightTenths = BleTelemetry.notAvailableInt16,
  int maxLeanLeftTenths = BleTelemetry.notAvailableInt16,
  int flags = 0,
  int rpmAgeMs = BleTelemetry.ageNeverReceived,
  int speedAgeMs = BleTelemetry.ageNeverReceived,
  int coolantTempAgeMs = BleTelemetry.ageNeverReceived,
  int throttlePosAgeMs = BleTelemetry.ageNeverReceived,
  int batteryVoltAgeMs = BleTelemetry.ageNeverReceived,
  int canBusState = 0,
  int canTxErrorCount = 0,
  int canRxErrorCount = 0,
  int canBusOffCount = 0,
  int unansweredDidCount = 0,
  int canFlags = 0,
  int stepGapMaxMs = 0,
  int stepGapOverCount = 0,
  int rttDid = 0,
  int rttMinMs = 65535,
  int rttMaxMs = 0,
  int rttSumMs = 0,
  int rttCount = 0,
  int rttNrc78Count = 0,
}) {
  final bytes = ByteData(BleTelemetry.totalBytesV4);
  bytes.setUint8(BleTelemetryV4Offsets.version, version);
  bytes.setUint8(BleTelemetryV4Offsets.seq, seq);
  bytes.setUint32(BleTelemetryV4Offsets.deviceTimeMs, deviceTimeMs, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.rpm, rpm, Endian.little);
  bytes.setUint8(BleTelemetryV4Offsets.speed, speed);
  bytes.setInt8(BleTelemetryV4Offsets.coolantTemp, coolantTemp);
  bytes.setUint8(BleTelemetryV4Offsets.throttlePos, throttlePos);
  bytes.setUint16(BleTelemetryV4Offsets.batteryVolt, batteryVoltMv, Endian.little);
  bytes.setInt16(BleTelemetryV4Offsets.leanAngle, leanAngleTenths, Endian.little);
  bytes.setInt16(BleTelemetryV4Offsets.maxLeanRight, maxLeanRightTenths, Endian.little);
  bytes.setInt16(BleTelemetryV4Offsets.maxLeanLeft, maxLeanLeftTenths, Endian.little);
  bytes.setUint8(BleTelemetryV4Offsets.flags, flags);
  bytes.setUint16(BleTelemetryV4Offsets.rpmAgeMs, rpmAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.speedAgeMs, speedAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.coolantTempAgeMs, coolantTempAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.throttlePosAgeMs, throttlePosAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.batteryVoltAgeMs, batteryVoltAgeMs, Endian.little);
  bytes.setUint8(BleTelemetryV4Offsets.canBusState, canBusState);
  bytes.setUint8(BleTelemetryV4Offsets.canTxErrorCount, canTxErrorCount);
  bytes.setUint8(BleTelemetryV4Offsets.canRxErrorCount, canRxErrorCount);
  bytes.setUint8(BleTelemetryV4Offsets.canBusOffCount, canBusOffCount);
  bytes.setUint16(BleTelemetryV4Offsets.unansweredDidCount, unansweredDidCount, Endian.little);
  bytes.setUint8(BleTelemetryV4Offsets.canFlags, canFlags);
  bytes.setUint16(BleTelemetryV4Offsets.stepGapMaxMs, stepGapMaxMs, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.stepGapOverCount, stepGapOverCount, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.rttDid, rttDid, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.rttMinMs, rttMinMs, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.rttMaxMs, rttMaxMs, Endian.little);
  bytes.setUint32(BleTelemetryV4Offsets.rttSumMs, rttSumMs, Endian.little);
  bytes.setUint32(BleTelemetryV4Offsets.rttCount, rttCount, Endian.little);
  bytes.setUint16(BleTelemetryV4Offsets.rttNrc78Count, rttNrc78Count, Endian.little);
  return bytes.buffer.asUint8List();
}

/// Builds a raw version-3 (37-byte) packet from field values.
Uint8List buildV3Packet({
  int version = TelemetryVersion.v3,
  int seq = 0,
  int deviceTimeMs = 0,
  int rpm = 0,
  int speed = 0,
  int coolantTemp = 0,
  int throttlePos = 0,
  int batteryVoltMv = 0,
  int leanAngleTenths = BleTelemetry.notAvailableInt16,
  int maxLeanRightTenths = BleTelemetry.notAvailableInt16,
  int maxLeanLeftTenths = BleTelemetry.notAvailableInt16,
  int flags = 0,
  int rpmAgeMs = BleTelemetry.ageNeverReceived,
  int speedAgeMs = BleTelemetry.ageNeverReceived,
  int coolantTempAgeMs = BleTelemetry.ageNeverReceived,
  int throttlePosAgeMs = BleTelemetry.ageNeverReceived,
  int batteryVoltAgeMs = BleTelemetry.ageNeverReceived,
  int canBusState = 0,
  int canTxErrorCount = 0,
  int canRxErrorCount = 0,
  int canBusOffCount = 0,
  int unansweredDidCount = 0,
  int canFlags = 0,
}) {
  final bytes = ByteData(BleTelemetry.totalBytesV3);
  bytes.setUint8(BleTelemetryV3Offsets.version, version);
  bytes.setUint8(BleTelemetryV3Offsets.seq, seq);
  bytes.setUint32(BleTelemetryV3Offsets.deviceTimeMs, deviceTimeMs, Endian.little);
  bytes.setUint16(BleTelemetryV3Offsets.rpm, rpm, Endian.little);
  bytes.setUint8(BleTelemetryV3Offsets.speed, speed);
  bytes.setInt8(BleTelemetryV3Offsets.coolantTemp, coolantTemp);
  bytes.setUint8(BleTelemetryV3Offsets.throttlePos, throttlePos);
  bytes.setUint16(BleTelemetryV3Offsets.batteryVolt, batteryVoltMv, Endian.little);
  bytes.setInt16(BleTelemetryV3Offsets.leanAngle, leanAngleTenths, Endian.little);
  bytes.setInt16(BleTelemetryV3Offsets.maxLeanRight, maxLeanRightTenths, Endian.little);
  bytes.setInt16(BleTelemetryV3Offsets.maxLeanLeft, maxLeanLeftTenths, Endian.little);
  bytes.setUint8(BleTelemetryV3Offsets.flags, flags);
  bytes.setUint16(BleTelemetryV3Offsets.rpmAgeMs, rpmAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV3Offsets.speedAgeMs, speedAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV3Offsets.coolantTempAgeMs, coolantTempAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV3Offsets.throttlePosAgeMs, throttlePosAgeMs, Endian.little);
  bytes.setUint16(BleTelemetryV3Offsets.batteryVoltAgeMs, batteryVoltAgeMs, Endian.little);
  bytes.setUint8(BleTelemetryV3Offsets.canBusState, canBusState);
  bytes.setUint8(BleTelemetryV3Offsets.canTxErrorCount, canTxErrorCount);
  bytes.setUint8(BleTelemetryV3Offsets.canRxErrorCount, canRxErrorCount);
  bytes.setUint8(BleTelemetryV3Offsets.canBusOffCount, canBusOffCount);
  bytes.setUint16(BleTelemetryV3Offsets.unansweredDidCount, unansweredDidCount, Endian.little);
  bytes.setUint8(BleTelemetryV3Offsets.canFlags, canFlags);
  return bytes.buffer.asUint8List();
}

/// Builds a raw version-2 (16-byte, low-MTU fallback) packet from field
/// values.
Uint8List buildV2Packet({
  int version = TelemetryVersion.v2,
  int seq = 0,
  int rpm = 0,
  int speed = 0,
  int coolantTemp = 0,
  int throttlePos = 0,
  int batteryVoltMv = 0,
  int leanAngleTenths = BleTelemetry.notAvailableInt16,
  int maxLeanRightTenths = BleTelemetry.notAvailableInt16,
  int maxLeanLeftTenths = BleTelemetry.notAvailableInt16,
  int flags = 0,
}) {
  final bytes = ByteData(BleTelemetry.totalBytesV2);
  bytes.setUint8(BleTelemetryV2Offsets.version, version);
  bytes.setUint8(BleTelemetryV2Offsets.seq, seq);
  bytes.setUint16(BleTelemetryV2Offsets.rpm, rpm, Endian.little);
  bytes.setUint8(BleTelemetryV2Offsets.speed, speed);
  bytes.setInt8(BleTelemetryV2Offsets.coolantTemp, coolantTemp);
  bytes.setUint8(BleTelemetryV2Offsets.throttlePos, throttlePos);
  bytes.setUint16(BleTelemetryV2Offsets.batteryVolt, batteryVoltMv, Endian.little);
  bytes.setInt16(BleTelemetryV2Offsets.leanAngle, leanAngleTenths, Endian.little);
  bytes.setInt16(BleTelemetryV2Offsets.maxLeanRight, maxLeanRightTenths, Endian.little);
  bytes.setInt16(BleTelemetryV2Offsets.maxLeanLeft, maxLeanLeftTenths, Endian.little);
  bytes.setUint8(BleTelemetryV2Offsets.flags, flags);
  return bytes.buffer.asUint8List();
}

/// Every telemetry flag mask except `imuActive` (the only one version 2
/// reserves).
const int _allFlagsButImu = BleTelemetryFlagBits.rpmValid |
    BleTelemetryFlagBits.speedValid |
    BleTelemetryFlagBits.coolantTempValid |
    BleTelemetryFlagBits.throttlePosValid |
    BleTelemetryFlagBits.batteryVoltValid |
    BleTelemetryFlagBits.leanValid |
    BleTelemetryFlagBits.ecuPresent;

const int _allFlags = _allFlagsButImu | BleTelemetryFlagBits.imuActive;

void main() {
  setUp(() {
    TelemetryData.resetStats();
  });

  group('decoder constants follow the generated schema', () {
    test('TelemetryVersion matches BleTelemetry versions', () {
      expect(TelemetryVersion.v2, BleTelemetry.legacyVersion);
      expect(TelemetryVersion.v4, BleTelemetry.currentVersion);
      expect(BleTelemetry.acceptedVersions, [TelemetryVersion.v2, TelemetryVersion.v3, TelemetryVersion.v4]);
    });

    test('expectedLength matches the generated totals', () {
      expect(TelemetryData.expectedLength(TelemetryVersion.v2), BleTelemetry.totalBytesV2);
      expect(TelemetryData.expectedLength(TelemetryVersion.v3), BleTelemetry.totalBytesV3);
      expect(TelemetryData.expectedLength(TelemetryVersion.v4), BleTelemetry.totalBytesV4);
      expect(TelemetryData.expectedLength(BleTelemetry.currentVersion), BleTelemetry.totalBytes);
      expect(TelemetryData.expectedLength(1), isNull);
      expect(TelemetryData.expectedLength(5), isNull);
    });

    test('the version 4 layout starts with the version 3 layout (same offsets)', () {
      final v3 = <String, int>{
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
      final v4 = <String, int>{
        'version': BleTelemetryV4Offsets.version,
        'seq': BleTelemetryV4Offsets.seq,
        'deviceTimeMs': BleTelemetryV4Offsets.deviceTimeMs,
        'rpm': BleTelemetryV4Offsets.rpm,
        'speed': BleTelemetryV4Offsets.speed,
        'coolantTemp': BleTelemetryV4Offsets.coolantTemp,
        'throttlePos': BleTelemetryV4Offsets.throttlePos,
        'batteryVolt': BleTelemetryV4Offsets.batteryVolt,
        'leanAngle': BleTelemetryV4Offsets.leanAngle,
        'maxLeanRight': BleTelemetryV4Offsets.maxLeanRight,
        'maxLeanLeft': BleTelemetryV4Offsets.maxLeanLeft,
        'flags': BleTelemetryV4Offsets.flags,
        'rpmAgeMs': BleTelemetryV4Offsets.rpmAgeMs,
        'speedAgeMs': BleTelemetryV4Offsets.speedAgeMs,
        'coolantTempAgeMs': BleTelemetryV4Offsets.coolantTempAgeMs,
        'throttlePosAgeMs': BleTelemetryV4Offsets.throttlePosAgeMs,
        'batteryVoltAgeMs': BleTelemetryV4Offsets.batteryVoltAgeMs,
        'canBusState': BleTelemetryV4Offsets.canBusState,
        'canTxErrorCount': BleTelemetryV4Offsets.canTxErrorCount,
        'canRxErrorCount': BleTelemetryV4Offsets.canRxErrorCount,
        'canBusOffCount': BleTelemetryV4Offsets.canBusOffCount,
        'unansweredDidCount': BleTelemetryV4Offsets.unansweredDidCount,
        'canFlags': BleTelemetryV4Offsets.canFlags,
      };
      for (final entry in v3.entries) {
        expect(v4[entry.key], entry.value, reason: 'offset of ${entry.key}');
      }
    });

    test('CanBusState values equal the generated BleCanBusState', () {
      expect(CanBusState.notInstalled.value, BleCanBusState.notInstalled);
      expect(CanBusState.running.value, BleCanBusState.running);
      expect(CanBusState.errorWarning.value, BleCanBusState.errorWarning);
      expect(CanBusState.busOff.value, BleCanBusState.busOff);
      expect(CanBusState.stopped.value, BleCanBusState.stopped);
    });
  });

  group('decoding a valid version-4 packet', () {
    test('decodes every field, including the eight tester-stats fields', () {
      final packet = buildV4Packet(
        seq: 5,
        deviceTimeMs: 123456,
        rpm: 4500,
        speed: 87,
        coolantTemp: -10,
        throttlePos: 42,
        batteryVoltMv: 12400,
        leanAngleTenths: 125,
        maxLeanRightTenths: 300,
        maxLeanLeftTenths: -280,
        flags: _allFlags,
        rpmAgeMs: 10,
        speedAgeMs: 20,
        coolantTempAgeMs: 30,
        throttlePosAgeMs: 40,
        batteryVoltAgeMs: 50,
        canBusState: BleCanBusState.running,
        canTxErrorCount: 3,
        canRxErrorCount: 4,
        canBusOffCount: 1,
        unansweredDidCount: 7,
        canFlags: BleCanFlagsBits.pollerEnabled,
        stepGapMaxMs: 321,
        stepGapOverCount: 12,
        rttDid: 0xF40C,
        rttMinMs: 25,
        rttMaxMs: 480,
        rttSumMs: 4000000000, // above int32: checks the uint32 read
        rttCount: 3999999999,
        rttNrc78Count: 9,
      );
      expect(packet.length, BleTelemetry.totalBytesV4);

      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, TelemetryVersion.v4);
      expect(data.deviceTimeMs, 123456);
      expect(data.rpm, 4500.0);
      expect(data.speed, 87);
      expect(data.coolantTemp, -10);
      expect(data.throttlePos, 42.0);
      expect(data.batteryVolt, closeTo(12.4, 1e-9));
      expect(data.leanAngle, closeTo(12.5, 1e-9));
      expect(data.maxLeanRight, closeTo(30.0, 1e-9));
      expect(data.maxLeanLeft, closeTo(-28.0, 1e-9));
      expect(data.rpmValid, isTrue);
      expect(data.speedValid, isTrue);
      expect(data.coolantTempValid, isTrue);
      expect(data.throttlePosValid, isTrue);
      expect(data.batteryVoltValid, isTrue);
      expect(data.leanValid, isTrue);
      expect(data.ecuPresent, isTrue);
      expect(data.imuActive, isTrue);
      expect(data.rpmAgeMs, 10);
      expect(data.speedAgeMs, 20);
      expect(data.coolantTempAgeMs, 30);
      expect(data.throttlePosAgeMs, 40);
      expect(data.batteryVoltAgeMs, 50);
      expect(data.canBusState, CanBusState.running);
      expect(data.canTxErrorCount, 3);
      expect(data.canRxErrorCount, 4);
      expect(data.canBusOffCount, 1);
      expect(data.unansweredDidCount, 7);
      expect(data.canFlags, BleCanFlagsBits.pollerEnabled);
      expect(data.pollerEnabled, isTrue);
      expect(data.latchedForeignTester, isFalse);
      expect(data.latchedBusOff, isFalse);
      expect(data.syntheticData, isFalse);

      expect(data.stepGapMaxMs, 321);
      expect(data.stepGapOverCount, 12);
      expect(data.rttDid, 0xF40C);
      expect(data.rttMinMs, 25);
      expect(data.rttMaxMs, 480);
      expect(data.rttSumMs, 4000000000);
      expect(data.rttCount, 3999999999);
      expect(data.rttNrc78Count, 9);

      expect(TelemetryData.receivedCount, 1);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 0);
    });

    test('a packet with no round-trip record decodes the sentinels as sent', () {
      final packet = buildV4Packet(seq: 1, rttDid: 0, rttMinMs: 65535, rttMaxMs: 0);
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, TelemetryVersion.v4);
      expect(data.rttDid, 0);
      expect(data.rttMinMs, 65535);
      expect(data.rttMaxMs, 0);
      expect(data.rttSumMs, 0);
      expect(data.rttCount, 0);
      expect(data.rttNrc78Count, 0);
      // Step-gap fields are still present (version 4) and zero here.
      expect(data.stepGapMaxMs, 0);
      expect(data.stepGapOverCount, 0);
    });

    test('saturated tester-stats values decode unchanged', () {
      final packet = buildV4Packet(
        seq: 1,
        stepGapMaxMs: 65535,
        stepGapOverCount: 65535,
        rttSumMs: 0xFFFFFFFF,
        rttCount: 0xFFFFFFFF,
        rttNrc78Count: 65535,
      );
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.stepGapMaxMs, 65535);
      expect(data.stepGapOverCount, 65535);
      expect(data.rttSumMs, 0xFFFFFFFF);
      expect(data.rttCount, 0xFFFFFFFF);
      expect(data.rttNrc78Count, 65535);
    });

    test('shared fields decode the same as in a version-3 packet', () {
      final v3 = TelemetryData.fromBinaryBuffer(buildV3Packet(
        seq: 1,
        rpm: 3000,
        speed: 55,
        canBusState: BleCanBusState.errorWarning,
        canFlags: BleCanFlagsBits.syntheticData,
        rpmAgeMs: 12,
      ));
      final v4 = TelemetryData.fromBinaryBuffer(buildV4Packet(
        seq: 2,
        rpm: 3000,
        speed: 55,
        canBusState: BleCanBusState.errorWarning,
        canFlags: BleCanFlagsBits.syntheticData,
        rpmAgeMs: 12,
      ));

      expect(v4.rpm, v3.rpm);
      expect(v4.speed, v3.speed);
      expect(v4.canBusState, v3.canBusState);
      expect(v4.canFlags, v3.canFlags);
      expect(v4.syntheticData, isTrue);
      expect(v4.rpmAgeMs, v3.rpmAgeMs);
    });
  });

  group('decoding a valid version-3 packet', () {
    test('decodes all fields correctly and leaves the version-4 fields null', () {
      final packet = buildV3Packet(
        seq: 5,
        deviceTimeMs: 123456,
        rpm: 4500,
        speed: 87,
        coolantTemp: -10,
        throttlePos: 42,
        batteryVoltMv: 12400,
        leanAngleTenths: 125,
        maxLeanRightTenths: 300,
        maxLeanLeftTenths: -280,
        flags: _allFlags,
        rpmAgeMs: 10,
        speedAgeMs: 20,
        coolantTempAgeMs: 30,
        throttlePosAgeMs: 40,
        batteryVoltAgeMs: 50,
        canBusState: BleCanBusState.running,
        canTxErrorCount: 3,
        canRxErrorCount: 4,
        canBusOffCount: 1,
        unansweredDidCount: 7,
        canFlags: BleCanFlagsBits.pollerEnabled,
      );
      expect(packet.length, BleTelemetry.totalBytesV3);

      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, TelemetryVersion.v3);
      expect(data.deviceTimeMs, 123456);
      expect(data.rpm, 4500.0);
      expect(data.speed, 87);
      expect(data.coolantTemp, -10);
      expect(data.throttlePos, 42.0);
      expect(data.batteryVolt, closeTo(12.4, 1e-9));
      expect(data.leanAngle, closeTo(12.5, 1e-9));
      expect(data.maxLeanRight, closeTo(30.0, 1e-9));
      expect(data.maxLeanLeft, closeTo(-28.0, 1e-9));
      expect(data.rpmValid, isTrue);
      expect(data.speedValid, isTrue);
      expect(data.coolantTempValid, isTrue);
      expect(data.throttlePosValid, isTrue);
      expect(data.batteryVoltValid, isTrue);
      expect(data.leanValid, isTrue);
      expect(data.ecuPresent, isTrue);
      expect(data.imuActive, isTrue);
      expect(data.rpmAgeMs, 10);
      expect(data.speedAgeMs, 20);
      expect(data.coolantTempAgeMs, 30);
      expect(data.throttlePosAgeMs, 40);
      expect(data.batteryVoltAgeMs, 50);
      expect(data.canBusState, CanBusState.running);
      expect(data.canTxErrorCount, 3);
      expect(data.canRxErrorCount, 4);
      expect(data.canBusOffCount, 1);
      expect(data.unansweredDidCount, 7);
      expect(data.canFlags, BleCanFlagsBits.pollerEnabled);
      expect(data.pollerEnabled, isTrue);
      expect(data.latchedForeignTester, isFalse);

      expect(data.stepGapMaxMs, isNull);
      expect(data.stepGapOverCount, isNull);
      expect(data.rttDid, isNull);
      expect(data.rttMinMs, isNull);
      expect(data.rttMaxMs, isNull);
      expect(data.rttSumMs, isNull);
      expect(data.rttCount, isNull);
      expect(data.rttNrc78Count, isNull);

      expect(TelemetryData.receivedCount, 1);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 0);
    });

    test('a flags byte with no bits set decodes all-invalid, including imuActive', () {
      final packet = buildV3Packet(seq: 1, flags: 0);
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.rpmValid, isFalse);
      expect(data.speedValid, isFalse);
      expect(data.coolantTempValid, isFalse);
      expect(data.throttlePosValid, isFalse);
      expect(data.batteryVoltValid, isFalse);
      expect(data.leanValid, isFalse);
      expect(data.ecuPresent, isFalse);
      expect(data.imuActive, isFalse);
    });

    test('each flag mask sets exactly its own validity getter', () {
      final cases = <int, bool Function(TelemetryData)>{
        BleTelemetryFlagBits.rpmValid: (d) => d.rpmValid,
        BleTelemetryFlagBits.speedValid: (d) => d.speedValid,
        BleTelemetryFlagBits.coolantTempValid: (d) => d.coolantTempValid,
        BleTelemetryFlagBits.throttlePosValid: (d) => d.throttlePosValid,
        BleTelemetryFlagBits.batteryVoltValid: (d) => d.batteryVoltValid,
        BleTelemetryFlagBits.leanValid: (d) => d.leanValid,
        BleTelemetryFlagBits.ecuPresent: (d) => d.ecuPresent,
        BleTelemetryFlagBits.imuActive: (d) => d.imuActive,
      };
      for (final entry in cases.entries) {
        final data = TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 1, flags: entry.key));
        for (final other in cases.entries) {
          expect(other.value(data), other.key == entry.key, reason: 'mask ${entry.key} read via mask ${other.key}');
        }
      }
    });

    test('ages of 65535 (neverReceived) decode to null', () {
      final packet = buildV3Packet(
        seq: 1,
        rpmAgeMs: BleTelemetry.ageNeverReceived,
        speedAgeMs: BleTelemetry.ageNeverReceived,
        coolantTempAgeMs: BleTelemetry.ageNeverReceived,
        throttlePosAgeMs: BleTelemetry.ageNeverReceived,
        batteryVoltAgeMs: BleTelemetry.ageNeverReceived,
      );
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.rpmAgeMs, isNull);
      expect(data.speedAgeMs, isNull);
      expect(data.coolantTempAgeMs, isNull);
      expect(data.throttlePosAgeMs, isNull);
      expect(data.batteryVoltAgeMs, isNull);
    });

    test('an age at the max saturation value is a real value, not null', () {
      final packet = buildV3Packet(seq: 1, rpmAgeMs: BleTelemetry.ageMax);
      final data = TelemetryData.fromBinaryBuffer(packet);
      expect(data.rpmAgeMs, BleTelemetry.ageMax);
    });

    test('canBusState decodes every documented value', () {
      for (final entry in {
        BleCanBusState.notInstalled: CanBusState.notInstalled,
        BleCanBusState.running: CanBusState.running,
        BleCanBusState.errorWarning: CanBusState.errorWarning,
        BleCanBusState.busOff: CanBusState.busOff,
        BleCanBusState.stopped: CanBusState.stopped,
      }.entries) {
        final data = TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 1, canBusState: entry.key));
        expect(data.canBusState, entry.value, reason: 'raw ${entry.key}');
      }
    });

    test('canFlags masks map to the four getters', () {
      final data = TelemetryData.fromBinaryBuffer(buildV3Packet(
        seq: 1,
        canFlags: BleCanFlagsBits.latchedForeignTester | BleCanFlagsBits.syntheticData,
      ));
      expect(data.pollerEnabled, isFalse);
      expect(data.latchedForeignTester, isTrue);
      expect(data.latchedBusOff, isFalse);
      expect(data.syntheticData, isTrue);
    });
  });

  group('decoding a valid version-2 (low-MTU fallback) packet', () {
    test('decodes the shared fields and leaves version-3/4-only fields absent', () {
      final packet = buildV2Packet(
        seq: 5,
        rpm: 4500,
        speed: 87,
        coolantTemp: -10,
        throttlePos: 42,
        batteryVoltMv: 12400,
        leanAngleTenths: 125,
        maxLeanRightTenths: 300,
        maxLeanLeftTenths: -280,
        flags: _allFlagsButImu,
      );
      expect(packet.length, BleTelemetry.totalBytesV2);

      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, TelemetryVersion.v2);
      expect(data.deviceTimeMs, isNull);
      expect(data.rpm, 4500.0);
      expect(data.speed, 87);
      expect(data.coolantTemp, -10);
      expect(data.throttlePos, 42.0);
      expect(data.batteryVolt, closeTo(12.4, 1e-9));
      expect(data.leanAngle, closeTo(12.5, 1e-9));
      expect(data.maxLeanRight, closeTo(30.0, 1e-9));
      expect(data.maxLeanLeft, closeTo(-28.0, 1e-9));
      expect(data.rpmValid, isTrue);
      expect(data.ecuPresent, isTrue);
      expect(data.imuActive, isFalse); // bit 7 is reserved/0 on version 2
      expect(data.rpmAgeMs, isNull);
      expect(data.speedAgeMs, isNull);
      expect(data.coolantTempAgeMs, isNull);
      expect(data.throttlePosAgeMs, isNull);
      expect(data.batteryVoltAgeMs, isNull);
      expect(data.canBusState, isNull);
      expect(data.canTxErrorCount, isNull);
      expect(data.canRxErrorCount, isNull);
      expect(data.canBusOffCount, isNull);
      expect(data.unansweredDidCount, isNull);
      expect(data.canFlags, isNull);
      expect(data.pollerEnabled, isNull);
      expect(data.stepGapMaxMs, isNull);
      expect(data.stepGapOverCount, isNull);
      expect(data.rttDid, isNull);
      expect(data.rttMinMs, isNull);
      expect(data.rttMaxMs, isNull);
      expect(data.rttSumMs, isNull);
      expect(data.rttCount, isNull);
      expect(data.rttNrc78Count, isNull);
    });

    test('-32768 decodes to null for all three lean fields', () {
      final packet = buildV2Packet(
        seq: 1,
        leanAngleTenths: BleTelemetry.notAvailableInt16,
        maxLeanRightTenths: BleTelemetry.notAvailableInt16,
        maxLeanLeftTenths: BleTelemetry.notAvailableInt16,
      );
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.leanAngle, isNull);
      expect(data.maxLeanRight, isNull);
      expect(data.maxLeanLeft, isNull);
    });
  });

  group('rejecting malformed packets', () {
    test('an unrecognized version is rejected and counted', () {
      final packet = buildV2Packet(version: 1, seq: 1);
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, 0);
      expect(data.rpm, 0);
      expect(data.leanAngle, isNull);
      expect(data.rttDid, isNull);
      expect(TelemetryData.versionRejectedCount, 1);
      expect(TelemetryData.receivedCount, 0);
    });

    test('a version above the newest known one is rejected even with the version-4 length', () {
      final packet = buildV4Packet(version: BleTelemetry.currentVersion + 1, seq: 1);
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, 0);
      expect(data.rttDid, isNull);
      expect(TelemetryData.versionRejectedCount, 1);
      expect(TelemetryData.sizeRejectedCount, 0);
      expect(TelemetryData.receivedCount, 0);
    });

    test('a version-4 byte with the wrong length is rejected and counted separately from version', () {
      // A version-3-sized payload claiming version 4.
      final shortPacket = Uint8List.fromList(List<int>.filled(BleTelemetry.totalBytesV3, 0)..[0] = TelemetryVersion.v4);
      final data = TelemetryData.fromBinaryBuffer(shortPacket);

      expect(data.packetVersion, 0);
      expect(data.rpm, 0);
      expect(data.rttDid, isNull);
      expect(TelemetryData.receivedCount, 0);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 1);
    });

    test('a version-3 byte with the wrong length is rejected and counted separately from version', () {
      final shortPacket = Uint8List.fromList(List<int>.filled(20, 0)..[0] = TelemetryVersion.v3);
      final data = TelemetryData.fromBinaryBuffer(shortPacket);

      expect(data.rpm, 0);
      expect(TelemetryData.receivedCount, 0);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 1);
    });

    test('a version-3 byte on a version-4-sized payload is rejected as a size mismatch', () {
      final longPacket = Uint8List.fromList(List<int>.filled(BleTelemetry.totalBytesV4, 0)..[0] = TelemetryVersion.v3);
      final data = TelemetryData.fromBinaryBuffer(longPacket);

      expect(data.packetVersion, 0);
      expect(TelemetryData.receivedCount, 0);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 1);
    });

    test('a version-2 byte with the wrong length is rejected and counted separately from version', () {
      final shortPacket = Uint8List.fromList(List<int>.filled(10, 0)..[0] = TelemetryVersion.v2);
      final data = TelemetryData.fromBinaryBuffer(shortPacket);

      expect(data.rpm, 0);
      expect(TelemetryData.receivedCount, 0);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 1);
    });

    test('an empty packet is rejected without touching counters', () {
      final data = TelemetryData.fromBinaryBuffer(Uint8List(0));

      expect(data.rpm, 0);
      expect(TelemetryData.receivedCount, 0);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 0);
    });
  });

  group('seq-based packet loss counting (shared by all versions)', () {
    test('consecutive seq numbers count no loss', () {
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 10));
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 11));
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 12));

      expect(TelemetryData.receivedCount, 3);
      expect(TelemetryData.lostCount, 0);
    });

    test('a gap between seq numbers is counted as lost packets', () {
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 10));
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 15));

      expect(TelemetryData.lostCount, 4); // seq 11, 12, 13, 14 missed
    });

    test('seq rollover from 255 to 0 counts no loss', () {
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 255));
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 0));

      expect(TelemetryData.lostCount, 0);
    });

    test('a gap across the 255->0 rollover is counted correctly', () {
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 254));
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 2));

      expect(TelemetryData.lostCount, 3); // seq 255, 0, 1 missed
    });

    test('seq is tracked across a mix of version 2, 3 and 4 packets', () {
      TelemetryData.fromBinaryBuffer(buildV4Packet(seq: 10));
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 11));
      TelemetryData.fromBinaryBuffer(buildV2Packet(seq: 13)); // gap of 1 (seq 12)

      expect(TelemetryData.receivedCount, 3);
      expect(TelemetryData.lostCount, 1);
    });
  });
}
