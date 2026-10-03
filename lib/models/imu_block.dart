import 'dart:typed_data';

import 'package:moto_defs/moto_defs.dart';

// IMU sample block decoder. The block layout (header/sample offsets and
// sizes, version, limits, flag bits, raw scale) is NOT defined here: the
// single source of truth is moto-vehicle-defs `ble/ble_schema.json`
// (`imuBlock`, D-061), taken through the generated `moto_defs` Dart package
// (`BleImuBlock`, `BleImuHeaderOffsets`, `BleImuSampleOffsets`,
// `BleImuFlagBits`, `BleImuScale`).
//
// Notified separately from telemetry on the `imu` characteristic
// (`BleGatt.imuCharacteristicUuid`) -- old firmware lacks this characteristic
// entirely, so its absence is not itself an error.
//
// Layout: a fixed header followed by 1..[BleImuBlock.maxSamples] fixed-size
// samples, little-endian throughout. Implementations of this schema: the
// generated C header (firmware) and this file (decoder).

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

  double get axG => axRaw / BleImuScale.accelLsbPerG;
  double get ayG => ayRaw / BleImuScale.accelLsbPerG;
  double get azG => azRaw / BleImuScale.accelLsbPerG;
  double get gxDps => gxRaw / BleImuScale.gyroLsbPerDps;
  double get gyDps => gyRaw / BleImuScale.gyroLsbPerDps;
  double get gzDps => gzRaw / BleImuScale.gyroLsbPerDps;
}

/// One decoded IMU block notification: a header plus 1..
/// [BleImuBlock.maxSamples] samples.
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

  bool get deviceOverflow => (flags & BleImuFlagBits.deviceOverflow) != 0;
  bool get readError => (flags & BleImuFlagBits.readError) != 0;

  /// Samples strictly before this block may be in the wrong scale or frozen
  /// -- see [BleImuFlagBits.sensorReconfigured].
  bool get sensorReconfigured => (flags & BleImuFlagBits.sensorReconfigured) != 0;

  /// Decodes one raw IMU block notification. Validates, in order: minimum
  /// length for the header, `version == BleImuBlock.version`, `sampleCount` in 1..
  /// [BleImuBlock.maxSamples], and the total length matching
  /// `headerBytes + sampleBytes * sampleCount` exactly. Throws
  /// [ImuBlockDecodeException] (never returns a partially-decoded block) on
  /// any mismatch.
  factory ImuBlock.decode(Uint8List bytes) {
    if (bytes.length < BleImuBlock.headerBytes) {
      throw ImuBlockDecodeException(
          'short block: ${bytes.length} bytes (min ${BleImuBlock.headerBytes})');
    }

    final buffer = ByteData.sublistView(bytes);
    final version = buffer.getUint8(BleImuHeaderOffsets.version);
    if (version != BleImuBlock.version) {
      throw ImuBlockDecodeException('version mismatch: got $version (expected ${BleImuBlock.version})');
    }

    final sampleCount = buffer.getUint8(BleImuHeaderOffsets.sampleCount);
    if (sampleCount < 1 || sampleCount > BleImuBlock.maxSamples) {
      throw ImuBlockDecodeException(
          'invalid sampleCount: $sampleCount (expected 1..${BleImuBlock.maxSamples})');
    }

    final expectedSize = BleImuBlock.headerBytes + BleImuBlock.sampleBytes * sampleCount;
    if (bytes.length != expectedSize) {
      throw ImuBlockDecodeException(
          'size mismatch: got ${bytes.length} bytes (expected $expectedSize for sampleCount=$sampleCount)');
    }

    final seq = buffer.getUint8(BleImuHeaderOffsets.seq);
    final deviceTimeMs = buffer.getUint32(BleImuHeaderOffsets.deviceTimeMs, Endian.little);
    final firstSampleIndex = buffer.getUint16(BleImuHeaderOffsets.firstSampleIndex, Endian.little);
    final samplePeriodMs = buffer.getUint8(BleImuHeaderOffsets.samplePeriodMs);
    final flags = buffer.getUint8(BleImuHeaderOffsets.flags);

    final samples = <ImuSample>[];
    for (var i = 0; i < sampleCount; i++) {
      final base = BleImuBlock.headerBytes + i * BleImuBlock.sampleBytes;
      samples.add(ImuSample(
        sampleIndex: (firstSampleIndex + i) & 0xFFFF,
        deviceTimeMs: (deviceTimeMs + i * samplePeriodMs) & 0xFFFFFFFF,
        axRaw: buffer.getInt16(base + BleImuSampleOffsets.ax, Endian.little),
        ayRaw: buffer.getInt16(base + BleImuSampleOffsets.ay, Endian.little),
        azRaw: buffer.getInt16(base + BleImuSampleOffsets.az, Endian.little),
        gxRaw: buffer.getInt16(base + BleImuSampleOffsets.gx, Endian.little),
        gyRaw: buffer.getInt16(base + BleImuSampleOffsets.gy, Endian.little),
        gzRaw: buffer.getInt16(base + BleImuSampleOffsets.gz, Endian.little),
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
