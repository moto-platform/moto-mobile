import 'dart:typed_data';

/// IMU sample block format, single source of truth:
/// moto-connectivity-node/docs/ble_telemetry_packet_schema.json, `imuBlock`.
/// Notified separately from telemetry on the `imu` characteristic
/// (`gatt.characteristics.imu`) -- old firmware lacks this characteristic
/// entirely, so its absence is not itself an error.
///
/// Layout: a fixed 12-byte header followed by 1..[ImuBlockLayout.maxSamples]
/// fixed 12-byte samples, little-endian throughout. Implementations of this
/// schema: src/ImuBlockPacket.h (firmware) and this file (decoder).
const int imuBlockVersion = 1;
const int imuBlockHeaderBytes = 12;
const int imuBlockSampleBytes = 12;
const int imuBlockMaxSamples = 10;
const int imuBlockSamplePeriodMsDefault = 10;

/// Byte offsets of the IMU block header fields (`imuBlock.headerFields` in
/// the schema).
class ImuBlockHeaderOffsets {
  static const int version = 0;
  static const int seq = 1;
  static const int deviceTimeMs = 2;
  static const int firstSampleIndex = 6;
  static const int sampleCount = 8;
  static const int samplePeriodMs = 9;
  static const int flags = 10;
  static const int reserved = 11;
}

/// Byte offsets within a single 12-byte sample, relative to the sample's own
/// start (`imuBlock.sampleFields` in the schema).
class ImuSampleOffsets {
  static const int ax = 0;
  static const int ay = 2;
  static const int az = 4;
  static const int gx = 6;
  static const int gy = 8;
  static const int gz = 10;
}

/// Bit positions within the IMU block `flags` byte (`imuBlock.flags` in the
/// schema).
class ImuBlockFlagBits {
  static const int deviceOverflow = 0;
  static const int readError = 1;

  /// The node found the sensor configuration lost (e.g. a brown-out reset it
  /// to its defaults) or reads failing, and configured it again since the
  /// previous block. Samples before this block may be in the wrong scale or
  /// frozen.
  static const int sensorReconfigured = 2;
}

/// Raw-to-physical scale factors (`imuBlock.scale` in the schema).
class ImuScale {
  /// accel_g = raw / lsbPerG
  static const double accelLsbPerG = 4096;

  /// gyro_dps = raw / lsbPerDps
  static const double gyroLsbPerDps = 65.5;
}

/// Thrown by [ImuBlock.decode] when a raw payload does not match the schema
/// (bad version, bad size, or an out-of-range `sampleCount`). The message is
/// suitable for the `decode_error` events column (contract: `imu:` prefix
/// added by the caller).
class ImuBlockDecodeException implements Exception {
  ImuBlockDecodeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One decoded IMU sample, with the block-relative fields (`deviceTimeMs`,
/// `sampleIndex`) already resolved per the schema's `timeRule` and
/// `sampleIndex.rule`.
class ImuSample {
  const ImuSample({
    required this.sampleIndex,
    required this.deviceTimeMs,
    required this.axRaw,
    required this.ayRaw,
    required this.azRaw,
    required this.gxRaw,
    required this.gyRaw,
    required this.gzRaw,
  });

  /// `firstSampleIndex + i`, wrapped to uint16 (the schema's tick counter).
  final int sampleIndex;

  /// `deviceTimeMs + i * samplePeriodMs` on the block's clock, wrapped to
  /// uint32 (the node's `millis()` clock wraps the same way).
  final int deviceTimeMs;

  final int axRaw;
  final int ayRaw;
  final int azRaw;
  final int gxRaw;
  final int gyRaw;
  final int gzRaw;

  double get axG => axRaw / ImuScale.accelLsbPerG;
  double get ayG => ayRaw / ImuScale.accelLsbPerG;
  double get azG => azRaw / ImuScale.accelLsbPerG;
  double get gxDps => gxRaw / ImuScale.gyroLsbPerDps;
  double get gyDps => gyRaw / ImuScale.gyroLsbPerDps;
  double get gzDps => gzRaw / ImuScale.gyroLsbPerDps;
}

/// One decoded IMU block notification: a header plus 1..
/// [imuBlockMaxSamples] samples.
class ImuBlock {
  const ImuBlock({
    required this.version,
    required this.seq,
    required this.deviceTimeMs,
    required this.firstSampleIndex,
    required this.sampleCount,
    required this.samplePeriodMs,
    required this.flags,
    required this.samples,
  });

  final int version;
  final int seq;
  final int deviceTimeMs;
  final int firstSampleIndex;
  final int sampleCount;
  final int samplePeriodMs;
  final int flags;
  final List<ImuSample> samples;

  bool get deviceOverflow => (flags & (1 << ImuBlockFlagBits.deviceOverflow)) != 0;
  bool get readError => (flags & (1 << ImuBlockFlagBits.readError)) != 0;

  /// Samples strictly before this block may be in the wrong scale or frozen
  /// -- see [ImuBlockFlagBits.sensorReconfigured].
  bool get sensorReconfigured => (flags & (1 << ImuBlockFlagBits.sensorReconfigured)) != 0;

  /// Decodes one raw IMU block notification. Validates, in order: minimum
  /// length for the header, `version == 1`, `sampleCount` in 1..
  /// [imuBlockMaxSamples], and the total length matching
  /// `headerBytes + sampleBytes * sampleCount` exactly. Throws
  /// [ImuBlockDecodeException] (never returns a partially-decoded block) on
  /// any mismatch.
  factory ImuBlock.decode(Uint8List bytes) {
    if (bytes.length < imuBlockHeaderBytes) {
      throw ImuBlockDecodeException(
          'short block: ${bytes.length} bytes (min $imuBlockHeaderBytes)');
    }

    final buffer = ByteData.sublistView(bytes);
    final version = buffer.getUint8(ImuBlockHeaderOffsets.version);
    if (version != imuBlockVersion) {
      throw ImuBlockDecodeException('version mismatch: got $version (expected $imuBlockVersion)');
    }

    final sampleCount = buffer.getUint8(ImuBlockHeaderOffsets.sampleCount);
    if (sampleCount < 1 || sampleCount > imuBlockMaxSamples) {
      throw ImuBlockDecodeException(
          'invalid sampleCount: $sampleCount (expected 1..$imuBlockMaxSamples)');
    }

    final expectedSize = imuBlockHeaderBytes + imuBlockSampleBytes * sampleCount;
    if (bytes.length != expectedSize) {
      throw ImuBlockDecodeException(
          'size mismatch: got ${bytes.length} bytes (expected $expectedSize for sampleCount=$sampleCount)');
    }

    final seq = buffer.getUint8(ImuBlockHeaderOffsets.seq);
    final deviceTimeMs = buffer.getUint32(ImuBlockHeaderOffsets.deviceTimeMs, Endian.little);
    final firstSampleIndex = buffer.getUint16(ImuBlockHeaderOffsets.firstSampleIndex, Endian.little);
    final samplePeriodMs = buffer.getUint8(ImuBlockHeaderOffsets.samplePeriodMs);
    final flags = buffer.getUint8(ImuBlockHeaderOffsets.flags);

    final samples = <ImuSample>[];
    for (var i = 0; i < sampleCount; i++) {
      final base = imuBlockHeaderBytes + i * imuBlockSampleBytes;
      samples.add(ImuSample(
        sampleIndex: (firstSampleIndex + i) & 0xFFFF,
        deviceTimeMs: (deviceTimeMs + i * samplePeriodMs) & 0xFFFFFFFF,
        axRaw: buffer.getInt16(base + ImuSampleOffsets.ax, Endian.little),
        ayRaw: buffer.getInt16(base + ImuSampleOffsets.ay, Endian.little),
        azRaw: buffer.getInt16(base + ImuSampleOffsets.az, Endian.little),
        gxRaw: buffer.getInt16(base + ImuSampleOffsets.gx, Endian.little),
        gyRaw: buffer.getInt16(base + ImuSampleOffsets.gy, Endian.little),
        gzRaw: buffer.getInt16(base + ImuSampleOffsets.gz, Endian.little),
      ));
    }

    return ImuBlock(
      version: version,
      seq: seq,
      deviceTimeMs: deviceTimeMs,
      firstSampleIndex: firstSampleIndex,
      sampleCount: sampleCount,
      samplePeriodMs: samplePeriodMs,
      flags: flags,
      samples: samples,
    );
  }
}

/// Tracks `firstSampleIndex` across consecutive IMU blocks within one
/// session to compute samples lost on the node (buffer overflow, read
/// error, missed tick) and in BLE together, per the schema's
/// `imuBlock.sampleIndex.rule`.
///
/// Stateful by design (a running uint16 tick counter needs the previous
/// block to make sense of); one instance per recording session.
class ImuGapTracker {
  int? _prevFirstSampleIndex;
  int? _prevSampleCount;

  /// Returns the number of samples missing between the previous block seen
  /// by this tracker and [block]: 0 for the first block observed, otherwise
  /// `(firstSampleIndex - (prev.firstSampleIndex + prev.sampleCount)) mod
  /// 65536`.
  int missingSamplesFor(ImuBlock block) {
    var missing = 0;
    final prevIndex = _prevFirstSampleIndex;
    final prevCount = _prevSampleCount;
    if (prevIndex != null && prevCount != null) {
      // Dart's `%` on ints always returns a non-negative result when the
      // divisor is positive, which is exactly the uint16-wrap semantics the
      // schema calls for.
      missing = (block.firstSampleIndex - (prevIndex + prevCount)) % 65536;
    }
    _prevFirstSampleIndex = block.firstSampleIndex;
    _prevSampleCount = block.sampleCount;
    return missing;
  }

  /// Resets tracking, e.g. between recording sessions.
  void reset() {
    _prevFirstSampleIndex = null;
    _prevSampleCount = null;
  }
}
