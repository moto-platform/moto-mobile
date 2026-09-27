import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mobile/models/telemetry_data.dart';

/// Builds a raw version-3 (37-byte) packet from field values, matching
/// moto-connectivity-node/docs/ble_telemetry_packet_schema.json.
Uint8List buildV3Packet({
  int version = bleTelemetryV3Version,
  int seq = 0,
  int deviceTimeMs = 0,
  int rpm = 0,
  int speed = 0,
  int coolantTemp = 0,
  int throttlePos = 0,
  int batteryVoltMv = 0,
  int leanAngleTenths = blePacketNotAvailable,
  int maxLeanRightTenths = blePacketNotAvailable,
  int maxLeanLeftTenths = blePacketNotAvailable,
  int flags = 0,
  int rpmAgeMs = bleTelemetryAgeNeverReceived,
  int speedAgeMs = bleTelemetryAgeNeverReceived,
  int coolantTempAgeMs = bleTelemetryAgeNeverReceived,
  int throttlePosAgeMs = bleTelemetryAgeNeverReceived,
  int batteryVoltAgeMs = bleTelemetryAgeNeverReceived,
  int canBusState = 0,
  int canTxErrorCount = 0,
  int canRxErrorCount = 0,
  int canBusOffCount = 0,
  int unansweredDidCount = 0,
  int canFlags = 0,
}) {
  final bytes = ByteData(bleTelemetryV3TotalBytes);
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

/// Builds a raw version-2 (16-byte, `lowMtuFallback`) packet from field
/// values.
Uint8List buildV2Packet({
  int version = bleTelemetryV2Version,
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
  final bytes = ByteData(bleTelemetryV2TotalBytes);
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

void main() {
  setUp(() {
    TelemetryData.resetStats();
  });

  group('schema fixture matches the decoder', () {
    late Map<String, dynamic> schema;

    setUpAll(() {
      final raw = File('test/fixtures/ble_telemetry_packet_schema.json').readAsStringSync();
      schema = jsonDecode(raw) as Map<String, dynamic>;
    });

    test('top-level packet metadata (version 3)', () {
      expect(schema['version'], bleTelemetryV3Version);
      expect(schema['totalBytes'], bleTelemetryV3TotalBytes);
      expect(schema['endianness'], 'little');
    });

    test('notAvailable / age sentinels', () {
      expect(schema['notAvailable']['int16'], blePacketNotAvailable);
      expect(schema['age']['neverReceived'], bleTelemetryAgeNeverReceived);
      expect(schema['age']['max'], bleTelemetryAgeMaxMs);
    });

    test('every version-3 field offset/size/type matches the decoder', () {
      final fields = (schema['fields'] as List).cast<Map<String, dynamic>>();
      final expectedOffsets = <String, int>{
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
      final expectedSizes = <String, int>{
        'version': 1,
        'seq': 1,
        'deviceTimeMs': 4,
        'rpm': 2,
        'speed': 1,
        'coolantTemp': 1,
        'throttlePos': 1,
        'batteryVolt': 2,
        'leanAngle': 2,
        'maxLeanRight': 2,
        'maxLeanLeft': 2,
        'flags': 1,
        'rpmAgeMs': 2,
        'speedAgeMs': 2,
        'coolantTempAgeMs': 2,
        'throttlePosAgeMs': 2,
        'batteryVoltAgeMs': 2,
        'canBusState': 1,
        'canTxErrorCount': 1,
        'canRxErrorCount': 1,
        'canBusOffCount': 1,
        'unansweredDidCount': 2,
        'canFlags': 1,
      };

      expect(fields.length, expectedOffsets.length);
      for (final field in fields) {
        final name = field['name'] as String;
        expect(expectedOffsets.containsKey(name), isTrue, reason: 'unexpected field $name in schema');
        expect(field['offset'], expectedOffsets[name], reason: 'offset mismatch for $name');
        expect(field['size'], expectedSizes[name], reason: 'size mismatch for $name');
      }
    });

    test('every version-2 (lowMtuFallback) field offset/size matches the decoder', () {
      final fallback = schema['lowMtuFallback'] as Map<String, dynamic>;
      expect(fallback['version'], bleTelemetryV2Version);
      expect(fallback['totalBytes'], bleTelemetryV2TotalBytes);

      final fields = (fallback['fields'] as List).cast<Map<String, dynamic>>();
      final expectedOffsets = <String, int>{
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
      expect(fields.length, expectedOffsets.length);
      for (final field in fields) {
        final name = field['name'] as String;
        expect(expectedOffsets.containsKey(name), isTrue, reason: 'unexpected field $name in lowMtuFallback');
        expect(field['offset'], expectedOffsets[name], reason: 'offset mismatch for $name');
      }
    });

    test('flag bit positions match the decoder', () {
      final bits = (schema['flags']['bits'] as List).cast<Map<String, dynamic>>();
      final expectedBits = <String, int>{
        'rpmValid': BleTelemetryFlagBits.rpmValid,
        'speedValid': BleTelemetryFlagBits.speedValid,
        'coolantTempValid': BleTelemetryFlagBits.coolantTempValid,
        'throttlePosValid': BleTelemetryFlagBits.throttlePosValid,
        'batteryVoltValid': BleTelemetryFlagBits.batteryVoltValid,
        'leanValid': BleTelemetryFlagBits.leanValid,
        'ecuPresent': BleTelemetryFlagBits.ecuPresent,
        'imuActive': BleTelemetryFlagBits.imuActive,
      };
      for (final bit in bits) {
        final name = bit['name'] as String;
        expect(expectedBits.containsKey(name), isTrue, reason: 'unexpected flag $name in schema');
        expect(bit['bit'], expectedBits[name], reason: 'bit position mismatch for $name');
      }
    });

    test('canHealth.busState values match CanBusState', () {
      final values = (schema['canHealth']['busState']['values'] as List).cast<Map<String, dynamic>>();
      final expected = <String, int>{
        'notInstalled': CanBusState.notInstalled.value,
        'running': CanBusState.running.value,
        'errorWarning': CanBusState.errorWarning.value,
        'busOff': CanBusState.busOff.value,
        'stopped': CanBusState.stopped.value,
      };
      expect(values.length, expected.length);
      for (final v in values) {
        final name = v['name'] as String;
        expect(expected.containsKey(name), isTrue, reason: 'unexpected busState $name in schema');
        expect(v['value'], expected[name], reason: 'busState value mismatch for $name');
      }
    });

    test('canHealth.canFlags bit positions match CanFlagsBits', () {
      final bits = (schema['canHealth']['canFlags']['bits'] as List).cast<Map<String, dynamic>>();
      final expected = <String, int>{
        'pollerEnabled': CanFlagsBits.pollerEnabled,
        'latchedForeignTester': CanFlagsBits.latchedForeignTester,
        'latchedBusOff': CanFlagsBits.latchedBusOff,
        'syntheticData': CanFlagsBits.syntheticData,
      };
      for (final bit in bits) {
        final name = bit['name'] as String;
        if (name == 'reserved') continue;
        expect(expected.containsKey(name), isTrue, reason: 'unexpected canFlags bit $name in schema');
        expect(bit['bit'], expected[name], reason: 'canFlags bit position mismatch for $name');
      }
    });
  });

  group('decoding a valid version-3 packet', () {
    test('decodes all fields correctly', () {
      const allValidFlags = (1 << BleTelemetryFlagBits.rpmValid) |
          (1 << BleTelemetryFlagBits.speedValid) |
          (1 << BleTelemetryFlagBits.coolantTempValid) |
          (1 << BleTelemetryFlagBits.throttlePosValid) |
          (1 << BleTelemetryFlagBits.batteryVoltValid) |
          (1 << BleTelemetryFlagBits.leanValid) |
          (1 << BleTelemetryFlagBits.ecuPresent) |
          (1 << BleTelemetryFlagBits.imuActive);

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
        flags: allValidFlags,
        rpmAgeMs: 10,
        speedAgeMs: 20,
        coolantTempAgeMs: 30,
        throttlePosAgeMs: 40,
        batteryVoltAgeMs: 50,
        canBusState: 1,
        canTxErrorCount: 3,
        canRxErrorCount: 4,
        canBusOffCount: 1,
        unansweredDidCount: 7,
        canFlags: 0x01,
      );

      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, bleTelemetryV3Version);
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
      expect(data.canFlags, 0x01);
      expect(data.pollerEnabled, isTrue);
      expect(data.latchedForeignTester, isFalse);
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

    test('ages of 65535 (neverReceived) decode to null', () {
      final packet = buildV3Packet(
        seq: 1,
        rpmAgeMs: bleTelemetryAgeNeverReceived,
        speedAgeMs: bleTelemetryAgeNeverReceived,
        coolantTempAgeMs: bleTelemetryAgeNeverReceived,
        throttlePosAgeMs: bleTelemetryAgeNeverReceived,
        batteryVoltAgeMs: bleTelemetryAgeNeverReceived,
      );
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.rpmAgeMs, isNull);
      expect(data.speedAgeMs, isNull);
      expect(data.coolantTempAgeMs, isNull);
      expect(data.throttlePosAgeMs, isNull);
      expect(data.batteryVoltAgeMs, isNull);
    });

    test('an age at the max saturation value (65534) is a real value, not null', () {
      final packet = buildV3Packet(seq: 1, rpmAgeMs: bleTelemetryAgeMaxMs);
      final data = TelemetryData.fromBinaryBuffer(packet);
      expect(data.rpmAgeMs, bleTelemetryAgeMaxMs);
    });

    test('canBusState decodes every documented value', () {
      for (final entry in {
        0: CanBusState.notInstalled,
        1: CanBusState.running,
        2: CanBusState.errorWarning,
        3: CanBusState.busOff,
        4: CanBusState.stopped,
      }.entries) {
        final data = TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 1, canBusState: entry.key));
        expect(data.canBusState, entry.value, reason: 'raw ${entry.key}');
      }
    });
  });

  group('decoding a valid version-2 (lowMtuFallback) packet', () {
    test('decodes the shared fields and leaves version-3-only fields absent', () {
      const allValidFlags = (1 << BleTelemetryFlagBits.rpmValid) |
          (1 << BleTelemetryFlagBits.speedValid) |
          (1 << BleTelemetryFlagBits.coolantTempValid) |
          (1 << BleTelemetryFlagBits.throttlePosValid) |
          (1 << BleTelemetryFlagBits.batteryVoltValid) |
          (1 << BleTelemetryFlagBits.leanValid) |
          (1 << BleTelemetryFlagBits.ecuPresent);

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
        flags: allValidFlags,
      );

      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.packetVersion, bleTelemetryV2Version);
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
    });

    test('-32768 decodes to null for all three lean fields', () {
      final packet = buildV2Packet(
        seq: 1,
        leanAngleTenths: blePacketNotAvailable,
        maxLeanRightTenths: blePacketNotAvailable,
        maxLeanLeftTenths: blePacketNotAvailable,
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
      expect(TelemetryData.versionRejectedCount, 1);
      expect(TelemetryData.receivedCount, 0);
    });

    test('a version-3 byte with the wrong length is rejected and counted separately from version', () {
      final shortPacket = Uint8List.fromList(List<int>.filled(20, 0)..[0] = bleTelemetryV3Version);
      final data = TelemetryData.fromBinaryBuffer(shortPacket);

      expect(data.rpm, 0);
      expect(TelemetryData.receivedCount, 0);
      expect(TelemetryData.versionRejectedCount, 0);
      expect(TelemetryData.sizeRejectedCount, 1);
    });

    test('a version-2 byte with the wrong length is rejected and counted separately from version', () {
      final shortPacket = Uint8List.fromList(List<int>.filled(10, 0)..[0] = bleTelemetryV2Version);
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

  group('seq-based packet loss counting (shared by both versions)', () {
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

    test('seq is tracked across a mix of version 2 and version 3 packets', () {
      TelemetryData.fromBinaryBuffer(buildV3Packet(seq: 10));
      TelemetryData.fromBinaryBuffer(buildV2Packet(seq: 12)); // gap of 1 (seq 11)

      expect(TelemetryData.receivedCount, 2);
      expect(TelemetryData.lostCount, 1);
    });
  });
}
