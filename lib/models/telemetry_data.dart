import 'dart:typed_data';

// G3.3 -- BLE telemetry packet format, single source of truth:
// docs/ble_telemetry_packet_schema.json (also mirrored in src/BLETelemetryPacket.h
// and mobile_app/app.js).
const int blePacketExpectedVersion = 1;
const int blePacketSizeBytes = 15;

/// Telemetry model representing binary BLE packet from Honda CL250 ESP32.
class TelemetryData {
  final double rpm;
  final int speed;
  final int coolantTemp;
  final double throttlePos;
  final double batteryVolt;
  final double leanAngle;
  final double maxLeanRight;
  final double maxLeanLeft;

  // G3.3 -- packet-loss measurement via the rolling `seq` field. Static because
  // fromBinaryBuffer is a pure factory with no persistent instance to hang this on,
  // mirroring mobile_app/app.js's appState.packetStats.
  static int? _lastSeq;
  static int receivedCount = 0;
  static int lostCount = 0;
  static int versionRejectedCount = 0;

  TelemetryData({
    required this.rpm,
    required this.speed,
    required this.coolantTemp,
    required this.throttlePos,
    required this.batteryVolt,
    required this.leanAngle,
    required this.maxLeanRight,
    required this.maxLeanLeft,
  });

  factory TelemetryData.initial() {
    return TelemetryData(
      rpm: 0,
      speed: 0,
      coolantTemp: 0,
      throttlePos: 0,
      batteryVolt: 0.0,
      leanAngle: 0.0,
      maxLeanRight: 0.0,
      maxLeanLeft: 0.0,
    );
  }

  /// Parses 15-byte binary packet received from BLE notification.
  /// G1.1 -- Wire format is LITTLE-ENDIAN (ESP32-S3 native byte order); every getX()
  /// call below passes Endian.little for that reason.
  /// G3.3 -- Layout, versioning and seq-based loss counting are defined in
  /// docs/ble_telemetry_packet_schema.json; must stay in sync with
  /// src/BLETelemetryPacket.h and mobile_app/app.js (handleTelemetryNotification).
  /// Returns TelemetryData.initial() both on a malformed packet and on a version
  /// mismatch -- callers can check [versionRejectedCount] to tell those apart.
  factory TelemetryData.fromBinaryBuffer(Uint8List bytes) {
    if (bytes.length < blePacketSizeBytes) return TelemetryData.initial();

    try {
      final buffer = ByteData.sublistView(bytes);

      final version = buffer.getUint8(0);
      if (version != blePacketExpectedVersion) {
        versionRejectedCount++;
        return TelemetryData.initial();
      }

      final seq = buffer.getUint8(1);
      final lastSeq = _lastSeq;
      if (lastSeq != null) {
        // Rolling 0-255 counter: gap = packets missed between the last seq seen
        // and this one, minus the one we did receive.
        final gap = (seq - lastSeq - 1 + 256) % 256;
        lostCount += gap;
      }
      _lastSeq = seq;
      receivedCount++;

      final rpm = buffer.getUint16(2, Endian.little).toDouble();
      final speed = buffer.getUint8(4);
      final coolantTemp = buffer.getInt8(5);
      final throttlePos = buffer.getUint8(6).toDouble();
      final batteryVolt = buffer.getUint16(7, Endian.little) / 1000.0;
      final leanAngle = buffer.getInt16(9, Endian.little) / 10.0;
      final maxLeanRight = buffer.getInt16(11, Endian.little) / 10.0;
      final maxLeanLeft = buffer.getInt16(13, Endian.little) / 10.0;

      return TelemetryData(
        rpm: rpm,
        speed: speed,
        coolantTemp: coolantTemp,
        throttlePos: throttlePos,
        batteryVolt: batteryVolt,
        leanAngle: leanAngle,
        maxLeanRight: maxLeanRight,
        maxLeanLeft: maxLeanLeft,
      );
    } catch (e) {
      return TelemetryData.initial();
    }
  }
}
