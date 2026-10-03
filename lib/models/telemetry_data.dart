import 'dart:typed_data';

import 'package:moto_defs/moto_defs.dart';

// BLE telemetry packet decoder. The packet layout (offsets, sizes, versions,
// sentinels, flag bits, bus states, UUIDs) is NOT defined here: the single
// source of truth is moto-vehicle-defs `ble/ble_schema.json` (D-061), taken
// through the generated `moto_defs` Dart package (`BleTelemetry*`,
// `BleTelemetryV2Offsets`, `BleTelemetryV3Offsets`, `BleTelemetryV4Offsets`,
// `BleTelemetryFlagBits`, `BleCanFlagsBits`, `BleCanBusState`). A layout
// change is a defs change plus a version bump; this file only decodes.
//
// Implementations of the schema: the generated C header (firmware,
// moto-connectivity-node) and this file (decoder, moto-mobile). Ported from
// HondaCl250_Telemetry@legacy-final (schema version 1) per D-023.
//
// Version history (see the schema's `versioning.history`):
//  - 1: legacy 15-byte layout (not implemented here, never seen on the wire).
//  - 2: 16-byte layout (low-MTU fallback). Still sent by the firmware when
//    the negotiated ATT MTU is too small for the full layout, or by old
//    firmware that only ever speaks version 2.
//  - 3 (D-032): 37-byte layout. Adds `deviceTimeMs`, per-signal ages and
//    CAN/tester health, and flags bit 7 (`imuActive`). The lean fields are
//    deprecated (D-023) and always report "not available".
//  - 4 (D-058, current): 57-byte layout = version 3 plus the tester step-gap
//    fields and one rotating per-DID round-trip record (`testerStats` in the
//    schema). TEMPORARY until rt-core's health DID 0xFD02 (D-055).
//
// Receivers dispatch on byte 0 (`version`) and decode with the matching
// layout; a version outside [BleTelemetry.acceptedVersions], or a payload
// whose length does not match that version's total size, is dropped.

/// Telemetry packet version numbers, one per generated layout family
/// (`BleTelemetryV2*`, `BleTelemetryV3*`, `BleTelemetryV4*`). The generated
/// code has no per-version number constant (the number is part of the class
/// name), so the decoder's dispatch is spelled out here; the tests pin these
/// to [BleTelemetry.legacyVersion], [BleTelemetry.currentVersion] and
/// [BleTelemetry.acceptedVersions] so a defs version bump fails loudly instead
/// of silently decoding with the wrong layout.
abstract final class TelemetryVersion {
  static const int v2 = 2;
  static const int v3 = 3;
  static const int v4 = 4;
}

/// Vehicle-bus TWAI state (`canHealth.busState` in the schema; values from
/// the generated [BleCanBusState]). Only present on version 3 and 4 packets;
/// `null` on version 2 (the field does not exist).
enum CanBusState {
  notInstalled(BleCanBusState.notInstalled),
  running(BleCanBusState.running),
  errorWarning(BleCanBusState.errorWarning),
  busOff(BleCanBusState.busOff),
  stopped(BleCanBusState.stopped);

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

/// Telemetry model representing a decoded binary BLE packet from
/// moto-connectivity-node, version 2, 3 or 4.
class TelemetryData {
  /// 0 for [TelemetryData.initial] (no packet decoded yet), otherwise
  /// [TelemetryVersion.v2], [TelemetryVersion.v3] or [TelemetryVersion.v4].
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
  /// these three fields are always `null` on version 3 and 4 packets and are
  /// kept only so the layout stays close to version 2. Do not use for
  /// analysis -- the eventual lean signal comes from the rt-core EKF instead.
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
  /// [BleTelemetry.ageNeverReceived] (no value since boot).
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

  /// Raw `canFlags` byte; see [BleCanFlagsBits] for the bit masks, or use the
  /// `pollerEnabled` / `latchedForeignTester` / `latchedBusOff` /
  /// `syntheticData` getters below.
  final int? canFlags;

  /// Tester statistics (`testerStats` in the schema, D-058), version 4 only;
  /// all `null` on version 2 and 3. TEMPORARY until rt-core's health DID
  /// 0xFD02 (D-055). Values are the raw wire values, sentinels included:
  ///  - [stepGapMaxMs]: largest gap between two tester steps since boot (ms,
  ///    saturates at 65535; 0 when the node has no tester).
  ///  - [stepGapOverCount]: gaps above `client_step_max_ms` (saturating).
  ///  - [rttDid]: DID of this packet's rotating round-trip record; 0 = no
  ///    record, in which case the other `rtt*` fields carry no sample.
  ///  - [rttMinMs]: smallest round trip of [rttDid]; 65535 = no sample yet.
  ///  - [rttMaxMs]: largest round trip; 0 = no sample yet.
  ///  - [rttSumMs] / [rttCount]: sum and count of samples (uint32, saturating;
  ///    average = sum / count, invalid if either saturated).
  ///  - [rttNrc78Count]: requests answered with NRC 0x78 (no sample).
  final int? stepGapMaxMs;
  final int? stepGapOverCount;
  final int? rttDid;
  final int? rttMinMs;
  final int? rttMaxMs;
  final int? rttSumMs;
  final int? rttCount;
  final int? rttNrc78Count;

  bool? get pollerEnabled => _canFlagBit(BleCanFlagsBits.pollerEnabled);
  bool? get latchedForeignTester => _canFlagBit(BleCanFlagsBits.latchedForeignTester);
  bool? get latchedBusOff => _canFlagBit(BleCanFlagsBits.latchedBusOff);
  bool? get syntheticData => _canFlagBit(BleCanFlagsBits.syntheticData);

  bool? _canFlagBit(int mask) {
    final flags = canFlags;
    if (flags == null) return null;
    return (flags & mask) != 0;
  }

  // Packet-loss measurement via the rolling `seq` field, shared by all
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
    this.stepGapMaxMs,
    this.stepGapOverCount,
    this.rttDid,
    this.rttMinMs,
    this.rttMaxMs,
    this.rttSumMs,
    this.rttCount,
    this.rttNrc78Count,
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

  /// Total packet size in bytes for [version] (from the generated
  /// [BleTelemetry] totals), or `null` if this decoder has no layout for it.
  static int? expectedLength(int version) {
    switch (version) {
      case TelemetryVersion.v2:
        return BleTelemetry.totalBytesV2;
      case TelemetryVersion.v3:
        return BleTelemetry.totalBytesV3;
      case TelemetryVersion.v4:
        return BleTelemetry.totalBytesV4;
      default:
        return null;
    }
  }

  /// Parses one raw binary BLE telemetry notification. Wire format is
  /// LITTLE-ENDIAN throughout.
  ///
  /// Dispatches on byte 0 (`version`): version 4 decodes as the 57-byte
  /// layout, version 3 as the 37-byte layout and version 2 as the 16-byte
  /// low-MTU layout. Any version outside [BleTelemetry.acceptedVersions], or a
  /// payload whose length does not match that version's expected size, is
  /// dropped -- [TelemetryData.initial] is returned and
  /// [versionRejectedCount] / [sizeRejectedCount] is incremented so callers
  /// can tell those apart.
  factory TelemetryData.fromBinaryBuffer(Uint8List bytes) {
    if (bytes.isEmpty) return TelemetryData.initial();

    try {
      final version = bytes[0];
      final expected = expectedLength(version);
      if (expected == null || !BleTelemetry.acceptedVersions.contains(version)) {
        versionRejectedCount++;
        return TelemetryData.initial();
      }
      if (bytes.length != expected) {
        sizeRejectedCount++;
        return TelemetryData.initial();
      }
      if (version == TelemetryVersion.v2) return _decodeV2(bytes);
      return _decodeV3OrV4(bytes, version);
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

  static int? _decodeAge(int raw) => raw == BleTelemetry.ageNeverReceived ? null : raw;

  // Battery voltage: raw millivolts -> volts. Schema `fields[batteryVolt].scale`
  // (and `lowMtuFallback.fields[batteryVolt].scale`) is 0.001; the generated
  // Dart has no scale constant, so the literal stays here.
  static double _batteryVoltFromRaw(int rawMv) => rawMv / 1000.0;

  // Deprecated lean fields (D-023): raw tenths of a degree, `notAvailable`
  // (BleTelemetry.notAvailableInt16) -> null. The schema carries no scale for
  // these deprecated fields; the 1/10 is the legacy tenths convention.
  static double? _leanFromRaw(int raw) => raw == BleTelemetry.notAvailableInt16 ? null : raw / 10.0;

  static TelemetryData _decodeV2(Uint8List bytes) {
    final buffer = ByteData.sublistView(bytes);
    _trackSeq(buffer.getUint8(BleTelemetryV2Offsets.seq));

    final rpm = buffer.getUint16(BleTelemetryV2Offsets.rpm, Endian.little).toDouble();
    final speed = buffer.getUint8(BleTelemetryV2Offsets.speed);
    final coolantTemp = buffer.getInt8(BleTelemetryV2Offsets.coolantTemp);
    final throttlePos = buffer.getUint8(BleTelemetryV2Offsets.throttlePos).toDouble();
    final batteryVolt = _batteryVoltFromRaw(buffer.getUint16(BleTelemetryV2Offsets.batteryVolt, Endian.little));

    final leanAngleRaw = buffer.getInt16(BleTelemetryV2Offsets.leanAngle, Endian.little);
    final maxLeanRightRaw = buffer.getInt16(BleTelemetryV2Offsets.maxLeanRight, Endian.little);
    final maxLeanLeftRaw = buffer.getInt16(BleTelemetryV2Offsets.maxLeanLeft, Endian.little);

    final flags = buffer.getUint8(BleTelemetryV2Offsets.flags);
    bool bit(int mask) => (flags & mask) != 0;

    return TelemetryData(
      packetVersion: TelemetryVersion.v2,
      rpm: rpm,
      speed: speed,
      coolantTemp: coolantTemp,
      throttlePos: throttlePos,
      batteryVolt: batteryVolt,
      leanAngle: _leanFromRaw(leanAngleRaw),
      maxLeanRight: _leanFromRaw(maxLeanRightRaw),
      maxLeanLeft: _leanFromRaw(maxLeanLeftRaw),
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

  /// Decodes the version 3 layout and, when [version] is
  /// [TelemetryVersion.v4], the eight tester-stats fields appended after it.
  /// The version 4 layout starts with the version 3 layout unchanged (same
  /// offsets, enforced by a test), so the shared fields are read through
  /// [BleTelemetryV3Offsets] for both.
  static TelemetryData _decodeV3OrV4(Uint8List bytes, int version) {
    final buffer = ByteData.sublistView(bytes);
    _trackSeq(buffer.getUint8(BleTelemetryV3Offsets.seq));

    final deviceTimeMs = buffer.getUint32(BleTelemetryV3Offsets.deviceTimeMs, Endian.little);
    final rpm = buffer.getUint16(BleTelemetryV3Offsets.rpm, Endian.little).toDouble();
    final speed = buffer.getUint8(BleTelemetryV3Offsets.speed);
    final coolantTemp = buffer.getInt8(BleTelemetryV3Offsets.coolantTemp);
    final throttlePos = buffer.getUint8(BleTelemetryV3Offsets.throttlePos).toDouble();
    final batteryVolt = _batteryVoltFromRaw(buffer.getUint16(BleTelemetryV3Offsets.batteryVolt, Endian.little));

    // Deprecated (D-023): always notAvailable on version 3 and 4, decoded
    // generically anyway so a future change in the firmware is not silently
    // hidden here.
    final leanAngleRaw = buffer.getInt16(BleTelemetryV3Offsets.leanAngle, Endian.little);
    final maxLeanRightRaw = buffer.getInt16(BleTelemetryV3Offsets.maxLeanRight, Endian.little);
    final maxLeanLeftRaw = buffer.getInt16(BleTelemetryV3Offsets.maxLeanLeft, Endian.little);

    final flags = buffer.getUint8(BleTelemetryV3Offsets.flags);
    bool bit(int mask) => (flags & mask) != 0;

    final canBusStateRaw = buffer.getUint8(BleTelemetryV3Offsets.canBusState);

    final isV4 = version == TelemetryVersion.v4;
    int? v4U16(int offset) => isV4 ? buffer.getUint16(offset, Endian.little) : null;
    int? v4U32(int offset) => isV4 ? buffer.getUint32(offset, Endian.little) : null;

    return TelemetryData(
      packetVersion: version,
      deviceTimeMs: deviceTimeMs,
      rpm: rpm,
      speed: speed,
      coolantTemp: coolantTemp,
      throttlePos: throttlePos,
      batteryVolt: batteryVolt,
      leanAngle: _leanFromRaw(leanAngleRaw),
      maxLeanRight: _leanFromRaw(maxLeanRightRaw),
      maxLeanLeft: _leanFromRaw(maxLeanLeftRaw),
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
      stepGapMaxMs: v4U16(BleTelemetryV4Offsets.stepGapMaxMs),
      stepGapOverCount: v4U16(BleTelemetryV4Offsets.stepGapOverCount),
      rttDid: v4U16(BleTelemetryV4Offsets.rttDid),
      rttMinMs: v4U16(BleTelemetryV4Offsets.rttMinMs),
      rttMaxMs: v4U16(BleTelemetryV4Offsets.rttMaxMs),
      rttSumMs: v4U32(BleTelemetryV4Offsets.rttSumMs),
      rttCount: v4U32(BleTelemetryV4Offsets.rttCount),
      rttNrc78Count: v4U16(BleTelemetryV4Offsets.rttNrc78Count),
    );
  }
}
