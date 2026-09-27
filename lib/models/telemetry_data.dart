import 'dart:typed_data';

/// BLE telemetry packet format, single source of truth:
/// moto-connectivity-node/docs/ble_telemetry_packet_schema.json.
/// This model mirrors that schema; the same file is checked verbatim into
/// test/fixtures/ble_telemetry_packet_schema.json and compared against the
/// constants below by test/schema_drift_test.dart.
///
/// Implementations of this schema: src/BLETelemetryPacket.h (firmware,
/// moto-connectivity-node) and this file (decoder, moto-mobile). Ported from
/// HondaCl250_Telemetry@legacy-final (schema version 1) per D-023.
///
/// Version history (see the schema's `versioning.history`):
///  - 1: legacy 15-byte layout (not implemented here, never seen on the wire).
///  - 2: 16-byte layout (`lowMtuFallback` in the schema). Still sent by the
///    firmware when the negotiated ATT MTU is too small for version 3, or by
///    old firmware that only ever speaks version 2.
///  - 3 (D-032, current): 37-byte layout at the top level of the schema.
///    Adds `deviceTimeMs`, per-signal ages and CAN/tester health, and flags
///    bit 7 (`imuActive`). The lean fields are deprecated (D-023) and always
///    report "not available" on version 3.
///
/// Receivers dispatch on byte 0 (`version`) and decode with the matching
/// layout; any other version, or a payload whose length does not match that
/// version's `totalBytes`, is dropped.
const int bleTelemetryV3Version = 3;
const int bleTelemetryV3TotalBytes = 37;
const int bleTelemetryV2Version = 2;
const int bleTelemetryV2TotalBytes = 16;

/// Deprecated aliases kept only so older call sites (and their compiled
/// tests) do not silently start decoding v3 packets as v2. Prefer
/// [bleTelemetryV2Version] / [bleTelemetryV2TotalBytes].
const int blePacketExpectedVersion = bleTelemetryV3Version;
const int blePacketSizeBytes = bleTelemetryV3TotalBytes;

/// Sentinel value for an int16 field that is "not available" (0x8000). Used
/// only by the deprecated lean fields.
const int blePacketNotAvailable = -32768;

/// Sentinel value for a uint16 `ageOf` field meaning "no value received
/// since boot" (`age.neverReceived` in the schema). The maximum real age is
/// `age.max` (65534); ages saturate there instead of wrapping.
const int bleTelemetryAgeNeverReceived = 65535;
const int bleTelemetryAgeMaxMs = 65534;

/// Byte offsets of each field in the version 3 (37-byte) packet, named after
/// the schema's `fields[].name` entries.
class BleTelemetryV3Offsets {
  static const int version = 0;
  static const int seq = 1;
  static const int deviceTimeMs = 2;
  static const int rpm = 6;
  static const int speed = 8;
  static const int coolantTemp = 9;
  static const int throttlePos = 10;
  static const int batteryVolt = 11;
  static const int leanAngle = 13;
  static const int maxLeanRight = 15;
  static const int maxLeanLeft = 17;
  static const int flags = 19;
  static const int rpmAgeMs = 20;
  static const int speedAgeMs = 22;
  static const int coolantTempAgeMs = 24;
  static const int throttlePosAgeMs = 26;
  static const int batteryVoltAgeMs = 28;
  static const int canBusState = 30;
  static const int canTxErrorCount = 31;
  static const int canRxErrorCount = 32;
  static const int canBusOffCount = 33;
  static const int unansweredDidCount = 34;
  static const int canFlags = 36;
}

/// Byte offsets of each field in the version 2 (16-byte) `lowMtuFallback`
/// packet, named after the schema's `lowMtuFallback.fields[].name` entries.
class BleTelemetryV2Offsets {
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

/// Deprecated alias: use [BleTelemetryV2Offsets] (or [BleTelemetryV3Offsets]
/// for version-3-only fields) directly. Kept because `seq` and `version` sit
/// at the same offset in both layouts, so old call sites that only peeked at
/// those two fields still work unchanged.
typedef BlePacketFieldOffsets = BleTelemetryV2Offsets;

/// Bit positions within the `flags` byte, shared by version 2 and version 3
/// (`flags.bits` in the schema). Version 2 packets always send 0 for bit 7.
class BleTelemetryFlagBits {
  static const int rpmValid = 0;
  static const int speedValid = 1;
  static const int coolantTempValid = 2;
  static const int throttlePosValid = 3;
  static const int batteryVoltValid = 4;
  static const int leanValid = 5;
  static const int ecuPresent = 6;
  static const int imuActive = 7;
}

/// Deprecated alias: use [BleTelemetryFlagBits].
typedef BlePacketFlagBits = BleTelemetryFlagBits;

/// Vehicle-bus TWAI state (`canHealth.busState` in the schema). Only present
/// on version 3 packets; `null` on version 2 (the field does not exist).
enum CanBusState {
  notInstalled(0),
  running(1),
  errorWarning(2),
  busOff(3),
  stopped(4);

  const CanBusState(this.value);
  final int value;

  /// Maps the raw `canBusState` byte to an enum value. An out-of-range byte
  /// (should never happen on the wire) defensively maps to [notInstalled]
  /// rather than throwing, so a single unexpected byte cannot take down the
  /// whole decode.
  static CanBusState fromRaw(int raw) {
    for (final v in CanBusState.values) {
      if (v.value == raw) return v;
    }
    return CanBusState.notInstalled;
  }
}

/// Bit positions within the `canFlags` byte (`canHealth.canFlags` in the
/// schema). Only present on version 3 packets.
class CanFlagsBits {
  static const int pollerEnabled = 0;
  static const int latchedForeignTester = 1;
  static const int latchedBusOff = 2;
  static const int syntheticData = 3;
}

/// Telemetry model representing a decoded binary BLE packet from
/// moto-connectivity-node, version 2 or version 3.
class TelemetryData {
  /// 0 for [TelemetryData.initial] (no packet decoded yet), otherwise
  /// [bleTelemetryV2Version] or [bleTelemetryV3Version].
  final int packetVersion;

  /// Node clock (ms) when the packet was built, see the schema's
  /// `deviceTime`. Always `null` on version 2 (the field does not exist).
  final int? deviceTimeMs;

  final double rpm;
  final int speed;
  final int coolantTemp;
  final double throttlePos;
  final double batteryVolt;

  /// DEPRECATED (D-023): the complementary-filter lean estimate was dropped;
  /// these three fields are always `null` on version 3 packets and are kept
  /// only so the layout stays close to version 2. Do not use for analysis --
  /// the eventual lean signal comes from the rt-core EKF instead.
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

  /// Bit 7 of `flags`: the IMU sampler is running and its last read
  /// succeeded. Always `false` on version 2 packets (the bit is reserved
  /// there and always sent as 0).
  final bool imuActive;

  /// Age (ms) since each signal was last written, at the time the packet was
  /// built (`age` in the schema). `null` on version 2 packets (no age
  /// fields) and `null` when the raw value is
  /// [bleTelemetryAgeNeverReceived] (no value since boot).
  final int? rpmAgeMs;
  final int? speedAgeMs;
  final int? coolantTempAgeMs;
  final int? throttlePosAgeMs;
  final int? batteryVoltAgeMs;

  /// CAN/tester health (`canHealth` in the schema). All `null` on version 2
  /// packets, which carry no health fields.
  final CanBusState? canBusState;
  final int? canTxErrorCount;
  final int? canRxErrorCount;
  final int? canBusOffCount;
  final int? unansweredDidCount;

  /// Raw `canFlags` byte; see [CanFlagsBits] for bit meanings, or use the
  /// `pollerEnabled` / `latchedForeignTester` / `latchedBusOff` /
  /// `syntheticData` getters below.
  final int? canFlags;

  bool? get pollerEnabled => _canFlagBit(CanFlagsBits.pollerEnabled);
  bool? get latchedForeignTester => _canFlagBit(CanFlagsBits.latchedForeignTester);
  bool? get latchedBusOff => _canFlagBit(CanFlagsBits.latchedBusOff);
  bool? get syntheticData => _canFlagBit(CanFlagsBits.syntheticData);

  bool? _canFlagBit(int position) {
    final flags = canFlags;
    if (flags == null) return null;
    return (flags & (1 << position)) != 0;
  }

  // Packet-loss measurement via the rolling `seq` field, shared by both
  // versions. Static because fromBinaryBuffer is a pure factory with no
  // persistent instance to hang this on.
  static int? _lastSeq;
  static int receivedCount = 0;
  static int lostCount = 0;
  static int versionRejectedCount = 0;

  /// Packets whose `version` byte was recognized but whose length did not
  /// match that version's expected size, and were dropped for it.
  static int sizeRejectedCount = 0;

  /// Resets all static counters. Intended for use between tests.
  static void resetStats() {
    _lastSeq = null;
    receivedCount = 0;
    lostCount = 0;
    versionRejectedCount = 0;
    sizeRejectedCount = 0;
  }

  TelemetryData({
    this.packetVersion = 0,
    this.deviceTimeMs,
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
    this.imuActive = false,
    this.rpmAgeMs,
    this.speedAgeMs,
    this.coolantTempAgeMs,
    this.throttlePosAgeMs,
    this.batteryVoltAgeMs,
    this.canBusState,
    this.canTxErrorCount,
    this.canRxErrorCount,
    this.canBusOffCount,
    this.unansweredDidCount,
    this.canFlags,
  });

  factory TelemetryData.initial() {
    return TelemetryData(
      packetVersion: 0,
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

  /// Parses one raw binary BLE telemetry notification. Wire format is
  /// LITTLE-ENDIAN throughout.
  ///
  /// Dispatches on byte 0 (`version`): version 3 decodes as the 37-byte
  /// layout, version 2 as the 16-byte `lowMtuFallback` layout. Any other
  /// version, or a payload whose length does not match that version's
  /// expected size, is dropped -- [TelemetryData.initial] is returned and
  /// [versionRejectedCount] / [sizeRejectedCount] is incremented so callers
  /// can tell those apart.
  factory TelemetryData.fromBinaryBuffer(Uint8List bytes) {
    if (bytes.isEmpty) return TelemetryData.initial();

    try {
      final version = bytes[0];
      if (version == bleTelemetryV3Version) {
        if (bytes.length != bleTelemetryV3TotalBytes) {
          sizeRejectedCount++;
          return TelemetryData.initial();
        }
        return _decodeV3(bytes);
      } else if (version == bleTelemetryV2Version) {
        if (bytes.length != bleTelemetryV2TotalBytes) {
          sizeRejectedCount++;
          return TelemetryData.initial();
        }
        return _decodeV2(bytes);
      } else {
        versionRejectedCount++;
        return TelemetryData.initial();
      }
    } catch (e) {
      return TelemetryData.initial();
    }
  }

  static void _trackSeq(int seq) {
    final lastSeq = _lastSeq;
    if (lastSeq != null) {
      // Rolling 0-255 counter: gap = packets missed between the last seq
      // seen and this one, minus the one we did receive.
      final gap = (seq - lastSeq - 1 + 256) % 256;
      lostCount += gap;
    }
    _lastSeq = seq;
    receivedCount++;
  }

  static int? _decodeAge(int raw) => raw == bleTelemetryAgeNeverReceived ? null : raw;

  static TelemetryData _decodeV2(Uint8List bytes) {
    final buffer = ByteData.sublistView(bytes);
    _trackSeq(buffer.getUint8(BleTelemetryV2Offsets.seq));

    final rpm = buffer.getUint16(BleTelemetryV2Offsets.rpm, Endian.little).toDouble();
    final speed = buffer.getUint8(BleTelemetryV2Offsets.speed);
    final coolantTemp = buffer.getInt8(BleTelemetryV2Offsets.coolantTemp);
    final throttlePos = buffer.getUint8(BleTelemetryV2Offsets.throttlePos).toDouble();
    final batteryVolt = buffer.getUint16(BleTelemetryV2Offsets.batteryVolt, Endian.little) / 1000.0;

    final leanAngleRaw = buffer.getInt16(BleTelemetryV2Offsets.leanAngle, Endian.little);
    final maxLeanRightRaw = buffer.getInt16(BleTelemetryV2Offsets.maxLeanRight, Endian.little);
    final maxLeanLeftRaw = buffer.getInt16(BleTelemetryV2Offsets.maxLeanLeft, Endian.little);

    final flags = buffer.getUint8(BleTelemetryV2Offsets.flags);
    bool bit(int position) => (flags & (1 << position)) != 0;

    return TelemetryData(
      packetVersion: bleTelemetryV2Version,
      rpm: rpm,
      speed: speed,
      coolantTemp: coolantTemp,
      throttlePos: throttlePos,
      batteryVolt: batteryVolt,
      leanAngle: leanAngleRaw == blePacketNotAvailable ? null : leanAngleRaw / 10.0,
      maxLeanRight: maxLeanRightRaw == blePacketNotAvailable ? null : maxLeanRightRaw / 10.0,
      maxLeanLeft: maxLeanLeftRaw == blePacketNotAvailable ? null : maxLeanLeftRaw / 10.0,
      rpmValid: bit(BleTelemetryFlagBits.rpmValid),
      speedValid: bit(BleTelemetryFlagBits.speedValid),
      coolantTempValid: bit(BleTelemetryFlagBits.coolantTempValid),
      throttlePosValid: bit(BleTelemetryFlagBits.throttlePosValid),
      batteryVoltValid: bit(BleTelemetryFlagBits.batteryVoltValid),
      leanValid: bit(BleTelemetryFlagBits.leanValid),
      ecuPresent: bit(BleTelemetryFlagBits.ecuPresent),
      imuActive: bit(BleTelemetryFlagBits.imuActive),
    );
  }

  static TelemetryData _decodeV3(Uint8List bytes) {
    final buffer = ByteData.sublistView(bytes);
    _trackSeq(buffer.getUint8(BleTelemetryV3Offsets.seq));

    final deviceTimeMs = buffer.getUint32(BleTelemetryV3Offsets.deviceTimeMs, Endian.little);
    final rpm = buffer.getUint16(BleTelemetryV3Offsets.rpm, Endian.little).toDouble();
    final speed = buffer.getUint8(BleTelemetryV3Offsets.speed);
    final coolantTemp = buffer.getInt8(BleTelemetryV3Offsets.coolantTemp);
    final throttlePos = buffer.getUint8(BleTelemetryV3Offsets.throttlePos).toDouble();
    final batteryVolt = buffer.getUint16(BleTelemetryV3Offsets.batteryVolt, Endian.little) / 1000.0;

    // Deprecated (D-023): always notAvailable on version 3, decoded
    // generically anyway so a future change in the firmware is not silently
    // hidden here.
    final leanAngleRaw = buffer.getInt16(BleTelemetryV3Offsets.leanAngle, Endian.little);
    final maxLeanRightRaw = buffer.getInt16(BleTelemetryV3Offsets.maxLeanRight, Endian.little);
    final maxLeanLeftRaw = buffer.getInt16(BleTelemetryV3Offsets.maxLeanLeft, Endian.little);

    final flags = buffer.getUint8(BleTelemetryV3Offsets.flags);
    bool bit(int position) => (flags & (1 << position)) != 0;

    final canBusStateRaw = buffer.getUint8(BleTelemetryV3Offsets.canBusState);

    return TelemetryData(
      packetVersion: bleTelemetryV3Version,
      deviceTimeMs: deviceTimeMs,
      rpm: rpm,
      speed: speed,
      coolantTemp: coolantTemp,
      throttlePos: throttlePos,
      batteryVolt: batteryVolt,
      leanAngle: leanAngleRaw == blePacketNotAvailable ? null : leanAngleRaw / 10.0,
      maxLeanRight: maxLeanRightRaw == blePacketNotAvailable ? null : maxLeanRightRaw / 10.0,
      maxLeanLeft: maxLeanLeftRaw == blePacketNotAvailable ? null : maxLeanLeftRaw / 10.0,
      rpmValid: bit(BleTelemetryFlagBits.rpmValid),
      speedValid: bit(BleTelemetryFlagBits.speedValid),
      coolantTempValid: bit(BleTelemetryFlagBits.coolantTempValid),
      throttlePosValid: bit(BleTelemetryFlagBits.throttlePosValid),
      batteryVoltValid: bit(BleTelemetryFlagBits.batteryVoltValid),
      leanValid: bit(BleTelemetryFlagBits.leanValid),
      ecuPresent: bit(BleTelemetryFlagBits.ecuPresent),
      imuActive: bit(BleTelemetryFlagBits.imuActive),
      rpmAgeMs: _decodeAge(buffer.getUint16(BleTelemetryV3Offsets.rpmAgeMs, Endian.little)),
      speedAgeMs: _decodeAge(buffer.getUint16(BleTelemetryV3Offsets.speedAgeMs, Endian.little)),
      coolantTempAgeMs: _decodeAge(buffer.getUint16(BleTelemetryV3Offsets.coolantTempAgeMs, Endian.little)),
      throttlePosAgeMs: _decodeAge(buffer.getUint16(BleTelemetryV3Offsets.throttlePosAgeMs, Endian.little)),
      batteryVoltAgeMs: _decodeAge(buffer.getUint16(BleTelemetryV3Offsets.batteryVoltAgeMs, Endian.little)),
      canBusState: CanBusState.fromRaw(canBusStateRaw),
      canTxErrorCount: buffer.getUint8(BleTelemetryV3Offsets.canTxErrorCount),
      canRxErrorCount: buffer.getUint8(BleTelemetryV3Offsets.canRxErrorCount),
      canBusOffCount: buffer.getUint8(BleTelemetryV3Offsets.canBusOffCount),
      unansweredDidCount: buffer.getUint16(BleTelemetryV3Offsets.unansweredDidCount, Endian.little),
      canFlags: buffer.getUint8(BleTelemetryV3Offsets.canFlags),
    );
  }
}
