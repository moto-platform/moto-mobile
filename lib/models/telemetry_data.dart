import 'dart:typed_data';

/// BLE telemetry packet format, single source of truth:
/// moto-connectivity-node/docs/ble_telemetry_packet_schema.json (v2).
/// This model mirrors that schema; the same file is checked verbatim into
/// test/fixtures/ble_telemetry_packet_schema.json and compared against the
/// constants below by test/telemetry_data_test.dart.
///
/// Implementations of this schema: src/BLETelemetryPacket.h (firmware,
/// moto-connectivity-node) and this file (decoder, moto-mobile). Ported from
/// HondaCl250_Telemetry@legacy-final (schema version 1) per D-023; version 2
/// added the `flags` byte and made the lean fields optional until the rt-core
/// EKF lean estimate reaches this node.
const int blePacketExpectedVersion = 2;
const int blePacketSizeBytes = 16;

/// Sentinel value for an int16 field that is "not available" (0x8000).
const int blePacketNotAvailable = -32768;

/// Byte offsets of each field in the packet, as defined by the schema.
class BlePacketFieldOffsets {
  static const int version = 0;
  static const int seq = 1;
  static const int rpm = 2;
  static const int speed = 4;
  static const int coolantTemp = 5;
  static const int throttlePos = 6;
  static const int batteryVolt = 7;
  static const int leanAngle = 9;
  static const int maxLeanRight = 11;
  static const int maxLeanLeft = 13;
  static const int flags = 15;
}

/// Bit positions within the `flags` byte (offset 15).
class BlePacketFlagBits {
  static const int rpmValid = 0;
  static const int speedValid = 1;
  static const int coolantTempValid = 2;
  static const int throttlePosValid = 3;
  static const int batteryVoltValid = 4;
  static const int leanValid = 5;
  static const int ecuPresent = 6;
  // Bit 7 is reserved and always 0.
}

/// Telemetry model representing a decoded binary BLE packet from
/// moto-connectivity-node.
class TelemetryData {
  final double rpm;
  final int speed;
  final int coolantTemp;
  final double throttlePos;
  final double batteryVolt;

  /// Lean (roll) angle in degrees, positive = right side down.
  /// Null when the packet reported it as not available (-32768).
  final double? leanAngle;
  final double? maxLeanRight;
  final double? maxLeanLeft;

  final bool rpmValid;
  final bool speedValid;
  final bool coolantTempValid;
  final bool throttlePosValid;
  final bool batteryVoltValid;
  final bool leanValid;
  final bool ecuPresent;

  // Packet-loss measurement via the rolling `seq` field. Static because
  // fromBinaryBuffer is a pure factory with no persistent instance to hang
  // this on.
  static int? _lastSeq;
  static int receivedCount = 0;
  static int lostCount = 0;
  static int versionRejectedCount = 0;

  /// Resets all static counters. Intended for use between tests.
  static void resetStats() {
    _lastSeq = null;
    receivedCount = 0;
    lostCount = 0;
    versionRejectedCount = 0;
  }

  TelemetryData({
    required this.rpm,
    required this.speed,
    required this.coolantTemp,
    required this.throttlePos,
    required this.batteryVolt,
    required this.leanAngle,
    required this.maxLeanRight,
    required this.maxLeanLeft,
    required this.rpmValid,
    required this.speedValid,
    required this.coolantTempValid,
    required this.throttlePosValid,
    required this.batteryVoltValid,
    required this.leanValid,
    required this.ecuPresent,
  });

  factory TelemetryData.initial() {
    return TelemetryData(
      rpm: 0,
      speed: 0,
      coolantTemp: 0,
      throttlePos: 0,
      batteryVolt: 0.0,
      leanAngle: null,
      maxLeanRight: null,
      maxLeanLeft: null,
      rpmValid: false,
      speedValid: false,
      coolantTempValid: false,
      throttlePosValid: false,
      batteryVoltValid: false,
      leanValid: false,
      ecuPresent: false,
    );
  }

  /// Parses a 16-byte binary packet received from a BLE notification.
  /// Wire format is LITTLE-ENDIAN; every getX() call below passes
  /// Endian.little for that reason.
  /// Returns TelemetryData.initial() both on a malformed/short packet and on
  /// a version mismatch -- callers can check [versionRejectedCount] to tell
  /// those apart.
  factory TelemetryData.fromBinaryBuffer(Uint8List bytes) {
    if (bytes.length < blePacketSizeBytes) return TelemetryData.initial();

    try {
      final buffer = ByteData.sublistView(bytes);

      final version = buffer.getUint8(BlePacketFieldOffsets.version);
      if (version != blePacketExpectedVersion) {
        versionRejectedCount++;
        return TelemetryData.initial();
      }

      final seq = buffer.getUint8(BlePacketFieldOffsets.seq);
      final lastSeq = _lastSeq;
      if (lastSeq != null) {
        // Rolling 0-255 counter: gap = packets missed between the last seq
        // seen and this one, minus the one we did receive.
        final gap = (seq - lastSeq - 1 + 256) % 256;
        lostCount += gap;
      }
      _lastSeq = seq;
      receivedCount++;

      final rpm = buffer.getUint16(BlePacketFieldOffsets.rpm, Endian.little).toDouble();
      final speed = buffer.getUint8(BlePacketFieldOffsets.speed);
      final coolantTemp = buffer.getInt8(BlePacketFieldOffsets.coolantTemp);
      final throttlePos = buffer.getUint8(BlePacketFieldOffsets.throttlePos).toDouble();
      final batteryVolt = buffer.getUint16(BlePacketFieldOffsets.batteryVolt, Endian.little) / 1000.0;

      final leanAngleRaw = buffer.getInt16(BlePacketFieldOffsets.leanAngle, Endian.little);
      final maxLeanRightRaw = buffer.getInt16(BlePacketFieldOffsets.maxLeanRight, Endian.little);
      final maxLeanLeftRaw = buffer.getInt16(BlePacketFieldOffsets.maxLeanLeft, Endian.little);

      final leanAngle = leanAngleRaw == blePacketNotAvailable ? null : leanAngleRaw / 10.0;
      final maxLeanRight = maxLeanRightRaw == blePacketNotAvailable ? null : maxLeanRightRaw / 10.0;
      final maxLeanLeft = maxLeanLeftRaw == blePacketNotAvailable ? null : maxLeanLeftRaw / 10.0;

      final flags = buffer.getUint8(BlePacketFieldOffsets.flags);
      bool bit(int position) => (flags & (1 << position)) != 0;

      return TelemetryData(
        rpm: rpm,
        speed: speed,
        coolantTemp: coolantTemp,
        throttlePos: throttlePos,
        batteryVolt: batteryVolt,
        leanAngle: leanAngle,
        maxLeanRight: maxLeanRight,
        maxLeanLeft: maxLeanLeft,
        rpmValid: bit(BlePacketFlagBits.rpmValid),
        speedValid: bit(BlePacketFlagBits.speedValid),
        coolantTempValid: bit(BlePacketFlagBits.coolantTempValid),
        throttlePosValid: bit(BlePacketFlagBits.throttlePosValid),
        batteryVoltValid: bit(BlePacketFlagBits.batteryVoltValid),
        leanValid: bit(BlePacketFlagBits.leanValid),
        ecuPresent: bit(BlePacketFlagBits.ecuPresent),
      );
    } catch (e) {
      return TelemetryData.initial();
    }
  }
}
