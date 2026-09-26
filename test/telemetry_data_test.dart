import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mobile/models/telemetry_data.dart';

/// Builds a raw 16-byte v2 packet from field values, matching
/// moto-connectivity-node/docs/ble_telemetry_packet_schema.json.
Uint8List buildPacket({
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

    test('top-level packet metadata', () {
      expect(schema['version'], blePacketExpectedVersion);
      expect(schema['totalBytes'], blePacketSizeBytes);
      expect(schema['endianness'], 'little');
    });

    test('notAvailable sentinel', () {
      expect(schema['notAvailable']['int16'], blePacketNotAvailable);
    });

    test('every field offset/size/type matches the decoder', () {
      final fields = (schema['fields'] as List).cast<Map<String, dynamic>>();
      final expectedOffsets = <String, int>{
        'version': BlePacketFieldOffsets.version,
        'seq': BlePacketFieldOffsets.seq,
        'rpm': BlePacketFieldOffsets.rpm,
        'speed': BlePacketFieldOffsets.speed,
        'coolantTemp': BlePacketFieldOffsets.coolantTemp,
        'throttlePos': BlePacketFieldOffsets.throttlePos,
        'batteryVolt': BlePacketFieldOffsets.batteryVolt,
        'leanAngle': BlePacketFieldOffsets.leanAngle,
        'maxLeanRight': BlePacketFieldOffsets.maxLeanRight,
        'maxLeanLeft': BlePacketFieldOffsets.maxLeanLeft,
        'flags': BlePacketFieldOffsets.flags,
      };
      final expectedSizes = <String, int>{
        'version': 1,
        'seq': 1,
        'rpm': 2,
        'speed': 1,
        'coolantTemp': 1,
        'throttlePos': 1,
        'batteryVolt': 2,
        'leanAngle': 2,
        'maxLeanRight': 2,
        'maxLeanLeft': 2,
        'flags': 1,
      };
      final expectedTypes = <String, String>{
        'version': 'uint8',
        'seq': 'uint8',
        'rpm': 'uint16',
        'speed': 'uint8',
        'coolantTemp': 'int8',
        'throttlePos': 'uint8',
        'batteryVolt': 'uint16',
        'leanAngle': 'int16',
        'maxLeanRight': 'int16',
        'maxLeanLeft': 'int16',
        'flags': 'uint8',
      };

      expect(fields.length, expectedOffsets.length);
      for (final field in fields) {
        final name = field['name'] as String;
        expect(expectedOffsets.containsKey(name), isTrue, reason: 'unexpected field $name in schema');
        expect(field['offset'], expectedOffsets[name], reason: 'offset mismatch for $name');
        expect(field['size'], expectedSizes[name], reason: 'size mismatch for $name');
        expect(field['type'], expectedTypes[name], reason: 'type mismatch for $name');
      }
    });

    test('flag bit positions match the decoder', () {
      final bits = (schema['flags']['bits'] as List).cast<Map<String, dynamic>>();
      final expectedBits = <String, int>{
        'rpmValid': BlePacketFlagBits.rpmValid,
        'speedValid': BlePacketFlagBits.speedValid,
        'coolantTempValid': BlePacketFlagBits.coolantTempValid,
        'throttlePosValid': BlePacketFlagBits.throttlePosValid,
        'batteryVoltValid': BlePacketFlagBits.batteryVoltValid,
        'leanValid': BlePacketFlagBits.leanValid,
        'ecuPresent': BlePacketFlagBits.ecuPresent,
      };
      for (final bit in bits) {
        final name = bit['name'] as String;
        if (name == 'reserved') continue;
        expect(expectedBits.containsKey(name), isTrue, reason: 'unexpected flag $name in schema');
        expect(bit['bit'], expectedBits[name], reason: 'bit position mismatch for $name');
      }
    });
  });

  group('decoding a valid packet', () {
    test('decodes all fields correctly', () {
      const allValidFlags = (1 << BlePacketFlagBits.rpmValid) |
          (1 << BlePacketFlagBits.speedValid) |
          (1 << BlePacketFlagBits.coolantTempValid) |
          (1 << BlePacketFlagBits.throttlePosValid) |
          (1 << BlePacketFlagBits.batteryVoltValid) |
          (1 << BlePacketFlagBits.leanValid) |
          (1 << BlePacketFlagBits.ecuPresent);

      final packet = buildPacket(
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
      expect(TelemetryData.receivedCount, 1);
      expect(TelemetryData.versionRejectedCount, 0);
    });

    test('a flags byte with no bits set decodes all-invalid', () {
      final packet = buildPacket(seq: 1, flags: 0);
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.rpmValid, isFalse);
      expect(data.speedValid, isFalse);
      expect(data.coolantTempValid, isFalse);
      expect(data.throttlePosValid, isFalse);
      expect(data.batteryVoltValid, isFalse);
      expect(data.leanValid, isFalse);
      expect(data.ecuPresent, isFalse);
    });
  });

  group('rejecting malformed packets', () {
    test('wrong version is rejected and counted', () {
      final packet = buildPacket(version: 1, seq: 1);
      final data = TelemetryData.fromBinaryBuffer(packet);

      expect(data.rpm, 0);
      expect(data.leanAngle, isNull);
      expect(TelemetryData.versionRejectedCount, 1);
      expect(TelemetryData.receivedCount, 0);
    });

    test('a packet shorter than 16 bytes is rejected without touching counters', () {
      final shortPacket = Uint8List.fromList(List<int>.filled(15, 0)..[0] = blePacketExpectedVersion);
      final data = TelemetryData.fromBinaryBuffer(shortPacket);

      expect(data.rpm, 0);
      expect(TelemetryData.receivedCount, 0);
      expect(TelemetryData.versionRejectedCount, 0);
    });
  });

  group('lean field not-available sentinel', () {
    test('-32768 decodes to null for all three lean fields', () {
      final packet = buildPacket(
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

  group('seq-based packet loss counting', () {
    test('consecutive seq numbers count no loss', () {
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 10));
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 11));
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 12));

      expect(TelemetryData.receivedCount, 3);
      expect(TelemetryData.lostCount, 0);
    });

    test('a gap between seq numbers is counted as lost packets', () {
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 10));
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 15));

      expect(TelemetryData.lostCount, 4); // seq 11, 12, 13, 14 missed
    });

    test('seq rollover from 255 to 0 counts no loss', () {
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 255));
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 0));

      expect(TelemetryData.lostCount, 0);
    });

    test('a gap across the 255->0 rollover is counted correctly', () {
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 254));
      TelemetryData.fromBinaryBuffer(buildPacket(seq: 2));

      expect(TelemetryData.lostCount, 3); // seq 255, 0, 1 missed
    });
  });
}
