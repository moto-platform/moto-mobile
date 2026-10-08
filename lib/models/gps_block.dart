import 'dart:typed_data';

import 'package:moto_defs/moto_defs.dart';

// GPS block decoder (D-060). The block layout (offsets, total size, version,
// fixType values, flag bits, scale) is NOT defined here: the single source of
// truth is moto-vehicle-defs `ble/ble_schema.json` (`gpsBlock`, D-061), taken
// through the generated `moto_defs` Dart package (`BleGpsBlock`,
// `BleGpsOffsets`, `BleGpsFixType`, `BleGpsFlagBits`, `BleGpsScale`).
//
// Speed and heading only: latitude, longitude and height never leave
// connectivity-node (D-060 item 3, invariant 7), so this block has no
// position and this app never records one.
//
// Notified on the `gps` characteristic (`BleGatt.gpsCharacteristicUuid`),
// one block per UBX-NAV-PVT (10 Hz). Subscribing needs a bonded, encrypted
// link (D-062); firmware without a GPS lacks the characteristic entirely.

/// Thrown by [GpsBlock.decode] when a raw payload does not match the schema
/// (bad size or bad version). The message is suitable for the `decode_error`
/// events column (contract: `gps:` prefix added by the caller).
class GpsBlockDecodeException implements Exception {
  GpsBlockDecodeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One decoded GPS block notification. The raw fields keep the wire units
/// (mm/s, 1e-5 deg); the getters scale them per the schema's `scale`.
class GpsBlock {
  const GpsBlock({
    required this.version,
    required this.seq,
    required this.deviceTimeMs,
    required this.groundSpeed,
    required this.headingOfMotion,
    required this.speedAccuracy,
    required this.headingAccuracy,
    required this.fixType,
    required this.numSv,
    required this.flags,
  });

  final int version;

  /// Rolling 0-255 counter; it also advances for blocks the node skipped
  /// because the MTU was too small (schema `sequenceRule`, D-062).
  final int seq;

  /// Node clock (the same clock as telemetry and IMU `deviceTimeMs`).
  final int deviceTimeMs;

  /// Ground speed, mm/s (signed, as in NAV-PVT).
  final int groundSpeed;

  /// Heading of motion, 1e-5 deg (signed, as in NAV-PVT).
  final int headingOfMotion;

  /// Speed accuracy estimate, mm/s.
  final int speedAccuracy;

  /// Heading accuracy estimate, 1e-5 deg.
  final int headingAccuracy;

  /// NAV-PVT fixType (see [BleGpsFixType]).
  final int fixType;

  /// Satellites used in the navigation solution.
  final int numSv;

  final int flags;

  double get groundSpeedMps => groundSpeed / BleGpsScale.speedLsbPerMps;
  double get headingOfMotionDeg => headingOfMotion / BleGpsScale.headingLsbPerDeg;
  double get speedAccuracyMps => speedAccuracy / BleGpsScale.speedLsbPerMps;
  double get headingAccuracyDeg => headingAccuracy / BleGpsScale.headingLsbPerDeg;

  bool get gnssFixOk => (flags & BleGpsFlagBits.gnssFixOk) != 0;

  /// The node's UBX parser dropped a message since the previous block (sent
  /// or skipped).
  bool get parseError => (flags & BleGpsFlagBits.parseError) != 0;

  /// The node's UART receive buffer overflowed since the previous block
  /// (sent or skipped).
  bool get uartOverflow => (flags & BleGpsFlagBits.uartOverflow) != 0;

  /// The schema's `fixType.rule`: the CAN speed check (D-060 item 4) uses only
  /// blocks with a 3-D fix (or GNSS + dead reckoning) and gnssFixOk set.
  bool get usableForSpeedCheck =>
      gnssFixOk && (fixType == BleGpsFixType.fix3d || fixType == BleGpsFixType.gnssDeadReckoning);

  /// Short display label of [fixType] for the UI.
  String get fixTypeLabel => switch (fixType) {
        BleGpsFixType.noFix => 'no fix',
        BleGpsFixType.deadReckoningOnly => 'DR only',
        BleGpsFixType.fix2d => '2D',
        BleGpsFixType.fix3d => '3D',
        BleGpsFixType.gnssDeadReckoning => '3D+DR',
        BleGpsFixType.timeOnly => 'time only',
        _ => 'fix $fixType',
      };

  /// Decodes one raw GPS block notification. The block has a fixed size and
  /// is never truncated (schema `mtuRule`), so the length must equal
  /// [BleGpsBlock.totalBytes] exactly and the version must equal
  /// [BleGpsBlock.version]. Throws [GpsBlockDecodeException] otherwise.
  factory GpsBlock.decode(Uint8List bytes) {
    if (bytes.length != BleGpsBlock.totalBytes) {
      throw GpsBlockDecodeException(
          'size mismatch: got ${bytes.length} bytes (expected ${BleGpsBlock.totalBytes})');
    }
    final buffer = ByteData.sublistView(bytes);
    final version = buffer.getUint8(BleGpsOffsets.version);
    if (version != BleGpsBlock.version) {
      throw GpsBlockDecodeException('version mismatch: got $version (expected ${BleGpsBlock.version})');
    }
    return GpsBlock(
      version: version,
      seq: buffer.getUint8(BleGpsOffsets.seq),
      deviceTimeMs: buffer.getUint32(BleGpsOffsets.deviceTimeMs, Endian.little),
      groundSpeed: buffer.getInt32(BleGpsOffsets.groundSpeed, Endian.little),
      headingOfMotion: buffer.getInt32(BleGpsOffsets.headingOfMotion, Endian.little),
      speedAccuracy: buffer.getUint32(BleGpsOffsets.speedAccuracy, Endian.little),
      headingAccuracy: buffer.getUint32(BleGpsOffsets.headingAccuracy, Endian.little),
      fixType: buffer.getUint8(BleGpsOffsets.fixType),
      numSv: buffer.getUint8(BleGpsOffsets.numSv),
      flags: buffer.getUint8(BleGpsOffsets.flags),
    );
  }
}

/// Tracks `seq` across GPS blocks within one session, per the schema's
/// `sequenceRule`: missing = (seq - prev.seq - 1) mod 256. The count covers
/// blocks lost on the radio *and* blocks the node skipped because the MTU was
/// too small (D-062 item 2), so it is not a radio-loss figure.
class GpsSeqTracker {
  int? _prevSeq;

  /// Returns the blocks lost or MTU-skipped between the previous block seen
  /// by this tracker and [block]; 0 for the first block.
  int missingBlocksFor(GpsBlock block) {
    final prev = _prevSeq;
    _prevSeq = block.seq;
    if (prev == null) return 0;
    return (block.seq - prev - 1) % 256;
  }

  void reset() => _prevSeq = null;
}

/// State of the phone's subscription to the `gps` characteristic on the
/// current connection.
enum GpsLinkState {
  /// No BLE connection.
  disconnected,

  /// Connected, but the firmware has no `gps` characteristic.
  notOffered,

  /// Bonding and/or enabling notifications.
  subscribing,

  /// Notifications enabled on a bonded link.
  subscribed,

  /// Bonding or the subscription failed on this connection (D-062: the
  /// characteristic needs a bonded, encrypted link). Telemetry and IMU are
  /// unaffected; the app retries on the next connection only.
  failed,
}

class GpsLinkStatus {
  const GpsLinkStatus(this.state, {this.reason});

  /// Why the subscription failed ([GpsLinkState.failed] only), with any
  /// device address redacted (see [redactDeviceIds]).
  final String? reason;
  final GpsLinkState state;

  static const disconnected = GpsLinkStatus(GpsLinkState.disconnected);
}

final RegExp _macAddress = RegExp(r'\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b');
final RegExp _uuid = RegExp(r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b');

/// Replaces Bluetooth device addresses (Android MAC) and UUID-shaped
/// identifiers (iOS device ids) in an error message, so a logged reason never
/// carries a device identifier (D-033).
String redactDeviceIds(String message) =>
    message.replaceAll(_macAddress, '<device>').replaceAll(_uuid, '<id>');
